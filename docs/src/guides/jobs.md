```@meta
CurrentModule=JuliaHub
DocTestSetup = :(using JuliaHub)
```
```@setup examples
using JuliaHub
```

# Jobs

JuliaHub.jl can be used to both [submit new jobs](../reference/job-submission.md), and to [inspect running or finished jobs](../reference/jobs.md).

```@contents
Pages = ["jobs.md"]
Depth = 2:10
```

## [Submitting batch jobs](@id jobs-guide-batch)

A common use case for this package is to programmatically submit Julia scripts as batch jobs to JuliaHub, to start non-interactive workloads.
In a nutshell, these are Julia scripts, together with an optional Julia environment, that get executed on the allocated hardware.

The easiest way to start a batch job is to submit a [single Julia script](@ref jobs-batch-script), which can optionally also include a Julia environment with the job.
However, for more complex jobs, with multiple inputs files etc., [appbundles](@ref jobs-batch-appbundles) are likely more suitable.

### [Script jobs](@id jobs-batch-script)

```@setup script-job
import JuliaHub
_temp_path = mktempdir()
cd(_temp_path)
write("myscript.jl", "@warn \"Hello World!\"\n")
```

The simplest job one can submit is a humble Julia script, together with an optional Julia environment (i.e. `Project.toml`, `Manifest.toml`, and/or `Artifacts.toml`).
These jobs can be created with the [`JuliaHub.@script_str`](@ref) string macro, for inline instantiation:

```@example script-job
JuliaHub.submit_job(
    JuliaHub.script"""
    @warn "Hello World!"
    """,
)
```

Alternatively, they can be created with the [`script`](@ref) function, which can load the Julia code from a script file:

```@example script-job
cd(_temp_path) do # hide
JuliaHub.submit_job(
    JuliaHub.script("myscript.jl"),
)
end # hide
```

The string macro also picks up the currently running environment (i.e. `Project.toml`, `Manifest.toml`, and `Artifacts.toml` files), which then gets instantiated on JuliaHub when the script is started.
If necessary, this can be disabled by appending the `noenv` suffix to the string macro.

```@example script-job
JuliaHub.script"""
@warn "Hello World!"
"""noenv
```

With the [`script`](@ref) function, you can also specify a path to directory containing the Julia package environment, if necessary.

If an environment is passed with the job, it gets instantiated on the JuliaHub node, and the script is run in that environment.
As such, any packages that are not available in the package registries or added via public Git URLs will not work.
If that is the case, [appbundles](@ref jobs-batch-appbundles) can be used instead to submit jobs that include private or local dependencies.

```@setup script-job
rm(_temp_path, recursive=true)
```

### [Appbundles](@id jobs-batch-appbundles)

A more advanced way of submitting a batch job is as an _appbundle_, which "bundles up" a whole directory and submits it together with the script.
The Julia environment in the directory is also immediately added into the bundle.

An appbundle can be constructed with the [`appbundle`](@ref) function, which takes as arguments the path to the directory to be bundled up, and a script _within that directory_.
This is meant to be used for project directories where you have your Julia environment in the top level of the directory or repository.

For example, suppose you have a submit at the top level of your project directory, then you can submit a bundle as follows:

```@example
import JuliaHub # hide
# We need to override the @__DIR__ here, because we actually construct a real appbundle # hide
macro __DIR__(); joinpath(dirname(dirname(pathof(JuliaHub))), "test", "jobenvs", "job1"); end # hide
JuliaHub.submit_job(
    JuliaHub.appbundle(@__DIR__, "script.jl"),
    ncpu = 4, memory = 16,
)
```

The bundler looks for a Julia environment (i.e. `Project.toml`, `Manifest.toml`, and/or `Artifacts.toml` files) at the root of the directory.
If the environment does not exist (i.e. the files are missing), one is created.
When the job starts on JuliaHub, this environment is instantiated.

A key feature of the appbundle is that development dependencies of the environment (i.e. packages added with `pkg> develop` or `Pkg.develop()`) are also bundled up into the archive that gets submitted to JuliaHub (including any current, uncommitted changes).
Registered packages are installed via the package manager via the standard environment instantiation, and their source code is not included in the bundle directly.

When the JuliaHub job starts, the working directory is set to the root of the unpacked appbundle directory.
This should be kept in mind especially when launching a script that is not at the root itself, and trying to open other files from the appbundle in that script (e.g. with `open`).
You can still use `@__DIR__` to load files relative to the script, and `include`s also work as expected (i.e. relative to the script file).

Finally, a `.juliabundleignore` file can be used to exclude certain directories, by adding the relevant [globs](https://en.wikipedia.org/wiki/Glob_(programming)), similar to how `.gitignore` files work.
In addition, `.git` directories are also automatically excluded from the bundle.

### Examining job configuration

The `dryrun` option to [`submit_job`](@ref) can be used to inspect the full job workload configuration that would be submitted to JuliaHub.

```@example
import JuliaHub # hide
JuliaHub.submit_job(
    JuliaHub.script"""
    println("hello world")
    """,
    ncpu = 4, memory = 8,
    env = Dict("ARG" => "value"),
    dryrun = true
)
```

## Query, extend, kill

The package has function that can be used to interact with running and past jobs.
The [`jobs`](@ref) function can be used to list jobs, returning an array of [`Job`](@ref) objects.

```@repl examples
js = JuliaHub.jobs(limit=3)
js[1]
```

If you know the name of the job, you can also query the job directly with [`job`](@ref).

```@setup examples
Main.setup_job_results_file!()
```

```@repl examples
job = JuliaHub.job("jr-eezd3arpcj")
job.status
JuliaHub.isdone(job)
```

Similarly, the [`kill_job`](@ref) function can be used to stop a running job, and the [`extend_job`](@ref) function can be used to extend the job's time limit.

## Waiting on jobs

A common pattern in a script is to submit one or more jobs, and then wait until the jobs complete, to then process their outputs.
[`isdone`](@ref) can be used to see if a job has completed.

```@setup examples
Main.MOCK_JULIAHUB_STATE[:jobs] = Dict("jr-novcmdtiz6" => Dict("status" => "Running"))
```
```@repl examples
job = JuliaHub.job("jr-novcmdtiz6")
JuliaHub.isdone(job)
```

```@setup examples
empty!(Main.MOCK_JULIAHUB_STATE)
```

The [`wait_job`](@ref) function also provides a convenient way for a script to wait for a job to finish.

```@repl examples
job = JuliaHub.wait_job("jr-novcmdtiz6")
JuliaHub.isdone(job)
```

## Accessing job outputs

There are two ways a JuliaHub job can store outputs that are directly related to a specific job[^1]:

1. Small, simple outputs can be stored by setting the `ENV["RESULTS"]` environment variable.
   Conventionally, this is often set to a JSON object, and will act as a dictionary of key value pairs.
2. Files or directories can be uploaded by setting the `ENV["RESULTS_FILE"]` to a local file path on the job.
   Note that directories are combined into a single tarball when uploaded.

[^1]: You can also e.g. [upload datasets](@ref datasets) etc. But in that case the resulting data is not, strictly speaking, related to a specific job.

The values set via the `RESULTS` environment variable can be accessed with the `.results` field of a [`Job`](@ref) object:

```@setup job-outputs
Main.MOCK_JULIAHUB_STATE[:jobs] = Dict(
    "jr-novcmdtiz6" => Dict(
        "outputs" => """
        {"user_param": 2, "output_value": 4}
        """
    )
)
import JuliaHub
job = JuliaHub.job("jr-novcmdtiz6")
```

```@repl job-outputs
job.results
```

As the `.results` string is often a JSON object, you can use the the [JSON.jl](https://github.com/JuliaIO/JSON.jl) or [JSON3.jl](https://github.com/quinnj/JSON3.jl) packages to easily parse it.
For example

```@repl job-outputs
import JSON
JSON.parse(job.results)
```

When it comes to job result files, they can all be accessed via the `.files` field.

```@repl job-outputs
job.files
```

The [`job_files`](@ref) function can be used to filter down to specific file types.

```@repl job-outputs
JuliaHub.job_files(job, :result)
```

And if you know the name of the file, you can also use the [`job_files`](@ref) to get the specific [`JobFile`](@ref) object for a particular file directly.

```@repl job-outputs
jobfile = JuliaHub.job_file(job, :result, "outdir.tar.gz")
```

To actually fetch the contents of a file, you can use the [`download_job_file`](@ref) function on the [`JobFile`](@ref) objects.

```@setup job-outputs
empty!(Main.MOCK_JULIAHUB_STATE)
```
