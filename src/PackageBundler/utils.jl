function pretty_byte_str(size)
    bytes, mb = Base.prettyprint_getunits(size, length(Base._mem_units), Int64(1024))
    return @sprintf("%.3f %s", bytes, Base._mem_units[mb])
end

function recursive_dir_size(path)
    size = 0
    for (root, _, files) in walkdir(path)
        for file in files
            path = joinpath(root, file)
            try
                size += lstat(path).size
            catch
                @warn "Failed to calculate size of $path"
            end
        end
    end
    return size
end

function load_all_deps(ctx)
    if isdefined(Pkg.Operations, :load_all_deps!)
        pkgs = Pkg.Types.PackageSpec[]
        Pkg.Operations.load_all_deps!(ctx, pkgs)
    else
        if VERSION >= v"1.7"
            pkgs = Pkg.Operations.load_all_deps(ctx.env)
        else
            pkgs = Pkg.Operations.load_all_deps(ctx)
        end
    end
    return pkgs
end

function source_path(ctx, pkg)
    if VERSION <= v"1.4.0-rc1"
        Pkg.Operations.source_path(pkg)
    elseif VERSION >= v"1.7"
        Pkg.Operations.source_path(ctx.env.project_file, pkg)
    else
        Pkg.Operations.source_path(ctx, pkg)
    end
end

function create_pkg_context(project, allownoenv)
    project_toml_path = Pkg.Types.projectfile_path(project; strict=true)
    if project_toml_path === nothing
        if allownoenv
            project_toml_path = joinpath(project, "Project.toml")
            open(project_toml_path, "w") do io
                println(io, "[deps]")
            end
        else
            error("Could not find project at $(repr(project))")
        end
    end
    return Pkg.Types.Context(; env=Pkg.Types.EnvCache(project_toml_path))
end

function prettyprint(io::IO, header, text)
    printstyled(io, header, " "; color=:light_green)
    println(io, text)
end

prettyprint(header, text) = prettyprint(stdout, header, text)

function is_subpath(dir, subpath)
    ispath(dir) || return false
    norm_dir = realpath(dir)
    spath = joinpath(norm_dir, subpath)
    ispath(spath) || return false
    norm_subpath = realpath(spath)
    return startswith(norm_subpath, norm_dir)
end

function get_bundleignore(file, top)
    dir = dirname(file)
    patterns = Set{Any}()
    try
        while true
            if isfile(joinpath(dir, ".juliabundleignore"))
                union!(
                    patterns,
                    Glob.FilenameMatch.(strip.(readlines(joinpath(dir, ".juliabundleignore")))),
                )
                return patterns, dir
            end
            if dir == dirname(dir) || dir == top
                break
            end
            dir = dirname(dir)
        end
    catch err
        @warn "Internal error" exception = (err, catch_backtrace())
    end
    return patterns, top
end

"""
    path_filterer(top)

Returns a function that takes a file or directory path and checks whether that is excluded by the
nearest `.juliabundleignore` file. The function will also ignore any `.git` files and directories.

The `top` argument specifies the highest directory up the tree that will be searched for
the `.juliabundleignore` file.

The function will return `false` for any excluded files and `true` otherwise, and can be used as
a predicate for filtering files that should be bundled.
"""
function path_filterer(top)
    function (path)
        if occursin(fn"*/.git", sanitize_windows_path(path)) ||
            occursin(fn"*/.git/*", sanitize_windows_path(path))
            return false
        end

        patterns, ignorepath = get_bundleignore(path, top)

        rpath = relpath(path, ignorepath)

        return !(
            any(p -> occursin(p, sanitize_windows_path(rpath)), patterns) ||
            # directories specifically can be excluded by patterns that end with a
            # path separator, and to match them in case `path` does not have that
            # path separator appended, we append it ourselves before matching
            isdir(path) &&
            any(p -> occursin(p, sanitize_windows_path(joinpath(rpath, ""))), patterns)
        )
    end
end

# Glob.jl assumes that path separators are unix-y forward slashes (consistent with
# e.g. .gitignore files). But so for those to properly match on windows, we need to
# essentially convert paths on Windows into unix paths.
sanitize_windows_path(path) = Sys.iswindows() ? replace(path, '\\' => '/') : path
