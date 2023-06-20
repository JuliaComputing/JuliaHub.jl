@testset "JuliaHub.authenticate()" begin
    empty!(MOCK_JULIAHUB_STATE)
    Mocking.apply(mocking_patch) do
        withenv("JULIA_PKG_SERVER" => nothing) do
            @test_throws JuliaHub.AuthenticationError JuliaHub.authenticate()
            @test JuliaHub.authenticate("https://juliahub.com") isa JuliaHub.Authentication
            @test JuliaHub.authenticate("juliahub.com") isa JuliaHub.Authentication
        end
        withenv("JULIA_PKG_SERVER" => "juliahub.com") do
            @test JuliaHub.authenticate() isa JuliaHub.Authentication
        end
        withenv("JULIA_PKG_SERVER" => "https://juliahub.com") do
            @test JuliaHub.authenticate() isa JuliaHub.Authentication
        end
        # Conflicting declarations, argument takes precendence
        withenv("JULIA_PKG_SERVER" => "https://juliahub-one.com") do
            auth = JuliaHub.authenticate("https://juliahub-two.com")
            @test auth isa JuliaHub.Authentication
            @test auth.server == URIs.URI("https://juliahub-two.com")
            # check_authentication
            MOCK_JULIAHUB_STATE[:invalid_authentication] = false
            @test JuliaHub.check_authentication(; auth) === true
            MOCK_JULIAHUB_STATE[:invalid_authentication] = true
            @test JuliaHub.check_authentication(; auth) === false
            delete!(MOCK_JULIAHUB_STATE, :invalid_authentication)
        end
    end
end
