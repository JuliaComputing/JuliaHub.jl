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
    proxyhost = job_hostname(job)
    if isnothing(proxyhost)
        throw(ArgumentError("Job '$(job.id)' does not expose a HTTPS port."))
    end
    if !startswith(uripath, "/")
        throw(ArgumentError("'uripath' must start with a /, got: '$uripath'"))
    end
    return Mocking.@mock _http_request_mockable(
        method,
        string("https://", proxyhost, uripath),
        [_authheaders(auth)..., extra_headers...],
        body;
        kwargs...
    )
end

_http_request_mockable(args...; kwargs...) = HTTP.request(args...; kwargs...)

"""
    JuliaHub.job_hostname(::Job) -> String

Returns the domain name that can be used to communicate with the JuliaHub job, if the job is
exposing a port and running an HTTP server. If the job is not exposing a port, it throws an
`ArgumentError`.

The server on the job is always exposed on port `443` on the public hostname, and the communication
is TLS-wrapped (i.e. you need to connect to it over the HTTPS protocol). In most cases, your requests
to the job also need to be authenticated (see also the [`JuliaHub.request`](@ref) function).

See also: [`expose` for `JuliaHub.submit_job`](@ref JuliaHub.submit_job), and
[the relevant section in the manual](@ref jobs-batch-expose-port)
"""
function job_hostname(job::Job)
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
    end
    return uri.host
end
