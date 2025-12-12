```@meta
CurrentModule=JuliaHub
DocTestSetup = :(using JuliaHub)
```

```@setup datasets
using JuliaHub
```

# [Datasets](@id datasets)

These APIs allow you to create, read, update, and delete datasets owned by [the currently authenticated user](@ref authentication).

* You can use [`datasets`](@ref), [`dataset`](@ref), and [`download_dataset`](@ref) to access datasets or their metadata.
* [`upload_dataset`](@ref), [`update_dataset`](@ref), and [`delete_dataset`](@ref) can be used to create, update, or delete datasets.

See also:
[help.julialang.org](https://help.juliahub.com/juliahub/stable/tutorials/datasets_intro/) on datasets, [DataSets.jl](https://github.com/JuliaComputing/DataSets.jl).

## Dataset types

JuliaHub currently has two distinct types of datasets:

1. `Blob`: a single file; or, more abstractly, a collection of bytes
2. `BlobTree`: a directory or a file; more abstractly a tree-like collection of `Blob`s, indexed by file system paths

These types mirror the concepts in [DataSets.jl](https://github.com/JuliaComputing/DataSets.jl)

JuliaHub.jl APIs do not rely that much on the dataset type for anything, except when downloading or uploading.
In that case, a local file always corresponds to a `Blob`, and a local directory corresponds to a `BlobTree`.
For example, when trying to upload a file as a new version of a `BlobTree`-type dataset will fail, because the dataset type can not change.

The [`upload_dataset`](@ref) function uses information filesystem to determine whether the created dataset is a `Blob` or a `BlobTree`, and similarly [`download_dataset`](@ref) will always download a `Blob` into a file, and a `BlobTree` as a directory.

## Dataset versions

A JuliaHub dataset can have zero or more versions.
A newly created dataset _usually_ has at least one version, but it may have zero versions if, for example, the upload did not finish.
The versions are indexed with a linear list of integers starting from `1`.

## MinIO backend

JuliaHub instances with the MinIO backend for data storage require at least JuliaHub.jl v0.1.6 for dataset uploads and downloads.

## Reference

```@docs
Dataset
DatasetVersion
datasets
DatasetReference
dataset
download_dataset
upload_dataset
update_dataset
delete_dataset
DatasetProjectLink
```

## Index

```@index
Pages = ["datasets.md"]
```
