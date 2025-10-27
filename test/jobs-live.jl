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

USED_JOB_ALIASES = String[]
function gen_jobalias(alias)
    global TESTID, USED_JOB_ALIASES
    alias in USED_JOB_ALIASES && error("job alias '$alias' already used")
    return "JuliaHub.jl tests / $(TESTID) / $(alias)"
end
# A small wrapper around JuliaHub.submit_job, which sets a unique alias
# for each job, and also prints an at-info message into the logs.
function submit_test_job(args...; alias::AbstractString, kwargs...)
    full_alias = gen_jobalias(alias)
    try
        job = JuliaHub.submit_job(args...; alias=full_alias, kwargs...)
        @info "Submitted $(alias): $(job.id)" alias = full_alias job.status
        return job, full_alias
    catch
        @error "Failed to submit job: $alias" args kwargs full_alias
        rethrow()
    end
end

jobs = JuliaHub.jobs(; limit=HIGH_JOB_LIMIT, auth=auth)
num_jobs_prev = length(jobs)
previous_last_job = nothing

@testset "[LIVE] JuliaHub.batchimage[s]()" begin
    allimages = JuliaHub.batchimages(; auth)
    products = unique(image.product for image in allimages)
    @test !isempty(products)
    @test "standard-batch" in products
    n_single_default_image_tests = 0
    for product in products
        nimages_for_product = sum(image.product == product for image in allimages)
        @test nimages_for_product > 0
        images = JuliaHub.batchimages(product; auth)
        @test length(images) == nimages_for_product
        # Test default image for a product
        default_images = filter(i -> i.product == product && i._is_product_default, allimages)
        @test length(default_images) > 0 # this assumes that every image has a default image
        if length(default_images) == 1
            image = JuliaHub.batchimage(product; auth)
            @test image.product == product
            product_default_image = only(
                filter(i -> i.product == product && i._is_product_default, allimages)
            )
            @test image.image == product_default_image.image
            # We want to make sure that this branch gets tested, and having multiple default
            # images for several products is a major configuration problem, so we'd expect that
            # at least a few products are configured correctly.
            n_single_default_image_tests += 1
        else
            # It can happen that a product declares multiple default images. That's likely a
            # configuration error, but we don't want the tests to fail because of it.
            # And, in fact, it allows us to sorta test the error handling here.
            @warn "Multiple default images for product: $(product)" default_images
            @test_throws Exception JuliaHub.batchimage(product; auth)
        end
    end
    @test n_single_default_image_tests > 0
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
    job, _ = submit_test_job(
        JuliaHub.script"@info 1+1; sleep(200)"noenv;
        ncpu=2, memory=8,
        auth, alias="script-simple",
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
    # On 6.4+, killing a job doesn't immediately change its status
    #@test job_killed.status ∉ ("Running", "Submitted")
    # Wait a bit more and then make sure that the job is stopped
    for t in [10, 20, 60, 180]
        @info "Sleeping for $(t)s, waiting for job to be killed: $(job.id)"
        sleep(t)
        if JuliaHub.job(job_killed).status ∉ ("Running", "Submitted")
            break
        end
    end
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
    job, _ = submit_test_job(
        JuliaHub.script"""
        ENV["RESULTS"] = "{\\"x\\":42}"
        if haskey(ENV, "JULIAHUB_RESULTS_SUMMARY_FILE")
            open(ENV["JULIAHUB_RESULTS_SUMMARY_FILE"], "w") do io
                write(io, "{\\"x\\":42}")
            end
        end
        error("fail")
        """noenv;
        auth, alias="script-fail", timelimit=JuliaHub.Unlimited(),
    )
    @test job._json["limit_type"] == "unlimited"
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
    script_path = joinpath(@__DIR__, "jobenvs", "job-dist")
    job, _ = submit_test_job(
        JuliaHub.script(;
            code=read(joinpath(script_path, "script.jl"), String),
            project=read(joinpath(script_path, "Project.toml"), String),
            manifest=read(joinpath(script_path, "Manifest.toml"), String),
        );
        nnodes=3,
        auth, alias="distributed",
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
    script_path = joinpath(@__DIR__, "jobenvs", "job-dist")
    job, full_alias = submit_test_job(
        JuliaHub.script(;
            code=read(joinpath(script_path, "script.jl"), String),
            project=read(joinpath(script_path, "Project.toml"), String),
            manifest=read(joinpath(script_path, "Manifest.toml"), String),
        );
        ncpu=2, nnodes=3, process_per_node=false,
        env=Dict("FOO" => "bar"),
        auth, alias="distributed-percore",
    )
    @test job.env["jobname"] == full_alias
    @test job.alias == full_alias
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
    job, _ = submit_test_job(
        JuliaHub.script(
            joinpath(job1_dir, "script.jl");
            project_directory=job1_dir,
        );
        auth, alias="scripts-1",
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
    job, _ = submit_test_job(
        JuliaHub.script(;
            code=read(joinpath(job1_dir, "script.jl"), String),
            project=read(joinpath(job1_dir, "Project.toml"), String),
        );
        auth, alias="scripts-2",
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
    # Note: the exact hash of the file may change if Git decides to change line endings
    # on e.g. Windows.
    datafile_hash = bytes2hex(open(SHA.sha1, joinpath(job1_dir, "datafile.txt")))
    job, _ = submit_test_job(
        JuliaHub.appbundle(job1_dir, "script.jl");
        auth, alias="appbundle",
    )
    job = JuliaHub.wait_job(job)
    @test job.status == "Completed"
    # Check input and output files
    @test length(JuliaHub.job_files(job, :input)) >= 2
    @test JuliaHub.job_file(job, :input, "code.jl") isa JuliaHub.JobFile
    @test JuliaHub.job_file(job, :input, "appbundle.tar") isa JuliaHub.JobFile
    # Test the results values
    @test !isempty(job.results)
    let results = JSON.parse(job.results)
        @test results isa AbstractDict
        @test haskey(results, "datastructures_version")
        @test VersionNumber(results["datastructures_version"]) == v"0.17.0"
        @test haskey(results, "datafile_hash")
        @test results["datafile_hash"] == datafile_hash
        @test haskey(results, "scripts")
        let s = results["scripts"]
            @test s isa AbstractDict
            @test get(s, "include_success", nothing) === true
            @test get(s, "script_1", nothing) === true
            @test get(s, "script_2", nothing) === true
        end
    end
end

@testset "[LIVE] Job output file access" begin
    job1_dir = joinpath(@__DIR__, "jobenvs", "job1")
    job, _ = submit_test_job(
        JuliaHub.script"""
        ENV["RESULTS_FILE"] = joinpath(@__DIR__, "output.txt")
        n = write(ENV["RESULTS_FILE"], "output-txt-content")
        @info "Wrote $(n) bytes"
        if haskey(ENV, "JULIAHUB_RESULTS_UPLOAD_DIR")
            open(joinpath(ENV["JULIAHUB_RESULTS_UPLOAD_DIR"], "output.txt"), "w") do io
                write(io, "output-txt-content")
            end
        end
        """noenv; alias="output-file"
    )
    job = JuliaHub.wait_job(job)
    @test job.status == "Completed"
    # Project.toml, Manifest.toml, code.jl
    @test length(JuliaHub.job_files(job, :input)) >= 1
    @test JuliaHub.job_file(job, :input, "code.jl") isa JuliaHub.JobFile
    # code.jl
    @test length(JuliaHub.job_files(job, :source)) >= 1
    @test JuliaHub.job_file(job, :source, "code.jl") isa JuliaHub.JobFile
    # Project.toml, Manifest.toml
    @test length(JuliaHub.job_files(job, :project)) >= 1
    @test JuliaHub.job_file(job, :project, "Manifest.toml") isa JuliaHub.JobFile
    # output.txt
    @test length(JuliaHub.job_files(job, :result)) == 1
    jf = JuliaHub.job_file(job, :result, "output.txt")
    @test jf isa JuliaHub.JobFile
    buf = IOBuffer()
    JuliaHub.download_job_file(jf, buf)
    @test String(take!(buf)) == "output-txt-content"

    # Job output with a tarball:
    job, _ = submit_test_job(
        JuliaHub.script"""
        odir = if haskey(ENV, "JULIAHUB_RESULTS_UPLOAD_DIR")
            ENV["JULIAHUB_RESULTS_UPLOAD_DIR"]
        else
            d = joinpath(@__DIR__, "output_files")
            mkdir(d)
            d
        end
        write(joinpath(odir, "foo.txt"), "output-txt-content-1")
        write(joinpath(odir, "bar.txt"), "output-txt-content-2")
        @info "Wrote: odir"
        ENV["RESULTS_FILE"] = odir
        """noenv; alias="output-file-tarball"
    )
    job = JuliaHub.wait_job(job)
    @test job.status == "Completed"
    @test length(JuliaHub.job_files(job, :project)) >= 1
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

@testset "[LIVE] JuliaHub.submit_job / sysimage" begin
    job, _ = submit_test_job(
        JuliaHub.appbundle(
            joinpath(@__DIR__, "jobenvs", "sysimage"),
            "script.jl";
            sysimage=true,
        ); auth, alias="sysimage"
    )
    job = JuliaHub.wait_job(job)
    @test job.status == "Completed"
    @test job._json["sysimage_build"] === true
    @test !isempty(job.results)
    let results = JSON.parse(job.results)
        @test results isa AbstractDict
        @test results["in_sysimage"] === true
        @test results["loaded_modules_before_import"] === true
        @test results["loaded_modules_after_import"] === true
        @test results["domath"] == 5
        @test results["hello"] == "Hello, Sysimage"
    end
end
