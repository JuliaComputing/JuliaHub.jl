abstract type _JobLoggingAPIVersion end

module _LoggingMode
@enum T NOKAFKA AUTOMATIC FORCEKAFKA
end
const _OPTION_LoggingMode = Ref{_LoggingMode.T}(_LoggingMode.NOKAFKA)

function _job_logging_api_version(
    auth::Authentication, jobname::AbstractString
)::_JobLoggingAPIVersion
    # For debugging, development, and testing purposes, we allow the user to force the
    # logging backend to use a particular endpoint. This is not a documented behaviour
    # and should not be relied on.
    if _OPTION_LoggingMode[] == _LoggingMode.NOKAFKA
        return _LegacyLogging()
    elseif _OPTION_LoggingMode[] == _LoggingMode.FORCEKAFKA
        return _KafkaLogging()
    elseif _OPTION_LoggingMode[] == _LoggingMode.AUTOMATIC
        query = Dict("jobname" => jobname)
        r = _restcall(auth, :HEAD, "juliaruncloud", "get_logs_v2"; query)
        # If HEAD /juliaruncloud/get_logs_v2 returns a 200, then we know we can try to fetch
        # the newer Kafka logs. If it returns anything else, we will try use the old endpoint.
        # However, it _should_ return a 404 in the latter case, and we'll warn if it returns a
        # different code.
        r.status == 200 && return _KafkaLogging()
        if r.status != 404
            @warn "Unexpected response from HEAD /juliaruncloud/get_logs_v2" r.status r.body
        end
        return _LegacyLogging()
    end
    error("Invalid _OPTION_LoggingMode: $(_OPTION_LoggingMode[])")
end

"""
    struct JobLogMessage

Contains a single JuliaHub job log message, and has the following fields:

* `timestamp :: Union{ZonedDateTime, Nothing}`: log message timestamp (in UTC)
* `message :: Union{String, Nothing}`: log message string. This generally corresponds
  to one line of printed output

Fields that can also be `nothing` may be missing for some log messages.

See also: [`job_logs`](@ref), [`job_logs_buffered`](@ref).

$(_DOCS_no_constructors_admonition)
"""
Base.@kwdef struct JobLogMessage
    _offset::Int
    timestamp::Union{TimeZones.ZonedDateTime, Nothing}
    message::Union{String, Nothing}
    _metadata::Dict{String, Any} # `metadata :: Dict{String, Any}`: additional metadata with not guaranteed fields; may also be empty (TODO)
    _keywords::Dict{String, Any} # `keywords :: Dict{String, Any}`: additional metadata with not guaranteed fields; may also be empty (TODO)
    _legacy_eventId::Union{String, Nothing}
    _kafka_stream::Union{String, Nothing}
    _json::Dict
end

function Base.show(io::IO, log::JobLogMessage)
    print(io, "JobLogMessage(ZonedDateTime(\"$(log.timestamp)\"), \"$(log.message)\", ...)")
end

_print_log_list(logs::Vector{JobLogMessage}; kwargs...) = _print_log_list(stdout, logs; kwargs...)
function _print_log_list(
    io::IO, logs::Vector{JobLogMessage}; all::Bool=false,
    nlines::Integer=_default_display_lines(io),
)
    @assert Base.all(x -> isa(x, JobLogMessage), logs) # note: kwarg shadows function
    @assert nlines >= 1
    isempty(logs) && return nothing
    logs_enumerated = if all || length(logs) <= nlines
        enumerate(logs)
    else
        nbefore, rem = divrem(nlines, 2)
        nafter = nbefore + rem
        logs = collect(enumerate(logs))
        vcat(
            @view(logs[1:nbefore]),
            (:skip, nothing),
            @view(logs[(end - nafter + 1):end])
        )
    end
    isfirst = true
    for (i, log) in logs_enumerated
        # This is to make sure we don't print a newline after the last print.
        if isfirst
            isfirst = false
        else
            println(io)
        end
        # If we're omitting some messages, we print ...
        if i == :skip
            print(io, " ...")
            continue
        end
        print(io, lpad(i, 5), ' ')
        if isnothing(log.message)
            print(io, '#')
        else
            print(io, "| ", log.message)
        end
    end
end
function _default_display_lines(io::IO; adjust=4, min_lines=6)
    # The default 'adjust' takes into account two prompts, the empty line
    # before the next prompt, and the ... skip line.
    nlines, _ = displaysize(io)
    return max(nlines - adjust, min_lines)
end

"""
    JuliaHub.job_logs(job; offset::Integer = 0, [limit::Integer], [auth::Authentication]) -> Vector{JobLogMessage}

Fetches the log messages for the specified JuliaHub job. The job is specifed by passing the
job name as a string, or by passing a [`Job`](@ref) object (i.e. `job::Union{AbstractString,Job}`).
Returns the log messages as an array of [`JobLogMessage`](@ref) objects.

Optionally, the function takes the following keyword arguments:

* `offset::Integer`: the offset of the first log message fetched (`0` corresponds to the first message);
  for the first method, this defaults to `0`; however, in the second (callback) case, if `offset` is not
  specified, any existing logs will be ignored.

* `limit::Integer`: the maximum number of messages fetched (all by default)

!!! note "No default limit"

    The `limit` keyword does not have a default limit, and so by default [`job_logs`](@ref) fetches all the
    log messages. This may take a while and require many requests to JuliaHub if the job has a huge number
    of log messages.
"""
function job_logs end

job_logs(job::Job; kwargs...) = job_logs(job.id; kwargs...)

function job_logs(
    jobname::AbstractString;
    offset::Integer=0,
    limit::Union{Integer, Nothing}=nothing,
    auth::Authentication=__auth__(),
)
    buffer = job_logs_buffered(jobname; offset, auth)
    JuliaHub.job_logs_newer!(buffer; count=limit, auth)
    return buffer.logs
end

struct _JobLogTask
    task::Task
    ch::Channel{Nothing}
end

function interrupt!(task::_JobLogTask; wait::Bool=true)::Nothing
    put!(task.ch, nothing)
    wait && Base.wait(task)
    return nothing
end

Base.wait(t::_JobLogTask) = wait(t.task)

"""
    abstract type AbstractJobLogsBuffer

Supertype of possible objects returned by [`job_logs_buffered`](@ref). See the [`job_logs_buffered`](@ref)
function for a description of the interface.
"""
abstract type AbstractJobLogsBuffer end

function Base.getproperty(jlb::AbstractJobLogsBuffer, s::Symbol)
    s == :logs && return _job_logs_active_logs(jlb)
    s == :_logs_as_view && return _job_logs_active_logs_view(jlb)
    return getfield(jlb, s)
end
function Base.propertynames(jlb::AbstractJobLogsBuffer, private::Bool=false)
    private = true # TODO
    if private
        (:logs, :_logs_as_view, fieldnames(typeof(jlb))...)
    else
        (:logs,)
    end
end

"""
    JuliaHub.interrupt!(::AbstractJobLogsBuffer; wait::Bool=true)

Can be use to interrupt the asynchronous log streaming task. If the log buffer is not streaming,
this function is a no-op.

Note that the effect of [`JuliaHub.interrupt!`](@ref) may not be immediate and the function will
block until the task has stopped. `wait = false` can be passed to make [`interrupt!`](@ref) return
immediately, but in that case the buffer may stream for a little while longer.
"""
interrupt!(buffer::AbstractJobLogsBuffer; kwargs...) = interrupt!(buffer._stream; kwargs...)

"""
    JuliaHub.hasfirst(::AbstractJobLogsBuffer) -> Bool

Determines whether the job log buffer has the first message of the job logs.

See also: [`haslast`](@ref), [`job_logs_buffered`](@ref).
"""
function hasfirst end

"""
    JuliaHub.haslast(::AbstractJobLogsBuffer) -> Bool

Determines whether the job log buffer has the last message of the job logs. Note that if the
job has not finished, this will always be `false`, since the job may produce additional logs.

See also: [`hasfirst`](@ref), [`job_logs_buffered`](@ref).
"""
function haslast end

"""
    JuliaHub.job_logs_buffered(
        [f::Base.Callable], job::Union{Job,AbstractString};
        stream::Bool=true, [offset::Integer],
        [auth::Authentication]
    ) -> AbstractJobLogsBuffer

A lower-level function to work with log streams, and is particularly useful when working
with jobs that have not finished yet and are actively producing new log messages.

The function accepts the following arguments:

* `f :: Base.Callable`: an optional callback function that gets called every time the buffer
  is updated. The callback must take two arguments: `f(::AbstractJobLogsBuffer, ::AbstractVector)`.
  The first argument is the buffer object itself, and the second argument will be passed a _read-only
  view_ of all the logs that have been loaded into the buffer, including the new ones.
* `job :: Union{Job,AbstractString}`: either the job name or a [`Job`](@ref) object.
* `stream :: Bool`: if set to `true`, the buffer object will automatically pull new logs in a
  an asynchronous background task. The streaming can be stopped with [`interrupt!`](@ref).
* `offset :: Integer`: optional non-negative value to specify the starting point of the buffer

# Interface of the returned object

Returns an instance of the abstract [`AbstractJobLogsBuffer`](@ref) type.
These objects contain log messages (of type [`JobLogMessage`](@ref)), but not all the log messages
are immediately available. Instead, at any given time the buffer represents a continuous section of
logs that can be extended in either direction.

The following functions can be used to interact with log buffers: [`job_logs_newer!`](@ref),
[`job_logs_older!`](@ref), [`JuliaHub.hasfirst`](@ref), [`JuliaHub.haslast`](@ref).
Additionally, the objects will have a `.logs :: Vector{JobLogMessage}` property that can be used
to access the log messages that have been loaded into the buffer.

See also: [`job_logs`](@ref), [`Job`](@ref).
"""
function job_logs_buffered end

function job_logs_buffered(
    f::Base.Callable, jobname::AbstractString;
    offset::Union{Integer, Nothing}=nothing,
    stream::Bool=false,
    auth::Authentication=__auth__(),
)
    if _job_logging_api_version(auth, jobname) == _KafkaLogging()
        return KafkaLogsBuffer(f, auth; jobname, offset, stream)
    else
        return _LegacyLogsBuffer(f, auth; jobname, offset, stream)
    end
end
job_logs_buffered(job::Union{AbstractString, Job}; kwargs...) =
    job_logs_buffered(_noop, job; kwargs...)
job_logs_buffered(f::Base.Callable, job::Job; kwargs...) = job_logs_buffered(f, job.id; kwargs...)

"""
    JuliaHub.job_logs_older!(
        buffer::AbstractJobLogsBuffer; [count::Integer], [auth::Authentication]
    ) -> AbstractJobLogsBuffer

Updates the [`AbstractJobLogsBuffer`](@ref) object by adding up to `count` log messages to
the beginning of the buffer. If `count` is omitted, it will seek all the way to the beginning
of the logs.

If all the logs have already been loaded into the buffer (i.e. `JuliaHub.hasfirst(buffer)` is
`true`), the function is a no-op.

See also: [`job_logs_buffered`](@ref), [`job_logs_newer!`](@ref).
"""
function job_logs_older! end
function job_logs_older!(
    buffer::AbstractJobLogsBuffer;
    count::Union{Integer, Nothing}=nothing,
    auth::Authentication=__auth__(),
)::AbstractJobLogsBuffer
    lock(buffer) do
        _job_logs_older!(auth, buffer; count)
    end
    return buffer
end

"""
    JuliaHub.job_logs_newer!(
        buffer::AbstractJobLogsBuffer; [count::Integer], [auth::Authentication]
    ) -> AbstractJobLogsBuffer

Updates the [`AbstractJobLogsBuffer`](@ref) object by adding up to `count` log messages to
the end of the buffer. If `count` is omitted, it will seek all the way to the end of the current
logs.

For a finished job, if all the logs have already been loaded into the buffer (i.e.
`JuliaHub.haslast(buffer)` is `true`), the function is a no-op. If the buffer is actively streaming
new logs for a running job,  then the function is also a no-op.

See also: [`job_logs_buffered`](@ref), [`job_logs_older!`](@ref).
"""
function job_logs_newer! end
function job_logs_newer!(
    buffer::AbstractJobLogsBuffer;
    # TODO: should count=nothing even be allowed..?
    count::Union{Integer, Nothing}=nothing,
    auth::Authentication=__auth__(),
)::AbstractJobLogsBuffer
    lock(buffer) do
        _job_logs_newer!(auth, buffer; count)
    end
    return buffer
end
