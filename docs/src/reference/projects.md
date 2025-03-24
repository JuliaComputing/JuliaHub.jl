```@meta
CurrentModule=JuliaHub
```

# Projects

These APIs allow you to interact with datasets that have been attached to projects.

* [`project_datasets`](@ref) and [`project_dataset`](@ref) let you list and access datasets linked to a project
* [`upload_project_dataset`](@ref) allows uploading new versions of project-linked datasets

## Automatic project authentication

The [`Authentication`](@ref) object can be associated with a default project UUID, which will
then be used to for all _project_ operations, unless an explicit `project` gets passed to
override the default.

Importantly, [`JuliaHub.authenticate`](@ref) will automatically pick up the the JuliaHub
project UUID from the `JULIAHUB_PROJECT_UUID` environment variable. This means in JuliaHub
cloud jobs and IDEs, it is not necessary to manually set the project, and JuliaHub.jl
will automatically.
However, you can opt-out of this behavior by explicitly passing a `project=nothing` to
[`JuliaHub.authenticate`](@ref).

You can always verify that your operations are running in the context of the correct project
by checking the [`Authentication`](@ref) object, e.g. via [`current_authentication`](@ref):

```jldoctest; setup = :(using JuliaHub; Main.projectauth_setup!()), teardown = :(Main.projectauth_teardown!())
julia> JuliaHub.current_authentication()
JuliaHub.Authentication("https://juliahub.com", "username", *****; project_id = "cd6c9ee3-d15f-414f-a762-7e1d3faed835")
```

## Reference

```@docs
project_datasets
project_dataset
upload_project_dataset
ProjectReference
```

## Index

```@index
Pages = ["project_datasets.md"]
```
