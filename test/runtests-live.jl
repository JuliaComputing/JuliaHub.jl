# Can be used to prefix test-related data on the instance (like dataset names)
# to avoid clashes with test suites running in parallel.
TESTID = Random.randstring(8)
TEST_PREFIX = "JuliaHubTest_$(TESTID)"
TESTDATA = joinpath(@__DIR__, "testdata")

# Authenticate the test session
JULIAHUB_SERVER = get(ENV, "JULIAHUB_SERVER") do
    error("JULIAHUB_SERVER environment variable must be set for these tests to work")
end
auth = if haskey(ENV, "JULIAHUB_TOKEN")
    JuliaHub.authenticate(JULIAHUB_SERVER, ENV["JULIAHUB_TOKEN"])
else
    @warn "JULIAHUB_TOKEN not set, attempting interactive authentication."
    @show JuliaHub.authenticate(JULIAHUB_SERVER)
end
@info "Authentication / API version: $(auth._api_version)"
extra_enabled_live_tests(; print_info=true)

function _delete_test_dataset(auth, dataset)
    try
        @info "Deleting dataset: $dataset"
        JuliaHub.delete_dataset(dataset; auth)
    catch err
        if isa(err, JuliaHub.InvalidRequestError)
            println("$dataset not deleted: $(err)")
        else
            @warn "Failed to delete dataset '$dataset'" exception = (err, catch_backtrace())
            if err isa JuliaHub.JuliaHubError && !isnothing(err.exception)
                @info "JuliaHubError inner exception" exception = err.exception
            end
        end
    end
end

@testset "JuliaHub.jl LIVE tests" begin
    @testset "Authentication" begin
        @test_throws JuliaHub.AuthenticationError("Authentication unsuccessful after 3 tries") JuliaHub.authenticate(
            "example.org"
        )
        @test auth isa JuliaHub.Authentication
        let api_info = JuliaHub._get_api_information(auth)
            @test api_info isa JuliaHub._JuliaHubInfo
            @test api_info.username == auth.username
        end

        @test JuliaHub.check_authentication(; auth) === true
        @test JuliaHub.check_authentication(;
            auth=JuliaHub.Authentication(
                auth.server, auth._api_version, auth.username, JuliaHub.Secret("")
            ),
        ) === false
    end

    is_enabled("datasets") &&
        @testset "Datasets" begin
            include("datasets-live.jl")
        end

    is_enabled("datasets-large") &&
        @testset "Large datasets" begin
            include("datasets-large-live.jl")
        end

    is_enabled("datasets-projects"; disabled_by_default=true) &&
        @testset "Project-dataset integration" begin
            include("projects-live.jl")
        end

    if is_enabled("jobs")
        @testset "JuliaHub Jobs" begin
            @testset "Basic" begin
                include("jobs-live.jl")
            end

            is_enabled("jobs-exposed-port"; disabled_by_default=true) &&
                @testset "Exposed ports" begin
                    include("jobs-exposed-port-live.jl")
                end

            is_enabled("jobs-applications") &&
                @testset "Applications" begin
                    include("jobs-applications-live.jl")
                end

            is_enabled("jobs-windows"; disabled_by_default=true) &&
                @testset "Windows" begin
                    include("jobs-windows-live.jl")
                end
        end
    end
end
