using JuliaHub
using Test

import Logging
import Dates
import HTTP
import Pkg
import Random
import Tar
import TimeZones
import SHA
import URIs

include("mocking.jl")

# Helper function to set Base.active_project() to the specified Project.toml
# file temporarily.
if VERSION < v"1.8"
    set_active_project(project) = (Base.ACTIVE_PROJECT[] = project)
else
    set_active_project(project) = Base.set_active_project(project)
end
function withproject(f, projectfile)
    isfile(projectfile) || error("Invalid projectfile: $projectfile")
    current_active_project = Base.active_project()
    try
        set_active_project(projectfile)
        f()
    finally
        set_active_project(current_active_project)
    end
end

# Hook into Pkg.test() to allow tests to be run as
#
# Pkg.test("JuliaHub", test_args=["jobs", "datasets"])
#
# Pass `--live` (without extra arguments) to enable all tests
# (except windows batch ones).
function is_enabled(testname=nothing; args=ARGS)
    enabled_tests = filter(!startswith('-'), lowercase.(args))
    run_live_tests = "--live" in args
    # If `testname` is not provided, we're calling this to check, in general,
    # if _any_ live tests are enabled (i.e. calling without an argument)
    isnothing(testname) && return run_live_tests
    # Check if the specified test set is enabled
    if isempty(enabled_tests) && run_live_tests && (testname == "jobs-windows")
        if get(ENV, "JULIAHUBJL_LIVE_WINDOWS_TESTS", nothing) == "true"
            @info "Running test set: $(testname)"
            return true
        else
            @warn "Skipping test set: $(testname) (windows tests disabled by default)"
            return false
        end
    elseif (isempty(enabled_tests) && run_live_tests) || (testname in enabled_tests)
        @info "Running test set: $(testname)"
        return true
    else
        @warn "Skipping test set: $(testname)"
    end
    return false
end

function list_datasets_prefix(prefix, args...; kwargs...)
    datasets = JuliaHub.datasets(args...; kwargs...)
    filter(datasets) do dataset::JuliaHub.Dataset
        startswith(dataset.name, prefix)
    end
end

@testset "JuliaHub.jl" begin
    # Just to make sure the logic within is_enabled() is correct.
    @testset "is_enabled" begin
        @test !is_enabled(; args=[])
        @test is_enabled(; args=["--live"])

        let args = ["datasets"]
            @test_logs (:info,) @test is_enabled("datasets"; args)
            @test_logs (:warn,) @test !is_enabled("jobs"; args)
            @test_logs (:warn,) @test !is_enabled("jobs-windows"; args)
        end
        let args = ["--live"]
            @test_logs (:info,) @test is_enabled("datasets"; args)
            @test_logs (:info,) @test is_enabled("jobs"; args)
            @test_logs (:warn,) @test !is_enabled("jobs-windows"; args)
            withenv("JULIAHUBJL_LIVE_WINDOWS_TESTS" => "foo") do
                @test_logs (:info,) @test is_enabled("datasets"; args)
                @test_logs (:info,) @test is_enabled("jobs"; args)
                @test_logs (:warn,) @test !is_enabled("jobs-windows"; args)
            end
            withenv("JULIAHUBJL_LIVE_WINDOWS_TESTS" => "true") do
                @test_logs (:info,) @test is_enabled("datasets"; args)
                @test_logs (:info,) @test is_enabled("jobs"; args)
                @test_logs (:info,) @test is_enabled("jobs-windows"; args)
            end
        end
        let args = ["datasets", "jobs"]
            @test_logs (:info,) @test is_enabled("datasets"; args)
            @test_logs (:info,) @test is_enabled("jobs"; args)
            @test_logs (:warn,) @test !is_enabled("jobs-windows"; args)
        end
        let args = ["jobs-windows"]
            @test_logs (:warn,) @test !is_enabled("datasets"; args)
            @test_logs (:warn,) @test !is_enabled("jobs"; args)
            @test_logs (:info,) @test is_enabled("jobs-windows"; args)
        end
        let args = ["jobs-windows", "datasets"]
            @test_logs (:info,) @test is_enabled("datasets"; args)
            @test_logs (:warn,) @test !is_enabled("jobs"; args)
            @test_logs (:info,) @test is_enabled("jobs-windows"; args)
        end
    end
    # This set tests that we haven't accidentally added or removed any public-looking
    # functions (i.e. ones that are not prefixed by _ basically).
    @testset "Public API" begin
        public_symbols = Set(
            filter(names(JuliaHub; all=true)) do s
                # Internal functions and types, prefixed by _
                startswith(string(s), "_") && return false
                # Internal macros, prefixed by _
                startswith(string(s), "@_") && return false
                # Strange generated functions
                startswith(string(s), "#") && return false
                # Some core functions that are not relevant for the package
                s in [:eval, :include] && return false
                return true
            end,
        )
        expected_public_symbols = Set([
            Symbol("@script_str"),
            :AbstractJobConfig, :AbstractJuliaHubApp,
            :appbundle, :AppBundleSizeError, :ApplicationJob, :Authentication,
            :AuthenticationError, :BatchJob, :BatchImage, :ComputeConfig,
            :Dataset, :DatasetReference, :DatasetVersion,
            :DefaultApp, :FileHash, :InvalidAuthentication, :InvalidRequestError, :Job,
            :WorkloadConfig, :JobFile, :JobLogMessage, :JobReference, :JobStatus,
            :JuliaHub, :JuliaHubConnectionError, :JuliaHubError,
            :JuliaHubException,
            :Limit, :NodeSpec, :PackageApp, :PackageJob,
            :PermissionError, :script, :Secret, :UserApp,
            :application, :applications, :authenticate,
            :batchimage, :batchimages,
            :check_authentication, :current_authentication,
            :dataset, :datasets, :delete_dataset, :download_dataset, :download_job_file,
            :extend_job,
            :interrupt!, :isdone, :job, :job_file, :job_files,
            :job_logs, :job_logs_buffered, :job_logs_newer!, :job_logs_older!,
            :AbstractJobLogsBuffer, :KafkaLogsBuffer,
            :hasfirst, :haslast, :jobs, :kill_job,
            :nodespec, :nodespecs, :reauthenticate!, :submit_job,
            :update_dataset, :upload_dataset, :wait_job,
        ])
        extra_public_symbols = setdiff(public_symbols, expected_public_symbols)
        isempty(extra_public_symbols) || @warn """
            Extra public symbols
            extra_public_symbols = $(sprint(show, MIME"text/plain"(), extra_public_symbols))
            """
        @test isempty(extra_public_symbols)
        extra_expected_symbols = setdiff(expected_public_symbols, public_symbols)
        isempty(extra_expected_symbols) || @warn """
            Missing public symbols
            extra_expected_symbols = $(sprint(show, MIME"text/plain"(), extra_expected_symbols))
            """
        @test isempty(extra_expected_symbols)
    end

    @testset "Utilities" begin
        include("utils.jl")
    end
    @testset "Authentication" begin
        include("authentication.jl")
    end
    @testset "Datasets" begin
        include("datasets.jl")
    end
    @testset "Batchimages" begin
        include("batchimages.jl")
    end
    @testset "Jobs" begin
        include("jobs.jl")
    end
    @testset "_PackageBundler" begin
        include("packagebundler.jl")
    end

    if is_enabled()
        @info "Running tests against a JuliaHub instance"
        @testset "JuliaHub.jl LIVE tests" begin
            include("runtests-live.jl")
        end
    end
end
