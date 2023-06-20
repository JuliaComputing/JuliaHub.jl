# Can be used to prefix test-related data on the instance (like dataset names)
# to avoid clashes with test suites running in parallel.
TESTID = Random.randstring(8)

# Authenticate the test session
JULIAHUB_SERVER = let
    juliahub_server = get(ENV, "JULIAHUB_SERVER") do
        error("JULIAHUB_SERVER environment variable must be set for these tests to work")
    end
    JuliaHub._sanitize_juliahub_uri(juliahub_server) do _, msg
        error("JULIAHUB_SERVER is invalid: $msg")
    end
end
auth = if haskey(ENV, "JULIAHUB_TOKEN")
    JULIAHUB_TOKEN = JuliaHub.Secret(ENV["JULIAHUB_TOKEN"])
    JuliaHub._authentication(JULIAHUB_SERVER; token=JULIAHUB_TOKEN)
else
    @warn "JULIAHUB_TOKEN not set, attempting interactive authentication."
    @show JuliaHub.authenticate(string(JULIAHUB_SERVER))
end
# manually set global auth ref
JuliaHub.__AUTH__[] = auth
@info "Authentication / API version: $(auth._api_version)"

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

    is_enabled("jobs") &&
        @testset "JuliaHub Jobs" begin
            include("jobs-live.jl")
        end
end
