"""
    function request(
        job::Job,
        method::AbstractString,
        uripath::AbstractString,
        [body];
        [auth::Authentication],
        [extra_headers],
        kwargs...
    ) -> HTTP.Response

Performs a HTTP against the HTTP server exposed by the job with the authentication
token of the authenticated user. The function is a thin wrapper around the `HTTP.request`
function, constructing the correct URL and setting the authentication headers.

Arguments:

* `job::Job`: JuliaHub job (from [`JuliaHub.job`](@ref))

* `method::AbstractString`: HTTP method (gets directly passed to HTTP.jl)

* `uripath::AbstractString`: the path and query portion of the URL, which gets
  appended to the scheme and hostname port of the URL. Must start with a `/`.

* `body`: gets passed as the `body` argument to HTTP.jl

Keyword arguments:

$(_DOCS_authentication_kwarg)

* `extra_headers`: an iterable of extra HTTP headers, that gets concatenated
  with the list of necessary authentication headers and passed on to `HTTP.request`.

  * Additional keyword arguments must be valid HTTP.jl keyword arguments and will
  get directly passed to the `HTTP.request` function.

!!! note

    See the [manual section on exposing ports](@ref jobs-batch-expose-port) and
    the `expose` argument to [`submit_job`](@ref).
"""
function request(
    job::Job,
    method::AbstractString,
    uripath::AbstractString,
    body::Any = UInt8[];
    auth::Authentication=__auth__(),
    extra_headers::Vector{Any} = [],
    kwargs...
)
    proxyhost = _job_proxy_host(job)
    if isnothing(proxyhost)
        throw(ArgumentError("Job '$(job.id)' does not expose a HTTP endpoint."))
    end
    if !startswith(uripath, "/")
        throw(ArgumentError("'uripath' must start with a /, got: '$uripath'"))
    end
    HTTP.request(
        method,
        string("https://", proxyhost, uripath),
        [_authheaders(auth)..., extra_headers...],
        body;
        kwargs...
    )
end

function _job_proxy_host(job::Job)
    proxy_link = get(job._json, "proxy_link", "")
    if isempty(proxy_link)
        return nothing
    end
    uri = try
        uri = URIs.URI(proxy_link)
        checks = (
            uri.scheme == "https",
            !isempty(uri.host),
            isempty(uri.path) || uri.path == "/",
            isempty(uri.query),
            isempty(uri.fragment),
        )
        all(checks) ? uri : nothing
    catch e
        isa(e, ParseError) || rethrow()
        nothing
    end
    if isnothing(uri)
        throw(JuliaHubError("Invalid proxy_link value for job: $(job.id)\n proxy_link=$(proxy_link)"))
        return nothing
    end
    return uri.host
end
