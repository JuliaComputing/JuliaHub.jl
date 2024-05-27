Base.@kwdef struct _JuliaHubInfo
    username::Union{String, Nothing}
    api_version::VersionNumber
    _user_emails::Vector{String} = String[]
    _userid::Union{Int, Nothing} = nothing
end

function _gql_request(server::AbstractString, token::Secret, query::AbstractString)
    query = Dict(
        "variables" => Dict(),
        "operationName" => nothing,
        "query" => query,
    )
    query = JSON.json(query)
    headers = [
        _authheaders(token)...,
        "X-Hasura-Role" => "jhuser",
    ]
    r = @_httpcatch HTTP.post("$server/v1/graphql", headers, query; status_exception=false)
    return _RESTResponse(r)
end

_gql_request(auth::Authentication, query::AbstractString) =
    _gql_request(string(auth.server), auth.token, query)

const _USERINFO_GQL = read(joinpath(@__DIR__, "userinfo.gql"), String)
function _get_authenticated_user_legacy_gql_request(server::AbstractString, token::Secret)
    _gql_request(server, token, _USERINFO_GQL)
end

function _get_authenticated_user_api_v1_request(server::AbstractString, token::Secret)
    headers = _authheaders(token)
    # We explicitly want HTTP to retry these requests, just to make it less likely that
    # we don't fail here due to an intermittent error. Note: retry=true is the default
    # actually, so this is mostly for documentation purposes.
    r = @_httpcatch HTTP.get("$server/api/v1", headers; retry=true, status_exception=false)
    return _RESTResponse(r)
end

function _get_authenticated_user_legacy(server::AbstractString, token::Secret)::_JuliaHubInfo
    r = Mocking.@mock _get_authenticated_user_legacy_gql_request(server, token)
    msg = "Unable to query for user information (Hasura)" # error message
    r.status == 200 || _throw_invalidresponse(r; msg)
    json, _ = _parse_response_json(r, Dict)
    users = _get_json(_get_json(json, "data", Dict; msg), "users", Vector)
    length(users) == 1 || throw(
        JuliaHubError("$msg\nInvalid JSON returned by the server: length(users)=$(length(users))")
    )
    user = only(users)
    userid = _get_json(user, "id", Int; msg)
    username = _get_json(user, "username", String; msg)
    info = _get_json(user, "info", Vector; msg)
    emails = [_get_json(x, "email", String) for x in info]
    return _JuliaHubInfo(;
        api_version=_MISSING_API_VERSION, username, _user_emails=emails, _userid=userid
    )
end

function _get_api_information(server::AbstractString, token::Secret)::_JuliaHubInfo
    # First, try to access the /api/v1 endpoint
    r = Mocking.@mock _get_authenticated_user_api_v1_request(server, token)
    if r.status == 200
        json, _ = _parse_response_json(r, Dict)
        username = _get_json_or(json, "username", String, nothing)
        api_version = _json_get(json, "api_version", VersionNumber; parse=true, var="/api/v1")
        return _JuliaHubInfo(; username, api_version)
    elseif r.status == 404
        return _get_authenticated_user_legacy(server, token)
    end
    _throw_invalidresponse(r; msg="Unable to query for user information (/api/v1)")
end

_get_api_information(auth::Authentication) = _get_api_information(string(auth.server), auth.token)
