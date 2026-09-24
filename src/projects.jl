"""
    struct ProjectNotSetError <: JuliaHubException

Exception thrown by a project-related operation that requires a project to be specified,
but neither an explicit project reference was provided, nor was the project set for the
authentication object.
"""
struct ProjectNotSetError <: JuliaHubException end

function Base.showerror(io::IO, ::ProjectNotSetError)
    print(io, "ProjectNotSetError: authentication object not associated with a project")
end

function _assert_projects_enabled(auth::Authentication)
    # The different project APIs are only present in JuliaHub 6.9 and later.
    if auth._api_version < v"0.2.0"
        msg = "Project APIs got added in JuliaHub 6.9 (expected API version >= 0.2.0, got $(auth._api_version), for $(auth.server))"
        throw(InvalidJuliaHubVersion(msg))
    end
end

"""
    const ProjectReference :: Type

Type constraint on the argument that specifies the project in projects-related
APIs that (e.g. [`project_datasets`](@ref)).

Presently, you can specify the project by directly passing the project UUID.
The UUID should be either a string (`<: AbstractString`) or an `UUIDs.UUID` object.
"""
const ProjectReference = Union{AbstractString, UUIDs.UUID}

# Parses the standard project::Union{ProjectReference, Nothing} we pass to
# project_* function into a project UUID object (or throws the appropriate error).
# If project is nothing, we fall back to the project_id of the authentication object,
# if present.
function _project_uuid(auth::Authentication, project::Union{ProjectReference, Nothing})::UUIDs.UUID
    if isnothing(project)
        project_id = auth.project_id
        if isnothing(project_id)
            throw(ProjectNotSetError())
        else
            return project_id
        end
    elseif isa(project, UUIDs.UUID)
        return project
    elseif isa(project, AbstractString)
        project_uuid = tryparse(UUIDs.UUID, project)
        if isnothing(project_uuid)
            throw(ArgumentError("`project` must be a UUID, got '$(project)'"))
        end
        return project_uuid
    else
        error("Bug. Unimplemented project reference: $(project)::$(typeof(project))")
    end
end

"""
    JuliaHub.project_dataset(dataset::DatasetReference; [project::ProjectReference], [auth]) -> Dataset

Looks up the specified dataset among the datasets attached to the project, returning a
[`Dataset`](@ref) object, or throwing an [`InvalidRequestError`](@ref) if the project
does not have such dataset attached.

```jldoctest; setup = :(Main.projectauth_setup!()), teardown = :(Main.projectauth_teardown!())
julia> JuliaHub.project_dataset(("username", "blobtree/example"))
Dataset: blobtree/example (BlobTree)
 owner: username
 description: An example dataset
 versions: 1
 size: 57 bytes
 tags: tag1, tag2
 project: cd6c9ee3-d15f-414f-a762-7e1d3faed835 (not writable)
```

!!! note "Implicit dataset owner"

    When passing just the dataset name for `dataset` (i.e. `<: AbstractString`), then, just
    like for the non-project [`JuliaHub.dataset`](@ref) function, it is assumed that the owner
    of the dataset should be the currently authenticated user.

    However, a project may have multiple datasets with the same name attached to it (if they are
    owned by different users). The best practice when accessing datasets in the context of projects is
    to fully specify their name (i.e. also include the username).

$(_DOCS_nondynamic_datasets_object_warning)
"""
function project_dataset end

function project_dataset(
    dataset::Dataset;
    project::Union{ProjectReference, Nothing}=nothing,
    auth::Authentication=__auth__(),
)
    _assert_projects_enabled(auth)
    project_uuid = _project_uuid(auth, project)
    datasets = _project_datasets(auth, project_uuid)
    for project_dataset in datasets
        if project_dataset.uuid == dataset.uuid
            return project_dataset
        end
    end
    throw(
        InvalidRequestError(
            "Dataset uuid:$(dataset.uuid) ('$(dataset.username)/$(dataset.dataset_name)') not attached to project '$(project_uuid)'."
        ),
    )
end

function project_dataset(
    dsref::_DatasetRefTuple;
    project::Union{ProjectReference, Nothing}=nothing,
    auth::Authentication=__auth__(),
)
    username, dataset_name = dsref
    project_uuid = _project_uuid(auth, project)
    datasets = _project_datasets(auth, project_uuid)
    for dataset in datasets
        if (dataset.owner == username) && (dataset.name == dataset_name)
            return dataset
        end
    end
    throw(
        InvalidRequestError(
            "Dataset '$(username)/$(dataset_name)' not attached to project '$(project_uuid)'."
        ),
    )
end

function project_dataset(
    dataset_name::AbstractString;
    project::Union{ProjectReference, Nothing}=nothing,
    auth::Authentication=__auth__(),
)
    return project_dataset((auth.username, dataset_name); project, auth)
end

"""
    JuliaHub.project_datasets([project::ProjectReference]; [auth::Authentication]) -> Vector{Dataset}

Returns the list of datasets attached to the project, as a list of [`Dataset`](@ref) objects.
If the project is not explicitly specified, it uses the project of the authentication object.

May throw a [`ProjectNotSetError`](@ref). Will throw an [`InvalidRequestError`] if the currently
authenticated user does not have access to the project or the project does not exists.

```jldoctest; setup = :(Main.projectauth_setup!()), teardown = :(Main.projectauth_teardown!())
julia> JuliaHub.current_authentication()
JuliaHub.Authentication("https://juliahub.com", "username", *****; project_id = "cd6c9ee3-d15f-414f-a762-7e1d3faed835")

julia> JuliaHub.project_datasets()
3-element Vector{JuliaHub.Dataset}:
 JuliaHub.project_dataset(("username", "example-dataset"); project="cd6c9ee3-d15f-414f-a762-7e1d3faed835")
 JuliaHub.project_dataset(("anotheruser", "publicdataset"); project="cd6c9ee3-d15f-414f-a762-7e1d3faed835")
 JuliaHub.project_dataset(("username", "blobtree/example"); project="cd6c9ee3-d15f-414f-a762-7e1d3faed835")
```
"""
function project_datasets(
    project::Union{ProjectReference, Nothing}=nothing;
    auth::Authentication=__auth__(),
)
    project_uuid = _project_uuid(auth, project)
    if isnothing(project_uuid)
        throw(ArgumentError("`project` must be a UUID, got '$(project)'"))
    end
    return _project_datasets(auth, project_uuid)
end

function _project_datasets(auth::Authentication, project::UUIDs.UUID)
    _assert_projects_enabled(auth)
    r = JuliaHub._restcall(
        auth, :GET, ("datasets",), nothing;
        query=["project" => string(project)],
    )
    if r.status == 400
        throw(
            InvalidRequestError(
                "Unable to fetch datasets for project '$(project)' ($(r.body))"
            ),
        )
    elseif r.status != 200
        JuliaHub._throw_invalidresponse(r; msg="Unable to fetch datasets.")
    end
    datasets, _ = JuliaHub._parse_response_json(r, Vector)
    return _parse_dataset_list(datasets; expected_project=project)
end

"""
    JuliaHub.upload_project_dataset(
        dataset::DatasetReference, local_path;
        progress=true,
        [project::ProjectReference],
        [auth::Authentication],
    ) -> Dataset

Uploads a new version of a project-linked dataset.

By default, the new dataset version will be associated with the project of the current authentication
session (if any), but this can be overridden by passing `project`.

!!! note "Permissions"

    Note that in order for this to work, you need to have edit rights on the projects and
    the dataset needs to have been marked writable by the dataset owner. However, unlike for
    normal datasets uploads (with [`upload_dataset`](@ref)), you do not need to be the dataset
    owner to upload new versions.

!!! tip

    The function call is functionally equivalent to the following [`upload_dataset`](@ref) call

    ```
    JuliaHub.upload_dataset(
        dataset, local_path;
        create=false, update=true, replace=false,
    )
    ```

    except that the upload is associated with a project.
"""
function upload_project_dataset end

function upload_project_dataset(
    ds::Dataset,
    local_path::AbstractString;
    progress::Bool=true,
    project::Union{ProjectReference, Nothing}=nothing,
    # Authentication
    auth::Authentication=__auth__(),
)
    project_uuid = _project_uuid(auth, project)
    dtype = _dataset_dtype(local_path)

    # Actually attempt the upload
    r = _open_dataset_version(auth, ds.uuid, project_uuid)
    if r.status in (400, 403, 404)
        # These response codes indicate a problem with the request
        msg = "Unable to upload to dataset ($(ds.owner), $(ds.name)): $(r.body) (code: $(r.status))"
        throw(InvalidRequestError(msg))
    elseif r.status != 200
        # Other response codes indicate a backend failure
        _throw_invalidresponse(r)
    end
    # ...
    upload_config = _check_dataset_upload_config(r, dtype; newly_created_dataset=false)
    # Upload the actual data
    try
        _upload_dataset(upload_config, local_path; progress)
    catch e
        throw(JuliaHubError("Data upload failed", e, catch_backtrace()))
    end
    # Finalize the upload
    try
        # _close_dataset_version will also throw on non-200 responses
        r = _close_dataset_version(auth, ds.uuid, upload_config; local_path)
        if r.status != 200
        end
    catch e
        throw(JuliaHubError("Finalizing upload failed", e, catch_backtrace()))
    end
    # If everything was successful, we'll return an updated DataSet object.
    return project_dataset(ds; project, auth)
end

function upload_project_dataset(
    dataset::Union{_DatasetRefTuple, AbstractString},
    local_path::AbstractString;
    progress::Bool=true,
    project::Union{ProjectReference, Nothing}=nothing,
    # Authentication
    auth::Authentication=__auth__(),
)
    project_uuid = _project_uuid(auth, project)
    dataset = project_dataset(dataset; project=project_uuid, auth)
    return upload_project_dataset(dataset, local_path; progress, project=project_uuid, auth)
end

# This calls the /datasets/{uuid}/versions?project={uuid} endpoint,
# which is different from /user/datasets/{name}/versions endpoint
# the other method calls.
function _open_dataset_version(
    auth::Authentication, dataset_uuid::UUID, project_uuid::UUID
)::_RESTResponse
    body = Dict("project" => string(project_uuid))
    r = JuliaHub._restcall(
        auth,
        :POST,
        ("datasets", string(dataset_uuid), "versions"),
        JSON.json(body),
    )
    _check_internal_error(r; var="POST /user/datasets/{name}/versions")
    return r
end

function _close_dataset_version(
    auth::Authentication, dataset_uuid::UUID, upload_config; local_path
)::_RESTResponse
    body = Dict(
        "upload_id" => upload_config["upload_id"],
        "action" => "close",
    )
    if isnothing(local_path)
        body["filename"] = local_path
    end
    return _restcall(
        auth,
        :POST,
        ("datasets", string(dataset_uuid), "versions"),
        JSON.json(body);
        headers=["Content-Type" => "application/json"],
    )
end

"""
    struct ProjectDeploymentSpec

Represents a deployment specification of a deployable JuliaHub project. Deployment
specifications are managed in the JuliaHub web UI, and can be listed with
[`project_deployment_specs`](@ref). A project can be deployed according to a specification
with [`deploy_project`](@ref).

Objects have the following properties:

* `id :: Int`: the numeric ID of the specification (unique across the JuliaHub instance)
* `project_id :: UUID`: the UUID of the project the specification belongs to
* `name :: String`: the (project-unique) name of the specification
* `description :: String`: description of the specification
* `machine_type :: String`: the JuliaHub machine type the deployment runs on (e.g. `"m64"`)
* `port :: Int`: the port the deployed application listens on
* `authentication :: String`: how access to the deployment is authenticated (e.g. `"me"`,
  `"password"`)
* `sysimage_build :: Bool`: whether a system image is built for the deployment
* `default :: Bool`: whether this is the default deployment specification of the project
"""
struct ProjectDeploymentSpec
    id::Int
    project_id::UUIDs.UUID
    name::String
    description::String
    machine_type::String
    port::Int
    authentication::String
    sysimage_build::Bool
    default::Bool
    _json::Dict{String, Any}

    function ProjectDeploymentSpec(json::AbstractDict)
        var = "project deployment spec"
        id = _json_get(json, "spec_id", Integer; var)
        project_id = _json_get(json, "project_id", UUIDs.UUID; var, parse=true)
        name = _json_get(json, "name", AbstractString; var)
        description = _get_json_or(json, "description", AbstractString, "")
        machine_type = _get_json_or(json, "machineType", AbstractString, "")
        port = _get_json_or(json, "port", Integer, 0)
        authentication = _get_json_or(json, "authentication", AbstractString, "")
        sysimage_build = _get_json_or(json, "sysimageBuild", Bool, false)
        default = _get_json_or(json, "default", Bool, false)
        new(
            id, project_id, name, description, machine_type, port, authentication,
            sysimage_build, default, Dict{String, Any}(json),
        )
    end
end

function Base.show(io::IO, spec::ProjectDeploymentSpec)
    print(io, "JuliaHub.ProjectDeploymentSpec(", spec.id, ", \"", spec.name, "\")")
end

function Base.show(io::IO, ::MIME"text/plain", spec::ProjectDeploymentSpec)
    printstyled(io, "ProjectDeploymentSpec:"; bold=true)
    print(io, " ", spec.name, " (id: ", spec.id, ")")
    spec.default && print(io, " [default]")
    print(io, "\n project: ", spec.project_id)
    isempty(spec.description) || print(io, "\n description: ", spec.description)
    print(io, "\n machine type: ", spec.machine_type)
    print(io, "\n port: ", spec.port)
    print(io, "\n authentication: ", spec.authentication)
    print(io, "\n sysimage build: ", spec.sysimage_build)
end

"""
    JuliaHub.project_deployment_specs([project::ProjectReference]; [auth::Authentication]) -> Vector{ProjectDeploymentSpec}

Returns the list of deployment specifications ([`ProjectDeploymentSpec`](@ref) objects)
of the project. If `project` is omitted, the project associated with the authentication
object is used.

Throws an [`InvalidRequestError`](@ref) if the project does not exist, if the user does not
have owner or editor access to it, or if the project is not a deployable project.

```jldoctest; setup = :(Main.projectauth_setup!()), teardown = :(Main.projectauth_teardown!())
julia> JuliaHub.project_deployment_specs()
2-element Vector{JuliaHub.ProjectDeploymentSpec}:
 JuliaHub.ProjectDeploymentSpec(33, "Default")
 JuliaHub.ProjectDeploymentSpec(96, "Large")
```
"""
function project_deployment_specs(
    project::Union{ProjectReference, Nothing}=nothing;
    auth::Authentication=__auth__(),
)
    project_uuid = _project_uuid(auth, project)
    return _project_deployment_specs(auth, project_uuid)
end

function _project_deployment_specs(
    auth::Authentication, project::UUIDs.UUID
)::Vector{ProjectDeploymentSpec}
    _assert_projects_enabled(auth)
    r = _restcall(auth, :GET, "api", "v1", "jobs", "project", string(project), "deploymentspec")
    _check_project_deployment_response(r, project; msg="Unable to fetch deployment specifications")
    specs, _ = _parse_response_json(r, Vector)
    return ProjectDeploymentSpec[ProjectDeploymentSpec(spec) for spec in specs]
end

# The project deployment endpoints return a bare 404 if the project does not exist
# (or the user does not have owner/editor access to it), and a 400 with a JSON
# {"message": ...} for other client errors (e.g. project is not deployable).
function _check_project_deployment_response(
    r::_RESTResponse, project::UUIDs.UUID; msg::AbstractString
)
    r.status == 200 && return nothing
    if r.status == 404
        throw(
            InvalidRequestError(
                "$(msg): project '$(project)' does not exist, or you do not have access to it."
            ),
        )
    elseif r.status == 400
        message = try
            json, _ = _parse_response_json(r, AbstractDict)
            _get_json_or(json, "message", AbstractString, String(r.body))
        catch
            String(r.body)
        end
        throw(InvalidRequestError("$(msg) for project '$(project)': $(message)"))
    end
    _throw_invalidresponse(r; msg)
end

"""
    JuliaHub.deploy_project(
        [project::ProjectReference];
        [spec::Union{ProjectDeploymentSpec, Integer, AbstractString}],
        [auth::Authentication]
    ) -> Job

Starts a new deployment of the project, according to one of its deployment specifications,
and returns the corresponding [`Job`](@ref) object. If `project` is omitted, the project
associated with the authentication object is used.

The deployment specification can be specified with `spec`, either as a
[`ProjectDeploymentSpec`](@ref) object, its numeric ID, or its name (see
[`project_deployment_specs`](@ref)). If `spec` is omitted, the project's default deployment
specification is used. If the project has no default specification, but has exactly one
specification, that one is used. Otherwise an [`InvalidRequestError`](@ref) is thrown.

Also throws an [`InvalidRequestError`](@ref) if the project does not exist, if the user does
not have owner or editor access to it, if the project is not a deployable project, or if the
specified deployment specification does not exist.

!!! note

    JuliaHub bundles the project before queueing the deployment job, so it can take a little
    while for the job to become visible. This function blocks until the job can be queried
    (up to a few minutes), and throws a [`JuliaHubError`](@ref) with the job name if the job
    does not show up in that time.

```jldoctest; setup = :(Main.projectauth_setup!()), teardown = :(Main.projectauth_teardown!())
julia> job = JuliaHub.deploy_project(; spec="Large")
JuliaHub.Job: jr-xf4tslavut (Completed)
 submitted: 2023-03-15T07:56:50.974+00:00
 started:   2023-03-15T07:56:51.251+00:00
 finished:  2023-03-15T07:56:59.000+00:00
 files:
  - code.jl (input; 3 bytes)
  - code.jl (source; 3 bytes)
  - Project.toml (project; 244 bytes)
  - Manifest.toml (project; 9056 bytes)
 outputs: "{}"
```

$(_DOCS_nondynamic_job_object_warning)
"""
function deploy_project(
    project::Union{ProjectReference, Nothing}=nothing;
    spec::Union{ProjectDeploymentSpec, Integer, AbstractString, Nothing}=nothing,
    auth::Authentication=__auth__(),
)
    project_uuid = _project_uuid(auth, project)
    _assert_projects_enabled(auth)
    spec_id = _project_deployment_spec_id(auth, project_uuid, spec)
    r = _restcall(
        auth, :POST,
        (
            "api",
            "v1",
            "jobs",
            "project",
            string(project_uuid),
            "deploymentspec",
            string(spec_id),
            "submit",
        ),
        nothing,
    )
    if r.status == 404
        # The endpoint also returns a bare 404 if the specification does not exist
        # (for a project the user does have access to).
        throw(
            InvalidRequestError(
                "Unable to deploy project '$(project_uuid)': deployment specification $(spec_id) not found, or project does not exist."
            ),
        )
    end
    _check_project_deployment_response(r, project_uuid; msg="Unable to deploy project")
    json, jsonstr = _parse_response_json(r, AbstractDict)
    data = _get_json_or(json, "data", AbstractDict, nothing)
    jobname = isnothing(data) ? nothing : _get_json_or(data, "job_name", AbstractString, nothing)
    if isnothing(jobname)
        throw(JuliaHubError("Invalid JSON returned by the server (missing job_name):\n$(jsonstr)"))
    end
    return _wait_for_deployment_job(auth, jobname)
end

# How long deploy_project waits for the newly submitted deployment job to become
# queryable (in seconds). A Ref so that the tests can shorten it.
const _DEPLOY_PROJECT_JOB_TIMEOUT = Base.RefValue(300.0)

# Unlike the legacy submit_job endpoint, the project deployment submit endpoint returns
# before the job is queryable: the server first bundles the project and only then queues
# the job. So we need to poll for a bit for the job to show up.
function _wait_for_deployment_job(auth::Authentication, jobname::AbstractString)::Job
    deadline = time() + _DEPLOY_PROJECT_JOB_TIMEOUT[]
    interval = 1.0
    while true
        j = job(jobname; throw=false, auth)
        isnothing(j) || return j
        if time() >= deadline
            throw(
                JuliaHubError(
                    "Deployment job '$(jobname)' was submitted, but is not visible after $(_DEPLOY_PROJECT_JOB_TIMEOUT[]) seconds. Use JuliaHub.job(\"$(jobname)\") to look it up later."
                ),
            )
        end
        sleep(min(interval, max(deadline - time(), 0.0)))
        interval = min(2 * interval, 10.0)
    end
end

# Resolves the `spec` argument of deploy_project into a spec ID. The specification list
# only gets fetched if we need it (i.e. for name lookups, or to determine the default spec).
function _project_deployment_spec_id(
    auth::Authentication, project::UUIDs.UUID,
    spec::Union{ProjectDeploymentSpec, Integer, AbstractString, Nothing},
)::Int
    if isa(spec, ProjectDeploymentSpec)
        spec.project_id == project || throw(
            ArgumentError(
                "Deployment specification '$(spec.name)' belongs to project '$(spec.project_id)', not '$(project)'"
            ),
        )
        return spec.id
    elseif isa(spec, Integer)
        spec > 0 || throw(ArgumentError("Invalid deployment specification ID: $(spec)"))
        return Int(spec)
    end
    specs = _project_deployment_specs(auth, project)
    if isa(spec, AbstractString)
        idx = findfirst(s -> s.name == spec, specs)
        isnothing(idx) && throw(
            InvalidRequestError(
                "Project '$(project)' does not have a deployment specification named '$(spec)'. Available: $(join(map(s -> "'$(s.name)'", specs), ", "))"
            ),
        )
        return specs[idx].id
    end
    # spec === nothing: fall back to the default specification, or the only specification
    isempty(specs) && throw(
        InvalidRequestError("Project '$(project)' does not have any deployment specifications.")
    )
    idx = findfirst(s -> s.default, specs)
    isnothing(idx) || return specs[idx].id
    length(specs) == 1 && return only(specs).id
    throw(
        InvalidRequestError(
            "Project '$(project)' has no default deployment specification; pass `spec` explicitly. Available: $(join(map(s -> "'$(s.name)'", specs), ", "))"
        ),
    )
end
