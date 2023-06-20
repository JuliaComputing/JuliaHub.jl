module _PackageBundler

# TODO: Compression

using Pkg
using Printf
using UUIDs
using Tar
using Glob

include("utils.jl")

if VERSION < v"1.7.0"
    function find_packages_tracked_pkg_server()
        # TODO: Check what registries that PkgServer actually track
        #       For now, assume all registries are tracked.
        packages_tracked_pkg_server = Set{Base.UUID}()
        for reg in Pkg.Types.collect_registries()
            reg_dir = reg.path
            reg_file = joinpath(reg_dir, "Registry.toml")
            if !isfile(reg_file)
                @warn "Registry.toml at `$reg_file` is missing. Please fix or remove the registry."
                continue
            end
            reg_data = Pkg.TOML.parsefile(reg_file)
            for uuid in UUID.(keys(get(reg_data, "packages", Dict)))
                # TODO: We should probably check the git-tree-sha1 that the registry tracks
                # instead of just the UUID
                push!(packages_tracked_pkg_server, uuid)
            end
        end
        return packages_tracked_pkg_server
    end
else
    function find_packages_tracked_pkg_server()
        # TODO: Check what registries that PkgServer actually track
        #       For now, assume all registries are tracked.
        packages_tracked_pkg_server = Set{Base.UUID}()
        for registry in Pkg.Registry.reachable_registries()
            union!(packages_tracked_pkg_server, keys(registry.pkgs))
        end
        return packages_tracked_pkg_server
    end
end

"""
    bundle(dir; output = "",  force=false, allownoenv=false, verbose = true)

Creates a `.tar` file with the contents of `dir` as well as
any packages that are either tracked by path (developed) outside
`dir` or packages that are not tracked by the PkgServer.
Artifacts are also bundled. The bundled packages and artifacts
go into a `.bundled/depot` directory and is set up like a depot and can thus
be made available by adding it to `DEPOT_PATH`.

`.git` and [globs](https://en.wikipedia.org/wiki/Glob_(programming)) listed in
`.juliabundleignore` are excluded form the bundle.
"""
function bundle(dir; output="", force=false, allownoenv=false, verbose=true)
    if !isdir(dir)
        error("'$(dir)' is not a directory")
    end
    name = splitpath(dir)[end]
    output_tar = output === "" ? name * ".tar" : output
    if ispath(output_tar)
        if force
            rm(output_tar; recursive=true)
        else
            error("file '$output_tar' already exists")
        end
    end
    tmp_dir = mktempdir()
    output_dir = joinpath(tmp_dir, name)
    cp(dir, output_dir; follow_symlinks=true)

    packages_tracked_pkg_server = find_packages_tracked_pkg_server()

    ctx = create_pkg_context(dir, allownoenv)
    if isempty(ctx.env.manifest)
        @warn "No Manifest available. Resolving environment."
        withenv("JULIA_PKG_PRECOMPILE_AUTO" => 0) do
            Pkg.instantiate(ctx)
            Pkg.resolve(ctx)
        end
        ctx = create_pkg_context(dir, allownoenv)
    end

    bundle_dir = joinpath(output_dir, ".bundle")
    mkpath(bundle_dir)
    # Bundle artifacts
    bundle_artifacts(ctx, bundle_dir, packages_tracked_pkg_server; verbose=verbose)

    # Bundle packages
    dev_path_map = bundle_packages(ctx, bundle_dir, packages_tracked_pkg_server; verbose=verbose)

    # Need to rewrite the devved paths that we have moved into the bundle
    bundle_manifest = joinpath(output_dir, "Manifest.toml")
    manifest = Pkg.Types.read_manifest(bundle_manifest)
    for (_, pkg) in manifest
        if pkg.path !== nothing
            pkg_path = try
                normpath(source_path(ctx, pkg))
            catch err
                @debug "source_path not supported, falling back to joinpath" exception = (
                    err, catch_backtrace()
                )
                joinpath(dir, pkg.path)
            end
            if haskey(dev_path_map, pkg_path)
                pkg.path = dev_path_map[pkg_path]
            end
        end
    end
    Pkg.Types.write_manifest(manifest, bundle_manifest)
    verbose && prettyprint("Archiving", "into $(repr(abspath(output_tar)))")

    Tar.create(path_filterer(tmp_dir), tmp_dir, output_tar)

    verbose && println(
        """

To run code on another machine:
- Upload `$(output_tar)` to the machine and unpack it
- Run `julia --project=$(name) -e 'push!(DEPOT_PATH, "$name/.bundle/depot"); import Pkg; Pkg.instantiate(); include("$name/main.jl"); main()'`""",
    )
    return nothing
end

function bundle_packages(ctx, dir, packages_tracked_pkg_server; verbose=true)
    pkgs = load_all_deps(ctx)
    package_paths = Dict{String, String}()
    package_dev_paths = Dict{String, String}()
    for pkg in pkgs
        # No need to bundle stdlibs
        if Pkg.Types.is_stdlib(pkg.uuid)
            continue
        end
        pkg_path = source_path(ctx, pkg)
        #=
        # TODO: Warn about build scripts?
        if isdir(pkg_path, "build")
            @warn "Package $(pkg.name) has a build script"
        end
        =#
        if pkg.path === nothing
            # TODO: What if we are tracking a branch in a git repo? Maybe need to bundle then?
            if pkg.uuid in packages_tracked_pkg_server
                @debug "Skipping bundling $(pkg.name) since Pkg Server tracks it"
                continue
            end
            # Check if this package is known by the registry
            package_paths[pkg_path] = pkg.name
        else
            # If the package is devved within dir we have already copied it
            need_to_copy = true
            if !isabspath(pkg.path)
                project_dir = dirname(ctx.env.project_file)
                if is_subpath(project_dir, joinpath(project_dir, pkg.path))
                    need_to_copy = false
                end
            end
            if need_to_copy
                package_dev_paths[pkg_path] = pkg.name
            end
        end
    end

    if !isempty(package_paths)
        package_bundle_path = joinpath(dir, "depot", "packages")
        mkpath(package_bundle_path)
        verbose && prettyprint("Bundling", "packages not tracked by PkgServer")
        for (package_path, name) in package_paths
            # Ignore if stdlib
            # Ignore if deved
            package_slug = joinpath(splitpath(package_path)[(end - 1):end]...)
            mkpath(joinpath(package_bundle_path, name))
            siz = recursive_dir_size(package_path)
            verbose && println("  - ", name, " (", pretty_byte_str(siz), ")")
            cp(package_path, joinpath(package_bundle_path, package_slug))
        end
        verbose && println()
    end

    dev_paths_map = Dict{String, String}()
    if !isempty(package_dev_paths)
        package_dev_bundle_path = joinpath(dir, "dev")
        mkpath(package_dev_bundle_path)
        verbose && prettyprint("Bundling", "packages tracked by path outside directory")
        for (package_path, name) in package_dev_paths
            package_path = normpath(package_path)
            # Ignore if stdlib
            # Ignore if deved
            siz = recursive_dir_size(package_path)
            verbose &&
                println("  - ", name, " [", package_path, "]", " (", pretty_byte_str(siz), ")")
            bundle_dev_path = joinpath(package_dev_bundle_path, name)
            cp(package_path, bundle_dev_path)
            dev_paths_map[package_path] = joinpath(splitpath(bundle_dev_path)[(end - 2):end]...)
        end
        verbose && println()
    end

    return dev_paths_map
end

function bundle_artifacts(ctx, dir, packages_tracked_pkg_server; verbose=true)
    pkgs = load_all_deps(ctx)

    # Also want artifacts for the project itself
    if ctx.env.pkg !== nothing
        # This is kinda ugly...
        ctx.env.pkg.path = dirname(ctx.env.project_file)
        push!(pkgs, ctx.env.pkg)
    end

    # Collect all artifacts needed for the project
    artifact_paths = Dict{String, String}()
    for pkg in pkgs
        pkg_source_path = source_path(ctx, pkg)
        pkg_source_path === nothing && continue
        # Check to see if this package has an (Julia)Artifacts.toml
        for f in Pkg.Artifacts.artifact_names
            artifacts_toml_path = joinpath(pkg_source_path, f)
            if isfile(artifacts_toml_path)
                if pkg.uuid in packages_tracked_pkg_server
                    @debug "Skipping bundling artifacts for $(pkg.name) since package is tracked by Pkg Server"
                    continue
                end
                artifact_dict = Pkg.Artifacts.load_artifacts_toml(artifacts_toml_path)
                for name in keys(artifact_dict)
                    meta = Pkg.Artifacts.artifact_meta(name, artifacts_toml_path)
                    meta == nothing && continue
                    artifact_paths[Pkg.Artifacts.ensure_artifact_installed(
                        name, artifacts_toml_path
                    )] = name
                end
                break
            end
        end
    end

    artifact_bundle_path = joinpath(dir, "depot", "artifacts")
    mkpath(artifact_bundle_path)

    if !isempty(artifact_paths)
        verbose && prettyprint("Bundling", "artifacts for packages not tracked by PkgServer")
        for (artifact_path, name) in artifact_paths
            artifact_name = basename(artifact_path)
            siz = recursive_dir_size(artifact_path)
            verbose && println("  - ", name, " (", pretty_byte_str(siz), ")")
            cp(artifact_path, joinpath(artifact_bundle_path, artifact_name))
        end
        verbose && println()
    end
    return nothing
end


end # module
