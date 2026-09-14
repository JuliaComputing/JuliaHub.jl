# A convenience macro that wraps the expression in a try-catch and catches all
# HTTP.jl exception (generally indicating a connection failure) and throws a
# JuliaHubError
#
# Note: `HTTP.HTTPError` is the top-level abstract supertype of all HTTP.jl exceptions
# on both HTTP.jl 1.x (where it is re-exported from the `HTTP.Exceptions` submodule)
# and 2.x (which dropped the submodule, leaving only a deprecating shim).
#
# A `msg` "keyword" can be used to customize the error message. E.g.
#
# @_httpcatch HTTP.get(...) msg = "Getting X failed"
macro _httpcatch(ex, kwargexprs...)
    kwargs = _parse_macro_kwargs(kwargexprs)
    message = Expr(:string)
    if haskey(kwargs, :msg)
        if isa(kwargs[:msg], String)
            push!(message.args, string(kwargs[:msg], '\n'))
        elseif isa(kwargs[:msg], Expr) && kwargs[:msg].head == :string
            append!(message.args, kwargs[:msg].args)
            push!(message.args, "\n")
        else
            error("@_httpcatch: `msg` must be a string")
        end
    end
    append!(message.args, ("HTTP connection to JuliaHub failed (", :(typeof(e)), ")"))
    quote
        try
            $(esc(ex))
        catch e
            e isa HTTP.HTTPError || rethrow(e)
            throw(JuliaHubConnectionError($message, e, catch_backtrace()))
        end
    end
end

function _parse_macro_kwargs(kwargexprs)
    kwargs = Dict{Symbol, Any}()
    for ex in kwargexprs
        ex.head == :(=) || error("Invalid kwarg: $ex ($(ex.head))")
        name, value = ex.args[1], ex.args[2]
        name isa Symbol || error("Invalid argument name: $name in $ex")
        kwargs[name] = value
    end
    return kwargs
end

# User-Agent header sent with requests where HTTP.jl does not add one itself. HTTP.jl 1.x
# added a default `User-Agent: HTTP.jl/...` to every request, including websocket handshakes,
# but 2.x only does so for regular `HTTP.request` calls. Some edge proxies (e.g. Cloudflare)
# reject requests without a User-Agent with a 403.
const _USER_AGENT = string(
    "JuliaHub.jl/",
    TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))["version"],
)

struct _RESTResponse
    status::Int
    body::String
end
_RESTResponse(response::HTTP.Response) = _RESTResponse(response.status, String(response.body))

Base.propertynames(::_RESTResponse) = (fieldnames(_RESTResponse)..., :json)
function Base.getproperty(r::_RESTResponse, name::Symbol)
    if name in fieldnames(_RESTResponse)
        getfield(r, name)
    elseif name == :json
        JSON.parse(getfield(r, :body))
    else
        error("_RESTResponse has no property $name")
    end
end

function _throw_invalidresponse(r::_RESTResponse; checkauth=true, msg=nothing)
    # If checkauth is passed and we got 401 or 403, we'll throw an AuthenticationError
    # to the user, instead of a JuliaHubError. This check can be disabled in cases where
    # you would never expect an authentication problem.
    if checkauth && r.status == 401
        throw(InvalidAuthentication())
    elseif r.status == 403
        throw(PermissionError(isnothing(msg) ? "Operation not permitted" : msg, String(r.body)))
    else
        errormsg = """
        Invalid HTTP response ($(r.status)) returned by the server:
        $(String(r.body))
        """
        isnothing(msg) || (errormsg = string(msg, '\n', errormsg))
        throw(JuliaHubError(errormsg))
    end
end

function _parse_response_json(r::_RESTResponse, ::Type{T})::Tuple{T, String} where {T}
    return _parse_response_json(r.body, T)
end

# Check that the API response is not a legacy 200 internal error, where
# we return
#
# {"success": false, "interal_error": true, "message": "..."}
#
# on internal errors. If it detects that this is an internal error, it throws
# a JuliaHubError. Returns `nothing` otherwise.
function _check_internal_error(r::_RESTResponse; var::AbstractString)
    if !(r.status == 200)
        return nothing
    end
    success = _get_json_or(r.json, "success", Any, nothing)
    internal_error = _get_json_or(r.json, "internal_error", Any, nothing)
    if (success === false) && (internal_error === true)
        e = JuliaHubError(
            """
            Internal Server Error 200 response from JuliaHub ($var):
            JSON: $(sprint(show, MIME("text/plain"), r.json))
            """,
        )
        throw(e)
    end
    return nothing
end

# _restcall calls _rest_request_mockable which calls _rest_request_http. The reason for this
# indirection is that the signature of _rest_request_mockable is extremely simple and therefore
# each to hook into with Mockable.
const _RESTCALL_DEBUG = Base.RefValue(false)

function _restcall(
    auth::Authentication, method::Symbol, url::NTuple{N, AbstractString}, payload;
    query=nothing, headers=nothing, hasura=false,
) where {N}
    url = JuliaHub._url(auth, url...)
    _RESTCALL_DEBUG[] && @debug "$(method) $(url)" headers payload query
    fullheaders = JuliaHub._authheaders(auth; hasura)
    isnothing(headers) || append!(fullheaders, headers)
    return Mocking.@mock _rest_request_mockable(method, url, fullheaders, payload; query)
end

function _restcall(auth::Authentication, method::Symbol, url::AbstractString...; kwargs...)
    _restcall(auth, method, (url...,), nothing; kwargs...)
end

# This is separated out here so that we could @mock it.
# Should return _RESTResponse (even if the server returns a bad code), or throw
# a JuliaHubConnectionError if there is a connection failure.
_rest_request_mockable(args...; kwargs...) = _rest_request_http(args...; kwargs...)
# `query` must be `nothing`, a string, a dictionary, or a vector of pairs. NamedTuples
# are accepted by HTTP.jl 1.x but not 2.x, so callers should not use them.
function _rest_request_http(method::Symbol, url::AbstractString, headers, payload; query=nothing)
    # HTTP.jl passes HTTP.nobody == UInt[] when it populates the `body` argument
    # with a default value, so we also do that here.
    body = isnothing(payload) ? UInt8[] : payload
    response::HTTP.Response = @_httpcatch HTTP.request(
        string(method), url, headers, body; status_exception=false, query
    ) msg = "HTTP connection to JuliaHub failed ($(typeof(e)))"
    return _RESTResponse(response)
end

#
_restput_mockable(args...; kwargs...) = _restput_http_put(args...; kwargs...)
function _restput_http_put(url::AbstractString, headers, input)
    r::HTTP.Response = @_httpcatch HTTP.put(url, headers, input)
    return _RESTResponse(r)
end
