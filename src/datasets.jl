const _DOCS_nondynamic_datasets_object_warning = """
!!! warning "Non-dynamic dataset objects"

    [`Dataset`](@ref) objects represents the dataset metadata when the Julia object was created
    (e.g. with [`dataset`](@ref)), and are not automatically kept up to date.
    To refresh the dataset metadata, you can pass an existing [`Dataset`](@ref) object
    to [`JuliaHub.dataset`](@ref) or [`project_dataset`](@ref).
"""

Base.@kwdef struct _DatasetStorage
    credentials_url::String
    region::String
    bucket::String
    prefix::String
end

"""
    struct DatasetVersion

Represents one version of a dataset.

Objects have the following properties:

- `.id`: unique dataset version identifier (used e.g. in [`download_dataset`](@ref) to
  identify the dataset version).
- `.size :: Int`: size of the dataset version in bytes
- `.timestamp :: ZonedDateTime`: dataset version timestamp

```jldoctest
julia> dataset = JuliaHub.dataset("example-dataset")
Dataset: example-dataset (Blob)
 owner: username
 description: An example dataset
 versions: 2
 size: 388 bytes
 tags: tag1, tag2

julia> dataset.versions
2-element Vector{JuliaHub.DatasetVersion}:
 JuliaHub.dataset(("username", "example-dataset")).versions[1]
 JuliaHub.dataset(("username", "example-dataset")).versions[2]

julia> dataset.versions[end]
DatasetVersion: example-dataset @ v2
 owner: username
 timestamp: 2022-10-14T01:39:43.237-04:00
 size: 331 bytes
```

See also: [`Dataset`](@ref), [`datasets`](@ref), [`dataset`](@ref).

$(_DOCS_no_constructors_admonition)
"""
struct DatasetVersion
    _dsref::Tuple{String, String}
    id::Int
    size::Int
    timestamp::TimeZones.ZonedDateTime
    _blobstore_path::String

    function DatasetVersion(json::Dict; owner::AbstractString, name::AbstractString)
        msg = "Unable to parse dataset version info for ($owner, $name)"
        version = _get_json(json, "version", Int; msg)
        size = _get_json(json, "size", Int; msg)
        timestamp = _parse_tz(_get_json(json, "date", String; msg); msg)
        blobstore_path = _get_json(json, "blobstore_path", String; msg)
        return new((owner, name), version, size, timestamp, blobstore_path)
    end
end

function Base.show(io::IO, dsv::DatasetVersion)
    owner, name = dsv._dsref
    dsref = string("(\"", owner, "\", \"", name, "\")")
    print(io, "JuliaHub.dataset($dsref).versions[$(dsv.id)]")
    return nothing
end

function Base.show(io::IO, ::MIME"text/plain", dsv::DatasetVersion)
    owner, name = dsv._dsref
    printstyled(io, "DatasetVersion:"; bold=true)
    print(io, " ", name, " @ v", dsv.id)
    print(io, "\n owner: ", owner)
    print(io, "\n timestamp: ", dsv.timestamp)
    print(io, "\n size: ", dsv.size, " bytes")
    return nothing
end

"""
    struct DatasetProjectLink

Holds the project-dataset link metadata for datasets that were accessed via a project
(e.g. when using [`project_datasets`](@ref)).

- `.uuid :: UUID`: the UUID of the project
- `.is_writable :: Bool`: whether the user has write access to the dataset via the
  this project

See also: [`project_dataset`](@ref), [`project_datasets`](@ref), [`upload_project_dataset`](@ref).

$(_DOCS_no_constructors_admonition)
"""
struct DatasetProjectLink
    uuid::UUIDs.UUID
    is_writable::Bool
end

"""
    struct Dataset

Information about a dataset stored on JuliaHub, and the following fields are considered to be
public API:

- `uuid :: UUID`: dataset UUID
- `owner :: String`: username of the dataset owner
- `name :: String`: dataset name
- `dtype :: String`: generally either `Blob` or `BlobTree`, but additional values may be added in the future
- `versions :: Vector{DatasetVersion}`: an ordered list of [`DatasetVersion`](@ref) objects, one for
  each dataset version, sorted from oldest to latest (i.e. you can use `last` to get the newest version).
- `size :: Int`: total size of the whole dataset (including all the dataset versions) in bytes
- Fields to access user-provided dataset metadata:
  - `description :: String`: dataset description
  - `tags :: Vector{String}`: a list of tags
- If the dataset was accessed via a project (e.g. via [`project_datasets`](@ref)), `.project` will
  contain project metadata (see also: [`DatasetProjectLink`](@ref)). Otherwise this field is `nothing`.
  - `project.uuid`: the UUID of the project
  - `project.is_writable`: whether the user has write access to the dataset via the
    this project
  Note that two `Dataset` objects are considered to be equal (i.e. `==`) regardless of the `.project`
  value -- it references the same dataset regardless of the project it was accessed in.

!!! note "Canonical fully qualified dataset name"

    In some contexts, like when accessing JuliaHub datasets with DataSets.jl, the `.owner`-`.name` tuple
    constitutes the fully qualifed dataset name, uniquely identifying a dataset on a JuliaHub instance.
    I.e. for a dataset object `dataset`, it can be constructed as `"\$(dataset.owner)/\$(dataset.name)"`.

$(_DOCS_nondynamic_datasets_object_warning)

$(_DOCS_no_constructors_admonition)
"""
Base.@kwdef struct Dataset
    owner::String
    name::String
    uuid::UUIDs.UUID
    dtype::String
    size::Int64
    versions::Vector{DatasetVersion}
    # User-set metadata
    description::String
    tags::Vector{String}
    project::Union{DatasetProjectLink, Nothing}
    # Additional metadata, but not part of public API
    _last_modified::Union{Nothing, TimeZones.ZonedDateTime}
    _downloadURL::String
    _storage::_DatasetStorage
    # Should not be used in code, but stores the full server
    # response for developer convenience.
    _json::Dict
end

function Dataset(d::Dict; expected_project::Union{UUID, Nothing}=nothing)
    owner = _get_json(
        _get_json(d, "owner", Dict),
        "username", String,
    )
    name = _get_json(d, "name", AbstractString)
    versions_json = _get_json_or(d, "versions", Vector, [])
    versions = sort(
        [DatasetVersion(json; owner, name) for json in versions_json];
        by=dsv -> dsv.id,
    )
    _storage = let storage_json = _get_json(d, "storage", Dict)
        _DatasetStorage(;
            credentials_url=_get_json(d, "credentials_url", AbstractString),
            region=_get_json(storage_json, "bucket_region", AbstractString),
            bucket=_get_json(storage_json, "bucket", AbstractString),
            prefix=_get_json(storage_json, "prefix", AbstractString),
        )
    end
    project = if !isnothing(expected_project)
        project_json = _get_json(d, "project", Dict)
        project_json_uuid = UUIDs.UUID(
            _get_json(project_json, "project_id", String)
        )
        if project_json_uuid != expected_project
            msg = "Project UUID mismatch in dataset response: $(project_json_uuid), requested $(project)"
            throw(JuliaHubError(msg))
        end
        is_writable = _get_json(
            project_json,
            "is_writable",
            Bool;
            msg="Unable to parse .project in /datasets?project response",
        )
        DatasetProjectLink(project_json_uuid, is_writable)
    else
        nothing
    end
    return Dataset(;
        uuid=_get_json_convert(d, "id", UUIDs.UUID),
        name, owner, versions,
        dtype=_get_json(d, "type", AbstractString),
        description=_get_json(d, "description", AbstractString),
        size=_get_json(d, "size", Integer),
        tags=_get_json(d, "tags", Vector),
        project,
        _downloadURL=_get_json(d, "downloadURL", AbstractString),
        _last_modified=_nothing_or(_get_json(d, "lastModified", AbstractString)) do last_modified
            datetime_utc = Dates.DateTime(
                last_modified, Dates.dateformat"YYYY-mm-ddTHH:MM:SS.ss"
            )
            _utc2localtz(datetime_utc)
        end,
        _storage,
        _json=d,
    )
end

function Base.propertynames(::Dataset)
    return (:owner, :name, :uuid, :dtype, :size, :versions, :description, :tags, :project)
end

function Base.show(io::IO, d::Dataset)
    dsref = string("(\"", d.owner, "\", \"", d.name, "\")")
    if isnothing(d.project)
        print(io, "JuliaHub.dataset(", dsref, ")")
    else
        print(io, "JuliaHub.project_dataset(", dsref, "; project=\"", d.project.uuid, "\")")
    end
end

function Base.show(io::IO, ::MIME"text/plain", d::Dataset)
    printstyled(io, "Dataset:"; bold=true)
    print(io, " ", d.name, " (", d.dtype, ")")
    print(io, "\n owner: ", d.owner)
    print(io, "\n description: ", d.description)
    print(io, "\n versions: ", length(d.versions))
    print(io, "\n size: ", d.size, " bytes")
    isempty(d.tags) || print(io, "\n tags: ", join(d.tags, ", "))
    if !isnothing(d.project)
        print(
            io,
            "\n project: ", d.project.uuid, " ",
            d.project.is_writable ? "(writable)" : "(not writable)",
        )
    end
end

function Base.:(==)(d1::Dataset, d2::Dataset)
    d1.name == d2.name &&
        d1.description == d2.description &&
        d1.versions == d2.versions &&
        d1._downloadURL == d2._downloadURL &&
        d1.size == d2.size &&
        d1.tags == d2.tags &&
        d1._last_modified == d2._last_modified &&
        d1.dtype == d2.dtype &&
        d1.uuid == d2.uuid
end

# Internal alias for (owner, dataset_name) tuples to be used in function signatures.
const _DatasetRefTuple = Tuple{<:AbstractString, <:AbstractString}
"""
    const DatasetReference :: Type

Type constraint on the first argument of most of the datasets-related functions, that is
used to uniquely specify the dataset that the operation will affect.

There are three different objects that can be passed as a dataset reference (`dsref::DatasetReference`):

* ```julia
  (owner::AbstractString, dataset_name::AbstractString)::Tuple{AbstractString,AbstractString}
  ```

  A tuple of the owner's username and the dataset's name.

* ```
  dataset_name::AbstractString
  ```

  Just a string with the dataset name; in this case the dataset's owner will be assumed to be the
  currently authenticated user (with the username determined from the [`Authentication`](@ref) objects
  passed via the `auth` keyword).

* ```
  dataset::Dataset
  ```

  Uses the owner and dataset name information from a [`Dataset`](@ref) object.

!!! warning "No UUID mismatch checks"

    When using the third option (i.e. passing a `Dataset`), the dataset UUID will _not_ be checked.
    So if the dataset with the same owner and username has been deleted and re-created as a new dataset
    (potentially of a different `dtype` etc), the functions will then act on the new dataset.
"""
const DatasetReference = Union{_DatasetRefTuple, AbstractString, Dataset}
# For each function taking a _DatasetRef as the first argument, like
#
#   @_authuser f(dsref::_DatasetRef, args...; kwargs...)
#
# it automatically adds two additional methods
#
#   f(ds::Dataset, args...; kwargs...) = f((ds.owner, ds.name), args...; kwargs...)
#   f(dataset_name::AbstractString, args...; auth, kwargs...) = f((auth.username, dataset_name), args...; kwargs...)
#
# to avoid having to manually add those methods.
#
# Note: since the macro returns an expression with multiple function definitions, you
# can't attach docstrings to it. So the pattern we use is:
#
#   """
#   docstring for foo
#   """
#   function foo end
#
#   @_authuser function foo(username::AbstractString, ...)
#
macro _authuser(fndef)
    @assert fndef.head === :function
    @assert length(fndef.args) == 2
    fnsig, fnbody = fndef.args
    @assert fnsig.head == :call
    fnname = fnsig.args[1]
    # Extract the arguments portion of the function definition.
    args =
        if length(fnsig.args) >= 2 && isa(fnsig.args[2], Expr) && fnsig.args[2].head == :parameters
            # If the function takes keyword arguments, this appears to the be in fnsig.args[2]
            fnsig.args[3:end]
        else
            fnsig.args[2:end]
        end
    # The args component should now always contain username and dataset_name parts.
    @assert length(args) >= 1
    @assert args[1] == :(dsref::_DatasetRefTuple)
    args = args[2:end]
    args_names = [arg.args[1] for arg in args]
    N = length(args)
    # Attach function docstring to a `function foo end` definition, create the standard method,
    # and one where the first `username` argument comes from the `auth` object.
    usernamemethod = quote
        function $(fnname)(
            dataset_name::AbstractString, $(args...); auth::Authentication=__auth__(), kwargs...
        )
            $(fnname)((auth.username, dataset_name), $(args_names...); auth, kwargs...)
        end
    end
    # Method taking ::Dataset
    datasetmethod = quote
        function $(fnname)(
            ds::Dataset, $(args...); auth::Authentication=__auth__(), kwargs...
        )
            $(fnname)((ds.owner, ds.name), $(args_names...); auth, kwargs...)
        end
    end

    quote
        $(esc(fndef))
        $(esc(usernamemethod))
        $(esc(datasetmethod))
    end
end

"""
    JuliaHub.datasets([username::AbstractString]; shared::Bool=false, [auth::Authentication]) -> Vector{Dataset}

List all datasets owned by `username`, returning a list of [`Dataset`](@ref) objects.

If `username` is omitted, it returns the datasets owned by the currently authenticated user.
If `username` is different from the currently authenticated user, it only returns the datasets
that are readable to (i.e. somehow shared with) the currently authenticated user.

If `shared = true`, it also returns datasets that belong to other users that have that have been
shared with the currently authenticated user. In this case, `username` is effectively ignored.

```jldoctest
julia> JuliaHub.datasets()
2-element Vector{JuliaHub.Dataset}:
 JuliaHub.dataset(("username", "example-dataset"))
 JuliaHub.dataset(("username", "blobtree/example"))

julia> JuliaHub.datasets(shared=true)
3-element Vector{JuliaHub.Dataset}:
 JuliaHub.dataset(("username", "example-dataset"))
 JuliaHub.dataset(("anotheruser", "publicdataset"))
 JuliaHub.dataset(("username", "blobtree/example"))

julia> JuliaHub.datasets("anotheruser")
1-element Vector{JuliaHub.Dataset}:
 JuliaHub.dataset(("anotheruser", "publicdataset"))
```

$(_DOCS_nondynamic_datasets_object_warning)
"""
function datasets end

function datasets(
    username::AbstractString;
    shared::Bool=false,
    auth::Authentication=__auth__(),
)
    datasets, _ = try
        _get_datasets(auth)
    catch e
        e isa JuliaHubException && rethrow(e)
        e isa JuliaHubError && rethrow(e)
        throw(
            JuliaHubError("Error while retrieving datasets from the server", e, catch_backtrace())
        )
    end
    # Note: unless `shared` is `true`, we filter down to the datasets owned by `username`.
    return _parse_dataset_list(datasets; username=shared ? nothing : username)
end

function _parse_dataset_list(
    datasets::Vector;
    username::Union{AbstractString, Nothing}=nothing,
    expected_project::Union{UUIDs.UUID, Nothing}=nothing,
)::Vector{Dataset}
    # It might happen that some of the elements of the `datasets` array can not be parsed for some reason,
    # and the Dataset() constructor will throw. Rather than having `datasets` throw an error (as we would
    # normally do for invalid backend responses), in this case we handle the situation more gracefully,
    # and just filter out the invalid elements (and print a warning to the user -- it's still an unusual
    # situation and should be reported). This is because we also re-use `JuliaHub.datasets` in
    # `JuliaHub.dataset` when fetching the information for just one dataset, and unconditionally throwing
    # would mean that `JuliaHub.dataset` can break due an issue with an unrelated dataset.
    n_erroneous_datasets = 0
    datasets = map(datasets) do dataset
        try
            # We also use the `nothing` method for filtering out datasets that are not owned by the
            # current `username`. If `username = nothing`, no filtering is done.
            if !isnothing(username) && (dataset["owner"]["username"] != username)
                return nothing
            end
            return Dataset(dataset; expected_project)
        catch e
            # If Dataset() fails due to some unexpected value in one of the dataset JSON objects that
            # JuliaHub.jl can not handle, it should only throw a JuliaHubError. So we rethrow on other
            # error types, as filtering all of them out could potentially hide JuliaHub.jl bugs.
            isa(e, JuliaHubError) || rethrow()
            @debug "Invalid dataset in GET /datasets response" dataset exception = (
                e, catch_backtrace()
            )
            n_erroneous_datasets += 1
            return nothing
        end
    end
    if n_erroneous_datasets > 0
        @warn "The JuliaHub GET /datasets response contains erroneous datasets. Omitting $(n_erroneous_datasets) entries."
    end
    # We'll filter down to just Dataset objects, and enforce type-stability on the array type here.
    return Dataset[ds for ds in datasets if isa(ds, Dataset)]
end

function datasets(; auth::Authentication=__auth__(), kwargs...)
    datasets(auth.username; auth, kwargs...)
end

function _get_datasets(auth::Authentication; writable=false)
    url_path = writable ? ("user", "datasets") : ("datasets",)
    r = _restcall(auth, :GET, url_path, nothing)
    r.status == 200 || _throw_invalidresponse(r; msg="Unable to fetch datasets.")
    _parse_response_json(r, Vector)
end

"""
    JuliaHub.dataset(dataset::DatasetReference; throw::Bool=true, [auth::Authentication]) -> Dataset

Looks up a dataset based on the [dataset reference `dataset`](@ref DatasetReference). Returns the
[`Dataset`](@ref) object corresponding to `dataset_name`, or throws a [`InvalidRequestError`](@ref)
if the dataset can not be found (if `throw=false` is passed, returns `nothing` instead).

By passing a [`Dataset`](@ref) object as `dataset`, this can be used to update the [`Dataset`](@ref)
object.

```jldoctest
julia> dataset = JuliaHub.dataset("example-dataset")
Dataset: example-dataset (Blob)
 owner: username
 description: An example dataset
 versions: 2
 size: 388 bytes
 tags: tag1, tag2

julia> JuliaHub.dataset(dataset)
Dataset: example-dataset (Blob)
 owner: username
 description: An example dataset
 versions: 2
 size: 388 bytes
 tags: tag1, tag2
```

If the specifed username is not the currently authenticated user, the dataset must be shared with
the currently authenticated user (i.e. contained in [`datasets(; shared=true)`](@ref datasets)).

!!! note

    This will call [`datasets`](@ref) every time, which might become a problem if you
    are processing a large number of datasets. In that case, you should call
    [`datasets`](@ref) and process the returned list yourself.

$(_DOCS_nondynamic_datasets_object_warning)
"""
function dataset end

@_authuser function dataset(
    dsref::_DatasetRefTuple;
    throw::Bool=true,
    auth::Authentication=__auth__(),
)
    username, dataset_name = dsref
    for dataset in datasets(; shared=true, auth)
        (dataset.owner == username) && (dataset.name == dataset_name) && return dataset
    end
    return _throw_or_nothing(;
        msg="No dataset with the name '$(dataset_name)' for user '$(username)'.", throw
    )
end

"""
    JuliaHub.delete_dataset(dataset::DatasetReference; force::Bool=false, [auth::Authentication]) -> Nothing

Delete the dataset specified by the [dataset reference `dataset`](@ref DatasetReference). Will return `nothing`
if the delete was successful, or throws an error if it was not.

Normally, when the dataset to be deleted does not exist, the function throws an error. This can be overridden by
setting `force = true`.

```jldoctest; setup = :(Main.MOCK_JULIAHUB_STATE[:existing_datasets] = ["username/example-dataset", "username/blobtree"])
julia> JuliaHub.datasets()
2-element Vector{JuliaHub.Dataset}:
 JuliaHub.dataset(("username", "example-dataset"))
 JuliaHub.dataset(("username", "blobtree"))

julia> JuliaHub.delete_dataset("example-dataset")

julia> JuliaHub.datasets()
1-element Vector{JuliaHub.Dataset}:
 JuliaHub.dataset(("username", "blobtree"))
```

!!! note
    Presently, it is only possible to delete datasets for the currently authenticated user.
"""
function delete_dataset end

@_authuser function delete_dataset(
    dsref::_DatasetRefTuple;
    force::Bool=false,
    auth::Authentication=__auth__(),
)
    username, dataset_name = dsref
    _assert_current_user(username, auth; op="delete_dataset")
    r = _restcall(auth, :DELETE, "user", "datasets", dataset_name)
    # Trying to delete a non-existent dataset is a user error, unless `force=true`.
    if r.status == 404 && !force
        throw(InvalidRequestError("Dataset '$dataset_name' for '$username' does not exist."))
    elseif r.status != 200 && !(r.status == 404 && force)
        _throw_invalidresponse(r)
    end
    return nothing
end

const _DOCS_datasets_metadata_fields = """
* `description`: description of the dataset (a string)
* `tags`: an iterable of strings of all the tags of the dataset
* `visibility`: a string with possible values `public` or `private`
* `license`: a valid SPDX license identifier (as a string or in a
  `(:spdx, licence_identifier)` tuple), or a tuple `(:fulltext, license_text)`,
  where `license_text` is the full text string of a custom license
* `groups`: an iterable of valid group names

!!! compat "JuliaHub.jl v0.1.12"

    The `license = (:fulltext, ...)` form requires v0.1.12, and `license = (:text, ...)`
    is deprecated since that version.
"""

"""
    JuliaHub.upload_dataset(dataset::DatasetReference, local_path; [auth,] kwargs...) -> Dataset

Uploads a new dataset or a new version of an existing dataset, with the dataset specified by the
[dataset reference `dataset`](@ref DatasetReference). The dataset type is determined from
the local path (`Blob` if a file, `BlobTree` if a directory). If a [`Dataset`](@ref) object is passed,
it attempts to update that dataset. Returns an updated [`Dataset`](@ref) object.

The following keyword arguments can be used to control the exact behavior of the function:

* `create :: Bool` (default: `true`): Create the dataset, if it already does not exist.
* `update :: Bool` (default: `false`): Upload the data as a new dataset version, if the dataset exists.
* `replace :: Bool` (default: `false`): If a dataset exists, delete all existing data and create a new
  dataset with the same name instead. Excludes `update = true`, and only creates a completely new dataset
  if `create=true` as well.

In addition, the following keyword arguments can be passed to set or updated the dataset metadata
when uploading:

$(_DOCS_datasets_metadata_fields)

If a dataset already exists, then these fields are updated as if [`update_dataset`](@ref) was called.

The function will throw an `ArgumentError` for invalid argument combinations.

Use the `progress` keyword argument to suppress upload progress from being printed.

!!! note
    Presently, it is only possible to upload datasets for the currently authenticated user.
"""
function upload_dataset end

@_authuser function upload_dataset(
    dsref::_DatasetRefTuple,
    local_path::AbstractString;
    progress::Bool=true,
    # Operation type
    create::Bool=true,
    update::Bool=false,
    replace::Bool=false,
    # Dataset metadata
    description::Union{AbstractString, Missing}=missing,
    tags=missing,
    visibility::Union{AbstractString, Missing}=missing,
    license::Union{AbstractString, Tuple{Symbol, <:AbstractString}, Missing}=missing,
    groups=missing,
    # Authentication
    auth::Authentication=__auth__(),
)
    username, dataset_name = dsref
    _assert_current_user(username, auth; op="upload_new_dataset")
    if !create && !update
        throw(ArgumentError("'create' and 'update' can not both be false"))
    end
    if update && replace
        throw(ArgumentError("'update' and 'replace' can not both be true"))
    end
    tags = _validate_iterable_argument(String, tags; argument="tags")
    groups = _validate_iterable_argument(String, groups; argument="groups")
    # We determine the dataset dtype from the local path.
    # This may throw an ArgumentError.
    dtype = _dataset_dtype(local_path)
    # We need to declare `r` here, because we want to reuse the variable name
    local r::_RESTResponse
    # If `create`, then we first try to create the dataset. If the dataset name
    # is already taken, then we should get a 409 back.
    local newly_created_dataset::Bool = false
    if create
        # Note: we do not set tags or description here (even though we could), but we
        # will do that in an update_dataset() call later.
        r = @timeit _TO "_new_dataset" _new_dataset(dataset_name, dtype; auth)
        if r.status == 409
            # 409 Conflict indicates that a dataset with this name already exists.
            if !update && !replace
                # If neither update nor replace is set, and the dataset exists, then
                # we must throw an invalid request error.
                throw(
                    InvalidRequestError(
                        "Dataset '$dataset_name' for user '$username' already exists, but update=false and replace=false."
                    ),
                )
            elseif replace
                # In replace mode we will delete the existing dataset and
                # create a new one.
                delete_dataset((username, dataset_name); auth)
                r_recreated::_RESTResponse = _new_dataset(dataset_name, dtype; auth)
                if r_recreated.status == 200
                    newly_created_dataset = true
                else
                    _throw_invalidresponse(r_recreated)
                end
            end
            # There is one more case -- `update && !replace` -- but in this case
            # we just move on to uploading a new version.
        elseif r.status == 200
            # The only other valid response is 200, when we create the dataset
            newly_created_dataset = true
        else
            # For any non-200/409 responses we throw a backend error.
            _throw_invalidresponse(r)
        end
    end
    # If `!create`, the only option allowed is `update` (`replace` is excluded).
    #
    # Acquire an upload for the dataset. By this point, the dataset with this name
    # should definitely exist, although race conditions are always a possibility.
    r = @timeit _TO "_open_dataset_version" _open_dataset_version(auth, dataset_name)
    if (r.status == 404) && !create
        # A non-existent dataset if create=false indicates a user error.
        throw(
            InvalidRequestError(
                "Dataset '$dataset_name' for '$username' does not exist and create=false."
            ),
        )
    elseif r.status != 200
        # Any other 404 or other non-200 response indicates a backend failure
        _throw_invalidresponse(r)
    end
    upload_config = _check_dataset_upload_config(r, dtype; newly_created_dataset)
    # Upload the actual data
    try
        @timeit "_upload_dataset" _upload_dataset(upload_config, local_path; progress)
    catch e
        throw(JuliaHubError("Data upload failed", e, catch_backtrace()))
    end
    # Finalize the upload
    try
        # _close_dataset_version will also throw on non-200 responses
        @timeit _TO "_close_dataset_version" _close_dataset_version(
            auth, dataset_name, upload_config; local_path
        )
    catch e
        throw(JuliaHubError("Finalizing upload failed", e, catch_backtrace()))
    end
    # Finally, update the dataset metadata with the new metadata fields.
    if !all(ismissing.((description, tags, visibility, license, groups)))
        update_dataset(
            (username, dataset_name); auth,
            description, tags, visibility, license, groups,
        )
    end
    # If everything was successful, we'll return an updated DataSet object.
    return @timeit _TO "dataset(...)" dataset((username, dataset_name); auth)
end

function _check_dataset_upload_config(
    r::_RESTResponse, expected_dtype::AbstractString; newly_created_dataset::Bool
)
    upload_config, _ = _parse_response_json(r, Dict)
    # Verify that the dtype of the remote dataset is what we expect it to be.
    if upload_config["dataset_type"] != expected_dtype
        if newly_created_dataset
            # If we just created the dataset, then there has been some strange error if dtypes
            # do not match.
            throw(JuliaHubError("Dataset types do not match."))
        else
            # Otherwise, it's a user error (i.e. they are trying to update dataset with the wrong
            # dtype).
            throw(
                InvalidRequestError(
                    "Local data type ($expected_dtype) does not match existing dataset dtype $(upload_config["dataset_type"])"
                ),
            )
        end
    end
    return upload_config
end

function _dataset_dtype(local_path::AbstractString)
    if isdir(local_path)
        return "BlobTree"
    elseif isfile(local_path)
        "Blob"
    elseif ispath(local_path)
        throw(ArgumentError("Unable to upload \"$local_path\": neither a file nor a directory"))
    else
        throw(ArgumentError("Unable to upload \"$local_path\": path does not exist"))
    end
end

function _validate_iterable_argument(::Type{T}, xs; argument) where {T}
    ismissing(xs) && return missing
    xs_converted = try
        T[x for x in xs]
    catch
        throw(
            ArgumentError(
                "Invalid iterable value for '$argument', elements can't be converted to $T"
            ),
        )
    end
    return xs_converted
end

function _new_dataset(
    name::AbstractString,
    dtype::AbstractString;
    # tags::Union{AbstractVector, Missing},
    # description::Union{AbstractString, Missing},
    auth::Authentication,
)::_RESTResponse
    @debug "Creating a new dataset '$name' ($dtype)"
    body = Dict(
        "name" => name,
        "type" => dtype,
        # "description" => ismissing(description) ? "" : description,
        # "tags" => ismissing(tags) ? [] : tags,
    )
    _restcall(
        auth,
        :POST,
        ("user", "datasets"),
        JSON.json(body);
        headers=["Content-Type" => "application/json"],
    )
end

function _open_dataset_version(auth::Authentication, name::AbstractString)::_RESTResponse
    r = _restcall(auth, :POST, "user", "datasets", name, "versions")
    _check_internal_error(r; var="POST /user/datasets/{name}/versions")
    return r
end

function _upload_dataset(upload_config, local_path; progress::Bool)
    type = upload_config["upload_type"]
    vendor = upload_config["vendor"]
    if type != "S3" || vendor != "aws"
        throw(JuliaHubError("Unknown upload type ($type) or vendor ($vendor)"))
    end
    mktemp() do rclone_conf_path, rclone_conf_io
        Mocking.@mock _rclone() do rclone_exe
            _write_rclone_config(rclone_conf_io, upload_config)
            close(rclone_conf_io)

            bucket = upload_config["location"]["bucket"]
            prefix = upload_config["location"]["prefix"]
            remote_path = "$bucket/$prefix"

            # --s3-no-check-bucket - don't check the bucket exists
            # --no-check-dest - don't check whether the file exists before uploading
            #
            # Additional useful options not included here:
            # * For restricted permissions, --s3-no-head avoids using HeadObject to
            #   check file upload success.
            # * To force multipart upload at a smaller threshold use something like
            #   --s3-upload-cutoff 1M --s3-chunk-size 5M

            # FIXME: remove `--s3-no-head` once policies are figured out (again)
            args = [
                "--s3-no-check-bucket",
                "--s3-no-head",
                "--no-check-dest",
            ]

            if progress
                pushfirst!(args, "--progress")
            end

            @timeit _TO "run:rclone" run(```
                $rclone_exe copyto $local_path "juliahub_remote:$remote_path"
                --config $rclone_conf_path
                $args
                ```)
        end
    end

    nothing
end

function _close_dataset_version(
    auth::Authentication, name, upload_config; local_path=nothing
)::_RESTResponse
    body = Dict(
        "name" => name,
        "upload_id" => upload_config["upload_id"],
        "action" => "close",
    )
    isnothing(local_path) || push!(body, "filename" => local_path)
    _restcall(
        auth,
        :POST,
        ("user", "datasets", name, "versions"),
        JSON.json(body);
        headers=["Content-Type" => "application/json"],
    )
end

function _write_rclone_config(
    io::IO;
    region::AbstractString,
    access_key_id::AbstractString,
    secret_access_key::AbstractString,
    session_token::AbstractString,
)
    write(
        io,
        """
[juliahub_remote]
type = s3
provider = AWS
env_auth = false
access_key_id = $access_key_id
secret_access_key = $secret_access_key
session_token = $session_token
region = $region
endpoint =
location_constraint = $region
acl = private
server_side_encryption =
storage_class =
""",
    )
end

function _write_rclone_config(io::IO, upload_config::Dict)
    region = upload_config["location"]["region"]
    access_key_id = upload_config["credentials"]["access_key_id"]
    secret_access_key = upload_config["credentials"]["secret_access_key"]
    session_token = upload_config["credentials"]["session_token"]
    _write_rclone_config(io; region, access_key_id, secret_access_key, session_token)
end

function _get_dataset_credentials(auth::Authentication, dataset::Dataset)
    r = @_httpcatch HTTP.get(dataset._storage.credentials_url, _authheaders(auth))
    r.status == 200 || _throw_invalidresponse(r; msg="Unable get credentials for $(dataset)")
    credentials, _ = _parse_response_json(r, Dict)
    return credentials
end

function _parse_dataset_version(version::AbstractString)
    m = match(r"v([0-9]+)", version)
    isnothing(m) && throw(JuliaHubError("Unable to parse dataset version string '$version'"))
    parse(Int, m[1])
end

function _find_dataset_version(dataset::Dataset, version::Integer)
    # Starting form latest first, assuming that it's more common to
    # try to find newer versions.
    for dsv in Iterators.reverse(dataset.versions)
        dsv.id == version && return dsv
    end
    return nothing
end

"""
    download_dataset(
        dataset::DatasetReference, local_path::AbstractString;
        replace::Bool = false, [version::Integer],
        [quiet::Bool = false], [auth::Authentication]
    ) -> String

Downloads the dataset specified by the [dataset reference `dataset`](@ref DatasetReference) to `local_path`
(which must not exist, unless `replace = true`), returning the absolute path to the downloaded file or directory.
If the dataset is a `Blob`, then the created `local_path` will be a file, and if the dataset is a `BlobTree`
the `local_path` will be a directory.

By default, it downloads the latest version, but an older version can be downloaded by specifying
the `version` keyword argument. Caution: you should never assume that the index of the `.versions` property
of [`Dataset`](@ref) matches the version number -- always explicitly use the `.id` propert of the
[`DatasetVersion`](@ref) object.

The function also prints download progress to standard output. This can be disabled by setting `quiet=true`.
Any error output from the download is still printed.

!!! warning

    Setting `replace = true` will recursively erase any existing data at `local_path` before replacing it
    with the dataset contents.
"""
function download_dataset end

function download_dataset(
    dataset_name::AbstractString,
    local_path::AbstractString;
    auth::Authentication=__auth__(),
    kwargs...,
)
    download_dataset((auth.username, dataset_name), local_path; auth, kwargs...)
end

function download_dataset(
    dsref::_DatasetRefTuple,
    local_path::AbstractString;
    auth::Authentication=__auth__(),
    kwargs...,
)
    ds = dataset(dsref; auth)
    download_dataset(ds, local_path; auth, kwargs...)
end

function download_dataset(
    dataset::Dataset, local_path::AbstractString;
    replace::Bool=false,
    version::Union{Integer, Nothing}=nothing,
    quiet::Bool=false,
    auth::Authentication=__auth__(),
)
    dataset.dtype ∈ ["Blob", "BlobTree"] || throw(
        InvalidRequestError(
            "Download only supported for Blobs and BlobTrees, but '$(dataset.name)' is $(dataset.type)"
        ),
    )

    isempty(dataset.versions) &&
        throw(InvalidRequestError("Dataset '$(dataset.name)' does not have any versions"))
    if isnothing(version)
        version = last(dataset.versions).id
    end
    version_info = _find_dataset_version(dataset, version)
    isnothing(version_info) &&
        throw(InvalidRequestError("Dataset '$(dataset.name)' does not have version 'v$version'"))

    credentials = Mocking.@mock _get_dataset_credentials(auth, dataset)
    credentials["vendor"] == "aws" ||
        throw(JuliaHubError("Unknown 'vendor': $(credentials["vendor"])"))
    credentials = credentials["credentials"]

    bucket = dataset._storage.bucket
    prefix = dataset._storage.prefix
    remote_uri = "juliahub_remote:$bucket/$prefix/$(dataset.uuid)/$(version_info._blobstore_path)"
    if dataset.dtype == "Blob"
        remote_uri *= "/data"
    end

    # Check the local path and create the root directory if need be.
    # We'll do it after fetching the credentials, in case that errors.
    local_path = abspath(local_path)
    if ispath(local_path)
        replace || throw(ArgumentError("Destination path exists: $local_path"))
        quiet || @warn "Removing existing data at: $(local_path)"
        rm(local_path; recursive=true, force=true)
    end
    let local_directory = (dataset.dtype == "Blob") ? dirname(local_path) : local_path
        isdir(local_directory) || mkpath(local_directory)
    end

    mktemp() do rclone_conf_path, rclone_conf_io
        Mocking.@mock _rclone() do rclone_exe
            _write_rclone_config(
                rclone_conf_io;
                region=dataset._storage.region,
                access_key_id=credentials["access_key_id"],
                secret_access_key=credentials["secret_access_key"],
                session_token=credentials["session_token"],
            )
            close(rclone_conf_io)

            cmd = ```
                $rclone_exe copyto "$remote_uri" "$local_path"
                --config $rclone_conf_path
                --progress
                --s3-no-check-bucket
                --no-check-dest
            ```
            quiet && (cmd = pipeline(cmd; stdout=devnull))
            run(cmd)
        end
    end
    return local_path
end

"""
    JuliaHub.update_dataset(dataset::DatasetReference; kwargs..., [auth]) -> Dataset

Updates the metadata of the dataset specified by the [dataset reference `dataset`](@ref DatasetReference),
as according to the keyword arguments keyword arguments. If the keywords are omitted, the metadata
corresponding to it remains unchanged. Returns the [`Dataset`](@ref) object corresponding to the updated
dataset.

The supported keywords are:

$(_DOCS_datasets_metadata_fields)

For example, to add a new tag to a dataset:

```julia
dataset = JuliaHub.dataset("my_dataset")
JuliaHub.update(dataset; tags = [dataset.tags..., "newtag"])
```

!!! note
    Presently, it is only possible to update datasets for the currently authenticated user.
"""
function update_dataset end
@_authuser function update_dataset(
    dsref::_DatasetRefTuple;
    description::Union{AbstractString, Missing}=missing,
    tags=missing,
    visibility::Union{AbstractString, Missing}=missing,
    license::Union{AbstractString, Tuple{Symbol, <:AbstractString}, Missing}=missing,
    groups=missing,
    auth::Authentication=__auth__(),
)
    username, dataset_name = dsref
    _assert_current_user(username, auth; op="update_dataset_metadata")
    tags = _validate_iterable_argument(String, tags; argument="tags")
    groups = _validate_iterable_argument(String, groups; argument="groups")
    # dataset metadata fields as of now:
    #   tags :: vector of arbitrary strings
    #   description :: string
    #   visibility :: string, one of ("public", "private")
    #   license :: Dict(spdx_id => ...) or Dict(text => ...), can't have both
    #   group_info :: list of strings (must be valid group names user belongs to)
    params = Dict{String, Any}()
    ismissing(description) || (params["description"] = description)
    ismissing(tags) || (params["tags"] = tags)
    ismissing(groups) || (params["group_info"] = groups)
    if !ismissing(visibility)
        allowed_visibility = ("public", "private")
        visibility in allowed_visibility ||
            throw(
                ArgumentError(
                    "Invalid visibility value '$visibility', allowed values: $allowed_visibility"
                ),
            )
        params["visibility"] = visibility
    end
    if !ismissing(license)
        if isa(license, AbstractString)
            license = (:spdx, license)
        end
        cmd, license_value = license
        params["license"] = if cmd == :spdx
            Dict("spdx_id" => license_value)
        elseif cmd in (:fulltext, :text)
            if cmd == :text
                Base.depwarn(
                    "Passing license=(:text, ...) is deprecated, use license=(:fulltext, ...) instead.",
                    :update_dataset;
                    force=true,
                )
            end
            Dict("text" => license_value)
        else
            throw(ArgumentError("Invalid license argument: $(cmd) ∉ [:spdx, :text]"))
        end
    end
    # Construct the REST call
    r = _update_dataset(auth, dataset_name, params)
    if r.status == 200
        return dataset((username, dataset_name); auth)
    elseif r.status == 404
        throw(InvalidRequestError("Dataset '$dataset_name' for '$username' does not exist."))
    end
    _throw_invalidresponse(r)
end

# Low-level internal function that just takes a dict of params, without caring
# if they are valid or not, and returns the raw HTTP response.
function _update_dataset(auth::Authentication, dataset_name::AbstractString, params::Dict)
    _restcall(auth, :PATCH, ("user", "datasets", dataset_name), JSON.json(params))
end

function _assert_current_user(username::AbstractString, auth::Authentication; op)
    username == auth.username ||
        throw(PermissionError("$op is only supported for the currently authenticated user"))
end

# Wrapping Rclone_jll.rclone here so that it could be mocked with Mocking.jl
function _rclone(f::Function)
    rclone_exe = Rclone_jll.rclone()
    f(rclone_exe)
end
