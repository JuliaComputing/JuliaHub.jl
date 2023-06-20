```@meta
CurrentModule=JuliaHub
```
```@setup shared
using JuliaHub
ENV["JULIA_PKG_SERVER"] = "juliahub.com"
```

# [Getting Started with JuliaHub.jl](@id getting-started)

This tutorial walks you through the basic operations you can do with JuliaHub.jl, from installation to submitting simple jobs and working with datasets.
If you are unfamiliar with JuliaHub.jl, this is a good place to get started.

If you already know what you wish to achieve with JuliaHub.jl, you can also skip this and jump directly into one of the more detailed how-to guides.

In particular, the tutorial will show

* How to install JuliaHub.jl and connect it to a JuliaHub instance.
* How to create, access and update a simple dataset.
* How to submit a simple job.

## Installation

JuliaHub.jl is a registered Julia package and can be installed using [Julia's package manager](https://pkgdocs.julialang.org/v1/getting-started/).
You can access the Julia package manager REPL mode by pressing `]`, and you can install JuliaHub.jl with

```
pkg> add JuliaHub
```

Alternatively, you can use the `Pkg` standard library functions to install it.

```julia
import Pkg
Pkg.add("JuliaHub")
```

Once it is installed, simply use `import` or `using` to load JuliaHub.jl into your current Julia session.

```julia-repl
julia> using JuliaHub
```

!!! note "No exported names"

    JuliaHub.jl does not have any exported names, so doing `using JuliaHub` does not introduce any functions or types in `Main`.
    Instead, JuliaHub.jl functions are designed to be used by prefixing them with `JuliaHub.` (e.g. `JuliaHub.authenticate(...)` or `JuliaHub.submit_job(...)`)

    That said, there is nothing stopping you from explicitly bringing some names into your current scope, by doing e.g. `using JuliaHub: submit_job`, if you so wish!

## Authentication

In order to communicate with a JuliaHub instance, you need a valid authentication token.
If you are working in a JuliaHub Cloud IDE, you actually do not need to do anything to be authenticated, as the authentication tokens are automatically set up in the cloud environment.
To verify this, you can still call [`authenticate`](@ref), which should load the pre-configured token.

```@repl shared
JuliaHub.authenticate()
```

If you are working on a local computer, the easiest way to get started is to pass the URL of the JuliaHub instance to [`authenticate`](@ref).
Unless you have authenticated before, this will initiate an interactive browser-based authentication.

```julia-repl
julia> JuliaHub.authenticate("juliahub.com")
Authentication required: please authenticate in browser.
The authentication page should open in your browser automatically, but you may need to switch to the opened window or tab. If the authentication page is not automatically opened, you can authenticate by manually opening the following URL: ...
```

Once you have completed the steps in the browser, the function should return a valid authentication token.

The [`authenticate`](@ref) function returns an [`Authentication`](@ref) object, which hold the authentication token.
In principle, you can pass these objects directly to JuliaHub.jl function via the `auth` keyword argument.
However, in practice, this is usually not needed, because JuliaHub.jl also remembers the last authentication in the Julia session in a global variable.
You can see the current globally stored authentication token with [`current_authentication`](@ref).

```@repl shared
JuliaHub.current_authentication()
```

!!! note "Authentication guide"

    There is more to authentication than this, including its relationship to the Julia package server and `JULIA_PKG_SERVER` environment variable.
    See the [Authentication how-to](@ref guide-authentication) if you want to learn more.

## Creating & accessing datasets

JuliaHub.jl allows you to create, access, and update the datasets that are hosted on JuliaHub.
This section shows some of the basic operations you can perform with datasets.

```@setup shared
Main.MOCK_JULIAHUB_STATE[:existing_datasets] = String[]
Main.MOCK_JULIAHUB_STATE[:dataset_params] = Dict(
    "description" => "",
    "tags" => String[],
)
```

The [`datasets`](@ref) function allows you to list the datasets you have.
Optionally, you can also make it show any other datasets you have access to.

```@repl shared
JuliaHub.datasets()
```

Unless you have created datasets in the web UI or in the IDE, this list will likely be empty currently.
To fix that, let us upload a simple dataset using JuliaHub.jl.

Just as an example, we'll generate a simple 5-by-5 matrix, and save it in a file using the using the [`DelimitedFiles` standard library](https://docs.julialang.org/en/v1/stdlib/DelimitedFiles/).

```@repl shared
using DelimitedFiles
mat = [i^2 + j^2 for i=1:5, j=1:5]
writedlm("matrix.dat", mat)
```

Now that the matrix has been serialized into a text file on the disk, we can upload that file to JuliaHub with [`upload_dataset`](@ref).

```@repl shared
JuliaHub.upload_dataset("tutorial-matrix", "matrix.dat")
```

!!! warning "Existing dataset"

    If you already happen to have a dataset with the same name, the `upload_dataset` call will fail.
    It is designed to be safe by default.
    However, you can pass `update=true` or `replace=true` to either upload your file as a new _version_ of the dataset, or to delete all existing versions and upload a brand new version.

If we now call [`datasets`](@ref), it should show up in the list of datasets.

```@repl shared
JuliaHub.datasets()
```

To see more details about the dataset, you can index into the array returned by [`datasets`](@ref).
Alternatively, you can also use the [`dataset`](@ref) function to pick out a single dataset by its name.

```@repl shared
JuliaHub.dataset("tutorial-matrix")
```

JuliaHub datasets also support basic metadata, such as tags and a description field.
You could set it directly in the [`upload_dataset`](@ref) function, but we did not.
But that is fine, since we can use [`update_dataset`](@ref) to update the metadata at any time.

```@repl shared
JuliaHub.update_dataset("tutorial-matrix", description="An i^2 + j^2 matrix")
```

The function also immediately queries JuliaHub for the updated dataset metadata by internally calling `JuliaHub.dataset("tutorial-matrix")`.

Finally, JuliaHub.jl also allows you to download the datasets you have with the [`download_dataset`](@ref) function.
We can also imagine doing this on a different computer or in a JuliaHub job.

```@repl shared
JuliaHub.download_dataset("tutorial-matrix", "matrix-downloaded.dat")
```
```@setup
cp("matrix.dat", "matrix-downloaded.dat")
```

This downloads the dataset into a local file, after which you can e.g. read it back into Julia and do operations on it.

```@repl shared
mat = readdlm("matrix-downloaded.dat", '\t', Int)
sum(mat)
```

!!! tip "Directories as datasets"

    While this demo uploaded a single file as a dataset, JuliaHub also supports uploading whole directories as a single dataset.
    For that, you can simply point [`upload_dataset`](@ref) to a directory, rather than a file.
    See the [datasets how-to](@ref guide-datasets) for more information on how to work with datasets.

## Submitting a job

JuliaHub.jl allows for an easy programmatic submission of JuliaHub jobs.
In this example, we submit a simple script that downloads the dataset from the previous step, does a simple calculations and then upload the result.
We then access the result locally with JuliaHub.jl.

First, we need to specify the code that we want to run in the job.
There are a few options for this, but in this example we use the [`@script_str`](@ref) string macro to construct a [`script`](@ref)-type computation, that simply runs the code snippet we specify.

The following script will access the dataset, calculates the sum of all the elements, and stores the value in the job results.
You will be able to access the contents of `RESULTS` in both the web UI, but also via JuliaHub.jl.

```@example shared
s = JuliaHub.script"""
using JuliaHub, DelimitedFiles
@info JuliaHub.authenticate()
JuliaHub.download_dataset("tutorial-matrix", "matrix-downloaded.dat")
mat = readdlm("matrix-downloaded.dat", '\t', Int)
mat_sum = @show sum(mat)
ENV["RESULTS"] = string(mat_sum)
"""
```

!!! note "Job environment"

    In most cases, you also submit a Julia package environment (i.e. `Project.toml` and `Manifest.toml` files together with a job).
    That environment then gets instantiated before the user-provided code is run.

    The [`script""`](@ref @script_str) string macro, by default, attaches the currently active environment to the job.
    This means that any packages that you are currently using should also be available on the job (although only registered packages added as non-development dependencies will work).
    You can use `Base.active_project()` or `pkg> status` to see what environment is currently active.

To submit a job, you can simply call [`submit_job`](@ref) on it.

```@setup
Main.MOCK_JULIAHUB_STATE[:jobs] = Dict(
    "jr-xf4tslavut" => Dict(
        "status" => "Submitted",
        "files" => [],
        "outputs" => "",
    )
)
```
```@repl shared
j = JuliaHub.submit_job(s)
```

The [`submit_job`](@ref) function also allows you to specify configure how the job gets run, such as how many CPUs or how much memory it has available.
By default, though, it runs your code on a single node, picking the smallest instance that is available.

At this point, if you go to the "Jobs" page web UI, you should see the job there.
It may take a few moments to actually start running.
You can also call [`job`](@ref) on the returned [`Job`](@ref) object to refresh the status of the job.

```@setup
Main.MOCK_JULIAHUB_STATE[:jobs] = Dict(
    "jr-xf4tslavut" => Dict(
        "status" => "Running",
        "files" => [],
        "outputs" => "",
    )
)
```
```@repl shared
j = JuliaHub.job(j)
```

Finally, after the job has completed, if you refresh the [`Job`](@ref) it should reflect the final status of the job, and also give you access to the

```@setup
Main.MOCK_JULIAHUB_STATE[:jobs] = Dict(
    "jr-xf4tslavut" => Dict(
        "status" => "Completed",
        "files" => [],
        "outputs" => "550",
    )
)
```
```@repl shared
j = JuliaHub.job(j)
j.results
```

See the [jobs how-to guide](guides/jobs.md) for more details on the different options when it comes to job submission.

## Next steps

This tutorial has hopefully given an overview of basic JuliaHub.jl usage.
For more advanced usage, you may want to read through the more detailed how-to guides.

```@contents
Pages = Main.PAGES_GUIDES
Depth = 1:1
```

```@setup shared
# Clear the mocking state, so that other pages and docstrings would not
# be affected.
empty!(Main.MOCK_JULIAHUB_STATE)
# We don't actually care about the generated files
rm("matrix.dat", force=true)
rm("matrix-downloaded.dat", force=true)
```
