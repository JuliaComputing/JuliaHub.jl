const JOBENV_EXPOSED_PORT = joinpath(@__DIR__, "jobenvs", "job-exposed-port")

function wait_exposed_job_502(job::JuliaHub.Job; maxtime::Real=300)
    test_request() = JuliaHub.request(job, "GET", "/"; auth, status_exception=false)
    # maxtime: it can definitely take at least 3 minutes for a job to start
    start_time = time()
    r = test_request()
    while r.status == 502
        @debug "Waiting for HTTP on job $(job.id) to start up (502-check)" time() - start_time maxtime
        time() > start_time + maxtime &&
            error("HTTP server on job $(job.id) didn't start in $(maxtime)s")
        sleep(5)
        r = test_request()
    end
    return r
end

function test_job_with_exposed_port(job::JuliaHub.Job; check_input::Bool=false, port::Integer)
    job = wait_submission(job)
    let r = wait_exposed_job_502(job)
        @test r.status == 200
        json = JSON.parse(String(r.body))
        @test json isa AbstractDict
        @test get(json, "success", nothing) === true
        @test get(json, "port", nothing) == port
        @test get(json, "nrequests", nothing) == 1
        if check_input
            @test get(json, "input", nothing) == "foobar"
        else
            @test get(json, "input", nothing) === nothing
        end
    end
    # For good measure, let's make another request, and make sure that NREQUESTS
    # gets incremented correctly.
    let r = JuliaHub.request(job, "GET", "/"; auth, status_exception=false)
        @test r.status == 200
        json = JSON.parse(String(r.body))
        @test json isa AbstractDict
        @test get(json, "success", nothing) === true
        @test get(json, "nrequests", nothing) == 2
    end
end

@testset "[LIVE] Test standard-batch image" begin
    # We'll check that the 'standard-batch' image correctly matches
    # up with the 'standard-interactive' image.
    image = JuliaHub.batchimage("standard-batch"; auth)
    @test image._interactive_product_name == "standard-interactive"
    # Submit a job that will determine the correct product name from the batchimage.
    job, _ = submit_test_job(
        JuliaHub.appbundle(JOBENV_EXPOSED_PORT, "server.jl"; image);
        expose=8080,
        alias="exposed-port", auth,
    )
    try
        test_job_with_exposed_port(job; port=8080)
    finally
        # Kill the job, since we don't want the job to run unnecessarily long
        JuliaHub.kill_job(job)
    end
end

@testset "[LIVE] Test standard-interactive (no image arg)" begin
    # Submit a job, but don't specify the image explicitly. But instead we
    # set env environment variable.
    job, _ = submit_test_job(
        JuliaHub.appbundle(JOBENV_EXPOSED_PORT, "server.jl");
        expose=23456, env=Dict("TEST_INPUT" => "foobar"),
        alias="exposed-port-no-image", auth,
    )
    try
        test_job_with_exposed_port(job; port=23456, check_input=true)
    finally
        # Kill the job, since we don't want the job to run unnecessarily long
        JuliaHub.kill_job(job)
    end
end
