```@meta
CurrentModule=JuliaHub
DocTestSetup = :(using JuliaHub)
```

# [Job submission](@id job-submission)

On JuliaHub you can submit _jobs_, which are user-defined workloads that get allocated a dedicated compute capacity.
For example, this includes running scripts in batch computations, cloud IDEs, interactive notebooks and so on.
The functions and types here deal with starting up such jobs and apps.
The functions to inspect running or finished jobs are [documented separately](@ref job-apis).

```@contents
Pages=["job-submission.md"]
Depth=2:3
```

A complete JuliaHub job workload is defined by the following configuration pieces:

- **Job configuration.** This specifies the computation that gets run, and includes information such as the type of computation (batch script vs starting a GUI application), any arguments or Julia code that gets passed to the job etc.

  As of now, there are three general types of jobs that can be run on JuliaHub:

  - [**Batch jobs**](@ref jobs-batch): non-interactive Julia scripts
  - [**Default Applications**](@ref jobs-default-apps): special, built-in, interactive applications (such as IDEs or product-specific dashboards)
  - [**External package applications**](@ref jobs-packages): Julia packages that can be run as either interactive or non-interactive jobs

  Each of these categories are configured slightly differently, and are described in more detail below.

- **Compute configuration.** This specifies the hardware and cluster topology that will be used to execute the job (such as the number of CPUs per node, whether there is a GPU present, the number of nodes), how the Julia processes are configured (e.g. single process per node vs process per cpu), and other low-level technical configuration.

- **Runtime parameters.** These are various additional parameters that control how a job behaves. Currently, this is limited to passing environment variables to the jobs, overriding the job's name in the UI, and to various configuration options related to running interactive jobs.

In the JuliaHub.jl code, the first two categories are encapsulated by the [`AbstractJobConfig`](@ref) and [`ComputeConfig`](@ref) types.
These two, together with the additional runtime parameters, make up a [`WorkloadConfig`](@ref) object that can be submitted to JuliaHub for executing with the [`submit_job`](@ref) function.

The following sections on this page explain the different aspects of job submission in more detail.
See the [guide on submitting batch jobs](@ref jobs-guide-batch) to see more practical examples of how to submit jobs.

## Compute configuration

JuliaHub supports a predefined set of node configurations, each of which have a specific number of CPUs, memory, GPUs etc.
A JuliaHub job must pick one of these node types to run on, although a distributed job can run across multiple instances of the same node type.
A list of these node specifications can be obtained with the [`nodespecs`](@ref) function (returning a list of [`NodeSpec`](@ref) objects).

```jldoctest
julia> JuliaHub.nodespecs()
9-element Vector{JuliaHub.NodeSpec}:
 JuliaHub.nodespec(#= m6: 3.5 GHz Intel Xeon Platinum 8375C, 0.33/hr =#; ncpu=4, memory=16, gpu=false)
 JuliaHub.nodespec(#= m6: 3.5 GHz Intel Xeon Platinum 8375C, 0.65/hr =#; ncpu=8, memory=32, gpu=false)
 JuliaHub.nodespec(#= m6: 3.5 GHz Intel Xeon Platinum 8375C, 2.4/hr =#; ncpu=32, memory=128, gpu=false)
 JuliaHub.nodespec(#= r6: 3.5 GHz Intel Xeon Platinum 8375C, 0.22/hr =#; ncpu=2, memory=16, gpu=false)
 JuliaHub.nodespec(#= r6: 3.5 GHz Intel Xeon Platinum 8375C, 0.42/hr =#; ncpu=4, memory=32, gpu=false)
 JuliaHub.nodespec(#= m6: 3.5 GHz Intel Xeon Platinum 8375C, 0.17/hr =#; ncpu=2, memory=8, gpu=false)
 JuliaHub.nodespec(#= r6: 3.5 GHz Intel Xeon Platinum 8375C, 1.3/hr =#; ncpu=8, memory=64, gpu=false)
 JuliaHub.nodespec(#= p2: Intel Xeon E5-2686 v4 (Broadwell), 1.4/hr =#; ncpu=4, memory=61, gpu=true)
 JuliaHub.nodespec(#= p3: Intel Xeon E5-2686 v4 (Broadwell), 4.5/hr =#; ncpu=8, memory=61, gpu=true)
```

While you can manually index into the list returned by [`nodespecs`](@ref), that is generally inconvenient.
Instead, the [`nodespec`](@ref) function should be used to find a suitable node for a particular job.

```jldoctest
julia> JuliaHub.nodespec(ncpu=2, memory=8)
Node: 3.5 GHz Intel Xeon Platinum 8375C
 - GPU: no
 - vCores: 2
 - Memory: 8 Gb
 - Price: 0.17 $/hr
```

By default, [`nodespec`](@ref) finds the smallest node that satisfies the specified requirements.
However, it also supports the `exactmatch` argument, which can be use to find the exactly matching node configuration.

```jldoctest; filter = r"Stacktrace:.*"s
julia> JuliaHub.nodespec(ncpu=3, memory=5; exactmatch=true)
ERROR: InvalidRequestError: Unable to find a nodespec: ncpu=3 memory=5 gpu=false
Stacktrace:
 ...

julia> JuliaHub.nodespec(ncpu=3, memory=5)
Node: 3.5 GHz Intel Xeon Platinum 8375C
 - GPU: no
 - vCores: 4
 - Memory: 16 Gb
 - Price: 0.33 $/hr
```

By default, JuliaHub jobs run on a single node.
However, for a distributed job, additional nodes can be allocated to a job by specifying the **`nnodes`** parameter.
In that case, a Julia process is started on each node, and the additional nodes are linked to the main process [via the `Distributed` module](https://docs.julialang.org/en/v1/manual/distributed-computing/).

While by default only a single Julia process is started on each node, by setting the **`process_per_cpu`** parameter, multiple Julia processes are started on the same node.
The processes are isolated from each other by running in separate containers, but they share the CPUs, GPUs, and most crucially, the memory.

See [`ComputeConfig`](@ref) and [`submit_job`](@ref) for more details on how exactly to set up this configuration.

## [Runtime configuration](@id jobs-runtime-config)

The [`submit_job`](@ref) function accepts various additional parameters that control aspects of the job.
See the function's docstring for more details.

| Parameter | Description |
| --------- | ----------- |
| `name` | can be used to override the name of the job shown in the UI |
| `project` | specifies the JuliaHub project UUID that the job is associate with |
| `timelimit` | sets the time limit after which the job gets killed |
| `env` | environment variables set at runtime |

As an example, to have an environment variable set while the job is running, you could call [`submit_job`](@ref) as follows:

```@example
import JuliaHub # hide
JuliaHub.submit_job(
    JuliaHub.script"""
    @info "Extracting 'MY_PARAMETER'" get(ENV, "MY_PARAMETER", nothing)
    """,
    env = Dict("MY_PARAMETER" => "example value"),
    dryrun = true
)
```

## [Batch jobs](@id jobs-batch)

Batch jobs are Julia scripts with (optional) associated Julia package environments (`Project.toml`, `Manifest.toml` and/or `Artifacts.toml`) that run on the cluster non-interactively.

See also: [`@script_str`](@ref), [`script`](@ref), [`appbundle`](@ref) for more details, and the [guide on submitting batch jobs](@ref jobs-guide-batch) for a tutorial.

### Specifying the job image

JuliaHub batch jobs can run in various container images.
Different JuliaHub products often have their own image tailored for the application (e.g. that come with custom sysimages to reduce load times).

The list of all images available to the user can be obtained with [`batchimages`](@ref), and a specific one can be picked out with [`batchimage`](@ref).
The latter function is particularly useful when submitting jobs.

```julia
JuliaHub.submit_job(
    JuliaHub.BatchJob(
        JuliaHub.script"""
        using SpecialProductModule
        SpecialProductModule.run()
        """,
        image = JuliaHub.batchimage("specialproduct"),
    )
)
```

## [Default Applications](@id jobs-default-apps)

!!! compat "Experimental feature"

    Starting application jobs with JuliaHub.jl is considered to be experimental.
    The APIs are likely to change in future JuliaHub.jl version.

Default applications are the JuliaHub-built in applications (such as dashboards and IDEs),
generally associated with specific JuliaHub products. Specific examples of default applications
available to everyone include the Pluto notebooks and the Julia IDE.

The list of available applications can be accessed via the [`applications`](@ref) function,
and specific applications can be picked out with [`application`](@ref).

```jldoctest
julia> apps = JuliaHub.applications()
7-element Vector{JuliaHub.AbstractJuliaHubApp}:
 JuliaHub.application(:default, "Linux Desktop")
 JuliaHub.application(:default, "Julia IDE")
 JuliaHub.application(:default, "Pluto")
 JuliaHub.application(:default, "Windows Workstation")
 JuliaHub.application(:package, "RegisteredPackageApp")
 JuliaHub.application(:package, "CustomDashboardApp")
 JuliaHub.application(:user, "ExampleApp.jl")

julia> JuliaHub.application(:default, "Pluto")
DefaultApp
 name: Pluto
 key: pluto
```

A JuliaHub job that launches an application can be started by passing the object returned by the [`application`](@ref) function to [`submit_job`](@ref).

```julia
import JuliaHub # hide
JuliaHub.submit_job(
    JuliaHub.application(:default, "Pluto"),
    ncpu = 8, memory = 16,
)
```

## [External package applications](@id jobs-packages)

!!! compat "Experimental feature"

    Starting package application jobs with JuliaHub.jl is considered to be experimental.
    The APIs are likely to change in future JuliaHub.jl version.

Specially crafted Julia packages can also be launched as JuliaHub jobs.
They are either automatically picked up from the packages registries served by the JuliaHub instance ([`PackageApp`](@ref)), or added by users themselves ([`UserApp`](@ref)) via a Git URL.

A package application must have a top-level package environment (i.e. it has a `Project.toml` the declares a name and a UUID), and it must have a entry script at `bin/main.jl`.
When a package job starts, the package is added to an environment and `bin/main.jl` is called.
Note that the `bin/main.jl` script does not have any access to any of the package dependencies.

The [`applications`](@ref) function can list all available packages (with filtering for user or registered).
[`JuliaHub.application`](@ref) can be used to pick a package by name.
It works for both registered packages

```julia
JuliaHub.submit_job(
    JuliaHub.application(:package, "RegisteredPackageApp"),
    ncpu = 4,
)
```

and for private, user applications

```julia
JuliaHub.submit_job(
    JuliaHub.application(:user, "ExampleApp.jl"),
    ncpu = 4,
    env = Dict("example_parameter" => "2")
)
```

!!! tip "Environment variables"

    Environment variables (i.e. `env`) are a common way to communicate options and settings to package applications.

## Reference

```@docs
NodeSpec
nodespecs
nodespec
BatchImage
batchimages
batchimage
AbstractJobConfig
BatchJob
script
@script_str
appbundle
ComputeConfig
submit_job
Limit
Unlimited
WorkloadConfig
```

## Experimental APIs

!!! compat "Experimental features"

    Starting application jobs with JuliaHub.jl is considered to be experimental.
    The APIs are likely to change in future JuliaHub.jl version.

```@docs
AbstractJuliaHubApp
applications
application
DefaultApp
PackageApp
UserApp
ApplicationJob
PackageJob
```

## Index

```@index
Pages = ["job-submission.md"]
```
