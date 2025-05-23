function _parse_registry(registry_dict::Dict)
    name, uuid = try
        registry_dict["name"], tryparse(UUIDs.UUID, registry_dict["uuid"])
    catch e
        @error "Invalid registry value in API response" exception = (e, catch_backtrace())
        return nothing
    end
    return Experimental.Registry(uuid, name)
end

"""
    JuliaHub.Experimental.registries() -> Vector{Experimental.Registry}

Return the list of registries configured on the JuliaHub instance.

$(Experimental._DOCS_EXPERIMENTAL_API)
"""
function Experimental.registries(auth::Authentication)
    # NOTE: this API endpoint is not considered stable as of now
    r = _restcall(auth, :GET, ("app", "packages", "registries"), nothing)
    if r.status != 200 || !r.json["success"]
        throw(JuliaHubError("Invalid response from JuliaHub (code $(r.status))\n$(r.body)"))
    end
    _parse_registry.(r.json["registries"])
end

"""
    JuliaHub.Experimental.register_package(
        auth::Authentication,
        registry::Union{AbstractString, Registry},
        repository_url::AbstractString;
        # Optional keyword arguments:
        [notes::AbstractString,]
        [branch::AbstractString,]
        [subdirectory::AbstractString,]
        [git_server_type::AbstractString]
    ) -> String | Nothing

Initiates a registration PR of the package at `repository_url` in
Returns the URL of the registry PR, or `nothing` if the registration failed.

# Example

```
using JuliaHub
auth = JuliaHub.authenticate("juliahub.com")
JuliaHub._registries(auth)

r = JuliaHub.Experimental.register_package(
    auth,
    "MyInternalRegistry",
    "https://github.com/MyUser/MyPackage.jl";
    notes = "This was initiated via JuliaHub.jl",
)
```

$(Experimental._DOCS_EXPERIMENTAL_API)
"""
function Experimental.register_package(
    auth::Authentication,
    registry::Union{AbstractString, Experimental.Registry},
    repository_url::AbstractString;
    notes::Union{AbstractString, Nothing}=nothing,
    branch::Union{AbstractString, Nothing}=nothing,
    subdirectory::AbstractString="",
    git_server_type::Union{AbstractString, Nothing}=nothing,
)
    if !isnothing(branch) && isempty(branch)
        throw(ArgumentError("branch can not be an empty string"))
    end
    git_server_type = if isnothing(git_server_type)
        if startswith(repository_url, "https://github.com")
            "github"
        else
            throw(
                ArgumentError(
                    "Unable to determine git_server_type for repository: $(repository_url)"
                ),
            )
        end
    else
        git_server_type
    end
    # Interpret the registry argument
    registry_name::String = if isa(registry, Experimental.Registry)
        registry.name
    else
        String(registry)
    end
    # Do the package registration POST request.
    # NOTE: this API endpoint is not considered stable as of now
    body = Dict(
        "requests" => [
            Dict(
                "registry_name" => registry_name,
                "repo_url" => repository_url,
                "branch" => something(branch, ""),
                "notes" => something(notes, ""),
                "subdir" => subdirectory,
                "git_server_type" => git_server_type,
            ),
        ],
    )
    r = _restcall(
        auth,
        :POST,
        ("app", "registrator", "register"),
        JSON.json(body);
        headers=["Content-Type" => "application/json"],
    )
    if r.status != 200
        throw(JuliaHubError("Invalid response from JuliaHub (code $(r.status))\n$(r.body)"))
    elseif !r.json["success"]
        error_message = get(get(r.json, "message", Dict()), "error", nothing)
        if isnothing(error_message)
            throw(JuliaHubError("Invalid response from JuliaHub (code $(r.status))\n$(r.body)"))
        end
        throw(InvalidRequestError(error_message))
    end
    id, message = r.json["id"], r.json["message"]
    @info "Initiated registration in $(registry_name)" id message repository_url
    sleep(1) # registration won't go through right away anyway
    status = _registration_status(auth, id)
    δt = 2
    while status.state == "pending"
        sleep(δt)
        δt = min(δt * 2, 10) # double the sleep time, to a max of 10s
        status = _registration_status(auth, id)
        if status.state == "pending"
            @info ".. waiting for registration to succeed" status.message
        end
    end
    if status.state != "success"
        @error "Registration failed ($id)" status.state status.message
        return nothing
    end
    return status.message
end

struct _RegistrationStatus
    state::String
    message::String
end

function _registration_status(auth::Authentication, id::AbstractString)
    # NOTE: this API endpoint is not considered stable as of now
    r = _restcall(
        auth,
        :POST,
        ("app", "registrator", "status"),
        JSON.json(Dict(
            "id" => id
        ));
        headers=["Content-Type" => "application/json"],
    )
    if r.status != 200 || !r.json["success"]
        throw(JuliaHubError("Invalid response from JuliaHub (code $(r.status))\n$(r.body)"))
    end
    return _RegistrationStatus(r.json["state"], r.json["message"])
end
