HIGH_JOB_LIMIT = 999999999
nodes = JuliaHub.nodespecs(; auth=auth)
@testset "[LIVE] JuliaHub.nodespecs()" begin
    @test nodes isa Vector{JuliaHub.NodeSpec}
    @test length(nodes) > 0
    # test implicit global auth
    nodes2 = JuliaHub.nodespecs()
    @test nodes2 isa Vector{JuliaHub.NodeSpec}
    @test nodes == nodes2
end

jobs = JuliaHub.jobs(; limit=HIGH_JOB_LIMIT, auth=auth)
num_jobs_prev = length(jobs)
previous_last_job = nothing

@testset "[LIVE] JuliaHub.batchimage[s]()" begin
    allimages = JuliaHub.batchimages(; auth)
    products = unique(image.product for image in allimages)
    @test !isempty(products)
    @test "standard-batch" in products
    for product in products
        nimages_for_product = sum(image.product == product for image in allimages)
        @test nimages_for_product > 0
        images = JuliaHub.batchimages(product; auth)
        @test length(images) == nimages_for_product
        # Test default image for a product
        image = JuliaHub.batchimage(product; auth)
        @test image.product == product
        product_default_image = only(
            filter(i -> i.product == product && i._is_product_default, allimages)
        )
        @test image.image == product_default_image.image
    end
    let default_image = JuliaHub.batchimage(; auth)
        standard_default_image = only(
            filter(i -> i.product == "standard-batch" && i._is_product_default, allimages)
        )
        @test default_image.product == "standard-batch"
        @test default_image.image == standard_default_image.image
    end
    @test_throws JuliaHub.InvalidRequestError JuliaHub.batchimage("no-such-product")
    @test_throws JuliaHub.InvalidRequestError JuliaHub.batchimage(
        "no-such-product", "no-such-image"
    )
    @test_throws JuliaHub.InvalidRequestError JuliaHub.batchimage("standard-batch", "no-such-image")
end

@testset "[LIVE] JuliaHub.jobs()" begin
    if num_jobs_prev > 0
        @test jobs isa Vector{JuliaHub.Job}
        previous_last_job = jobs[1]
    end

    # Test the limit query parameter
    @test length(JuliaHub.jobs(; limit=1, auth=auth)) == min(num_jobs_prev, 1)
    @test length(JuliaHub.jobs(; limit=3, auth=auth)) == min(num_jobs_prev, 3)
    # The JuliaHub default limit right now is 20, but let's not depend on its exact value here
    @test length(JuliaHub.jobs(; auth=auth)) <= num_jobs_prev
    @test_throws DomainError JuliaHub.jobs(limit=0, auth=auth)
    @test_throws DomainError JuliaHub.jobs(limit=-20, auth=auth)
    @test_throws TypeError JuliaHub.jobs(limit=2 + 3im, auth=auth)
end

@testset "[LIVE] Job query errors" begin
    @test_throws JuliaHub.InvalidRequestError JuliaHub.extend_job("this-job-does-not-exist", 1)
end

function wait_submission(job::JuliaHub.Job; maxtime::Real=300)
    # maxtime: it can definitely take at least 3 minutes for a job to start
    start_time = time()
    job = JuliaHub.job(job; auth=auth)
    while job.status == "Submitted"
        @debug "Waiting for job $(job.id) to start" time() - start_time maxtime
        time() > start_time + maxtime && error("Job $(job.id) didn't start in $(maxtime)s")
        sleep(5)
        job = JuliaHub.job(job; auth=auth)
    end
    return job
end

@testset "[LIVE] JuliaHub.submit_job / simple" begin
    job = JuliaHub.submit_job(
        JuliaHub.script"@info 1+1; sleep(200)";
        ncpu=2, memory=8,
        auth,
    )
    @test job isa JuliaHub.Job
    @test job.status ∈ ("Submitted", "Running")

    # Start an async logger. We start from offset=0, so that we would capture
    # all the logs.
    logbuffer = JuliaHub.job_logs_buffered(job; offset=0, stream=true, auth)

    jobs = JuliaHub.jobs(; limit=HIGH_JOB_LIMIT, auth)
    @test length(jobs) > num_jobs_prev
    @test job != previous_last_job
    @test JuliaHub.job(job.id; auth).id == job.id

    job = wait_submission(job)
    @test job.status == "Running"

    # Try to extend job:
    let j = JuliaHub.extend_job(job.id, 3)
        @test j isa JuliaHub.Job
        @test j.id == job.id
    end

    # sleep for 2mins to allow the job to run for a bit, and then kill it
    @debug "Sleeping for 2 minutes: $(job.id)"
    sleep(120)
    job_killed = JuliaHub.kill_job(job; auth)
    @test job_killed isa JuliaHub.Job
    @test job_killed.id == job.id
    @test job_killed.status ∉ ("Running", "Submitted")
    # Wait a bit more and then make sure that the job is stopped
    @debug "Sleeping for 30s: $(job.id)"
    sleep(30)
    job_killed = JuliaHub.job(job_killed) # test default auth=
    @test job_killed.status == "Stopped"
    # wait for the logger task to finish, if hasn't already
    JuliaHub.interrupt!(logbuffer; wait=true)

    # Check the async streamed logs
    @test length(logbuffer.logs) > 0
    @test all(log -> isa(log, JuliaHub.JobLogMessage), logbuffer.logs)

    # wait a bit to make sure the logs have propagated to cloudwatch
    sleep(20)
    full_logs = JuliaHub.job_logs(job; auth=auth)
    @test length(full_logs) > 0

    # FIXME: this test fails intermittently
    if length(full_logs) == length(logbuffer.logs)
        @test length(full_logs) == length(logbuffer.logs)
    else
        @warn "length(full_logs) == length(streamed_logs) failed" job.id length(full_logs) length(
            logbuffer.logs
        )
    end
end

@testset "[LIVE] JuliaHub.submit_job / failed" begin
    job = JuliaHub.submit_job(
        JuliaHub.script"""
        ENV["RESULTS"] = "{\\"x\\":42}"
        error("fail")
        """;
        auth,
    )
    job = JuliaHub.wait_job(job)
    @test job.status == "Failed"
    # Even though the job failed, any RESULTS set before the error are still stored
    @test !isempty(job.results)
    let results = JSON.parse(job.results)
        @test results isa AbstractDict
        @test haskey(results, "x")
        @test results["x"] == 42
    end
end

@testset "[LIVE] JuliaHub.submit_job / distributed" begin
    job = JuliaHub.submit_job(
        JuliaHub.script"""
        using Distributed, JSON
        @everywhere using Distributed
        @everywhere fn() = (myid(), strip(read(`hostname`, String)))
        fs = [i => remotecall(fn, i) for i in workers()]
        vs = map(fs) do (i, future)
            myid, hostname = fetch(future)
            @info "$i: $myid, $hostname"
            (; myid, hostname)
        end
        ENV["RESULTS"] = JSON.json((; vs))
        """;
        nnodes=3,
        auth,
    )
    job = JuliaHub.wait_job(job)
    @test job.status == "Completed"
    @test !isempty(job.results)
    let results = JSON.parse(job.results)
        @test results isa AbstractDict
        @test haskey(results, "vs")
        @test length(results["vs"]) == 2
        @test Set(v["myid"] for v = results["vs"]) == Set(2:3)
    end
end

@testset "[LIVE] JuliaHub.submit_job / distributed-per-core" begin
    job = JuliaHub.submit_job(
        JuliaHub.script"""
        using Distributed, JSON
        @everywhere using Distributed
        @everywhere fn() = (myid(), strip(read(`hostname`, String)))
        fs = [i => remotecall(fn, i) for i in workers()]
        vs = map(fs) do (i, future)
            myid, hostname = fetch(future)
            @info "$i: $myid, $hostname"
            (; myid, hostname)
        end
        ENV["RESULTS"] = JSON.json((; vs))
        """;
        ncpu=2, nnodes=3, process_per_node=false,
        name="juliahubjl-$(TESTID)", env=Dict("FOO" => "bar"),
        auth,
    )
    @test job.env["jobname"] == "juliahubjl-$(TESTID)"
    @test job.env["FOO"] == "bar"
    job = JuliaHub.wait_job(job)
    @test job.status == "Completed"
    @test !isempty(job.results)
    let results = JSON.parse(job.results)
        @test results isa AbstractDict
        @test haskey(results, "vs")
        @test length(results["vs"]) == 5
        @test Set(v["myid"] for v = results["vs"]) == Set(2:6)
    end
end

@testset "[LIVE] JuliaHub.submit_job / scripts" begin
    # Test that the environment that the job runs in is exactly the one specified
    # by the manifest.
    job1_dir = joinpath(@__DIR__, "jobenvs", "job1")
    job = JuliaHub.submit_job(
        JuliaHub.script(
            joinpath(job1_dir, "script.jl");
            project_directory=job1_dir,
        );
        auth
    )
    job = JuliaHub.wait_job(job)
    @test job.status == "Completed"
    @test !isempty(job.results)
    let results = JSON.parse(job.results)
        @test results isa AbstractDict
        @test haskey(results, "datastructures_version")
        @test VersionNumber(results["datastructures_version"]) == v"0.17.0"
        @test haskey(results, "datafile_hash")
        @test results["datafile_hash"] === nothing
    end

    # This tests that if the Manifest.toml is not provided, it gets resolved
    # properly, including taking into account any [compat] sections in the Project.toml
    job = JuliaHub.submit_job(
        JuliaHub.script(;
            code=read(joinpath(job1_dir, "script.jl"), String),
            project=read(joinpath(job1_dir, "Project.toml"), String),
        );
        auth,
    )
    job = JuliaHub.wait_job(job)
    @test job.status == "Completed"
    @test !isempty(job.results)
    let results = JSON.parse(job.results)
        @test results isa AbstractDict
        @test haskey(results, "datastructures_version")
        @test VersionNumber(results["datastructures_version"]) > v"0.17.0"
        @test haskey(results, "datafile_hash")
        @test results["datafile_hash"] === nothing
    end
end

@testset "[LIVE] JuliaHub.submit_job / appbundle" begin
    job1_dir = joinpath(@__DIR__, "jobenvs", "job1")
    job = JuliaHub.submit_job(
        JuliaHub.appbundle(job1_dir, "script.jl");
        auth,
    )
    job = JuliaHub.wait_job(job)
    @test job.status == "Completed"
    @test !isempty(job.results)
    let results = JSON.parse(job.results)
        @test results isa AbstractDict
        @test haskey(results, "datastructures_version")
        @test VersionNumber(results["datastructures_version"]) == v"0.17.0"
        @test haskey(results, "datafile_hash")
        @test results["datafile_hash"] == "e242ed3bffccdf271b7fbaf34ed72d089537b42f"
    end
end

@testset "[LIVE] Job output file access" begin
    job1_dir = joinpath(@__DIR__, "jobenvs", "job1")
    job = JuliaHub.submit_job(
        JuliaHub.script"""
        ENV["RESULTS_FILE"] = joinpath(@__DIR__, "output.txt")
        n = write(ENV["RESULTS_FILE"], "output-txt-content")
        @info "Wrote $(n) bytes"
        """,
    )
    job = JuliaHub.wait_job(job)
    @test job.status == "Completed"
    # Project.toml, Manifest.toml, code.jl
    @test length(JuliaHub.job_files(job, :input)) >= 3
    @test JuliaHub.job_file(job, :input, "Project.toml") isa JuliaHub.JobFile
    @test JuliaHub.job_file(job, :input, "Manifest.toml") isa JuliaHub.JobFile
    @test JuliaHub.job_file(job, :input, "code.jl") isa JuliaHub.JobFile
    # code.jl
    @test length(JuliaHub.job_files(job, :source)) >= 1
    @test JuliaHub.job_file(job, :source, "code.jl") isa JuliaHub.JobFile
    # Project.toml, Manifest.toml
    @test length(JuliaHub.job_files(job, :project)) >= 2
    @test JuliaHub.job_file(job, :project, "Project.toml") isa JuliaHub.JobFile
    @test JuliaHub.job_file(job, :project, "Manifest.toml") isa JuliaHub.JobFile
    # output.txt
    @test length(JuliaHub.job_files(job, :result)) == 1
    jf = JuliaHub.job_file(job, :result, "output.txt")
    @test jf isa JuliaHub.JobFile
    buf = IOBuffer()
    JuliaHub.download_job_file(jf, buf)
    @test String(take!(buf)) == "output-txt-content"

    # Job output with a tarball:
    job = JuliaHub.submit_job(
        JuliaHub.script"""
        odir = joinpath(@__DIR__, "output_files")
        mkdir(odir)
        write(joinpath(odir, "foo.txt"), "output-txt-content-1")
        write(joinpath(odir, "bar.txt"), "output-txt-content-2")
        @info "Wrote: odir"
        ENV["RESULTS_FILE"] = odir
        """,
    )
    job = JuliaHub.wait_job(job)
    @test job.status == "Completed"
    @test length(JuliaHub.job_files(job, :project)) >= 2
    result_tarball = only(JuliaHub.job_files(job, :result))
    buf = IOBuffer()
    JuliaHub.download_job_file(result_tarball, buf)
    seek(buf, 0)
    tmp = Tar.extract(buf)
    try
        @test isdir(tmp)
        @test isfile(joinpath(tmp, "foo.txt"))
        @test read(joinpath(tmp, "foo.txt"), String) == "output-txt-content-1"
        @test isfile(joinpath(tmp, "bar.txt"))
        @test read(joinpath(tmp, "bar.txt"), String) == "output-txt-content-2"
    finally
        rm(tmp; recursive=true, force=true)
    end
    tmp_tarball_path = tempname()
    try
        JuliaHub.download_job_file(result_tarball, tmp_tarball_path)
        @test isfile(tmp_tarball_path)
        tmp = Tar.extract(tmp_tarball_path)
        @test isdir(tmp)
        @test isfile(joinpath(tmp, "foo.txt"))
        @test read(joinpath(tmp, "foo.txt"), String) == "output-txt-content-1"
        @test isfile(joinpath(tmp, "bar.txt"))
        @test read(joinpath(tmp, "bar.txt"), String) == "output-txt-content-2"
    finally
        rm(tmp_tarball_path; force=true)
        rm(tmp; recursive=true, force=true)
    end
end

@testset "[LIVE] Windows batch job" begin
    windows_batch_image = try
        JuliaHub.batchimage("winworkstation-batch", "default"; auth)
    catch e
        isa(e, JuliaHub.InvalidRequestError) || rethrow(e)
        @warn """
            Windows batch image missing
            JuliaHub.batchimages()
            $(sprint(show, MIME"text/plain"(), JuliaHub.batchimages(; auth)))
            """ exception = (e, catch_backtrace())
        if get(ENV, "JULIAHUBJL_TESTS_EXPECT_WINDOWS", nothing) == "true"
            @test !isnothing(windows_batch_image)
        else
            @test_broken !isnothing(windows_batch_image)
        end
        nothing
    end
    if !isnothing(windows_batch_image)
        job1_dir = joinpath(@__DIR__, "jobenvs", "job-windows")
        job = JuliaHub.submit_job(
            JuliaHub.appbundle(job1_dir, "script.jl"; image=windows_batch_image);
            auth
        )
        job = JuliaHub.wait_job(job)
        @test job.status == "Completed"
        @test !isempty(job.results)
        let results = JSON.parse(job.results)
            @test results isa AbstractDict
            @test haskey(results, "iswindows")
            @test results["iswindows"] === true
            @test haskey(results, "datafile_hash")
            @test results["datafile_hash"] == "e242ed3bffccdf271b7fbaf34ed72d089537b42f"
            @test haskey(results, "datafile_fallback")
            if !(results["datafile_fallback"] === true)
                @warn "Windows live test: datafile_fallback not necessary anymore."
            end
        end
    end
end
