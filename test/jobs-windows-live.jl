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
        datafile_hash = bytes2hex(open(SHA.sha1, joinpath(job1_dir, "datafile.txt")))
        job, full_alias = submit_test_job(
            JuliaHub.appbundle(job1_dir, "script.jl"; image=windows_batch_image);
            auth, alias="windows-batch",
        )
        job = JuliaHub.wait_job(job)
        @test job.status == "Completed"
        @test job.alias == full_alias
        @test !isempty(job.results)
        let results = JSON.parse(job.results)
            @test results isa AbstractDict
            @test haskey(results, "iswindows")
            @test results["iswindows"] === true
            @test haskey(results, "datafile_hash")
            @test results["datafile_hash"] == datafile_hash
            @test haskey(results, "datafile_fallback")
            if !(results["datafile_fallback"] === true)
                @warn "Windows live test: datafile_fallback not necessary anymore."
            end
        end
    end
end
