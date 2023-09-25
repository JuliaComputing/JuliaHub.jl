# The JULIAHUBJL_LIVE_IDE_NAME can be used to override the default Julia
# IDE name, should it change in the backend.
DEFAULT_IDE_NAME = get(ENV, "JULIAHUBJL_LIVE_IDE_NAME", "Julia IDE")

@testset "[LIVE] Application job" begin
    default_ide = JuliaHub.application(:default, DEFAULT_IDE_NAME)
    job = JuliaHub.submit_job(default_ide)
    @test job.alias == DEFAULT_IDE_NAME
    job = wait_submission(job)
    @test job.status == "Running"
    job = JuliaHub.kill_job(job)
    job = JuliaHub.wait_job(job)
    @test job.status == "Stopped"
end
