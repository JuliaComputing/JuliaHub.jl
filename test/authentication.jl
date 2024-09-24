@testset "JuliaHub.authenticate()" begin
    empty!(MOCK_JULIAHUB_STATE)
    Mocking.apply(mocking_patch) do
        withenv("JULIA_PKG_SERVER" => nothing) do
            @test_throws JuliaHub.AuthenticationError JuliaHub.authenticate()
            @test JuliaHub.authenticate("https://juliahub.example.org") isa JuliaHub.Authentication
            @test JuliaHub.authenticate("juliahub.example.org") isa JuliaHub.Authentication
        end
        withenv("JULIA_PKG_SERVER" => "juliahub.example.org") do
            @test JuliaHub.authenticate() isa JuliaHub.Authentication
        end
        withenv("JULIA_PKG_SERVER" => "https://juliahub.example.org") do
            @test JuliaHub.authenticate() isa JuliaHub.Authentication
        end
        # Conflicting declarations, argument takes precendence
        withenv("JULIA_PKG_SERVER" => "https://juliahub-one.example.org") do
            auth = JuliaHub.authenticate("https://juliahub-two.example.org")
            @test auth isa JuliaHub.Authentication
            @test auth.server == URIs.URI("https://juliahub-two.example.org")
            # check_authentication
            MOCK_JULIAHUB_STATE[:invalid_authentication] = false
            @test JuliaHub.check_authentication(; auth) === true
            MOCK_JULIAHUB_STATE[:invalid_authentication] = true
            @test JuliaHub.check_authentication(; auth) === false
            delete!(MOCK_JULIAHUB_STATE, :invalid_authentication)
        end
    end
end

# In the general authenticate() tests, we mock the call to JuliaHub._authenticate()
# So here we call a lower level JuliaHub._authenticat**ion** implementation, with
# the REST calls mocked.
@testset "JuliaHub._authenticate()" begin
    empty!(MOCK_JULIAHUB_STATE)
    server = URIs.URI("https://juliahub.example.org")
    token = JuliaHub.Secret("")
    Mocking.apply(mocking_patch) do
        let a = JuliaHub._authentication(server; token)
            @test a isa JuliaHub.Authentication
            @test a.server == server
            @test a.username == MOCK_USERNAME
            @test a.token == token
            @test a._api_version == v"0.0.1"
            @test a._email === nothing
            @test a._expires === nothing
        end
        let a = JuliaHub._authentication(
                server;
                token,
                username="authfile_username",
                expires=1234,
                email="authfile@example.org",
            )
            @test a isa JuliaHub.Authentication
            @test a.server == server
            @test a.username == MOCK_USERNAME
            @test a._api_version == v"0.0.1"
            @test a._email == "authfile@example.org"
            @test a._expires == 1234
        end
        # On old instances, we handle if /api/v1 404s
        MOCK_JULIAHUB_STATE[:auth_v1_status] = 404
        let a = JuliaHub._authentication(
                server;
                token,
                username="authfile_username",
                expires=1234,
                email="authfile@example.org",
            )
            @test a isa JuliaHub.Authentication
            @test a.server == server
            @test a.username == MOCK_USERNAME
            @test a._api_version == JuliaHub._MISSING_API_VERSION
            @test a._email == "testuser@example.org"
            @test a._expires == 1234
        end
        # .. but on a 500, it will actually throw
        MOCK_JULIAHUB_STATE[:auth_v1_status] = 500
        @test_throws JuliaHub.AuthenticationError JuliaHub._authentication(
            server;
            token,
            username="authfile_username",
            expires=1234,
            email="authfile@example.org",
        )
        # Testing the fallback to legacy GQL endpoint
        MOCK_JULIAHUB_STATE[:auth_v1_status] = 404
        let a = JuliaHub._authentication(
                server;
                token,
                username="authfile_username",
                email="authfile@example.org",
            )
            @test a isa JuliaHub.Authentication
            @test a.server == server
            @test a.username == MOCK_USERNAME
            @test a._api_version == JuliaHub._MISSING_API_VERSION
            @test a._email == "testuser@example.org"
            @test a._expires === nothing
        end
        # Error when the fallback also 500s
        MOCK_JULIAHUB_STATE[:auth_gql_fail] = true
        @test_throws JuliaHub.AuthenticationError JuliaHub._authentication(
            server;
            token,
            username="authfile_username",
            expires=1234,
            email="authfile@example.org",
        )
        # Missing username in /api/v1 -- success, but with a warning
        delete!(MOCK_JULIAHUB_STATE, :auth_v1_status)
        MOCK_JULIAHUB_STATE[:auth_v1_username] = nothing
        let a = @test_logs (:warn,) JuliaHub._authentication(
                server;
                token,
                username="authfile_username",
                email="authfile@example.org",
            )
            @test a isa JuliaHub.Authentication
            @test a.server == server
            @test a.username == "authfile_username"
            @test a._api_version == v"0.0.1"
            @test a._email == "authfile@example.org"
        end
    end
end

# The two-argument JuliaHub.authenticate does not trigger PkgAuthentication, but
# it does do the REST calls, like JuliaHub._authentication() above
@testset "JuliaHub.authenticate(server, token)" begin
    empty!(MOCK_JULIAHUB_STATE)
    server = "https://juliahub.example.org"
    token = JuliaHub.Secret("")
    Mocking.apply(mocking_patch) do
        let a = JuliaHub.authenticate(server, token)
            @test a isa JuliaHub.Authentication
            @test a.server == URIs.URI(server)
            @test a.username == MOCK_USERNAME
            @test a.token == token
            @test a._api_version == v"0.0.1"
            @test a._email === nothing
            @test a._expires === nothing
        end
        # On old instances, we handle if /api/v1 404s
        MOCK_JULIAHUB_STATE[:auth_v1_status] = 404
        let a = JuliaHub.authenticate(server, token)
            @test a isa JuliaHub.Authentication
            @test a.server == URIs.URI(server)
            @test a.username == MOCK_USERNAME
            @test a._api_version == JuliaHub._MISSING_API_VERSION
            @test a._email === "testuser@example.org"
            @test a._expires === nothing
        end
        # .. but on a 500, it will actually throw
        MOCK_JULIAHUB_STATE[:auth_v1_status] = 500
        @test_throws JuliaHub.AuthenticationError JuliaHub.authenticate(server, token)
        # Testing the fallback to legacy GQL endpoint
        MOCK_JULIAHUB_STATE[:auth_v1_status] = 404
        let a = JuliaHub.authenticate(server, token)
            @test a isa JuliaHub.Authentication
            @test a.server == URIs.URI(server)
            @test a.username == MOCK_USERNAME
            @test a._api_version == JuliaHub._MISSING_API_VERSION
            @test a._email === "testuser@example.org"
            @test a._expires === nothing
        end
        # Error when the fallback also 500s
        MOCK_JULIAHUB_STATE[:auth_gql_fail] = true
        @test_throws JuliaHub.AuthenticationError JuliaHub.authenticate(server, token)
        # Missing username in /api/v1 -- throws an AuthenticationError, since there is
        # no auth.toml file to fall back to.
        delete!(MOCK_JULIAHUB_STATE, :auth_v1_status)
        MOCK_JULIAHUB_STATE[:auth_v1_username] = nothing
        @test_throws JuliaHub.AuthenticationError JuliaHub.authenticate(server, token)
    end
end
