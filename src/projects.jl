"""
    struct ProjectNotSetError <: JuliaHubException

Exception thrown when the authentication object is not set to a project, nor was
an explicit project UUID provided, but the operation requires a project to be
specified.
"""
struct ProjectNotSetError <: JuliaHubException end

function Base.showerror(io::IO, e::ProjectNotSetError)
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
    struct ProjectDataset

A dataset object returned by the functions that return project dataset links.

Has the same fields as [`Dataset`](@ref) plus the following fields that are specific
to project-dataset links:

- `project_uuid::UUID`: identifies the project in the context of which the dataset was listed
- `is_writable :: Bool`: whether this dataset has been marked writable by the dataset owner
"""
struct ProjectDataset
    _dataset::Dataset
    project_uuid::UUIDs.UUID
    is_writable::Bool
end

function Base.getproperty(pd::ProjectDataset, name::Symbol)
    dataset = getfield(pd, :_dataset)
    if name in fieldnames(ProjectDataset)
        return getfield(pd, name)
    elseif name in propertynames(dataset)
        return getproperty(dataset, name)
    else
        throw(ArgumentError("No property $name for ProjectDataset"))
    end
end

function Base.show(io::IO, pd::ProjectDataset)
    print(
        io,
        "JuliaHub.project_dataset((\"",
        pd.owner,
        "\", \"",
        pd.name,
        "\"); project=\"",
        pd.project_uuid,
        "\")",
    )
end
function Base.show(io::IO, ::MIME"text/plain", pd::ProjectDataset)
    printstyled(io, "ProjectDataset:"; bold=true)
    print(io, " ", pd.name, " (", pd.dtype, ")")
    print(io, "\n owner: ", pd.owner)
    print(
        io, "\n project: ", pd.project_uuid, " ",
        pd.is_writable ? "(writable)" : "(not writable)",
    )
    print(io, "\n description: ", pd.description)
    print(io, "\n versions: ", length(pd.versions))
    print(io, "\n size: ", pd.size, " bytes")
    isempty(pd.tags) || print(io, "\n tags: ", join(pd.tags, ", "))
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
        if isnothing(auth.project_id)
            throw(ProjectNotSetError())
        else
            return auth.project_id
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
    JuliaHub.project_dataset(dataset::DatasetReference; [project::ProjectReference], [auth]) -> ProjectDataset

Looks up the specified dataset among the datasets attached to the project, returning a
[`ProjectDataset`](@ref) object, or throwing an [`InvalidRequestError`](@ref) if the project
does not have the dataset attached.

$(_DOCS_nondynamic_datasets_object_warning)
"""
function project_dataset end

function project_dataset(
    dataset::Union{Dataset, ProjectDataset};
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

Returns the list of datasets attached to the project, as a list of [`ProjectDataset`](@ref) objects.
If the project is not explicitly specified, it uses the project of the authentication object.
"""
function project_datasets end

function project_datasets(; auth::Authentication=__auth__())
    project_id = auth.project_id
    if isnothing(project_id)
        throw(ArgumentError("Not authenticated in the context of a project."))
    end
    return _project_datasets(auth, project_id)
end

function project_datasets(project::AbstractString; auth::Authentication=__auth__())
    project_uuid = tryparse(UUIDs.UUID, project)
    if isnothing(project_uuid)
        throw(ArgumentError("`project` must be a UUID, got '$(project)'"))
    end
    return project_datasets(project_uuid; auth)
end

function _project_datasets(auth::Authentication, project::UUIDs.UUID)
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
    n_erroneous_datasets = 0
    datasets = map(_parse_dataset_list(datasets)) do dataset
        try
            project_json = _get_json(dataset._json, "project", Dict)
            project_json_uuid = _get_json(project_json, "project_id", String; msg=".project")
            if project_json_uuid != string(project)
                @debug "Invalid dataset in GET /datasets?project= response" dataset project_json_uuid project
                n_erroneous_datasets += 1
                return nothing
            end
            is_writable = _get_json(
                project_json,
                "is_writable",
                Bool;
                msg="Unable to parse .project in /datasets?project response",
            )
            return ProjectDataset(dataset, project, is_writable)
        catch e
            isa(e, JuliaHubError) || rethrow(e)
            @debug "Invalid dataset in GET /datasets?project= response" dataset exception = (
                e, catch_backtrace()
            )
            n_erroneous_datasets += 1
            return nothing
        end
    end
    if n_erroneous_datasets > 0
        @warn "The JuliaHub GET /datasets?project= response contains erroneous project datasets. Omitting $(n_erroneous_datasets) entries."
    end
    # We'll filter down to just ProjectDataset objects, and enforce
    # type-stability of the array type here.
    return ProjectDataset[pd for pd in datasets if isa(pd, ProjectDataset)]
end

"""
    JuliaHub.upload_project_dataset(dataset::DatasetReference, local_path; [auth,] kwargs...) -> Dataset

Uploads a new version of a project-linked dataset.

!!! note "Permissions"

    Note that in order for this to work, you need to have edit rights on the projects and
    the dataset needs to have been marked writable by the dataset owner.

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
    ds::Union{Dataset, ProjectDataset},
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
        msg = "Unable to upload to dataset ($(ds.owner), $(ds.name)): $(r.json) (code: $(r.status))"
        throw(InvalidRequestError(msg))
    elseif r.status != 200
        # Other response codes indicate a backend failure
        _throw_invalidresponse(r)
    end
    # ...
    upload_config = _check_dataset_upload_config(r, dtype)
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
