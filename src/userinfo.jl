Base.@kwdef struct _JuliaHubInfo
    username::String
    api_version::Union{VersionNumber, Nothing}
    _user_emails::Vector{String} = String[]
    _userid::Union{Int, Nothing} = nothing
end

const _USERINFO_GQL = read(joinpath(@__DIR__, "userinfo.gql"), String)

function _get_authenticated_user_legacy_gql_request(server::AbstractString, token::Secret)
    query = Dict(
        "variables" => Dict(),
        "operationName" => nothing,
        "query" => _USERINFO_GQL,
    )
    query = JSON.json(query)
    headers = [
        _authheaders(token)...,
        "X-Hasura-Role" => "jhuser",
    ]
    @_httpcatch HTTP.post("$server/v1/graphql", headers, query; status_exception=false)
end

function _get_authenticated_user_api_v1_request(server::AbstractString, token::Secret)
    headers = _authheaders(token)
    @_httpcatch HTTP.get("$server/api/v1", headers; status_exception=false)
end

function _get_authenticated_user_60(server::AbstractString, token::Secret)
    r = _get_authenticated_user_legacy_gql_request(server, token)
    msg = "Unable to query for user information (Hasura)" # error message
    r.status == 200 || _throw_invalidresponse(r; msg)
    json, _ = _parse_response_json(r, Dict)
    users = _get_json(_get_json(json, "data", Dict; msg), "users", Vector)
    length(users) == 1 || throw(
        JuliaHubError("$msg\nInvalid JSON returned by the server: length(users)=$(length(users))"),
    )
    user = only(users)
    userid = _get_json(user, "id", Int; msg)
    username = _get_json(user, "username", String; msg)
    info = _get_json(user, "info", Vector; msg)
    emails = [_get_json(x, "email", String) for x in info]
    return _JuliaHubInfo(; api_version=nothing, username, _user_emails=emails, _userid=userid)
end

function _get_api_information(server::AbstractString, token::Secret)
    # First, try to access the /api/v1 endpoint
    r = _get_authenticated_user_api_v1_request(server, token)
    if r.status == 200
        json, _ = _parse_response_json(r, Dict)
        username = _get_json(json, "username", String)
        api_version = _json_get(json, "api_version", VersionNumber; parse=true, var="/api/v1")
        return _JuliaHubInfo(; username, api_version)
    elseif r.status == 404
        return _get_authenticated_user_60(server, token)
    end
    _throw_invalidresponse(r; msg="Unable to query for user information (/api/v1)")
end

_get_api_information(auth::Authentication) = _get_api_information(string(auth.server), auth.token)

function _get_user_groups(auth::Authentication)
    r = HTTP.get(
        _url(auth, "user", "groups"),
        _authheaders(auth),
    )
    r.status == 200 && return JSON.parse(String(r.body))
    _throw_invalidresponse(r)
end
