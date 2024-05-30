const _DOCS_nondynamic_job_object_warning_fn = """
!!! warning "Non-dynamic job objects"

    [`Job`](@ref) objects represents the jobs when the objects were created (e.g. by a
    [`job`](@ref) function) and are not automatically kept up to date. As such, the result
    from this function may not represent the current _live_ state of the job. To refresh
    the job information, you can pass the existing [`Job`](@ref) to [`JuliaHub.job`](@ref)
    before passing it to this function.
"""

const _DOCS_nondynamic_job_object_warning = """
!!! warning "Non-dynamic job objects"

    [`Job`](@ref) objects represents the jobs when the objects were created (e.g. by a
    [`job`](@ref) function) and are not automatically kept up to date. To refresh
    the job information, you can pass the existing [`Job`](@ref) to [`JuliaHub.job`](@ref)
    before passing it to this function.
"""

"""
    struct JobFile

A reference to a job input or output file, with the following properties:

- `.name :: String`: the name of the [`Job`](@ref) this file is attached to
- `.type :: Symbol`: indicated the file type (see below)
- `.filename :: String`: file name
- `.size :: Int`: size of the file in bytes (reported to be zero in cases where the file contents is missing)
- `.hash :: Union{FileHash, Nothing}`: a [`FileHash`](@ref) object containing the file hash, but may
  also be missing (`nothing`) in some cases, like when the file upload has not completed yet.

The file is uniquely identified by the `(job, type, filename)` triplet.

The type of the file should be one of:

- `:input`: various job input files, which includes code, environment, and appbundle files.
- `:source`: source
- `:project`: Julia project environment files (e.g. `Project.toml`, `Manifest.toml`, `Artifacts.toml`)
- `:result`: output results file, defined via the `RESULTS_FILE` environment variable in the job

Note that some files are duplicated under multiple categories.

See also: [`Job`](@ref), [`job_files`](@ref), [`job_file`](@ref).

$(_DOCS_no_constructors_admonition)
"""
struct JobFile
    jobname::String
    type::Symbol
    filename::String
    size::Int
    hash::Union{FileHash, Nothing}
    _upload_timestamp::String

    function JobFile(jobname::AbstractString, jf::AbstractDict; var)
        filehash = let hash = _json_get(jf, "hash", Dict; var)
            hash_algorithm = _json_get(hash, "algorithm", Union{String, Nothing}; var)
            hash_value = _json_get(hash, "value", Union{String, Nothing}; var)
            if isnothing(hash_algorithm) || isnothing(hash_value)
                nothing
            else
                FileHash(hash_algorithm, hash_value)
            end
        end
        # It is possible to the 'size' field to be 'null', which normally indicates that
        # the file has not actually been uploaded yet. Defaulting the file size to zero bytes.
        file_size = something(_json_get(jf, "size", Union{Int, Nothing}; var), 0)
        new(
            jobname,
            Symbol(_json_get(jf, "type", String; var)),
            _json_get(jf, "name", String; var),
            file_size,
            filehash,
            # this is not exported, so let's not throw if it's missing:
            get(jf, "upload_timestamp", ""),
        )
    end
end

Base.show(io::IO, jf::JobFile) = print(
    io,
    "JuliaHub.job_file(JuliaHub.job(\"$(jf.jobname)\"), :",
    jf.type,
    ", \"",
    jf.filename,
    "\")",
)

function Base.show(io::IO, ::MIME"text/plain", jf::JobFile)
    printstyled(io, "JuliaHub.JobFile"; bold=true)
    file_size = isnothing(jf.hash) && (jf.size == 0) ? "missing data" : string(jf.size, " bytes")
    println(io, " ", jf.filename, " (", jf.jobname, ", :", jf.type, ", ", file_size, ")")
    if !isnothing(jf.hash)
        println(io, string(jf.hash.algorithm), ":", Base64.base64encode(jf.hash.hash))
    end
    print(io, "Uploaded: ", jf._upload_timestamp)
end

const _KNOWN_VALID_JOB_STATES = (
    "Submitted",
    "Running",
    "Failed",
    "Stopped",
    "Completed",
)
const _OTHER_JOB_STATES = String[]

# This const here is just to work around a syntax highlighter bug:
# https://github.com/julia-vscode/julia-vscode/issues/3258
const _KNOWN_VALID_JOB_STATES_STRING = join(("`$s`" for s in _KNOWN_VALID_JOB_STATES), ", ")
"""
    struct JobStatus

Type of the `.status` field of a [`Job`](@ref) object, representing the current state
of the job. Should be one of: $(_KNOWN_VALID_JOB_STATES_STRING).

In practice, the `.status` field should be treated as string and only used in string
comparisons.

See also: [`isdone`](@ref).

```jldoctest
julia> job = JuliaHub.job("jr-novcmdtiz6")
JuliaHub.Job: jr-novcmdtiz6 (Completed)
 submitted: 2023-03-15T07:56:50.974+00:00
 started:   2023-03-15T07:56:51.251+00:00
 finished:  2023-03-15T07:56:59.000+00:00
 files:
  - code.jl (input; 3 bytes)
  - code.jl (source; 3 bytes)
  - Project.toml (project; 244 bytes)
  - Manifest.toml (project; 9056 bytes)
 outputs: "{}"

julia> job.status == "Submitted"
false

julia> job.status == "Completed"
true
```

$(_DOCS_no_constructors_admonition)
"""
struct JobStatus
    status::String

    function JobStatus(status::AbstractString)
        if !(status in _KNOWN_VALID_JOB_STATES)
            if lowercase(strip(status)) in lowercase.(_KNOWN_VALID_JOB_STATES)
                throw(JuliaHubError("Invalid job status formatting: '$(status)'"))
            end
            if !(status in _OTHER_JOB_STATES)
                @warn "Unknown job state: $(status)"
                push!(_OTHER_JOB_STATES, status)
            end
        end
        new(status)
    end
end

Base.convert(::Type{JobStatus}, status::AbstractString) = JobStatus(status)
Base.convert(::Type{String}, js::JobStatus) = js.status

Base.show(io::IO, s::JobStatus) = print(io, '"', s.status, '"')
Base.print(io::IO, s::JobStatus) = print(io, s.status)

Base.:(==)(x::JobStatus, y::JobStatus) = (x.status == y.status)
function Base.:(==)(x::JobStatus, y::AbstractString)
    (y in _KNOWN_VALID_JOB_STATES) && return x.status == y
    # Handle invalid status values
    valid_lowercase = lowercase.(_KNOWN_VALID_JOB_STATES)
    idx = findfirst(isequal(lowercase(strip(y))), valid_lowercase)
    err_string = "Invalid job status string ($y) used in comparison."
    if isnothing(idx)
        @error err_string
    else
        valid = _KNOWN_VALID_JOB_STATES[idx]
        @error "$(err_string) Use '$(valid)'."
    end
    return false
end
Base.:(==)(x::AbstractString, y::JobStatus) = (y == x)
function Base.:(==)(::JobStatus, ::Symbol)
    @error "Comparing job statuses with Symbols not supported."
    return false
end
Base.:(==)(x::Symbol, y::JobStatus) = (y == x)

"""
    struct Job

Represents a single job submitted to JuliaHub. Objects have the following properties:

* `id :: String`: the unique, automatically generated ID of the job
* `alias :: String`: a non-unique, but descriptive alias for the job (often set by e.g. applications)
* `status :: JobStatus`: a string-like [`JobStatus`](@ref) object storing the state of the job
* `env :: Dict`: a dictionary of environment variables that were set when the job was submitted
* `results :: String`: the output value set via `ENV["RESULTS"]` (an empty string if it was not
  explicitly set)
* `files :: Vector{JobFiles}`: a list of [`JobFile`](@ref) objects, representing the input and
  output files of the job (see: [`job_files`](@ref), [`job_file`](@ref), [`download_job_file`](@ref)).
* `hostname :: Union{String, Nothing}`: for jobs that expose a port over HTTP, this will be set to the
  hostname of the job (`nothing` otherwise; see: [the relevant section in the manual](@ref jobs-batch-expose-port))

See also: [`job`](@ref), [`jobs`](@ref).

$(_DOCS_nondynamic_job_object_warning)

$(_DOCS_no_constructors_admonition)
"""
struct Job
    id::String
    alias::Union{String, Nothing}
    status::JobStatus
    env::Dict{String, Any}
    results::String
    files::Vector{JobFile}
    hostname::Union{String, Nothing}
    _timestamp_submit::Union{String, Nothing}
    _timestamp_start::Union{String, Nothing}
    _timestamp_end::Union{String, Nothing}
    _json::Dict

    function Job(j::AbstractDict)
        jobname = _json_get(j, "jobname", String; var="get_jobs")
        # We'll try to parse 'outputs' as a string, but
        var = "get_jobs/$jobname"
        outputs = _json_get(j, "outputs", String; var)
        # Inputs should always be valid JSON.. except under some unclear circumstances it
        # can also be Nothing (null?).
        inputs = _json_get(j, "inputs", Union{String, Nothing}; var)
        inputs = if isnothing(inputs)
            Dict{String, Any}() # TODO: drop Nothing?
        else
            try
                JSON.parse(unescape_string(inputs))
            catch e
                throw(
                    JuliaHubError("Unable to parse 'inputs' JSON for job $jobname:\n$(inputs)",
                        e, catch_backtrace(),
                    ),
                )
            end
        end
        hostname = let proxy_link = get(j, "proxy_link", "")
            if isempty(proxy_link)
                nothing
            else
                uri = URIs.URI(proxy_link)
                checks = (
                    uri.scheme == "https",
                    !isempty(uri.host),
                    isempty(uri.path) || uri.path == "/",
                    isempty(uri.query),
                    isempty(uri.fragment),
                )
                if !all(checks)
                    throw(
                        JuliaHubError(
                            "Unable to parse 'proxy_link' JSON for job $jobname:\n$(proxy_link)"
                        )
                    )
                end
                uri.host
            end
        end
        return new(
            jobname,
            _get_json_or(j, "jobname_alias", Union{String, Nothing}, nothing),
            JobStatus(_json_get(j, "status", String; var)),
            inputs,
            outputs,
            haskey(j, "files") ? JobFile.(jobname, j["files"]; var) : JobFile[],
            hostname,
            # Under some circumstances, submittimestamp can also be nothing, even though that is
            # weird.
            _json_get(j, "submittimestamp", Union{String, Nothing}; var), # TODO: drop Nothing?
            _json_get(j, "starttimestamp", Union{String, Nothing}; var),
            _json_get(j, "endtimestamp", Union{String, Nothing}; var),
            j,
        )
    end
end

Base.show(io::IO, job::Job) = print(io, "JuliaHub.job(\"", job.id, "\")")

function Base.show(io::IO, ::MIME"text/plain", job::Job)
    printstyled(io, "JuliaHub.Job"; bold=true)
    print(io, ": ", job.id, " (", job.status)
    if !isnothing(job.alias)
        print(io, "; \"")
        escape_string(io, job.alias)
        print(io, '"')
    end
    print(io, ")")
    print(io, '\n', " submitted: ", job._timestamp_submit)
    isnothing(job._timestamp_start) || print(io, '\n', " started:   ", job._timestamp_start)
    isnothing(job._timestamp_end) || print(io, '\n', " finished:  ", job._timestamp_end)
    isnothing(job.hostname) || print(io, '\n', " hostname:  ", job.hostname)
    # List of job files:
    if !isempty(job.files)
        print(io, '\n', " files: ")
        for file in job.files
            print(io, '\n', "  - ", file.filename, " (", file.type, "; ", file.size, " bytes)")
        end
    end
    if !isempty(job.env)
        print(io, '\n', " inputs: ")
        for (k, v) in job.env
            print(io, '\n', "  - ", k, ": ", v)
        end
    end
    if !isempty(job.results)
        print(io, '\n', " outputs: ", repr(job.results))
    end
end

"""
    const JobReference :: Type

A type constraint on the arguments of many jobs-related functions that is used to specify
the job. A job reference must be either a [`Job`](@ref) object, or an `AbstractString`
containing the unique job ID.
"""
const JobReference = Union{Job, AbstractString}

"""
    JuliaHub.isdone(::Job)

A helper function to check if a [`Job`](@ref) is "done", i.e. its status is one of `Completed`,
`Stopped`, or `Failed`.

$(_DOCS_nondynamic_job_object_warning_fn)
"""
isdone(job::Job) = job.status in ("Completed", "Stopped", "Failed")

"""
    JuliaHub.jobs(; [limit::Integer], [auth::Authentication]) -> Vector{Job}

Retrieve the list of jobs, latest first, visible to the currently authenticated user.

By default, JuliaHub only returns up to 20 jobs. However, this default limit can be overridden by
passing the `limit` keyword (which must be a positive integer).

$(_DOCS_nondynamic_job_object_warning)
"""
function jobs(; limit::Union{Integer, Nothing}=nothing, auth::Authentication=__auth__())
    isnothing(limit) || limit > 0 ||
        throw(DomainError(limit, "limit parameter must be a positive integer"))
    r = _jobs(auth, limit)
    if r.status == 200
        jobs_json, _ = _parse_response_json(r, Vector)
        return Job.(jobs_json)
    end
    _throw_invalidresponse(r)
end

function _jobs(auth::Authentication, limit::Union{Integer, Nothing}=nothing)
    query = isnothing(limit) ? (;) : (; limit)
    _restcall(auth, :GET, "juliaruncloud", "get_jobs"; query)
end

"""
    JuliaHub.job(job::JobReference; throw::Bool=true, [auth::Authentication]) -> Job

Fetch the details of a job based on the [job reference `ref`](@ref JobReference).
Will throw an [`InvalidRequestError`](@ref) if the job does not exist, or returns `nothing`
if `throw=false` is passed.

$(_DOCS_nondynamic_job_object_warning)
"""
function job end

function job(id::AbstractString; throw::Bool=true, auth::Authentication=__auth__())
    r = _restcall(auth, :GET, "api", "rest", "jobs", id; hasura=true)
    r.status == 200 || _throw_invalidresponse(r)
    job, json = _parse_response_json(r, Dict)
    details = get(job, "details") do
        Base.throw(JuliaHubError("Invalid JSON returned by the server:\n$(json)"))
    end
    if isempty(details)
        return _throw_or_nothing(; msg="Job '$(id)' does not exist.", throw)
    end
    length(details) > 1 &&
        Base.throw(JuliaHubError("Invalid JSON returned by the server:\n$(json)"))
    return Job(only(details))
end

job(j::Job; kwargs...) = job(j.id; kwargs...)

const _JOB_WAIT_DEFAULT_INTERVAL = 30

"""
    wait_job(
        job::AbstractString;
        interval::Integer = $(_JOB_WAIT_DEFAULT_INTERVAL), [auth::Authentication]
    ) -> Job

Blocks until remote job referred to by the [job reference `job`](@ref JobReference) has completed,
by polling it with every `interval` seconds. Returns an updated [`Job`](@ref) object.
"""
function wait_job end

wait_job(
    jobid::AbstractString;
    interval::Integer=_JOB_WAIT_DEFAULT_INTERVAL,
    auth::Authentication=__auth__(),
) = wait_job(job(jobid; auth); interval, auth)

function wait_job(
    j::Job; interval::Integer=_JOB_WAIT_DEFAULT_INTERVAL, auth::Authentication=__auth__()
)
    j = job(j; auth=auth)
    while !isdone(j)
        sleep(interval)
        j = JuliaHub.job(j; auth=auth)
    end
    return j
end

"""
    JuliaHub.job_files(job::Job, [filetype::Symbol]) -> Vector{JobFile}

Return the list of inputs and/or output files associated `job`.

The optional `filetype` argument should be one of `:input`, `:source`, `:result` or `:project`,
and can be used to filter the file list down to either just job input files (such as the
appbundle or Julia environment files), or output files (such as the one uploaded via
`RESULTS_FILE`).

Note: `job_file(job)` is equivalent to `job.files`, and the latter is preferred. This function
is primarily meant to be used when filtering by file type.

See also: [`Job`](@ref).
"""
function job_files(job::Job, filetype::Union{Symbol, Nothing}=nothing)
    isnothing(filetype) && return job.files
    if !_known_jobfile_type(filetype, job)
        @warn "Filtering for an unknown JuliaHub job output file type: :$(filetype)" known_types =
            _KNOWN_JOB_FILE_TYPES
    end
    return filter(jf -> jf.type == filetype, job.files)
end
const _KNOWN_JOB_FILE_TYPES = (:input, :project, :source, :result)
# Checks if the job file type is a known one, so that we could warn in job_files()
function _known_jobfile_type(type::Symbol, job::Job)
    # First, we check the basic ones (_KNOWN_JOB_FILE_TYPES).
    (type in _KNOWN_JOB_FILE_TYPES) && return true
    # However, as a fallback, we also allow for any types that
    # the job has, in case the JuliaHub backend has added file types.
    return any(isequal(type), jf for jf in job.files)
end

"""
    JuliaHub.job_file(job::Job, type::Symbol, filename::AbstractString) -> JobFile | Nothing

Searches for a job output file of a specified type and with the specific filename for
job `job`, or `nothing` if the file was not found.

`type` should be one of the standard job file types. See [`JobFile`](@ref) and
[`job_files`](@ref) for more information.
"""
function job_file(job::Job, filetype::Symbol, filename::AbstractString)
    if !_known_jobfile_type(filetype, job)
        @warn "Unknown JuliaHub job output file type: :$(filetype)" known_types =
            _KNOWN_JOB_FILE_TYPES
    end
    idx = findfirst(jf -> (jf.type == filetype) && (jf.filename == filename), job.files)
    isnothing(idx) ? nothing : job.files[idx]
end

"""
    JuliaHub.download_job_file(file::JobFile, path::AbstractString; [auth]) -> String
    JuliaHub.download_job_file(file::JobFile, io::IO; [auth])

Downloads a [`JobFile`](@ref) to a local path. Alternative, writeable stream object can be
passed as the second argument to write the contents directly into the stream.

When a local path is passed, it returns the path (which can be useful when calling the function
as e.g. `JuliaHub.download_job_file(file, tempname()))`). When an `IO` object is passed, it
returns `nothing`.

For example, to download a file into a temporary file:

```jldoctest download; setup = :(using SHA: sha2_256; Main.setup_job_results_file!()), filter=r"/tmp/[A-Za-z0-9_]+"
julia> file = JuliaHub.job_file(JuliaHub.job("jr-eezd3arpcj"), :result, "outdir.tar.gz")
JuliaHub.JobFile outdir.tar.gz (jr-eezd3arpcj, :result, 632143 bytes)
sha2_256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
Uploaded: 2023-03-15T07:59:29.473898+00:00

julia> tmp = tempname()
"/tmp/jl_nE3uvkZwvC"

julia> JuliaHub.download_job_file(file, tmp)
"/tmp/jl_BmHgj8rQXe"

julia> bytes2hex(open(sha2_256, tmp))
"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
```

Alternatively, you can also download the file into a writable `IO` stream, such
as `IOBuffer`:

```jldoctest download
julia> buffer = IOBuffer();

julia> JuliaHub.download_job_file(file, buffer)

julia> bytes2hex(sha2_256(take!(buffer)))
"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
```

See also: [`Job`](@ref), [`JobFile`](@ref).
"""
function download_job_file end

function download_job_file(file::JobFile, io::IO; auth::Authentication=__auth__())
    Mocking.@mock _download_job_file(auth, file, io)
    return nothing
end

function download_job_file(file::JobFile, path::AbstractString; auth::Authentication=__auth__())
    path = abspath(path)
    ispath(path) && throw(ArgumentError("Destination file already exists: $(path)"))
    isdir(dirname(path)) || mkpath(dirname(path))
    open(path, "w") do io
        Mocking.@mock _download_job_file(auth, file, io)
    end
    return path
end

# Internal, mockable version of download_job_file
function _download_job_file(auth::Authentication, file::JobFile, io::IO)
    job_file_url = _url(
        auth, "jobs", file.jobname, "files", file.filename; filetype=string(file.type)
    )
    r = @_httpcatch HTTP.get(
        job_file_url,
        _authheaders(auth);
        status_exception=false,
        response_stream=io,
    )
    r.status == 200 || _throw_invalidresponse(r)
    return nothing
end

"""
    JuliaHub.kill_job(job::JobRefererence; [auth::Authentication]) -> Job

Stop the job referred to by the [job reference `ref`](@ref JobReference).
Returns the updated [`Job`](@ref) object.

See also: [`Job`](@ref).
"""
function kill_job end

kill_job(job::Job; auth::Authentication=__auth__()) = kill_job(job.id; auth)

function kill_job(jobname::AbstractString; auth::Authentication=__auth__())
    r = _restcall(auth, :GET, "juliaruncloud", "kill_job"; query=(; jobname=string(jobname)))
    if r.status == 200
        response, json = _parse_response_json(r, Dict)
        # response_json["status"] might not be a Bool
        if get(response, "status", false) != true
            throw(JuliaHubError("Unexpected JSON returned by the server\n$(json)"))
        end
        return job(jobname; auth)
    elseif r.status == 403
        # Non-existing jobs make the endpoint return a 403
        @debug "403 from /juliaruncloud/kill_job:\n$(r.body)"
        throw(InvalidRequestError("$(jobname) does not exist"))
    end
    _throw_invalidresponse(r)
end

"""
    JuliaHub.extend_job(job::JobReference, extension::Limit; [auth::Authentication]) -> Job

Extends the time limit of the job referred to by the [job reference `ref`](@ref JobReference) by
`extension` (`Dates.Period`, or `Integer` number of hours). Returns an updated [`Job`](@ref) object.

See [`Limit`](@ref) for more information on how the `extension` argument is interpreted. Note that
[`Unlimited`](@ref) is not allowed as `extension`.

See also: [`Job`](@ref).
"""
function extend_job end

extend_job(job::Job, extension::Limit; auth::Authentication=__auth__()) =
    extend_job(job.id, extension; auth=auth)

function extend_job(jobname::AbstractString, extension::Limit; auth::Authentication=__auth__())
    if extension isa Unlimited
        throw(ArgumentError("extension argument to extend_job can not be Unlimited"))
    end
    payload = JSON.json(
        Dict(
            "jobname" => jobname,
            "extendby" => _nhours(@_timelimit(extension)),
        ),
    )
    r = _restcall(auth, :POST, ("juliaruncloud", "extend_job_time_limit"), payload)
    if r.status == 200
        response, json = _parse_response_json(r, Dict)
        success = get(response, "success", nothing)
        message = get(response, "message", "")
        if success === true
            return job(jobname; auth)
        elseif success === false && startswith(message, "Invalid jobname")
            # In some cases the endpoint returns a 200 with an error instead when
            # the user is requesting a non-existent job.
            throw(InvalidRequestError("$(jobname) does not exist"))
        else
            throw(JuliaHubError("Unexpected JSON returned by the server\n$(json)"))
        end
    elseif r.status == 403
        # Non-existing jobs make the endpoint return a 403
        @debug "403 from /juliaruncloud/extend_job_time_limit:\n$(r.body)"
        throw(InvalidRequestError("$(jobname) does not exist"))
    end
    _throw_invalidresponse(r)
end
