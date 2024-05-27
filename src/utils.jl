const _DOCS_no_constructors_admonition = """
!!! compat "No public constructors"

    Objects of this type should not be constructed explicitly.
    The contructor methods are not considered to be part of the public API.
"""

"""
    abstract type JuliaHubException <: Exception

Abstract supertype of all JuliaHub.jl exception types.
"""
abstract type JuliaHubException <: Exception end

"""
    struct JuliaHubError <: JuliaHubException

An exception thrown if there is an unexpected response from or backend failure in JuliaHub.

The `.msg` field contains the error message. If there is an underlying exception,
it is stored in the `.exception` field.
"""
struct JuliaHubError <: JuliaHubException
    msg::String
    exception::Union{Tuple{Any, Any}, Nothing}

    JuliaHubError(msg::AbstractString) = new(msg, nothing)
    JuliaHubError(msg::AbstractString, exception, backtrace) = new(msg, (exception, backtrace))
end
Base.showerror(io::IO, e::JuliaHubError) = print(io, "JuliaHubError: $(e.msg)")

"""
    struct JuliaHubConnectionError <: JuliaHubException

An exception thrown if there is a communication error with JuliaHub.

The `.msg` field contains the error message. If there is an underlying exception,
it is stored in the `.exception` field.
"""
struct JuliaHubConnectionError <: JuliaHubException
    msg::String
    exception::Union{Tuple{Any, Any}, Nothing}

    JuliaHubConnectionError(msg::AbstractString) = new(msg, nothing)
    JuliaHubConnectionError(msg::AbstractString, exception, backtrace) =
        new(msg, (exception, backtrace))
end
Base.showerror(io::IO, e::JuliaHubConnectionError) = print(io, "JuliaHubConnectionError: $(e.msg)")

"""
    struct InvalidRequestError <: JuliaHubException

An exception thrown if the request was rejected by the backend due to request parameters
that are inconsistent with the backend state. The `.msg` field contains the error message.
"""
struct InvalidRequestError <: JuliaHubException
    msg::String
end
Base.showerror(io::IO, e::InvalidRequestError) = print(io, "InvalidRequestError: $(e.msg)")

"""
    struct InvalidAuthentication <: JuliaHubException

This exception is thrown if the authentication token is invalid or has expired.
Re-authenticating with [`JuliaHub.authenticate`](@ref) should generally be sufficient to
resolve the issue.
"""
struct InvalidAuthentication <: JuliaHubException end
Base.showerror(io::IO, ::InvalidAuthentication) = print(
    io,
    """
    InvalidAuthentication: authentication token invalid or expired
    Please re-authenticate with JuliaHub.authenticate()""",
)

"""
    struct PermissionError <: JuliaHubException

Thrown if the currently authenticated user does not have the necessary permissions to perform
the operation. The `.msg` field contains the error message, and `.response` may contain the raw
server response.
"""
struct PermissionError <: JuliaHubException
    msg::String
    response::Union{String, Nothing}

    PermissionError(msg::AbstractString, response::Union{AbstractString, Nothing}=nothing) =
        new(msg, isnothing(response) ? nothing : strip(response))
end
PermissionError(msg::AbstractString, response::HTTP.Response) =
    PermissionError(msg, _takebody!(response, String))
function Base.showerror(io::IO, e::PermissionError)
    print(io, "PermissionError: $(e.msg)")
    isnothing(e.response) || print(io, '\n', e.response)
end

_takebody!(r::HTTP.Response)::Vector{UInt8} = isa(r.body, IO) ? take!(r.body) : r.body
_takebody!(r::HTTP.Response, ::Type{T}) where {T} = T(_takebody!(r))

# This function is used to throw a consistent error message when the status code from
# the server is not recognized.
function _throw_invalidresponse(r::HTTP.Response; checkauth=true, msg=nothing)
    # If checkauth is passed and we got 401, we'll throw an AuthenticationError
    # to the user, instead of a JuliaHubError. This check can be disabled in cases where
    # you would never expect an authentication problem.
    if checkauth && r.status == 401
        throw(InvalidAuthentication())
    elseif r.status == 403
        throw(PermissionError(isnothing(msg) ? "Operation not permitted." : msg, r))
    else
        errormsg = """
        Invalid HTTP response ($(r.status)) returned by the server:
        $(String(r.body))
        """
        isnothing(msg) || (errormsg = string(msg, '\n', errormsg))
        throw(JuliaHubError(errormsg))
    end
end

# A function to throw a consistent error message when the backend happens to return
# invalid JSON.
#
# Returns the (parsed_json::Dict/Vector/..., json_string::String) tuple. The second
# element would generally be ignored, but can be use to print useful error messages
# in the callee.
function _parse_response_json(r::HTTP.Response, ::Type{T})::Tuple{T, String} where {T}
    _parse_response_json(String(r.body), T)
end
function _parse_response_json(s::AbstractString, ::Type{T})::Tuple{T, String} where {T}
    object = try
        JSON.parse(s)
    catch e
        throw(
            JuliaHubError(
                "Invalid JSON returned by the server:\n$(s)",
                e, catch_backtrace(),
            ),
        )
    end
    if !isa(object, T)
        throw(
            JuliaHubError(
                "Invalid JSON returned by the server (expected `$T`, got `$(typeof(object))`):\n$(s)"
            ),
        )
    end
    return object, s
end

function _get_json(
    json::Dict, key::AbstractString, ::Type{T}; msg::Union{AbstractString, Nothing}=nothing
)::T where {T}
    value = get(json, key) do
        errormsg = """
        Invalid JSON returned by the server: `$key` missing in the response.
        Keys present: $(join(keys(json), ", "))
        json: $(sprint(show, MIME"text/plain"(), json))"""
        isnothing(msg) || (errormsg = string(msg, '\n', errormsg))
        throw(JuliaHubError(errormsg))
    end
    if !isa(value, T)
        errormsg = "Invalid JSON returned by the server: `$key` of type `$(typeof(value))`, expected `<: $T`."
        isnothing(msg) || (errormsg = string(msg, '\n', errormsg))
        throw(JuliaHubError(errormsg))
    end
    return value
end

function _get_json_or(
    json::Dict,
    key::AbstractString,
    ::Type{T},
    default::U=nothing;
    msg::Union{AbstractString, Nothing}=nothing,
)::Union{T, U} where {T, U}
    haskey(json, key) ? _get_json(json, key, T; msg) : default
end

"""
    mutable struct Secret

A helper type for storing secrets. Internally it is a covenience wrapper around
`Base.SecretBuffer`. Predominantly used in [`Authentication`](@ref) objects to store
the JuliaHub authentication token.

The `String(::Secret)` function can be used to obtain an unsecure string copy of the
secret stored in the object.

```jldoctest
julia> s = JuliaHub.Secret("secret-string")
JuliaHub.Secret("*******")

julia> String(s)
"secret-string"
```

# Constructors

```julia
Secret(::AbstractString)
Secret(::Vector{UInt8})
```

Create a `Secret` object from the input strings.
"""
mutable struct Secret
    # It's just a wrapper around Base.SecretBuffer. The main reason for declaring
    # a new type is that we could attach our own finalizer to it. Otherwise we will
    # get warnings about GC destroying Base.SecretBuffer objects.
    sb::Base.SecretBuffer
    function Secret(sb::Base.SecretBuffer)
        s = new(sb)
        # Finalizer to quietly shred! Secrets when they get garbage-collected.
        finalizer(s) do secret
            Base.shred!(secret.sb)
        end
        return s
    end
end
Secret(s::AbstractString) = Secret(Base.SecretBuffer(s))
Secret(s::Vector{UInt8}) = Secret(Base.SecretBuffer!(s))
Base.show(io::IO, ::Secret) = print(io, "JuliaHub.Secret(\"*******\")")
function Base.String(secret::Secret)::String
    seek(secret.sb, 0)
    return read(secret.sb, String)
end

"""
    struct FileHash

Stores a hash and the algorithm used to calcute it. The object has the following
properties:

- `.algorithm :: Symbol`: hash algorithm
- `.hash :: Vector{UInt8}`: the hash as a sequence of bytes

$(_DOCS_no_constructors_admonition)
"""
struct FileHash
    algorithm::Symbol
    hash::Vector{UInt8}

    function FileHash(algorithm::AbstractString, hash::AbstractString)
        new(Symbol(algorithm), Base64.base64decode(hash))
    end
end

function Base.show(io::IO, filehash::FileHash)
    print(
        io,
        "JuliaHub.FileHash(\"",
        string(filehash.algorithm),
        "\", ",
        Base64.base64encode(filehash.hash),
        "\")",
    )
end

# Estimates the size of the bundle directory
function _max_appbundle_dir_size(dir; maxsize=100 * 1024 * 1024)
    sz = 0
    pred = _PackageBundler.path_filterer(dir)
    for (root, _, files) in walkdir(dir)
        for file in files
            file = joinpath(root, file)
            if !pred(file)
                @debug "ignoring $file in dir size measurement"
                continue
            end

            sz > maxsize && return sz, false
            sz += filesize(file)
        end
    end
    return sz, sz < maxsize
end

function _json_get(d::Dict, key, ::Type{T}; var::AbstractString, parse=false) where {T}
    haskey(d, key) || _throw_jsonerror(var, "key `$key` missing", d)
    if parse
        isa(d[key], AbstractString) || _throw_jsonerror(
            var, "key `$key` of invalid type (`$(typeof(d[key]))`, expected a string)", d
        )
        parsed_value = tryparse(T, d[key])
        isnothing(parsed_value) && _throw_jsonerror(var, "can't parse key `$key` to `$T`", d)
        return parsed_value
    else
        isa(d[key], T) || _throw_jsonerror(
            var, "key `$key` of invalid type (`$(typeof(d[key]))`, expected `$T`)", d
        )
        return d[key]
    end
end

function _throw_jsonerror(var::AbstractString, msg::AbstractString, json::Dict)
    e = JuliaHubError(
        """
        Invalid JSON response from JuliaHub ($var): $msg
        JSON: $(sprint(show, MIME("text/plain"), json))
        """,
    )
    throw(e)
end

# Checks that the 'success' field is set and === true
function _json_check_success(json::Dict; var::AbstractString)
    success = _json_get(json, "success", Bool; var)
    success || throw(JuliaHubError(
        """
        Invalid JSON response from JuliaHub ($var): success=false
        JSON: $(sprint(show, MIME("text/plain"), json))
        """,
    ))
    return nothing
end

# Performs the print of f(::IO), but prepends `indent` spaces in front of
# each line, to make it indented.
function _print_indented(io::IO, f; indent::Integer)
    @assert indent >= 0
    buffer = IOBuffer()
    f(IOContext(buffer, io)) # inheriting the IOContext from io for buffer
    seek(buffer, 0)
    for line in eachline(buffer; keep=true)
        # We don't print indents on empty lines
        if isempty(rstrip(line, ('\n', '\r')))
            println(io)
            continue
        end
        for _ in 1:indent
            write(io, ' ')
        end
        write(io, line)
    end
    return nothing
end

# A functional nothing. Placeholder for any callback that shouldn't do anything.
_noop(args...; kwargs...) = nothing

function _taskstamp(t::Task=current_task())
    # Stolen from https://github.com/JuliaLang/julia/blob/6a2e50dee302f4e9405d82db2fc0374b420948a1/base/task.jl#L106-L108
    taskname = string("0x", convert(UInt, pointer_from_objref(t)))
    timestamp = Dates.now()
    "$taskname @ $timestamp"
end

# All timestamps are assumed to be in UTC. Returns a TimeZones.ZonedDateTime,
# representing the timestamp in the user's local timezone.
_utc2localtz(timestamp::Number) = _utc2localtz(Dates.unix2datetime(timestamp))
function _utc2localtz(datetime_utc::Dates.DateTime)::TimeZones.ZonedDateTime
    datetimez_utc = TimeZones.ZonedDateTime(datetime_utc, TimeZones.tz"UTC")
    return TimeZones.astimezone(datetimez_utc, _LOCAL_TZ[])
end
# Special version of _utc2localtz to handle integer ms timestamp
function _ms_utc2localtz(timestamp::Integer)::TimeZones.ZonedDateTime
    s, ms = divrem(timestamp, 1000)
    _utc2localtz(Dates.unix2datetime(s) + Dates.Millisecond(ms))
end

_nothing_or(f::Base.Callable, x) = isnothing(x) ? nothing : f(x)

# Helper function to help manage the pattern where a function takes a 'throw::Bool` keyword
# argument and should either throw an InvalidRequestError, or return nothing.
#
# The nothrow_extra_logic_f(msg) callback can be used (via do syntax) do run additional code
# before returning if throw=false. 'msg' is passed as the first argument.
function _throw_or_nothing(
    nothrow_extra_logic_f::Union{Base.Callable, Nothing}=nothing;
    msg::AbstractString,
    throw::Bool,
)
    throw && Base.throw(InvalidRequestError(msg))
    isnothing(nothrow_extra_logic_f) || nothrow_extra_logic_f(msg)
    return nothing
end

# Parses a timezoned timestamp string into a local timezone object
const _VALID_TZ_DATEFORMATS = [
    Dates.dateformat"yyyy-mm-ddTHH:MM:SS.ssszzz",
    Dates.dateformat"yyyy-mm-ddTHH:MM:SS.sszzz",
    Dates.dateformat"yyyy-mm-ddTHH:MM:SS.szzz",
    Dates.dateformat"yyyy-mm-ddTHH:MM:SSzzz",
]
function _parse_tz(timestamp_str::AbstractString; msg::Union{AbstractString, Nothing}=nothing)
    timestamp = nothing
    for dateformat in _VALID_TZ_DATEFORMATS
        timestamp = try
            TimeZones.ZonedDateTime(timestamp_str, dateformat)
        catch e
            isa(e, ArgumentError) && continue
            rethrow(e)
        end
    end
    if isnothing(timestamp)
        errmsg = "Unable to parse timestamp '$timestamp_str'"
        if !isnothing(msg)
            errmsg = string(msg, '\n', errmsg)
        end
        throw(JuliaHubError(errmsg))
    end
    return TimeZones.astimezone(timestamp, _LOCAL_TZ[])
end

# It's quite easy to make TimeZones.localzone() fail and throw.
# So this wraps it, and adds a UTC fallback (which seems like the sensible
# default) in the case where somehow the local timezone is not configured properly.
function _localtz()
    try
        TimeZones.localzone()
    catch e
        @debug "Unable to determine local timezone" exception = (e, catch_backtrace())
        TimeZones.tz"UTC"
    end
end
