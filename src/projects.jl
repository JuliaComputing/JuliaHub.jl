struct ProjectDataset
    project_uuid::UUIDs.UUID
    dataset::Dataset
    is_writable::Bool
end

function Base.getproperty(pd::ProjectDataset, name::Symbol)
    if name in fieldnames(ProjectDataset)
        return getfield(pd, name)
    elseif name in propertynames(Dataset)
        return getproperty(getfield(pd, :dataset), name)
    else
        throw(ArgumentError("No property $name for ProjectDataset"))
    end
end


"""
    struct ProjectNotSetError <: JuliaHubException

Exception thrown when the authentication object is not set to a project, but the
operation is meant to take place in the context of a project.
"""
struct ProjectNotSetError <: JuliaHubException end
function Base.showerror(io::IO, e::ProjectNotSetError)
    print(io, "ProjectNotSetError: authentication object not associated with a project")
end

const ProjectReference = Union{AbstractString, UUIDs.UUID}

# Parses the standard project::Union{ProjectReference, Nothing} we pass to
# project_* function into a project UUID object (or throws the appropriate error).
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
JuliaHub.project_dataset(dataset::DatasetReference; [project::ProjectReference], [auth]) -> Dataset

Looks up a dataset in the context of a project.
"""
function project_dataset end

function project_dataset(
    dataset::Dataset;
    project::Union{ProjectReference, Nothing},
    auth::Authentication=__auth__(),
)
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
    project::Union{ProjectReference, Nothing},
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
    project::Union{ProjectReference, Nothing},
    auth::Authentication=__auth__(),
)
    return project_dataset((auth.username, dataset_name); project, auth)
end

"""
    JuliaHub.project_datasets([project::Union{AbstractString, UUID}]; [auth::Authentication]) -> Vector{Dataset}

Returns the list of datasets linked to the given project.
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
    return map(_parse_dataset_list(datasets)) do dataset
        @assert dataset._json["project"]["project_id"] == string(project)
        ProjectDataset(project, dataset, dataset._json["project"]["is_writable"])
    end
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
    dataset::Dataset,
    local_path::AbstractString;
    progress::Bool=true,
    project::Union{ProjectReference, Nothing}=nothing,
    # Authentication
    auth::Authentication=__auth__(),
)
    project_uuid = _project_uuid(auth, project)
    dtype = _dataset_dtype(local_path)

    # Actually attempt the upload
    r = _open_dataset_version(auth, dataset.uuid, project_uuid)
    if r.status in (400, 403, 404)
        throw(
            InvalidRequestError(
                "Can't upload :cry:"
            ),
        )
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
        _close_dataset_version(auth, dataset_name, upload_config; local_path)
    catch e
        throw(JuliaHubError("Finalizing upload failed", e, catch_backtrace()))
    end
    # If everything was successful, we'll return an updated DataSet object.
    return dataset((username, dataset_name); auth)
end

function upload_project_dataset(
    ::Union{_DatasetRefTuple, AbstractString}
)
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
