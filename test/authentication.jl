@testset "_juliahub_project" begin
    uuid1 = "80c74bbd-fd5a-4f99-a647-0eec08183ed4"
    uuid2 = "24d0f8a7-4c3f-4168-aef4-e49248f3cb40"
    withenv("JULIAHUB_PROJECT_UUID" => nothing) do
        @test JuliaHub._juliahub_project(uuid1) == UUIDs.UUID(uuid1)
        @test_throws ArgumentError JuliaHub._juliahub_project("invalid")
        @test JuliaHub._juliahub_project(nothing) === nothing
        @test JuliaHub._juliahub_project(missing) === nothing
    end
    withenv("JULIAHUB_PROJECT_UUID" => "") do
        @test JuliaHub._juliahub_project(uuid1) == UUIDs.UUID(uuid1)
        @test_throws ArgumentError JuliaHub._juliahub_project("invalid")
        @test_throws ArgumentError JuliaHub._juliahub_project("")
        @test JuliaHub._juliahub_project(nothing) === nothing
        @test JuliaHub._juliahub_project(missing) === nothing
    end
    withenv("JULIAHUB_PROJECT_UUID" => "  ") do
        @test JuliaHub._juliahub_project(missing) === nothing
    end
    withenv("JULIAHUB_PROJECT_UUID" => uuid1) do
        @test JuliaHub._juliahub_project(uuid2) == UUIDs.UUID(uuid2)
        @test_throws ArgumentError JuliaHub._juliahub_project("invalid")
        @test JuliaHub._juliahub_project(nothing) === nothing
        @test JuliaHub._juliahub_project(missing) === UUIDs.UUID(uuid1)
    end
    withenv("JULIAHUB_PROJECT_UUID" => "  $(uuid1) ") do
        @test JuliaHub._juliahub_project(missing) == UUIDs.UUID(uuid1)
    end
end

@testset "JuliaHub.authenticate()" begin
    empty!(MOCK_JULIAHUB_STATE)
    Mocking.apply(mocking_patch) do
        withenv("JULIA_PKG_SERVER" => nothing, "JULIAHUB_PROJECT_UUID" => nothing) do
            @test_throws JuliaHub.AuthenticationError JuliaHub.authenticate()
            @test JuliaHub.authenticate("https://juliahub.example.org") isa JuliaHub.Authentication
            @test JuliaHub.authenticate("juliahub.example.org") isa JuliaHub.Authentication
        end
        withenv("JULIA_PKG_SERVER" => "juliahub.example.org", "JULIAHUB_PROJECT_UUID" => nothing) do
            @test JuliaHub.authenticate() isa JuliaHub.Authentication
        end
        withenv(
            "JULIA_PKG_SERVER" => "https://juliahub.example.org", "JULIAHUB_PROJECT_UUID" => nothing
        ) do
            @test JuliaHub.authenticate() isa JuliaHub.Authentication
        end
        # Conflicting declarations, explicit argument takes precedence
        withenv(
            "JULIA_PKG_SERVER" => "https://juliahub-one.example.org",
            "JULIAHUB_PROJECT_UUID" => nothing,
        ) do
            auth = JuliaHub.authenticate("https://juliahub-two.example.org")
            @test auth isa JuliaHub.Authentication
            @test auth.server == URIs.URI("https://juliahub-two.example.org")
            @test auth.project_id === nothing
            # check_authentication
            MOCK_JULIAHUB_STATE[:invalid_authentication] = false
            @test JuliaHub.check_authentication(; auth) === true
            MOCK_JULIAHUB_STATE[:invalid_authentication] = true
            @test JuliaHub.check_authentication(; auth) === false
            delete!(MOCK_JULIAHUB_STATE, :invalid_authentication)
        end

        # Projects integration
        uuid1 = "80c74bbd-fd5a-4f99-a647-0eec08183ed4"
        uuid2 = "24d0f8a7-4c3f-4168-aef4-e49248f3cb40"
        withenv(
            "JULIA_PKG_SERVER" => nothing,
            "JULIAHUB_PROJECT_UUID" => uuid1,
        ) do
            auth = JuliaHub.authenticate("https://juliahub.example.org")
            @test auth.server == URIs.URI("https://juliahub.example.org")
            @test auth.project_id === UUIDs.UUID(uuid1)
            auth = JuliaHub.authenticate("https://juliahub.example.org"; project=uuid2)
            @test auth.server == URIs.URI("https://juliahub.example.org")
            @test auth.project_id === UUIDs.UUID(uuid2)
            auth = JuliaHub.authenticate("https://juliahub.example.org"; project=nothing)
            @test auth.server == URIs.URI("https://juliahub.example.org")
            @test auth.project_id === nothing
        end
    end
end

# In the general authenticate() tests, we mock the call to JuliaHub._authenticate()
# So here we call a lower level JuliaHub._authenticat**ion** implementation, with
# the REST calls mocked.
@testset "JuliaHub._authentication()" begin
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
        # Projects integration
        # The JuliaHub.authenticate(server, token) method also takes the `project`
        # keyword, and also falls back to the JULIAHUB_PROJECT_UUID.
        uuid1 = "80c74bbd-fd5a-4f99-a647-0eec08183ed4"
        uuid2 = "24d0f8a7-4c3f-4168-aef4-e49248f3cb40"
        withenv(
            "JULIA_PKG_SERVER" => nothing,
            "JULIAHUB_PROJECT_UUID" => uuid1,
        ) do
            auth = JuliaHub.authenticate(server, token)
            @test auth.server == URIs.URI("https://juliahub.example.org")
            @test auth.project_id === UUIDs.UUID(uuid1)
            auth = JuliaHub.authenticate(server, token; project=uuid2)
            @test auth.server == URIs.URI("https://juliahub.example.org")
            @test auth.project_id === UUIDs.UUID(uuid2)
            auth = JuliaHub.authenticate(server, token; project=nothing)
            @test auth.server == URIs.URI("https://juliahub.example.org")
            @test auth.project_id === nothing
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

        # Test that we handle InvalidAuthentication correctly in _authentication()
        empty!(MOCK_JULIAHUB_STATE)
        MOCK_JULIAHUB_STATE[:auth_v1_status] = 401
        @test_throws JuliaHub.AuthenticationError(
            "The authentication token is invalid"
        ) JuliaHub.authenticate(server, token)
    end
end
