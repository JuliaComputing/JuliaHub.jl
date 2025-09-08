# This object can be used to submit requests against the legacy /juliaruncloud/submit_job
# endpoint.
struct _JobSubmission1
    # User code & app configuration
    appType::Union{String, Nothing} # defaults to 'batch'
    appArgs::Union{String, Nothing}
    args::String
    projectid::Union{String, Nothing}
    ## batch jobs
    customcode::String
    usercode::Union{String, Nothing}
    projecttoml::Union{String, Nothing}
    manifesttoml::Union{String, Nothing}
    ## appbundle
    appbundle::Union{String, Nothing}
    appbundle_upload_info::Union{String, Nothing}
    ## package jobs (appType=userapp)
    registry_name::Union{String, Nothing}
    package_name::Union{String, Nothing}
    branch_name::Union{String, Nothing}
    git_revision::Union{String, Nothing}
    # Job image configuration
    product_name::Union{String, Nothing}
    image::Union{String, Nothing}
    image_tag::Union{String, Nothing}
    image_sha256::Union{String, Nothing}
    sysimage_build::Union{String, Nothing}
    sysimage_manifest_sha::Union{String, Nothing}
    # Job hardware configuration
    node_class::String
    cpu::String
    nworkers::String
    elastic::Union{String, Nothing}
    min_workers_required::Union{String, Nothing}
    isthreaded::String
    limit_type::String
    limit_value::Union{String, Nothing}
    # These values must be set in the request, but values are pretty much ignored
    # on the backend. Except in 6.0.
    effective_time_limit::Union{String, Nothing}

    function _JobSubmission1(;
        # User code arguments
        appType::Union{AbstractString, Nothing}=nothing,
        appArgs::Union{Dict, Nothing}=nothing,
        args::Dict,
        projectid::Union{AbstractString, Nothing},
        customcode::Bool, usercode::Union{AbstractString, Nothing}=nothing,
        projecttoml::Union{AbstractString, Nothing}=nothing,
        manifesttoml::Union{AbstractString, Nothing}=nothing,
        appbundle::Union{AbstractString, Nothing}=nothing,
        appbundle_upload_info::Union{Dict, Nothing}=nothing,
        registry_name::Union{AbstractString, Nothing}=nothing,
        package_name::Union{AbstractString, Nothing}=nothing,
        branch_name::Union{AbstractString, Nothing}=nothing,
        git_revision::Union{AbstractString, Nothing}=nothing,
        # Job image configuration
        product_name::Union{AbstractString, Nothing}=nothing,
        image::Union{AbstractString, Nothing}=nothing,
        image_tag::Union{AbstractString, Nothing}=nothing,
        image_sha256::Union{AbstractString, Nothing}=nothing,
        sysimage_build::Union{Bool, Nothing}=nothing,
        sysimage_manifest_sha::Union{AbstractString, Nothing}=nothing,
        # Job hardware configuration
        node_class::AbstractString,
        cpu::Integer,
        nworkers::Integer,
        elastic::Union{Bool, Nothing}=nothing,
        min_workers_required::Union{Int, Nothing}=nothing,
        limit_type::AbstractString,
        limit_value::Union{Integer, Nothing},
        isthreaded::Bool,
    )
        cpu > 0 || throw(ArgumentError("Invalid value for 'cpu': $cpu"))
        if !(limit_type in ("time", "unlimited"))
            throw(ArgumentError("Invalid limit_type: '$limit_type'"))
        end
        if !isnothing(limit_value) && limit_value <= 0
            throw(ArgumentError("Invalid value for 'limit_value': $limit_value"))
        end
        nworkers >= 0 || throw(ArgumentError("Invalid value for 'nworkers': $nworkers"))
        customcode && isnothing(usercode) &&
            throw(ArgumentError("If `customcode` is set, `usercode` must be set."))
        args = JSON.json(Dict(string(k) => string(v) for (k, v) in args))
        if !isnothing(projectid) && isnothing(tryparse(UUIDs.UUID, projectid))
            throw(ArgumentError("Invalid projectid UUID: $(projectid)"))
        end
        !isnothing(image) && isempty(image) && throw(ArgumentError("Empty value for 'image'"))
        if !isnothing(min_workers_required) && (elastic === true)
            throw(ArgumentError("'min_workers_required' and 'elastic' must not both be specified"))
        end
        if !isnothing(min_workers_required) && !(0 <= min_workers_required < nworkers)
            e = "Invalid `min_workers_required` ($min_workers_required) (`nworkers=$nworkers`)"
            throw(ArgumentError(e))
        end
        if !isnothing(image_sha256) && !_isvalid_image_sha256(image_sha256)
            throw(ArgumentError("Invalid image_sha256: '$image_sha256'"))
        end
        if !isnothing(sysimage_manifest_sha) &&
            isnothing(match(r"^[0-9a-f]{64}$", sysimage_manifest_sha))
            throw(ArgumentError("Invalid sysimage_manifest_sha: '$sysimage_manifest_sha'"))
        end
        # appbundle validation & processing
        if isnothing(appbundle)
            isnothing(appbundle_upload_info) || throw(
                ArgumentError(
                    "Either both appbundle & appbundle_upload_info must be set or unset."
                ),
            )
        else
            isnothing(appbundle_upload_info) && throw(
                ArgumentError(
                    "Either both appbundle & appbundle_upload_info must be set or unset."
                ),
            )
            appbundle == "__APPBUNDLE_EXTERNAL_UPLOAD__" ||
                throw(ArgumentError("Only external uploads supported"))
            for k in ("file_type", "file_name", "hash", "hash_alg")
                _check_key(
                    appbundle_upload_info, k, AbstractString; varname="appbundle_upload_info"
                )
            end
            _check_key(
                appbundle_upload_info, "file_size", Integer; varname="appbundle_upload_info"
            )
            appbundle_upload_info = JSON.json(appbundle_upload_info)
        end
        limit_value = isnothing(limit_value) ? nothing : string(limit_value)
        appArgs = isnothing(appArgs) ? nothing : JSON.json(appArgs)
        # Create the _JobSubmission1 object
        new(
            # User code & app configuration
            appType, appArgs, args, projectid,
            ## batch job configuration
            string(customcode),
            usercode,
            projecttoml,
            manifesttoml,
            ## appbundles
            appbundle, appbundle_upload_info,
            registry_name, package_name, branch_name, git_revision,
            # Job image configuration
            product_name, image, image_tag, image_sha256,
            string(sysimage_build), sysimage_manifest_sha,
            # Compute configuration
            node_class, string(cpu),
            string(nworkers), _string_or_nothing(elastic), _string_or_nothing(min_workers_required),
            string(isthreaded),
            limit_type, limit_value, limit_value,
        )
    end
end

# The image_sha256 value must be a string of the form `sha256:(SHA256 hash in hex)`
function _isvalid_image_sha256(image_sha256::AbstractString)
    return !isnothing(match(r"^sha256:[0-9a-f]{64}$", image_sha256))
end

_string_or_nothing(x) = isnothing(x) ? nothing : string(x)

function _check_key(d::Dict, key, ::Type{T}; varname) where {T}
    haskey(d, key) || throw(ArgumentError("Dictionary `$varname` is missing key `$key`."))
    isa(d[key], T) ||
        throw(ArgumentError("`$varname[\"$key\"]` is not `<: $T` (got `$(typeof(d[key]))`)."))
    return nothing
end

_job_params(j::_JobSubmission1) = Dict{String, Any}(
    # If any of the fields of _JobSubmission1 are set to `nothing`, we won't
    # include them in the request.
    (
        string(fieldname) => getfield(j, fieldname)
        for fieldname in fieldnames(typeof(j))
        if !isnothing(getfield(j, fieldname))
    )...,
    # These values must be set in the request, but are ignored by the backend.
    "est_cost" => "0",
)

function _submit_job(auth::Authentication, j::_JobSubmission1)
    params = _job_params(j)
    @debug """
    Submitting _JobSubmission1 with parameters:
    $(sprint(show, MIME("text/plain"), params))
    """
    r = _restcall(auth, :POST, ("juliaruncloud", "submit_job"), HTTP.Form(params))
    if r.status == 200
        r_json, _ = _parse_response_json(r, Dict)
        haskey(r_json, "success") && r_json["success"] || throw(JuliaHubError(
            """
            Invalid response JSON from JuliaHub:
            $(sprint(show, MIME("text/plain"), r_json))
            """,
        ))
        r_json["success"] || _throw_invalidresponse(r)
        return r_json["jobname"]
    end
    _throw_invalidresponse(r)
end

"""
    abstract type AbstractJobConfig

Abstract supertype of all application configuration types that can be passed to [`submit_job`](@ref)
for submission as a JuliaHub job. The package has built-in support for the following application
configurations:

* [`JuliaHub.BatchJob`](@ref)
* [`JuliaHub.ApplicationJob`](@ref)
* [`JuliaHub.PackageApp`](@ref)
"""
abstract type AbstractJobConfig end

# Some application need to perform additional processing during submission
# phase (e.g. appbundle upload). Returns the updated object.
_submit_preprocess(app::AbstractJobConfig; auth::Authentication) = app

# These values are re-used in submit_job
const _DEFAULT_ComputeConfig_nnodes = 1
const _DEFAULT_ComputeConfig_elastic = false
const _DEFAULT_ComputeConfig_process_per_node = true

"""
    struct ComputeConfig

This type encapsulates the configuration of a jobs's compute cluster, including the hardware
configuration and the cluster topology.

See also: [`submit_job`](@ref).

# Constructors

```julia
JuliaHub.ComputeConfig(
    node::NodeSpec;
    nnodes::Integer = 1,
    process_per_node::Bool = true,
    elastic::Bool = false,
)
```

* `node`: a [`NodeSpec`](@ref) object that specifies the hardware of a single node.

* `nnodes::Union{Integer, Tuple{Integer, Integer}} = 1`: specifies the number of nodes of type `node` that
  will be allocated. Alternatively, a two-integer tuple can also be passed, where the first value
  specifies the minimum number of nodes required to start a job. By default, a single-node job is
  started.

* `process_per_node::Bool = true`: if true, there will only be a single Julia process per _node_,
  and the total number of Julia processes will be `nnodes`. If set to `false`, however, each _core_
  on each node will be allocated a separate Julia process (running in an isolated container on the
  same node), and so the total number of Julia processes will be `nnodes × ncpu`, and it will essentially
  always be a multi-process job.

* `elastic::Bool = false`: if set, the job will be started in an elastic cluster mode. In this case,
  a minimum number of `nnodes` must not be passed.
"""
struct ComputeConfig
    node::NodeSpec
    process_per_node::Bool
    nnodes_min::Union{Int, Nothing}
    nnodes_max::Int
    elastic::Bool

    function ComputeConfig(
        node::NodeSpec;
        nnodes::Union{Integer, Tuple{Integer, Integer}}=_DEFAULT_ComputeConfig_nnodes,
        elastic::Bool=_DEFAULT_ComputeConfig_elastic,
        process_per_node::Bool=_DEFAULT_ComputeConfig_process_per_node,
    )
        nnodes_min, nnodes_max = if isa(nnodes, Integer)
            nnodes >= 1 || throw(ArgumentError("Invalid 'nnodes' value '$nnodes'"))
            nothing, nnodes
        else
            @assert nnodes isa Tuple
            if !(1 <= nnodes[1] < nnodes[2])
                throw(ArgumentError("Invalid 'nnodes' tuple '$nnodes'"))
            end
            if elastic
                e = "'elastic=true' and minum 'nnodes' can not be specified simultaneously"
                throw(ArgumentError(e))
            end
            nnodes
        end
        new(node, process_per_node, nnodes_min, nnodes_max, elastic)
    end
end

function Base.show(io::IO, c::ComputeConfig)
    print(io, typeof(c), "(", c.node, "; ")
    print(io, "nnodes = ")
    if !isnothing(c.nnodes_min)
        print(io, "(", c.nnodes_min, ", ", c.nnodes_max, ")")
    else
        print(io, c.nnodes_max)
    end
    print(io, ", ")
    print(io, "process_per_node = ", c.process_per_node, ", ")
    print(io, "elastic = ", c.elastic)
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", c::ComputeConfig)
    printstyled(io, typeof(c); bold=true)
    println(io)
    _print_indented(io, io -> show(io, MIME"text/plain"(), c.node); indent=1)
    println(io)
    println(io, " Process per node: ", c.process_per_node)
    println(io, " Number of nodes: ", c.nnodes_max)
    if !isnothing(c.nnodes_min)
        println(io, " Minimum number of nodes: ", c.nnodes_min)
    end
    c.elastic && println(io, " Elastic cluster mode: enabled")
end

struct _ScriptEnvironment
    project_toml::Union{String, Nothing}
    manifest_toml::Union{String, Nothing}
    artifacts_toml::Union{String, Nothing}

    function _ScriptEnvironment(;
        project::Union{AbstractString, Nothing}=nothing,
        manifest::Union{AbstractString, Nothing}=nothing,
        artifacts::Union{AbstractString, Nothing}=nothing,
    )
        _check_toml_parse("project", project)
        _check_toml_parse("manifest", manifest)
        _check_toml_parse("artifacts", artifacts)
        new(project, manifest, artifacts)
    end
end
_sysimage_manifest_sha(e::_ScriptEnvironment) =
    isnothing(e.manifest_toml) ? nothing : bytes2hex(SHA.sha2_256(e.manifest_toml))

struct _AppBundleEnvironment
    tarball_path::String
    manifest_sha256::Union{String, Nothing}

    function _AppBundleEnvironment(
        path::AbstractString; manifest_sha256::Union{AbstractString, Nothing}
    )
        isfile(path) || throw(ArgumentError("Tarball does not exist: $(path)"))
        new(path, manifest_sha256)
    end
end
_sysimage_manifest_sha(e::_AppBundleEnvironment) = e.manifest_sha256

# Note: if this is extended, _sysimage_manifest_sha must be implemented for the
# new _BatchJobEnvironment.
const _BatchJobEnvironment = Union{_ScriptEnvironment, _AppBundleEnvironment}

const _DEFAULT_BatchJob_image = nothing
const _DEFAULT_BatchJob_sysimage = false

"""
    struct BatchJob <: AbstractJobConfig

Represents the application configuration of a JuliaHub batch job. A batch job is defined
by the following information:

* The Julia code that is to be executed in the job.
* Julia package environment (i.e. `Project.toml`, `Manifest.toml`) and other files,
  such as the appbundle.
* The underlying batch job container image (see also [`batchimages`](@ref)), which defaults
  to the standard Julia image by default.

Instances of this types should normally not be constructed directly, and the following functions
should be used instead:

* [`script`](@ref) or [`@script_str`](@ref): for submitting simple Julia scripts or code
  snippets
* [`appbundle`](@ref): for submitting more complex "appbundles" that include additional
  file, private or modified package dependencies etc.

# Optional arguments

* `image  :: Union{BatchImage, Nothing}`: can be used to specify which product's batch job image
  will be used when running the job, by passing the appropriate [`BatchImage`](@ref) object
  (see also: [`batchimage`](@ref) and [`batchimages`](@ref)). If set to `$(_DEFAULT_BatchJob_image)`
  (the default), the job runs with the default Julia image.

* `sysimage :: Bool`: if set to `true`, requests that a system image is built from the job's
  `Manifest.toml` file before starting the job. Defaults to `$(_DEFAULT_BatchJob_sysimage)`.

!!! compat "JuliaHub compatibility"

    The `sysimage = true` option requires JuliaHub 6.3 to have an effect. When running against
    older JuliaHub versions, it does not have an effect.

# Constructors

```julia
BatchJob(::BatchJob; [image::BatchImage], [sysimage::Bool]) -> BatchJob
```

Construct a [`BatchJob`](@ref), but override some of the optional arguments documented above.
When the argument is omitted, the value from the underlying [`BatchJob`](@ref) object is used.
This is the only constructor that is part of the public API.

This method is particularly useful when used in in combination with the [`@script_str`](@ref)
string macro, to be able to specify the job image or trigger a sysimage build. For example,
the following snippet will set a different batch image for the script-type job:

```julia
JuliaHub.BatchJob(
    JuliaHub.script\"""
    @info "Hello World"
    \""",
    image = JuliaHub.batchimage("...")
)
```
"""
struct BatchJob <: AbstractJobConfig
    environment::_BatchJobEnvironment
    code::String
    image::Union{BatchImage, Nothing}
    sysimage::Bool

    # Private constructor
    function BatchJob(
        environment::_BatchJobEnvironment, code::String;
        image::Union{BatchImage, Nothing}=_DEFAULT_BatchJob_image,
        sysimage::Bool=_DEFAULT_BatchJob_sysimage,
    )
        # This can happen if the user constructs a script-type job without passing the manifest,
        # and then tries to enable sysimage (either in `script` or later with `BatchJob`).
        if sysimage && isnothing(_sysimage_manifest_sha(environment))
            throw(ArgumentError("Unable to construct a sysimage batch job without a Manifest.toml"))
        end
        new(environment, code, image, sysimage)
    end
end

# Public constructor
function BatchJob(
    batch::BatchJob;
    image::Union{BatchImage, Nothing, Missing}=missing,
    sysimage::Union{Bool, Missing}=missing,
)
    return BatchJob(
        batch.environment, batch.code;
        image=ismissing(image) ? batch.image : image,
        sysimage=ismissing(sysimage) ? batch.sysimage : sysimage,
    )
end

function Base.show(io::IO, ::MIME"text/plain", batch::BatchJob)
    printstyled(io, "JuliaHub.BatchJob:"; bold=true)
    print(io, "\ncode = ", '"'^3, '\n', batch.code)
    print(io, '"'^3)
    _batchcompute_env_show(io, batch.environment)
    if batch.sysimage
        print(io, "\nsysimage = ", _sysimage_manifest_sha(batch.environment))
    end
end

function _batchcompute_env_show(io::IO, script_env::_ScriptEnvironment)
    for s in (:project_toml, :manifest_toml, :artifacts_toml)
        toml = getproperty(script_env, s)
        isnothing(toml) && continue
        print(io, "\nsha256($s) = ")
        print(io, bytes2hex(SHA.sha256(toml)))
    end
end
function _batchcompute_env_show(io::IO, appbundle_env::_AppBundleEnvironment)
    hash = if isfile(appbundle_env.tarball_path)
        bytes2hex(open(SHA.sha256, appbundle_env.tarball_path))
    else
        "<APPBUNDLE MISSING: $(appbundle_env.tarball_path)>"
    end
    print(io, "\nsha256(appbundle) = ", hash)
end

"""
    JuliaHub.script(...) -> BatchJob

Constructs the configuration for a script-type batch job, returning the respective
[`BatchJob`](@ref) object that can then be passed to [`submit_job`](@ref).
A script-type batch job is defined by the following:

* A user-provided Julia script that gets executed on the server. Note that no validation
  of the input code is done.

* An optional Julia package environment (e.g. `Project.toml`, `Manifest.toml` and
  `Artifacts.toml`). If any of the TOML files are provided, they must parse as valid TOML
  files, but no further validation is done client-side.

  If the manifest is not provided, the project environment must be instantiated from scratch,
  generally pulling in the latest versions of all the dependencies (although `[compat]` sections
  are honored).

  It is also fine to omit the project file, and just provide the manifest, and the environment
  defined by the manifest still gets instantiated. If both are omitted, the job runs in an empty
  environment.

* A JuliaHub job image, which determines the container environment that will be used to execute
  the code in (see [`batchimage`](@ref), [`batchimages`](@ref), [`BatchImage`](@ref)). If omitted,
  the default Julia image is used.

See also the [`@script_str`](@ref) string macro to more easily submit simple scripts that are
defined in code.

# Methods

```julia
script(
    scriptfile::AbstractString;
    [project_directory::AbstractString], [image::BatchImage], [sysimage::Bool]
) -> BatchJob
```

Constructs a script-type batch job configuration the will execute the code in `scriptfile`.
Optionally, a path to a project environment directory can be passed via `project_directory`,
which will be searched for the environment TOML files, and a job image can be specified
via `image`.

```julia
script(;
    code::AbstractString,
    [project::AbstractString], [manifest::AbstractString], [artifacts::AbstractString],
    [image::BatchImage], [sysimage::Bool]
) -> BatchJob
```

A lower-level method that can be used to construct the script-type [`BatchJob`](@ref)
configuration directly in memory (i.e. without having to write out intermediate files).

The `code` keyword argument is mandatory and will specify contents of the Julia script that
gets executed on the server. The Julia project environment can be specified by passing the
contents of the TOML files via the corresponding arguments (`project`, `manifest`, `artifacts`).
The job image can be specified via `image`.

!!! note "Optional arguments"

    See [`BatchJob`](@ref) for a more thorough description of the optional arguments.
"""
function script end

function script(
    scriptfile::AbstractString;
    project_directory::Union{AbstractString, Nothing}=nothing,
    image::Union{BatchImage, Nothing}=_DEFAULT_BatchJob_image,
    sysimage::Bool=_DEFAULT_BatchJob_sysimage,
)
    isfile(scriptfile) || throw(ArgumentError("Invalid `scriptfile`: $(scriptfile)"))
    code = read(scriptfile, String)
    project, manifest, artifacts = if isnothing(project_directory)
        nothing, nothing, nothing
    else
        isdir(project_directory) ||
            throw(ArgumentError("Invalid `project_directory`: $(project_directory)"))
        _load_project_env(project_directory)
    end
    return BatchJob(_ScriptEnvironment(; project, manifest, artifacts), code; image, sysimage)
end

function script(;
    code::AbstractString,
    project::Union{AbstractString, Nothing}=nothing,
    manifest::Union{AbstractString, Nothing}=nothing,
    artifacts::Union{AbstractString, Nothing}=nothing,
    image::Union{BatchImage, Nothing}=_DEFAULT_BatchJob_image,
    sysimage::Bool=_DEFAULT_BatchJob_sysimage,
)
    return BatchJob(_ScriptEnvironment(; project, manifest, artifacts), code; image, sysimage)
end

function _load_project_env(d::AbstractString)
    @assert isdir(d)
    project = _load_project_env(d, "Project.toml")
    manifest = _load_project_env(d, "Manifest.toml")
    artifacts = _load_project_env(d, "Artifacts.toml")
    return project, manifest, artifacts
end

function _load_project_env(d::AbstractString, file::AbstractString)
    path = joinpath(d, file)
    isfile(path) ? read(path, String) : nothing
end

"""
    JuliaHub.@script_str -> JuliaHub.BatchJob

A string macro to conveniently construct a script-type batch job configuration
([`BatchJob`](@ref)) that can be submitted as a JuliaHub job.

```julia
script = JuliaHub.script\"""
@info "Hello World!"
\"""
```

This allows for an easy submission of simple single-script jobs to JuliaHub:

```julia
JuliaHub.submit_job(
    JuliaHub.script\"""
    @info "Hello World!"
    \"""
)
```

By default, the macro picks up the currently active Julia project environment
(via `Base.active_project()`), and attaches the environment `.toml` files to the script.
To disable this, you can call the macro with the `noenv` suffix, e.g.

```
script = JuliaHub.script\"""
@info "Hello World!"
\"""noenv
```

However, if your local environment has development dependencies, you likely need to use an
appbundle instead (see [`appbundle`](@ref)).

!!! note "Using a different job image"

    There is no way to specify the job image with the string macro, and it will use the default
    Julia image. To use a different job image, you should either use the [`script`](@ref) function,
    either by fully constructing the batch job configuration with the keyword arguments, or by
    using the `BatchJob(::BatchJob; image=...)` method.

    ```julia
    JuliaHub.submit_job(
        JuliaHub.BatchJob(
            JuliaHub.script\"""
            @info "Hello World!"
            \""",
            image = JuliaHub.batchimage(...)
        )
    )
    ```

    You can also use this pattern to set the `sysimage` option.
"""
macro script_str(s, suffix="")
    if suffix == "noenv"
        quote
            BatchJob(_ScriptEnvironment(), $(esc(s)))
        end
    elseif isempty(suffix)
        # Empty suffix => we pick up the current environment
        quote
            let project = dirname(Base.active_project())
                project, manifest, artifacts = if isdir(project)
                    _load_project_env(project)
                else
                    @warn "Currently active project does not exist on disk" dirname(
                        Base.active_project()
                    ) = project
                    nothing, nothing, nothing
                end
                BatchJob(_ScriptEnvironment(; project, manifest, artifacts), $(esc(s)))
            end
        end
    else
        error("Invalid macro suffix for JuliaHub.@script_str: $suffix")
    end
end

function _check_toml_parse(name::AbstractString, tomlcode::AbstractString)
    try
        TOML.parse(tomlcode)
    catch e
        isa(e, TOML.ParserError) || rethrow(e)
        throw(ArgumentError("""
        Invalid TOML code for: $name.
        $(sprint(showerror, e))"""))
    end
    return nothing
end
_check_toml_parse(::AbstractString, ::Nothing) = nothing

const _APPBUNDLE_MAX_SIZE = 2 * 2^30 # bytes

struct AppBundleSizeError <: JuliaHubException
    size_bytes::Int
    max_size_bytes::Int
end

function Base.show(io::IO, err::AppBundleSizeError)
    mib = 2^20
    size_MiB, max_size_MiB = round(err.size_bytes / mib; digits=2),
    round(err.max_size_bytes / mib; digits=2)
    print(
        io,
        "AppBundleSizeError: Bundle size of $(size_MiB) MiB exceeds limit of $(max_size_MiB) MiB.",
    )
end

"""
    JuliaHub.appbundle(
        directory::AbstractString, codefile::AbstractString;
        [image::BatchImage], [sysimage::Bool]
    ) -> BatchJob
    JuliaHub.appbundle(
        directory::AbstractString;
        code::AbstractString, [image::BatchImage], [sysimage::Bool]
    ) -> BatchJob

Construct an appbundle-type JuliaHub batch job configuration. An appbundle is a directory containing a Julia environment
that is bundled up, uploaded to JuliaHub, and then unpacked and instantiated as the job starts.

The primary, two-argument method will submit a job that runs a file from within the appbundle (specified by `codefile`,
which must be a path relative to the root of the appbundle).
The code that gets executed is read from `codefile`, which should be a path to Julia source file relative to `directory`.

```julia
JuliaHub.appbundle(@__DIR__, "my-script.jl")
```

Alternatively, if `codefile` is omitted, the code must be provided as a string via the `code` keyword argument.

```julia
JuliaHub.appbundle(
    @__DIR__,
    code = \"""
    @show ENV
    \"""
)
```

See [`BatchJob`](@ref) for a description of the optional arguments.

# Extended help

The following should be kept in mind about how appbundles are handled:

* The bundler looks for a Julia environment (i.e. `Project.toml` and/or `Manifest.toml` files)
  at the root of the directory. If the environment does not exist (i.e. the files are missing),
  the missing files are created. If the manifest is missing, then the environment is re-instantiated
  from scratch based on the contents of `Project.toml`. The generated files will also be left
  in the user-provided directory `directory`.

* Development dependencies of the environment (i.e. packages added with `pkg> develop` or
  `Pkg.develop()`) are also bundled up into the archive that gets submitted to JuliaHub
  (including any current, uncommitted changes).
  Registered packages are installed via the package manager via the standard environment
  instantiation, and their source code is not included in the bundle directly.

* You can use `.juliabundleignore` files to omit some files from the appbundle (secrets, large data files etc).
  See the [relevant section in the reference manual](@ref jobs-batch-juliabundleignore) for more details.

* When the JuliaHub job starts, the bundle is unpacked and the job's starting working directory
  is set to the root of the unpacked appbundle directory, and you can e.g. load the data from those
  files with just `read("my-data.txt", String)`.

  !!! compat "JuliaHub 6.2 and older"

      On some JuliaHub versions (6.2 and older), the working directory was set to the parent directory
      of unpacked appbundle (with the appbundle directory called `appbundle`), and so it was necessary
      to do `joinpath("appbundle", "mydata.dat")` to load files.

* When submitting appbundles with the two-argument `codefile` method, you can expect `@__DIR__` and
  `include` to work as expected.

  However, when submitting the Julia code as a string (via the `code` keyword argument), the behavior of
  `@__DIR__` and `include` should be considered undefined and subject to change in the future.

* The one-argument + `code` keyword argument method is a lower-level method, that more closely mirrors
  the underlying platform API. The custom code that is passed via `code` is sometimes referred to as the
  "driver script", and the two-argument method is implemented by submitting an automatically
  constructed driver script that actually loads the specified file.

!!! compat "Deprecation: v0.1.10"

    As of JuliaHub.jl v0.1.10, the ability to launch appbundles using the two-argument method where
    the `codefile` parameter point to a file outside of the appbundle itself, is deprecated. You can still
    submit the contents of the script as the driver script via the `code` keyword argument.
"""
function appbundle end

function appbundle(
    bundle_directory::AbstractString;
    code::AbstractString,
    image::Union{BatchImage, Nothing}=_DEFAULT_BatchJob_image,
    sysimage::Bool=_DEFAULT_BatchJob_sysimage,
)
    _check_packagebundler_dir(bundle_directory)
    # The maximum size of appbundles is 2 GiB
    let (sz, smallenough) = _max_appbundle_dir_size(
            bundle_directory; maxsize=_APPBUNDLE_MAX_SIZE
        )
        smallenough || throw(AppBundleSizeError(sz, _APPBUNDLE_MAX_SIZE))
    end
    bundle_tar_path = tempname()
    manifest_sha256 = _PackageBundler.bundle(
        bundle_directory; output=bundle_tar_path, force=true, allownoenv=true, verbose=false
    )
    return BatchJob(_AppBundleEnvironment(bundle_tar_path; manifest_sha256), code; image, sysimage)
end

function appbundle(bundle_directory::AbstractString, codefile::AbstractString; kwargs...)
    haskey(kwargs, :code) &&
        throw(ArgumentError("'code' keyword not supported if 'codefile' passed"))
    codefile_fullpath = abspath(bundle_directory, codefile)
    isfile(codefile_fullpath) ||
        throw(ArgumentError("'codefile' does not point to an existing file: $codefile_fullpath"))
    codefile_relpath = relpath(codefile_fullpath, bundle_directory)
    # It is possible that the user passes a `codefile` path that is outside of the appbundle
    # directory. This used to work back when `codefile` was just read() and submitted as the
    # code argument. So we still support this, but print a loud deprecation warning.
    if startswith(codefile_relpath, "..")
        @warn """
        Deprecated: codefile outside of the appbundle $(codefile_relpath)
        The support for codefiles outside of the appbundle will be removed in a future version.
        Also note that in this mode, the behaviour of @__DIR__, @__FILE__, and include() with
        a relative path are undefined.

        To avoid the warning, but retain the old behavior, you can explicitly pass the code
        keyword argument instead of `codefile`:

        JuliaHub.appbundle(
            bundle_directory;
            code = read(joinpath(bundle_directory, codefile), String),
            kwargs...
        )
        """
        appbundle(bundle_directory; kwargs..., code=read(codefile_fullpath, String))
    else
        # TODO: we could check that codefile actually exists within the appbundle tarball
        # (e.g. to also catch if it is accidentally .juliabundleignored). This would require
        # Tar.list-ing the bundled tarball, and checking that the file is in there.
        driver_script = replace(
            _APPBUNDLE_DRIVER_TEMPLATE,
            "{PATH_COMPONENTS}" => _tuple_encode_path_components(codefile_relpath),
        )
        appbundle(bundle_directory; kwargs..., code=driver_script)
    end
end

# We'll hard-code the file path directly into the driver script as string literals.
# We trust here that repr() will take care of any necessary escaping of the path
# components. In the end, we'll write the path "x/y/z" into the file as
#
#   "x", "y", "z"
#
# Note: splitting up the path into components also helps avoid any cross-platform
# path separator issues.
_tuple_encode_path_components(path) = join(repr.(splitpath(path)), ",")

const _APPBUNDLE_DRIVER_TEMPLATE = read(abspath(@__DIR__, "appbundle-driver.jl"), String)

function _upload_appbundle(appbundle_tar_path::AbstractString; auth::Authentication)
    isfile(appbundle_tar_path) ||
        throw(ArgumentError("Appbundle file missing: $(appbundle_tar_path)"))
    upload_url, appbundle_params = _get_appbundle_upload_url(auth, appbundle_tar_path)
    r::_RESTResponse = open(appbundle_tar_path, "r") do input
        Mocking.@mock _restput_mockable(
            upload_url,
            ["Content-Length" => filesize(appbundle_tar_path)],
            input,
        )
    end
    # The response body of a successful upload is empty
    r.status == 200 || _throw_invalidresponse(r; msg="Unable to upload appbundle to JuliaHub.")
    return appbundle_params
end

# Fetches and returns the pre-signed upload URL for appbundle uploads
function _get_appbundle_upload_url(auth::Authentication, appbundle_tar_path::AbstractString)
    appbundle_params = Dict{String, Any}(
        "file_type" => "input",
        "file_name" => "appbundle.tar",
        "file_size" => filesize(appbundle_tar_path),
        "hash" => bytes2hex(open(SHA.sha2_256, appbundle_tar_path)),
        "hash_alg" => "sha2_256",
    )
    r = _restcall(auth, :GET, "jobs", "appbundle_upload_url"; query=appbundle_params)
    r.status == 200 || _throw_invalidresponse(r; msg="Unable to upload appbundle to JuliaHub.")
    r_json, _ = _parse_response_json(r, Dict)
    _get_json(r_json, "success", Bool) ||
        _throw_invalidresponse(r; msg="Unable to upload appbundle to JuliaHub.")
    message = _get_json(r_json, "message", Dict)
    upload_url = _get_json(message, "upload_url", AbstractString)
    return upload_url, appbundle_params
end

"""
    struct PackageJob <: AbstractJobConfig

[`AbstractJobConfig`](@ref) that wraps a [`PackageApp`](@ref) or [`UserApp`](@ref).
This is primarily used internally and should rarely be constructed explicitly.

# Constructors

```julia
JuliaHub.PackageJob(app::Union{JuliaHub.PackageApp,JuliaHub.UserApp}; [sysimage::Bool = false])
```

Can be used to construct a [`PackageApp`](@ref) or [`UserApp`](@ref) based job, but allows for some
job parameters to be overridden. Currently, only support the enabling of a system image based job
by setting `sysimage = true`.

```jldoctest; setup = :(Main.MOCK_JULIAHUB_STATE[:jobs] = Dict("jr-xf4tslavut" => Dict("status" => "Submitted","files" => [],"outputs" => "")))
julia> app = JuliaHub.application(:package, "RegisteredPackageApp")
PackageApp
 name: RegisteredPackageApp
 uuid: db8b4d46-bfad-4aa5-a5f8-40df1e9542e5
 registry: General (23338594-aafe-5451-b93e-139f81909106)

julia> JuliaHub.submit_job(JuliaHub.PackageJob(app; sysimage = true))
JuliaHub.Job: jr-xf4tslavut (Submitted)
 submitted: 2023-03-15T07:56:50.974+00:00
 started:   2023-03-15T07:56:51.251+00:00
 finished:  2023-03-15T07:56:59.000+00:00
```
"""
struct PackageJob <: AbstractJobConfig
    _app::Union{PackageApp, UserApp}
    name::String
    registry::Union{String, Nothing}
    jr_uuid::String
    args::Dict
    sysimage::Bool

    PackageJob(app::PackageApp; args::Dict=Dict(), sysimage::Bool=_DEFAULT_BatchJob_sysimage) =
        new(app, app.name, app._registry.name, string(app._uuid), args, sysimage)
    PackageJob(app::UserApp; args::Dict=Dict(), sysimage::Bool=_DEFAULT_BatchJob_sysimage) =
        new(app, app.name, nothing, app._repository, args, sysimage)
end

function _check_packagebundler_dir(bundlepath::AbstractString)
    isdir(bundlepath) ||
        throw(ArgumentError("Path can not be bundled into an appbundle: $bundlepath"))
    return nothing
end

function _check_job_args(args::Dict)
    for k in keys(args)
        isa(k, AbstractString) ||
            throw(
                ArgumentError(
                    "Job input argument keys must be strings, got '$(repr(k))' ($(typeof(k)))"
                ),
            )
    end
end

"""
    struct ApplicationJob <: AbstractJobConfig

[`AbstractJobConfig`](@ref) that wraps a [`DefaultApp`](@ref).
This is primarily used internally and should rarely be constructed explicitly.
"""
struct ApplicationJob <: AbstractJobConfig
    app::DefaultApp

    ApplicationJob(app::DefaultApp) = new(app)
end

"""
    struct Unlimited

An instance of this type can be passed as the [`timelimit`] option to [`submit_job`](@ref) to start
jobs that run indefinitely, until killed manually.

```julia
JuliaHub.submit_job(..., timelimit = JuliaHub.Unlimited())
```
"""
struct Unlimited end

"""
    JuliaHub.Limit

Type-constraint on JuliaHub job `timelimit` arguments in [`submit_job`](@ref).

The job time limit can either be a time period (an instance of `Dates.Period`), an `Integer`,
(interpreted as the number of hours), or [`JuliaHub.Unlimited()`](@ref JuliaHub.Unlimited).

Only an integer number of hours are accepted by JuliaHub, and fractional hours from get rounded up
to the next full integer number of hours (e.g. `Dates.Minute(90)` will be interpreted as 2 hours).
"""
const Limit = Union{Dates.Period, Integer, Unlimited}

# Internal function to convert ::Limit objects to a unified representation as
# Dates.Hour objects. Unlimited() values stay Unlimited.
function _timelimit(value::Dates.Hour; var::Symbol)
    if value <= Dates.Hour(0)
        throw(ArgumentError("Invalid `$(var)` value: $value"))
    end
    return value
end
function _timelimit(period::Dates.Period; var::Symbol)
    period_rounded = ceil(period, Dates.Hour)
    if period_rounded != period
        @warn "Non-integer number of hours in a job limit ($period) rounded up to $(period_rounded)."
    end
    return _timelimit(period_rounded; var)
end
_timelimit(value::Integer; var::Symbol) = _timelimit(Dates.Hour(value); var)
_timelimit(value::Unlimited; var::Symbol) = value
# Convenience macro for timelimit() that passes var= along automatically.
#
#   @_timelimit(foo) == _timelimit(foo; var=:foo)
macro _timelimit(var)
    @assert isa(var, Symbol)
    var_sym = Expr(:quote, var) # can't directly interpolate a Symbol
    :(_timelimit($(esc(var)); var=$(var_sym)))
end
_nhours(timelimit::Dates.Hour) = div(timelimit, Dates.Hour(1))

const _DEFAULT_WorkloadConfig_timelimit = Dates.Hour(1)

"""
    struct WorkloadConfig

Represents a full job configuration, including the application, compute and runtime configuration.

Instances of this type can be constructed by passing `dryrun = true` to [`submit_job`](@ref),
and can also be directly submitted to JuliaHub with the same function.
"""
struct WorkloadConfig
    app::AbstractJobConfig
    compute::ComputeConfig
    # Runtime configuration:
    alias::Union{String, Nothing}
    env::Dict{String, String}
    project::Union{UUIDs.UUID, Nothing}
    timelimit::Union{Dates.Hour, Unlimited}
    exposed_port::Union{Int, Nothing}
    # internal, undocumented, may be removed an any point, not part of the public API:
    _image_sha256::Union{String, Nothing}

    function WorkloadConfig(
        app::AbstractJobConfig, compute::ComputeConfig;
        alias::Union{String, Nothing}=nothing,
        env=(),
        project::Union{UUIDs.UUID, Nothing}=nothing,
        timelimit::Limit=_DEFAULT_WorkloadConfig_timelimit,
        expose::Union{Integer, Nothing}=nothing,
        # internal, undocumented, may be removed an any point, not part of the public API:
        _image_sha256::Union{AbstractString, Nothing}=nothing,
    )
        if !isnothing(_image_sha256) && !_isvalid_image_sha256(_image_sha256)
            Base.throw(
                ArgumentError(
                    "Invalid _image_sha256 value: '$_image_sha256', expected 'sha256:\$(hash)'"
                ),
            )
        end
        if !isnothing(expose) && !_is_valid_port(expose)
            Base.throw(
                ArgumentError(
                    "Invalid port value for expose: '$(expose)', must be in 1025:9008, 9010:23399, 23500:32767"
                ),
            )
        end
        new(
            app,
            compute,
            alias,
            Dict(string(k) => v for (k, v) in pairs(env)),
            project,
            @_timelimit(timelimit),
            expose,
            _image_sha256,
        )
    end
end

_is_valid_port(port::Integer) = any(
    portrange -> in(port, portrange),
    (1025:9008, 9010:23399, 23500:32767),
)

_is_gpu_job(workload::WorkloadConfig) = workload.compute.node.hasGPU

function Base.show(io::IO, ::MIME"text/plain", jc::WorkloadConfig)
    printstyled(io, "JuliaHub.WorkloadConfig:"; bold=true)
    println(io, "\napplication:")
    _print_indented(io, io -> show(io, MIME"text/plain"(), jc.app); indent=2)
    println(io, "\ncompute:")
    _print_indented(io, io -> show(io, MIME"text/plain"(), jc.compute); indent=2)
    isnothing(jc.alias) || print(io, "\nalias: $(jc.alias)")
    print(io, "timelimit = ", jc.timelimit, ", ")
    print(io, "\nenv: ")
    if isempty(jc.env)
        print(io, "∅")
    else
        for (k, v) in jc.env
            print(io, "\n  $k: $v")
        end
    end
    isnothing(jc.project) || print(io, "\nproject: $(jc.project)")
    if !isnothing(jc._image_sha256)
        print(io, "\n_image_sha256: ", jc._image_sha256)
    end
end

"""
    JuliaHub.submit_job(
        app::Union{AbstractJuliaHubApp, AbstractJobConfig},
        [compute::ComputeConfig];
        # Compute keyword arguments
        ncpu::Integer = 1, ngpu::Integer = 0, memory::Integer = 1,
        nnodes::Integer = 1, minimum_nnodes::Union{Integer,Nothing} = nothing,
        elastic::Bool = false,
        process_per_node::Bool = true,
        # Runtime configuration keyword arguments
        [alias::AbstractString], [env], [expose::Integer],
        [project::Union{UUID, AbstractString}], timelimit::Limit = Hour(1),
        # General keyword arguments
        dryrun::Bool = false,
        [auth :: Authentication]
    ) -> Job

Submits the specified application config `app` as a job to JuliaHub. Returns a [`Job`](@ref) object
corresponding to the submitted job.

**Compute arguments.** If `compute` is passed, the compute keyword arguments can not be passed.
If `compute` is not passed, the following arguments can be used to specify the compute configration
via keyword arguments:

* `ncpu`, `ngpu` and `memory` are used to pick a node type that will be used to run the job.
  The node type will be a minimum one that satisfies the constraints, but may have more compute
  resources than specified by the arguments (it corresponds to the `exactmatch = false` case of
  [`nodespec`](@ref)).

* `nnodes`, `minimum_nnodes`, `process_per_node`, and `elastic` specify the corresponding arguments
  in [`ComputeConfig`](@ref).

**Runtime configuration.** These are used to set the [Runtime configuration](@ref jobs-runtime-config)
of the job.

* `alias :: Union{AbstractString, Nothing}`: can be used to override the name of the job that gets displayed
  in the UI. Passing `nothing` is equivalent to omitting the argument.

* `timelimit :: Limit`: sets the job's time limit (see [`Limit`](@ref) for valid values)

* `env`: an iterable of key-value pairs that can be used to set environment variable that get set before,
  the job code gets executed.

* `project :: Union{UUID, AbstractString, Nothing}`: the UUID of the project that the job will be associated
  with. If a string is passed, it must parse as a valid UUID. Passing `nothing` is equivalent to omitting the
  argument.

* `expose :: Union{Integer, Nothing}`: if set to an integer in the valid port ranges, that port will be exposed
  over HTTPS, allowing for (authenticated) HTTP request to be performed against the job, as long as the job
  binds an HTTP server to that port. The allowed port ranges are `1025-9008``, `9010-23399`, `23500-32767`
  (in other words, `<= 1024`, `9009`, `23400-23499`, and `>= 32768` can not be used).
  [See the relevant manual section for more information.](@ref jobs-batch-expose-port)

**General arguments.**

$(_DOCS_authentication_kwarg)

* `dryrun :: Bool`: if set to true, `submit_job` does not actually submit the job, but instead
  returns a [`WorkloadConfig`](@ref) object, which can be used to inspect the configuration
  that would be submitted.

  The [`WorkloadConfig`](@ref) object can then be submitted to JuliaHub with the additional
  [`submit_job`](@ref) method:

  ```julia
  JuliaHub.submit_job(::WorkloadConfig; [auth::Authentication])
  ```

!!! compat "JuliaHub compatibility"

    The `timelimit = JuliaHub.Unlimited()` argument requires JuliaHub 6.3+.
"""
function submit_job end

function submit_job(app::AbstractJuliaHubApp, args...; kwargs...)
    appconfig = if app isa UserApp || app isa PackageApp
        PackageJob(app)
    elseif app isa DefaultApp
        ApplicationJob(app)
    else
        throw(ArgumentError("Unsupported app type $(typeof(app)): $(app)"))
    end
    return submit_job(appconfig, args...; kwargs...)
end

function submit_job(
    app::AbstractJobConfig;
    # Node & compute specification:
    ncpu::Integer=_DEFAULT_NodeSpec_ncpu,
    ngpu::Integer=_DEFAULT_NodeSpec_ngpu,
    memory::Integer=_DEFAULT_NodeSpec_memory,
    nnodes::Union{Integer, Tuple{Integer, Integer}}=_DEFAULT_ComputeConfig_nnodes,
    elastic::Bool=_DEFAULT_ComputeConfig_elastic,
    process_per_node::Bool=_DEFAULT_ComputeConfig_process_per_node,
    # General submit_job arguments
    auth::Authentication=__auth__(),
    kwargs...,
)
    n = nodespec(; ncpu, ngpu, memory, auth)
    c = ComputeConfig(n; nnodes, process_per_node, elastic)
    submit_job(app, c; auth, kwargs...)
end

function submit_job(
    app::AbstractJobConfig, compute::ComputeConfig;
    # Runtime configuration:
    name::Union{AbstractString, Nothing}=nothing, # deprecated
    alias::Union{AbstractString, Nothing}=nothing,
    env=(),
    project::Union{UUIDs.UUID, AbstractString, Nothing}=nothing,
    timelimit::Limit=_DEFAULT_WorkloadConfig_timelimit,
    expose::Union{Integer, Nothing}=nothing,
    # internal, undocumented, may be removed an any point, not part of the public API:
    _image_sha256::Union{AbstractString, Nothing}=nothing,
    # General submit_job arguments
    kwargs...,
)
    if !isnothing(name)
        isnothing(alias) || throw(ArgumentError("alias and (deprecated) name can not both be set"))
        @warn "The `name` argument to `submit_job` is deprecated and will be removed in 0.2.0"
        alias = name
    end
    project = if isa(project, AbstractString)
        project_uuid = tryparse(UUIDs.UUID, project)
        isnothing(project_uuid) &&
            throw(ArgumentError("Invalid UUID string for 'project': $(project)"))
        project_uuid
    else
        project
    end
    submit_job(
        WorkloadConfig(app, compute; alias, env, project, timelimit, expose, _image_sha256);
        kwargs...,
    )
end

function submit_job(
    c::WorkloadConfig;
    # General submit_job arguments
    dryrun::Bool=false,
    auth::Authentication=__auth__(),
)
    dryrun && return c

    app = _job_submit_args(auth, c, _submit_preprocess(c.app; auth), _JobSubmission1)
    compute = _job_submit_args(auth, c, c.compute, _JobSubmission1)

    # Merge the job name override into the env dictionary, if applicable.
    args::Dict = if haskey(c.env, "jobname")
        if isnothing(c.alias)
            @warn """
            'jobname' environment variable overrides the job name in the UI. Use the 'alias' argument
            in submit_job instead to set the job name.
            """
            c.env
        else
            throw(ArgumentError("'jobname' environment variable can not be set if job name is set"))
        end
    elseif !isnothing(c.alias)
        merge(c.env, Dict("jobname" => c.alias))
    else
        c.env
    end
    args = merge(
        # Note: we need to ::Dict type assertion here to avoid JET complaining with:
        # no matching method found `convert(::Type{Dict}, ::NamedTuple)`: convert(JuliaHub.Dict, _26::NamedTuple)
        get(app, :args, Dict())::Dict,
        args,
    )

    projectid = isnothing(c.project) ? nothing : string(c.project)

    limit_type, limit_value = if isa(c.timelimit, Unlimited)
        "unlimited", nothing
    else
        "time", _nhours(c.timelimit)
    end

    submission = _JobSubmission1(;
        compute..., app...,
        projectid, args,
        limit_type, limit_value,
        # if present in WorkloadConfig, we also pass image_sha256 along
        image_sha256=c._image_sha256,
    )
    jobname = _submit_job(auth, submission)
    return job(jobname; auth)
end

function _job_submit_args(
    auth::Authentication, workload::WorkloadConfig, c::ComputeConfig, ::Type{_JobSubmission1};
    kwargs...,
)
    return (;
        node_class=c.node.nodeClass,
        cpu=Int(c.node.vcores), # .vcores is a float
        # 'nworkers' in the API defined how many _extra_ nodes gets allocated
        nworkers=c.nnodes_max - 1,
        min_workers_required=isnothing(c.nnodes_min) ? nothing : c.nnodes_min - 1,
        elastic=c.elastic,
        isthreaded=c.process_per_node,
    )
end

function _job_submit_args(
    auth::Authentication, workload::WorkloadConfig, batch::BatchJob, ::Type{_JobSubmission1};
    kwargs...,
)
    image_args = if !isnothing(batch.image)
        image = if _is_gpu_job(workload)
            if isnothing(batch.image._gpu_image_key)
                throw(
                    InvalidRequestError(
                        "GPU job requested, but $(batch.image) does not support GPU jobs."
                    ),
                )
            end
            batch.image._gpu_image_key
        else
            if isnothing(batch.image._cpu_image_key)
                throw(
                    InvalidRequestError(
                        "CPU job requested, but $(batch.image) does not support CPU jobs."
                    ),
                )
            end
            batch.image._cpu_image_key
        end
        (;
            product_name=batch.image.product,
            image,
            image_tag=batch.image._image_tag,
            image_sha256=batch.image._image_sha,
        )
    else
        (;)
    end
    # Note: this set of arguments will also set product_name which must override the value
    # in `image_args`, achieved by splatting it later in the named tuple constructor below.
    exposed_port_args = if !isnothing(workload.exposed_port)
        product_name = if isnothing(batch.image)
            # If the image was not specified for the job submissions, we assume that the
            # corresponding interactive product is called 'standard-interactive' and that it
            # is available to the user (we can not verify that at this point anymore though).
            "standard-interactive"
        elseif isnothing(batch.image._interactive_product_name)
            throw(
                InvalidRequestError(
                    "Product '$(batch.image.product_name)' does not support exposing a port."
                ),
            )
        else
            batch.image._interactive_product_name
        end
        (;
            product_name,
            appArgs=Dict(
                "authentication" => true,
                "authorization" => "me",
                "port" => workload.exposed_port,
            ),
        )
    else
        (;)
    end
    sysimage_args = if batch.sysimage
        sysimage_manifest_sha = _sysimage_manifest_sha(batch.environment)
        if isnothing(sysimage_manifest_sha)
            throw(InvalidRequestError("Manifest.toml must be provided for a sysimage job"))
        end
        (; sysimage_build=true, sysimage_manifest_sha)
    else
        (;)
    end
    return (;
        _job_submit_args(auth, workload, batch, batch.environment, _JobSubmission1; kwargs...)...,
        image_args..., exposed_port_args..., sysimage_args...,
    )
end

function _job_submit_args(
    auth::Authentication,
    workload::WorkloadConfig,
    batch::BatchJob,
    ::_ScriptEnvironment,
    ::Type{_JobSubmission1};
    kwargs...,
)
    return (;
        customcode=true,
        usercode=batch.code,
        projecttoml=batch.environment.project_toml,
        manifesttoml=batch.environment.manifest_toml,
    )
end

function _job_submit_args(
    auth::Authentication,
    workload::WorkloadConfig,
    batch::BatchJob,
    ::_AppBundleEnvironment,
    ::Type{_JobSubmission1};
    kwargs...,
)
    appbundle_params = _upload_appbundle(batch.environment.tarball_path; auth)
    return (;
        customcode=true,
        usercode=batch.code,
        appbundle="__APPBUNDLE_EXTERNAL_UPLOAD__",
        appbundle_upload_info=appbundle_params,
    )
end

function _job_submit_args(
    auth::Authentication, workload::WorkloadConfig, packagejob::PackageJob, ::Type{_JobSubmission1};
    kwargs...,
)
    return (;
        appType="userapp",
        customcode=false,
        package_name=packagejob.name,
        registry_name=packagejob.registry,
        args=merge(
            Dict("jobname" => packagejob.name, "jr_uuid" => packagejob.jr_uuid),
            packagejob.args,
        ),
        # Just in case, we want to omit sysimage_build altogether when it is not requested.
        sysimage_build=packagejob.sysimage ? true : nothing,
    )
end

function _job_submit_args(
    auth::Authentication, workload::WorkloadConfig, appjob::ApplicationJob, ::Type{_JobSubmission1};
    kwargs...,
)
    return (;
        appType=appjob.app._apptype,
        appArgs=Dict("authentication" => true, "authorization" => "me"),
        customcode=false,
        # `jr_uuid` is set to associate the running job with the application icon in the UI
        args=Dict("jobname" => appjob.app.name, "jr_uuid" => appjob.app._apptype),
    )
end
