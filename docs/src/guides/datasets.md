```@meta
CurrentModule=JuliaHub
DocTestSetup = :(using JuliaHub)
```
```@setup datasets
using JuliaHub
```

# [Datasets guide](@id guide-datasets)

JuliaHub.jl offers a programmatic way to work with your JuliaHub datasets, and this section demonstrates a few common workflows you can use with these APIs.

```@contents
Pages = ["datasets.md"]
Depth = 2:10
```

See the [datasets reference page](../reference/datasets.md) for a detailed reference of the datasets-related functionality.

## Accessing datasets

The [`datasets`](@ref) function can be use to list all the datasets owned by the currently authenticated user, returning an array of [`Dataset`](@ref) objects.

```jldoctest
julia> JuliaHub.datasets()
2-element Vector{JuliaHub.Dataset}:
 JuliaHub.dataset(("username", "example-dataset"))
 JuliaHub.dataset(("username", "blobtree/example"))
```

If you know the name of the dataset, you can also directly access it with the [`dataset`](@ref) function, and you can access the dataset metadata via the properties of the [`Dataset`](@ref) object.

```jldoctest example-dataset
julia> ds = JuliaHub.dataset("example-dataset")
Dataset: example-dataset (Blob)
 owner: username
 description: An example dataset
 versions: 2
 size: 388 bytes
 tags: tag1, tag2

julia> ds.owner
"username"

julia> ds.description
"An example dataset"

julia> ds.size
388
```

If you want to work with dataset that you do not own but is shared with you in JuliaHub, you can pass `shared=true` to [`datasets`](@ref), or specify the username.

```jldoctest
julia> JuliaHub.datasets(shared=true)
3-element Vector{JuliaHub.Dataset}:
 JuliaHub.dataset(("username", "example-dataset"))
 JuliaHub.dataset(("anotheruser", "publicdataset"))
 JuliaHub.dataset(("username", "blobtree/example"))

julia> JuliaHub.datasets("anotheruser")
1-element Vector{JuliaHub.Dataset}:
 JuliaHub.dataset(("anotheruser", "publicdataset"))

julia> JuliaHub.dataset(("anotheruser", "publicdataset"))
Dataset: publicdataset (Blob)
 owner: anotheruser
 description: An example dataset
 versions: 1
 size: 57 bytes
 tags: tag1, tag2
```

Finally, JuliaHub.jl can also be used to download to your local machine with the [`download_dataset`](@ref) function.

```jldoctest; filter = r"\"/.+/mydata\""
julia> JuliaHub.download_dataset("example-dataset", "mydata")
Transferred:       86.767 KiB / 86.767 KiB, 100%, 0 B/s, ETA -
Transferred:            1 / 1, 100%
Elapsed time:         2.1s
"/home/username/my-project/mydata"
```

As datasets can have multiple versions, the [`.versions` property of `Dataset`](@ref Dataset) can be used to see information about the individual versions (represented with [`DatasetVersion`](@ref) objects).
When downloading, you can also specify the version you wish to download (with the default being the newest version).

```jldoctest example-dataset; filter = r"\"/.+/mydata\""
julia> ds.versions
2-element Vector{JuliaHub.DatasetVersion}:
 JuliaHub.DatasetVersion(dataset = ("username", "example-dataset"), version = 1)
 JuliaHub.DatasetVersion(dataset = ("username", "example-dataset"), version = 2)

julia> ds.versions[1]
DatasetVersion: example-dataset @ v1
 owner: username
 timestamp: 2022-10-13T01:39:42.963-04:00
 size: 57 bytes

julia> JuliaHub.download_dataset("example-dataset", "mydata", version=ds.versions[1].id)
Transferred:       86.767 KiB / 86.767 KiB, 100%, 0 B/s, ETA -
Transferred:            1 / 1, 100%
Elapsed time:         2.1s
"/home/username/my-project/mydata"

```

The dataset version are sorted with oldest first.
To explicitly access the newest dataset, you can use the `last` function on the `.versions` property.

```jldoctest example-dataset
julia> last(ds.versions)
DatasetVersion: example-dataset @ v2
 owner: username
 timestamp: 2022-10-14T01:39:43.237-04:00
 size: 331 bytes

```

!!! tip "Tip: DataSets.jl"

    In JuliaHub jobs and Cloud IDEs you can also use the [DataSets.jl](https://github.com/JuliaComputing/DataSets.jl) package to access and work with datasets.
    See the [help.julialang.org section on datasets](https://help.juliahub.com/juliahub/stable/tutorials/datasets_intro/) for more information.

## Create, update, or replace

The [`upload_dataset`](@ref) function can be used to programmatically create new datasets on JuliaHub.

```@setup datasets
touch("local-file")
mkdir("local-directory")
Main.MOCK_JULIAHUB_STATE[:existing_datasets] = []
```

```@repl datasets
JuliaHub.upload_dataset("example-dataset", "local-file")
```

The type of the dataset (`Blob` or `BlobTree`) depends on whether the uploaded object is a file or a directory.
A directory will be store as a `BlobTree`-type dataset on JuliaHub.

```@repl datasets
JuliaHub.upload_dataset("example-blobtree", "local-directory")
```

The `create`, `update`, and `replace` options control how [`upload_dataset`](@ref) behaves with respect to existing datasets.
By default, the function only creates brand new datasets, and trying to upload a dataset that already exists will fail with an error.

```@repl datasets
JuliaHub.upload_dataset("example-dataset", "local-file")
```

This behavior can be overridden by setting `update=true`, which will then upload a new version of a dataset if it already exists.
This is useful for jobs and workflows that are meant to be re-run, updating the dataset each time they run.

```@repl datasets
JuliaHub.upload_dataset("example-dataset", "local-file"; update=true)
```

The `replace=true` option can be used to erase earlier versions of a dataset.
This will delete all information about the existing dataset and is a destructive, non-recoverable action.
This may also lead to the dataset type being changed.

```@repl datasets
JuliaHub.upload_dataset("example-dataset", "local-file"; replace=true)
```

## Bulk updates

You can also use the package to perform bulk updates or deletions of datasets.
The following example, adds a new tag to all the datasets where the name matches a particular pattern.

```julia
# Find all the datasets that have names that start with 'my-analysis-'
myanalysis_datasets = filter(
    dataset -> startswith(dataset.name, r"my-analysis-.*"),
    JuliaHub.datasets()
)
# .. and now add a 'new-tag' tag to each of them
for dataset in myanalysis_datasets
    @info "Updating" dataset
    # Note: tags = ... overrides the whole list, so you need to manually retain
    # old tags.
    new_tags = [dataset.tags..., "new-tag"]
    JuliaHub.update_dataset(dataset, tags = new_tags)
end
```

While this example shows the [`update_dataset`](@ref), for example, the [`delete_dataset`](@ref) function could be used in the same way.
