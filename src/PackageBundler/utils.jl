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

# Parse a single `.juliabundleignore` line.  Returns a vector of patterns
# (Glob.FilenameMatch or String for directory prefixes), or `nothing` for
# blank lines and comments.  Directory patterns (trailing `/`) are split into
# a dir match + contents match; plain prefixes use `startswith`.
function _parse_bundleignore_line(line)
    s = strip(line)
    (isempty(s) || startswith(s, '#')) && return nothing
    if endswith(s, '/')
        has_glob = any(c -> c in ('*', '?', '['), s)
        if has_glob
            # Glob directory pattern: match both the dir and its contents
            return [Glob.FilenameMatch(s), Glob.FilenameMatch(s * "*")]
        else
            # Plain directory prefix: use startswith matching
            return [String(s)]
        end
    end
    return [Glob.FilenameMatch(s)]
end

function get_bundleignore(file, top)
    dir = dirname(file)
    patterns = Set{Any}()
    try
        while true
            if isfile(joinpath(dir, ".juliabundleignore"))
                for line in readlines(joinpath(dir, ".juliabundleignore"))
                    parsed = _parse_bundleignore_line(line)
                    parsed !== nothing && union!(patterns, parsed)
                end
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
    cp_skip_dangling_symlinks(src, dst)

Recursively copies the directory `src` to `dst`, mirroring the behaviour of
`cp(src, dst; follow_symlinks=true)` but silently skipping any dangling symlinks
(symlinks whose target does not exist) instead of erroring on them.
"""
function cp_skip_dangling_symlinks(src::AbstractString, dst::AbstractString)
    mkpath(dst)
    for entry in readdir(src)
        src_entry = joinpath(src, entry)
        dst_entry = joinpath(dst, entry)
        if isdir(src_entry)
            cp_skip_dangling_symlinks(src_entry, dst_entry)
        elseif isfile(src_entry)
            cp(src_entry, dst_entry; follow_symlinks=true)
        elseif islink(src_entry)
            # Dangling symlink: isfile/isdir follow symlinks so both return false for a
            # dangling symlink, while islink uses lstat so it returns true.
            @warn "Skipping dangling symlink" path = src_entry
        end
    end
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

        rpath = sanitize_windows_path(relpath(path, ignorepath))
        # Ensure rpath uses forward slashes for consistent matching
        rpath_dir = sanitize_windows_path(joinpath(relpath(path, ignorepath), ""))

        return !(
            any(patterns) do p
                if p isa Glob.FilenameMatch
                    # Glob pattern: match against the relative path
                    occursin(p, rpath) || (isdir(path) && occursin(p, rpath_dir))
                else
                    # String directory prefix (e.g. "script/experiment/"):
                    # exclude if the relative path starts with the prefix.
                    # Only match the rpath_dir form for actual directories,
                    # to avoid "foo.csv/" matching a FILE named "foo.csv".
                    startswith(rpath, p) || (isdir(path) && startswith(rpath_dir, p))
                end
            end
        )
    end
end

# Glob.jl assumes that path separators are unix-y forward slashes (consistent with
# e.g. .gitignore files). But so for those to properly match on windows, we need to
# essentially convert paths on Windows into unix paths.
sanitize_windows_path(path) = Sys.iswindows() ? replace(path, '\\' => '/') : path
