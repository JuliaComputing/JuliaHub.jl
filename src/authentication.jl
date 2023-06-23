"""
    struct AuthenticationError <: JuliaHubException

Exception thrown if the authentication fails. The `.msg` fields contains a human-readable
error message.
"""
struct AuthenticationError <: JuliaHubException
    msg::String
end
Base.showerror(io::IO, e::AuthenticationError) = print(io, "AuthenticationError: $(e.msg)")

# Fallback api_version value for Authentication objects. Indicates an old JuliaHub version,
# with JuliaHub 6.0 - 6.1 compatibility.
const _MISSING_API_VERSION = v"0.0.0-legacy"

const _DEFAULT_authenticate_maxcount = 3

"""
    mutable struct Authentication

Authentication object constructed by the [`authenticate`](@ref) function that
can be passed to the various JuliaHub.jl function via the `auth` keyword argument.

Objects have the following properties:

* `server :: URIs.URI`: URL of the JuliaHub instance this authentication token applies to.
* `username :: String`: user's JuliaHub username (used for e.g. to namespace datasets)
* `token :: JuliaHub.Secret`: a [`Secret`](@ref) object storing the JuliaHub authentication token

Note that the object is mutable, and hence will be shared as it is passed around. And at the same
time, functions such as [`reauthenticate!`](@ref) may modify the object.

See also: [`authenticate`](@ref), [`reauthenticate!`](@ref), [`current_authentication`](@ref).

$(_DOCS_no_constructors_admonition)
"""
mutable struct Authentication
    server::URIs.URI
    username::String
    token::Secret
    _api_version::VersionNumber
    _tokenpath::Union{String, Nothing}
    _email::Union{String, Nothing}
    _expires::Union{Int, Nothing}

    function Authentication(
        server::URIs.URI, api_version::VersionNumber, username::AbstractString, token::Secret;
        tokenpath::Union{AbstractString, Nothing}=nothing,
        email::Union{AbstractString, Nothing}=nothing,
        expires::Union{Integer, Nothing}=nothing,
    )
        # The authentication() function should take care of sanitizing the inputs here,
        # so it is fine to just error() here.
        server = _sanitize_juliahub_uri(server) do _, error_msg
            error("Invalid server URI ($error_msg): $(server)")
        end
        if !isnothing(tokenpath) && !isfile(tokenpath)
            @warn "Invalid auth.toml token path passed to Authentication, ignoring." tokenpath
            tokenpath = nothing
        end
        new(server, username, token, api_version, tokenpath, email, expires)
    end
end

function Base.show(io::IO, auth::Authentication)
    print(io, "JuliaHub.Authentication(")
    print(io, '"', auth.server, "\", ")
    print(io, '"', auth.username, "\", ")
    print(io, "*****)")
end

function _sanitize_juliahub_uri(f::Base.Callable, server::URIs.URI)
    # Check that the URL is valid
    invalid_uri_msg = _invalid_juliahub_uri_msg(server)
    if !isnothing(invalid_uri_msg)
        f(server, invalid_uri_msg)
        return nothing
    end
    # If it is, return a sanitized version of it where we strip
    # query parameters and such.
    sanitized_uri = URIs.URI(;
        scheme=server.scheme,
        host=server.host,
        port=server.port,
        # We'll sanitize the path part of the URI, making sure it does not have a trailing slash
        path=rstrip(server.path, '/'),
    )
    return sanitized_uri
end
_sanitize_juliahub_uri(f::Base.Callable, server::AbstractString) =
    _sanitize_juliahub_uri(f, URIs.URI(server))
# Returns `nothing` if the URI is fine, or a string with the error message otherwise
function _invalid_juliahub_uri_msg(server::URIs.URI)
    server.scheme == "https" || return "invalid scheme '$(server.scheme)'"
    isempty(server.userinfo) || return "userinfo must be empty, got '$(server.userinfo)'"
    isempty(server.host) && return "empty hostname"
    isempty(server.query) || return "query must be empty, got '$(server.query)'"
    isempty(server.fragment) || return "fragment must be empty, got '$(server.fragment)'"
    return nothing
end

# Global storing the authentication object from the last authenticate() call
# Should only be accessed in __auth__() and authenticate()
const __AUTH__ = Ref{Union{Authentication, Nothing}}(nothing)
# Internal function to populate the `auth` keyword of the various function
# with the default, global authentication.
function __auth__()
    __AUTH__[] isa Authentication && return __AUTH__[]
    auth = try
        authenticate()
    catch e
        @error "Automatic authentication failed, explicit `auth` keyword argument required."
        rethrow(e)
    end
    return auth
end

"""
    JuliaHub.current_authentication() -> Union{Authentication, Nothing}

Returns the current globally active [`Authentication`](@ref) object, or `nothing` if
[`authenticate`](@ref) has not yet been called.

```jldoctest
julia> JuliaHub.current_authentication()
JuliaHub.Authentication("https://juliahub.com", "username", *****)
```

!!! note

    Calling this function will not initialize authentication.
"""
current_authentication() = __AUTH__[]

# Internal function used to construct endpoint URLs for an authentication object.
function _url(auth::Authentication, path...; query...)
    path = URIs.escapeuri.(path)
    uri = URIs.URI(;
        scheme=auth.server.scheme,
        host=auth.server.host,
        path=string(auth.server.path, '/', join(path, '/')),
        # nothing can be used to omit a query parameter
        query=filter(q -> !isnothing(q.second), pairs(query)),
    )
    return string(uri)
end
# Internal function for constructing the authentication headers
_authheaders(auth::Authentication; kwargs...) = _authheaders(auth.token; kwargs...)
function _authheaders(token::Secret; hasura=false)
    auth = "Authorization" => string("Bearer ", String(token))
    if hasura
        [auth, "X-Hasura-Role" => "jhuser", "X-JuliaHub-Ensure-JS" => "true"]
    else
        [auth]
    end
end

"""
    JuliaHub.authenticate(server = Pkg.pkg_server(); force::Bool = false, maxcount::Integer = $(_DEFAULT_authenticate_maxcount), [hook::Base.Callable])

Authenticates with a JuliaHub server. If a valid authentication token does not exist in
the Julia depot, a new token is acquired via an interactive browser based prompt.
Returns an [`Authentication`](@ref) object if the authentication was successful, or throws an
[`AuthenticationError`](@ref) if authentication fails.

The interactive prompts tries to authenticate for a maximum of `maxcount` times.
If `force` is set to `true`, an existing authentication token is first deleted. This can be
useful when the existing authentication token is causing the authentication to fail.

# Extended help

By default, it attemps to connect to the currently configured Julia package server URL
(configured e.g. via the `JULIA_PKG_SERVER` environment variable). However, this can
be overridden by passing the `server` argument.

`hook` can be set to a function taking a single string-type argument, and will be passed the
authorization URL the user should interact with in the browser. This can be used to override the default
behavior coming from [PkgAuthentication](https://github.com/JuliaComputing/PkgAuthentication.jl).

The returned [`Authentication`](@ref) object is also cached globally (overwriting any previously
cached authentications), making it unnecessary to pass the returned object manually to other
function calls. This is useful for interactive use, but should not be used in library code,
as different authentication calls may clash.
"""
function authenticate(
    server::Union{AbstractString, Nothing}=nothing;
    force::Bool=false,
    maxcount::Integer=_DEFAULT_authenticate_maxcount,
    hook::Union{Base.Callable, Nothing}=nothing,
)
    maxcount >= 1 || throw(ArgumentError("maxcount must be >= 1, got '$maxcount'"))
    if !isnothing(hook) && !hasmethod(hook, Tuple{AbstractString})
        throw(
            ArgumentError(
                "Browser hook ($hook) must have a method taking a single URL string argument."
            ),
        )
    end
    # PkgAuthentication.token_path can not handle server values that do not
    # prepend `https://`, so we use Pkg.pkg_server() to normalize it, just in case.
    server_uri_string = if isnothing(server)
        haskey(ENV, "JULIA_PKG_SERVER") || throw(
            AuthenticationError(
                "Either JULIA_PKG_SERVER must be set, or explicit `server` argument passed to JuliaHub.authenticate().",
            ),
        )
        Pkg.pkg_server()
    else
        withenv(Pkg.pkg_server, "JULIA_PKG_SERVER" => server)
    end
    # It is possible to Pkg.pkg_server to return nothing
    isnothing(server_uri_string) && throw(AuthenticationError("No package server set."))

    server_uri = _sanitize_juliahub_uri(server_uri_string) do _, error_msg
        name, value =
            isnothing(server) ? ("Pkg.pkg_server()", Pkg.pkg_server()) : ("server", server)
        throw(AuthenticationError("Invalid $name value '$value' ($error_msg)"))
    end
    auth = Mocking.@mock _authenticate(server_uri; force, maxcount, hook)
    global __AUTH__[] = auth
    return auth
end

function _authenticate(
    server_uri::URIs.URI; force::Bool, maxcount::Integer, hook::Union{Base.Callable, Nothing}
)
    isnothing(hook) || PkgAuthentication.register_open_browser_hook(hook)
    try
        # _authenticate either returns a valid token, or throws
        auth_toml = _authenticate_retry(string(server_uri), 1; force, maxcount)
        # Note: _authentication may throw, which gets passed on to the user
        _authentication(server_uri; auth_toml...)
    finally
        isnothing(hook) || PkgAuthentication.clear_open_browser_hook()
    end
end

function _authenticate_retry(
    server::AbstractString, count::Integer; force::Bool=false, maxcount::Integer=3
)
    @debug "_authenticate($server)" count = count force = force maxcount = maxcount

    newcount(success) = count + !(success isa PkgAuthentication.Success)

    count > maxcount &&
        throw(AuthenticationError("Authentication unsuccessful after $maxcount tries"))

    toml_file_path = PkgAuthentication.token_path(server)
    @debug "toml_file_path" toml_file_path

    if !isfile(toml_file_path)
        @debug "toml_file_path"
        success = PkgAuthentication.authenticate(server)
        return _authenticate_retry(server, newcount(success); maxcount=maxcount)
    end

    if force
        @debug "force == true -- removing existing authentication TOML file"
        try
            rm(toml_file_path; force=true)
        catch err
            @warn "Removing existing authentication TOML file failed\n  path: $(toml_file_path)" exception = (
                err, catch_backtrace()
            )
        end
        success = PkgAuthentication.authenticate(server)
        return _authenticate_retry(server, newcount(success); maxcount=maxcount)
    end

    toml = TOML.parsefile(toml_file_path)

    if !haskey(toml, "id_token")
        @debug "id_token"
        success = PkgAuthentication.authenticate(server)
        return _authenticate_retry(server, newcount(success); maxcount=maxcount)
    end

    expires = get(toml, "expires", get(toml, "expires_at", nothing))
    if isnothing(expires) || expires < time()
        @debug "expires"
        success = PkgAuthentication.authenticate(server)
        return _authenticate_retry(server, newcount(success); maxcount=maxcount)
    end

    # Note: return value gets passed on to _authentication via keyword arguments
    return (;
        token=Secret(toml["id_token"]),
        expires,
        email=get(toml, "user_email", nothing),
        username=get(toml, "user_name", nothing),
        tokenpath=toml_file_path,
    )
end

# Internal function to construct an Authentication object by connecting to 'server'
# with 'token' and running the _get_authenticated_user query against it to fetch the
# username.
function _authentication(
    server::URIs.URI;
    token::Secret,
    expires::Union{Number, Nothing}=nothing,
    email::Union{AbstractString, Nothing}=nothing,
    username::Union{AbstractString, Nothing}=nothing,
    tokenpath::Union{AbstractString, Nothing}=nothing,
)
    # If something goes badly wrong in _get_api_information, it may throw. We won't really
    # be able to proceed, since we do not know what JuliaHub APIs to use, so we need to
    # propagate this to the user. But we'll change the exception type here to
    # AuthenticationError to be consistent with what authenticate() should throw.
    api = try
        _get_api_information(string(server), token)
    catch e
        errmsg = """
        Unable to determine JuliaHub API version.
        _get_api_information failed with an exception:
        $(sprint(showerror, e))"""
        # Note: the original stacktrace should available from the "caused by" stack.
        throw(AuthenticationError(errmsg))
    end
    # If fetching user information was successful, we use that to populate the Authentication
    # object. Otherwise, we'll fall back to the auth.toml values.
    email = if isempty(api._user_emails)
        @debug "No user emails provided by the server, falling back to auth.toml value"
        email
    else
        first(api._user_emails)
    end
    # It is sometimes possible for the username to not be set in /api/v1 endpoint. In that case
    # we warn (since this is unusual, but still fall back to auth.toml value).
    if isnothing(api.username)
        @warn "Failed to acquire username from server, falling back to auth.toml value (may be incorrect)" username
        # However, if user auth.toml username is also missing, then we don't really have any
        # other opportunity other than to throw.
        if isnothing(username)
            throw(AuthenticationError("Unable to determine username."))
        end
    else
        username = api.username
    end
    return Authentication(server, api.api_version, username, token; email, expires, tokenpath)
end
_authentication(server::AbstractString; kwargs...) = _authentication(URIs.URI(server); kwargs...)

"""
    JuliaHub.check_authentication(; [auth::Authentication]) -> Bool

Checks if the authentication to a JuliaHub instance is still valid or not.

This can be used to periodically check an authentication token, to see if it is necessary
to re-authenticate.

See also: [`reauthenticate!`](@ref).
"""
function check_authentication(; auth::Authentication=__auth__())::Bool
    # Normally we want to check the /api/v1 endpoint, but we'll query
    # app/config/nodespecs/info on older JuliaHub versions.
    r = if auth._api_version == _MISSING_API_VERSION
        _restcall(auth, :GET, "app", "config", "nodespecs", "info")
    else
        _restcall(auth, :GET, "api", "v1")
    end
    (r.status == 200) && return true
    # Note: JuliaHub may sometimes return a 500 when a bad token is used
    (r.status == 401 || r.status == 500) && return false
    _throw_invalidresponse(r)
end

"""
    JuliaHub.reauthenticate!([auth::Authentication]; force::Bool = false, maxcount::Integer = $(_DEFAULT_authenticate_maxcount), [hook::Base.Callable])

Attempts to update the authentication token in `auth`:

* If the original `auth.toml` file has been updated, it simply reloads the token from the file.
* If loading from `auth.toml` fails or `force=true`, it will attempt to re-authenticate with the
  server, possibly interactively.

If `auth` is omitted, it will reauthenticate the global [`Authentication`](@ref) object.
The `force`, `maxcount` and `hook` are relevant for interactive authentication, and behave the
same way as in the [`authenticate`](@ref) function.

This is mostly meant to be used to re-acquire authentication tokens in long-running sessions, where
the initial authentication token may have expired.

As [`Authentication`](@ref) objects are mutable, the token will be updated in all contexts
where the reference to the [`Authentication`](@ref) has been passed to.

See also: [`authenticate`](@ref), [`current_authentication`](@ref), [`Authentication`](@ref),
[`check_authentication`](@ref).
"""
function reauthenticate! end

function reauthenticate!(; kwargs...)
    global_auth::Union{Authentication, Nothing} = __auth__()
    if isnothing(global_auth)
        throw(AuthenticationError("No global authentication set, call authenticate() first."))
    end
    reauthenticate!(global_auth; kwargs...)
end

function reauthenticate!(
    auth::Authentication;
    force::Bool=false,
    maxcount::Integer=_DEFAULT_authenticate_maxcount,
    hook::Union{Base.Callable, Nothing}=nothing,
)
    if !force && !isnothing(auth._tokenpath) && isfile(auth._tokenpath)
        @debug "reauthenticate! -- trying to reload token from a file"
        toml = TOML.parsefile(auth._tokenpath)
        if haskey(toml, "id_token")
            token = Secret(toml["id_token"])
            api = try
                _get_api_information(string(auth.server), token)
            catch e
                # If we detect here that the auth.toml is bad, we will set force=true,
                # to make sure that PkgAuthentication doesn't just go ahead and read it from
                # disk anyway (and then fail later).
                force = true
                @debug "Failed to acquire API & user information from server" exception = (
                    e, catch_backtrace()
                )
            end
            if !isnothing(api) && auth.username == api.username
                auth.token = token
                auth._api_version =
                    isnothing(api.api_version) ? _MISSING_API_VERSION : api.api_version
                auth._expires = get(toml, "expires", nothing)
                return auth
            end
        else
            # If we detect here that the auth.toml is bad, we will set force=true,
            # to make sure that PkgAuthentication doesn't just go ahead and read it from
            # disk anyway (and then fail later).
            force = true
            @warn "Invalid auth.toml file at $(auth._tokenpath)" haskey(toml, "id_token") haskey(
                toml, "expires"
            )
        end
    end
    @debug "reauthenticate! -- calling PkgAuthentication" auth.server
    new_auth = _authenticate(auth.server; force, maxcount, hook)
    if new_auth.username != auth.username
        throw(
            AuthenticationError(
                "Username in new authentication ($(new_auth.username)) does not match original authentication ($(auth.username))",
            ),
        )
    end
    auth.token = new_auth.token
    auth._api_version = new_auth.api_version
    auth._expires = new_auth._expires
    auth._email = new_auth._email
    auth._tokenpath = new_auth._tokenpath
    return auth
end
