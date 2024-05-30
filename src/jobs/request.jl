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

Performs an authenticated HTTP request against the HTTP server exposed by the job
(with the authentication token of the currently authenticated user).
The function is a thin wrapper around the `HTTP.request` function, constructing the
correct URL and setting the authentication headers.

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

    See the [manual section on jobs with exposed ports](@ref jobs-apis-expose-ports)
    and the `expose` argument to [`submit_job`](@ref).
"""
function request(
    job::Job,
    method::AbstractString,
    uripath::AbstractString,
    body::Any=UInt8[];
    auth::Authentication=__auth__(),
    extra_headers::Vector{Any}=[],
    kwargs...,
)
    if isnothing(job.hostname)
        throw(ArgumentError("Job '$(job.id)' does not expose a HTTPS port."))
    end
    if !startswith(uripath, "/")
        throw(ArgumentError("'uripath' must start with a /, got: '$uripath'"))
    end
    return Mocking.@mock _http_request_mockable(
        method,
        string("https://", job.hostname, uripath),
        [_authheaders(auth)..., extra_headers...],
        body;
        kwargs...,
    )
end

_http_request_mockable(args...; kwargs...) = HTTP.request(args...; kwargs...)
