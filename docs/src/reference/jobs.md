```@meta
CurrentModule = JuliaHub
DocTestSetup = :(using JuliaHub)
```
```@setup examples
using JuliaHub
```

# [Jobs API reference](@id job-apis)

JuliaHub.jl provides various methods to inspect and interact jobs that [have been submitted to JuliaHub](@ref job-submission).
It is also possible to get access to job outputs programmatically.

## Job status states

A job will be in various "states" during its execution, and its current state can be inspected via the [`.status`] field.

The following diagram illustrates the possible states a job can be in, and how it moves between them during a job lifecycle.

```mermaid
stateDiagram-v2
direction LR
[*] --> SUBMIT:::user
SUBMIT --> Submitted
Submitted --> Running
Running --> FINISHED
state FINISHED {
  direction LR
  [*] --> Failed
  [*] --> Stopped
  [*] --> Completed
}
FINISHED:::user

classDef user fill:lightgray
```

!!! note "Refreshing a Job object"

    An instance of a [`Job`](@ref) object reflects the state of the job when the [`job`](@ref) function was called.
    If you want to inspect the current state of a job, you must first "refresh" the job object, which can simply be done with the help of the [`job`](@ref) function.

    ```julia
    job = JuliaHub.job(job)
    ```

## Reference

```@docs
JuliaHub.JobReference
JuliaHub.jobs
JuliaHub.job
JuliaHub.isdone
JuliaHub.wait_job
JuliaHub.kill_job
JuliaHub.extend_job
JuliaHub.JobLogMessage
JuliaHub.job_logs
JuliaHub.job_logs_buffered
JuliaHub.job_logs_older!
JuliaHub.job_logs_newer!
JuliaHub.AbstractJobLogsBuffer
JuliaHub.hasfirst
JuliaHub.haslast
JuliaHub.interrupt!
JuliaHub.job_files
JuliaHub.job_file
JuliaHub.download_job_file
JuliaHub.Job
JuliaHub.JobStatus
JuliaHub.JobFile
JuliaHub.FileHash
```

## Index

```@index
Pages = ["jobs.md"]
```
