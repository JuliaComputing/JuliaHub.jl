@testset "JuliaHub._api_registries" begin
    Mocking.apply(mocking_patch) do
        registries = JuliaHub._api_registries(auth)
        @test registries isa Vector{JuliaHub._RegistryInfo}
        @test length(registries) == 2
        @test "General" in (r.name for r in registries)
        @test "JuliaComputingRegistry" in (r.name for r in registries)
    end
end

@testset "JuliaHub.application(s)" begin
    Mocking.apply(mocking_patch) do
        @test length(JuliaHub.applications()) == 7
        @test length(JuliaHub.applications(:default)) == 4
        @test length(JuliaHub.applications(:package)) == 2
        @test length(JuliaHub.applications(:user)) == 1
        let app = JuliaHub.application(:default, "Linux Desktop")
            @test app isa JuliaHub.DefaultApp
            @test app.name == "Linux Desktop"
        end
        @test_throws JuliaHub.InvalidRequestError JuliaHub.application(:default, "no-such-app")
        @test JuliaHub.application(:default, "no-such-app"; throw=false) === nothing
    end
end
