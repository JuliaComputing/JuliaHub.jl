const _VALID_APP_CATEGORIES = (:default, :package, :user)

_DOCS_apps_experimental = """
!!! compat "Experimental API"

    Applications-related APIs are experimental, and may be changed or removed
    without notice.
"""

# Internal object to store registry information
struct _RegistryInfo
    id::Int
    name::String
    uuid::UUIDs.UUID

    function _RegistryInfo(json::AbstractDict; var="_RegistryInfo")
        id = _json_get(json, "id", Integer; var)
        name = _json_get(json, "name", AbstractString; var)
        uuid = _json_get(json, "uuid", UUIDs.UUID; var, parse=true)
        new(id, name, uuid)
    end
end

function _api_registries(auth::Authentication)::Vector{_RegistryInfo}
    r = _restcall(auth, :GET, "app", "packages", "registries")
    json, _ = _parse_response_json(r, AbstractDict)
    _json_check_success(json; var="app/packages/registries")
    registries = _json_get(json, "registries", Vector; var="app/packages/registries")
    # Note: this broadcast can return Any[] if `registries` is empty, hence
    # the need for a return type.
    return _RegistryInfo.(registries; var="app/packages/registries")
end

"""
    abstract type AbstractJuliaHubApp

Abstract supertype for JuliaHub applications object types.

$(_DOCS_apps_experimental)
"""
abstract type AbstractJuliaHubApp end

function Base.show(io::IO, app::AbstractJuliaHubApp)
    print(io, "JuliaHub.application(:", _app_category(app), ", \"", app.name, "\")")
end

# Fallback definition, but it can be overridden for particular types
_appname(app::AbstractJuliaHubApp) = app.name

"""
    struct DefaultApp <: AbstractJuliaHubApp

Represents a default JuliaHub instance application, and they can be started as jobs with
[`submit_job`](@ref).

The list of available applications can be accessed via the [`applications`](@ref) function,
and specific applications can be picked out with [`application`](@ref).

```jldoctest
julia> apps = JuliaHub.applications(:default)
4-element Vector{JuliaHub.DefaultApp}:
 JuliaHub.application(:default, "Linux Desktop")
 JuliaHub.application(:default, "Julia IDE")
 JuliaHub.application(:default, "Pluto")
 JuliaHub.application(:default, "Windows Workstation")

julia> JuliaHub.application(:default, "Pluto")
DefaultApp
 name: Pluto
 key: pluto
```

$(_DOCS_apps_experimental)
"""
struct DefaultApp <: AbstractJuliaHubApp
    name::String
    _appargs::Vector{Dict}
    _apptype::String
    _json::Dict{String, Any}

    function DefaultApp(json::AbstractDict, appargs::AbstractVector)
        apptype = _json_get(json, "appType", AbstractString; var="default app")
        name = _json_get(json, "name", AbstractString; var="default app")
        new(name, appargs, apptype, json)
    end
end
_app_category(::DefaultApp) = :default

function Base.show(io::IO, ::MIME"text/plain", app::DefaultApp)
    printstyled(io, nameof(typeof(app)); bold=true)
    print(io, '\n', " name: ", app.name)
    print(io, '\n', " key: ", app._apptype)
end

"""
    struct PackageApp <: AbstractJuliaHubApp

Represents a JuliaHub package application that is available in one of the instance's package
registries. These packages can be started as JuliaHub jobs with [`submit_job`](@ref).

The list of available applications can be accessed via the [`applications`](@ref) function,
and specific applications can be picked out with [`application`](@ref).

```jldoctest
julia> apps = JuliaHub.applications(:package)
2-element Vector{JuliaHub.PackageApp}:
 JuliaHub.application(:package, "RegisteredPackageApp")
 JuliaHub.application(:package, "CustomDashboardApp")

julia> JuliaHub.application(:package, "RegisteredPackageApp")
PackageApp
 name: RegisteredPackageApp
 uuid: db8b4d46-bfad-4aa5-a5f8-40df1e9542e5
 registry: General (23338594-aafe-5451-b93e-139f81909106)
```

See also: [`help.juliahub.com` on applications](https://help.juliahub.com/juliahub/stable/tutorials/applications/)

$(_DOCS_apps_experimental)
"""
struct PackageApp <: AbstractJuliaHubApp
    name::String
    _uuid::UUIDs.UUID
    _registry::_RegistryInfo
    _json::Dict{String, Any}

    function PackageApp(json::AbstractDict, registries::Vector{_RegistryInfo})
        name = _json_get(json, "name", AbstractString; var="registered app")
        uuid = _json_get(json, "uuid", UUIDs.UUID; var="registered app", parse=true)
        registrymap = _json_get(json, "registrymap", Vector; var="registered app")
        isempty(registrymap) && throw(JuliaHubError("""
        Invalid JSON response from JuliaHub (registered app): empty 'registrymap'
        JSON: $(sprint(show, MIME("text/plain"), json))
        """))
        length(registrymap) > 1 && @warn "Multiple registries for $name ($uuid)"
        registry_id = _json_get(first(registrymap), "id", Int; var="registered app", parse=true)
        registry = _find_registry(registries, registry_id)
        isnothing(registry) && throw(JuliaHubError("""
        Invalid JSON response from JuliaHub (registered app): invalid registry ID $(registry_id)
        JSON: $(sprint(show, MIME("text/plain"), json))
        """))
        new(name, uuid, registry, json)
    end
end
_app_category(::PackageApp) = :package

function Base.show(io::IO, ::MIME"text/plain", app::PackageApp)
    printstyled(io, nameof(typeof(app)); bold=true)
    print(io, '\n', " name: ", app.name)
    print(io, '\n', " uuid: ", app._uuid)
    print(io, '\n', " registry: ", app._registry.name, " (", app._registry.uuid, ")")
end

"""
    struct UserApp <: AbstractJuliaHubApp

Represents a private application that has been added to the user account via a
Git repository. These applications can be started as JuliaHub jobs with [`submit_job`](@ref).

The list of available applications can be accessed via the [`applications`](@ref) function,
and specific applications can be picked out with [`application`](@ref).

```jldoctest
julia> apps = JuliaHub.applications(:user)
1-element Vector{JuliaHub.UserApp}:
 JuliaHub.application(:user, "ExampleApp.jl")

julia> JuliaHub.application(:user, "ExampleApp.jl")
UserApp
 name: ExampleApp.jl
 repository: https://github.com/JuliaHubExampleOrg/ExampleApp.jl
```

See also: [`help.juliahub.com` on applications](https://help.juliahub.com/juliahub/stable/tutorials/applications/)

$(_DOCS_apps_experimental)
"""
struct UserApp <: AbstractJuliaHubApp
    name::String
    _repository::String
    _json::Dict{String, Any}

    function UserApp(json::AbstractDict)
        name = _json_get(json, "name", AbstractString; var="user app")
        repository_url = _json_get(json, "repourl", AbstractString; var="user app")
        new(name, repository_url, json)
    end
end
_app_category(::UserApp) = :user

function Base.show(io::IO, ::MIME"text/plain", app::UserApp)
    printstyled(io, nameof(typeof(app)); bold=true)
    print(io, '\n', " name: ", app.name)
    print(io, '\n', " repository: ", app._repository)
end

"""
    JuliaHub.applications([category::Symbol]; [auth::Authentication]) -> Vector{AbstractJuliaHubApp}

Returns the list of applications enabled for the authenticated user, optionally in the specified
category only. Returns a vector of [`AbstractJuliaHubApp`](@ref) instances.

```jldoctest
julia> JuliaHub.applications()
7-element Vector{JuliaHub.AbstractJuliaHubApp}:
 JuliaHub.application(:default, "Linux Desktop")
 JuliaHub.application(:default, "Julia IDE")
 JuliaHub.application(:default, "Pluto")
 JuliaHub.application(:default, "Windows Workstation")
 JuliaHub.application(:package, "RegisteredPackageApp")
 JuliaHub.application(:package, "CustomDashboardApp")
 JuliaHub.application(:user, "ExampleApp.jl")

julia> JuliaHub.applications(:default)
4-element Vector{JuliaHub.DefaultApp}:
 JuliaHub.application(:default, "Linux Desktop")
 JuliaHub.application(:default, "Julia IDE")
 JuliaHub.application(:default, "Pluto")
 JuliaHub.application(:default, "Windows Workstation")

julia> JuliaHub.applications(:package)
2-element Vector{JuliaHub.PackageApp}:
 JuliaHub.application(:package, "RegisteredPackageApp")
 JuliaHub.application(:package, "CustomDashboardApp")

julia> JuliaHub.applications(:user)
1-element Vector{JuliaHub.UserApp}:
 JuliaHub.application(:user, "ExampleApp.jl")

```

$(_DOCS_apps_experimental)
"""
function applications end

function applications(category::Symbol; auth::Authentication=__auth__())
    if category == :default
        return filter!(!_is_batch_app, _apps_default(auth))
    elseif category == :package
        registries = _api_registries(auth)
        return _api_apps_registered(auth, registries)
    elseif category == :user
        return _api_apps_userapps(auth)
    end
    err = """Invalid `category` value: `$category`
    Must be one of: $(join(string.(":", _VALID_APP_CATEGORIES), ", "))"""
    throw(ArgumentError(err))
end

function applications(; auth::Authentication=__auth__())
    vcat(
        applications(:default; auth),
        applications(:package; auth),
        applications(:user; auth),
    )
end

function _api_apps_default(auth::Authentication)
    r = _restcall(auth, :GET, "app", "applications", "default")
    r.status == 200 || _throw_invalidresponse(r; msg="Unable to list default applications.")
    return _parse_response_json(r, AbstractDict)
end

function _apps_default(auth::Authentication)
    json, _ = _api_apps_default(auth)
    default_apps_json = _json_get(json, "defaultApps", Vector; var="user app")
    appargs = _json_get(json, "defaultUserAppArgs", Vector; var="user app")
    return [DefaultApp(app_json, appargs) for app_json in default_apps_json]
end

function _api_apps_registered(auth::Authentication, registries::AbstractVector{_RegistryInfo})
    r = _restcall(auth, :GET, "app", "applications", "info")
    r.status == 200 || _throw_invalidresponse(r; msg="Unable to list registered applications.")
    json, _ = _parse_response_json(r, Vector)
    return [PackageApp(app, registries) for app in json]
end

function _api_apps_userapps(auth::Authentication)
    r = _restcall(auth, :GET, "app", "applications", "myapps")
    r.status == 200 || _throw_invalidresponse(r; msg="Unable to list user applications.")
    json, _ = _parse_response_json(r, Vector)
    return UserApp.(json)
end

function _find_registry(registries::AbstractVector{_RegistryInfo}, id::Integer)
    idx = findfirst(app -> app.id == id, registries)
    return isnothing(idx) ? nothing : registries[idx]
end

"""
    JuliaHub.application(
        category::Symbol, name::AbstractString;
        throw::Bool=true, [auth::Authentication]
    ) -> AbstractJuliaHubApp

Returns the application corresponding to `name` from the specified category of applications.
Will throw an [`InvalidRequestError`](@ref) if the application can't be found, or returns
`nothing` in this situation if `throw=false` is passed.

`category` specifies the application category and must be one of: `:default`,
`:package`, or `:user`. This is necessary to disambiguate apps with the same name
in the different categories.

See also: [`applications`](@ref).

## Examples

```jldoctest
julia> JuliaHub.applications()
7-element Vector{JuliaHub.AbstractJuliaHubApp}:
 JuliaHub.application(:default, "Linux Desktop")
 JuliaHub.application(:default, "Julia IDE")
 JuliaHub.application(:default, "Pluto")
 JuliaHub.application(:default, "Windows Workstation")
 JuliaHub.application(:package, "RegisteredPackageApp")
 JuliaHub.application(:package, "CustomDashboardApp")
 JuliaHub.application(:user, "ExampleApp.jl")
```

$(_DOCS_apps_experimental)
"""
function application(
    category::Symbol, name::AbstractString; throw::Bool=true, auth::Authentication=__auth__()
)
    apps = applications(category; auth)
    idx = findfirst(app -> _appname(app) == name, apps)
    if isnothing(idx)
        return _throw_or_nothing(; msg="No application matching ($category, $name)", throw)
    end
    return apps[idx]
end
