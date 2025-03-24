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
 JuliaHub.project_dataset(("username", "example-dataset"); project=cd6c9ee3-d15f-414f-a762-7e1d3faed835)
 JuliaHub.project_dataset(("anotheruser", "publicdataset"); project=cd6c9ee3-d15f-414f-a762-7e1d3faed835)
 JuliaHub.project_dataset(("username", "blobtree/example"); project=cd6c9ee3-d15f-414f-a762-7e1d3faed835)
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
        query=(; project=string(project)),
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
    return JuliaHub._restcall(
        auth,
        :POST,
        ("datasets", string(dataset_uuid), "versions"),
        JSON.json(body),
    )
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
