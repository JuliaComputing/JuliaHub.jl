@testset "JuliaHub.Experimental.registries" begin
    @testset "Basic functionality" begin
        @testset "default registries" begin
            empty!(MOCK_JULIAHUB_STATE)
            Mocking.apply(mocking_patch) do
                registries = JuliaHub.Experimental.registries(DEFAULT_GLOBAL_MOCK_AUTH)
                @test registries isa Vector
                @test length(registries) == 2
                @test any(r -> r.name == "General", registries)
                @test any(r -> r.name == "JuliaComputingRegistry", registries)
                # Verify UUID parsing
                general_idx = findfirst(r -> r.name == "General", registries)
                @test registries[general_idx].uuid ==
                    UUIDs.UUID("23338594-aafe-5451-b93e-139f81909106")
                jc_idx = findfirst(r -> r.name == "JuliaComputingRegistry", registries)
                @test registries[jc_idx].uuid == UUIDs.UUID("bbcd6645-47a4-41f8-a415-d8fc8421bd34")
            end
            empty!(MOCK_JULIAHUB_STATE)
        end
    end

    @testset "500 server error" begin
        MOCK_JULIAHUB_STATE[:app_packages_registries_status] = 500
        Mocking.apply(mocking_patch) do
            err = @test_throws JuliaHub.JuliaHubError JuliaHub.Experimental.registries(
                DEFAULT_GLOBAL_MOCK_AUTH
            )
            @test occursin("Invalid response from JuliaHub", err.value.msg)
            @test occursin("500", err.value.msg)
        end
        empty!(MOCK_JULIAHUB_STATE)
    end

    @testset "Invalid registry data" begin
        @testset "missing name field" begin
            MOCK_JULIAHUB_STATE[:app_packages_registries] = [
                Dict("uuid" => "23338594-aafe-5451-b93e-139f81909106", "id" => 1)
            ]
            Mocking.apply(mocking_patch) do
                registries = JuliaHub.Experimental.registries(DEFAULT_GLOBAL_MOCK_AUTH)
                @test length(registries) == 1
                # BUG: function doesn't filter nothing values
                @test registries[1] === nothing
            end
            empty!(MOCK_JULIAHUB_STATE)
        end

        @testset "missing uuid field" begin
            MOCK_JULIAHUB_STATE[:app_packages_registries] = [
                Dict("name" => "TestRegistry", "id" => 1)
            ]
            Mocking.apply(mocking_patch) do
                registries = JuliaHub.Experimental.registries(DEFAULT_GLOBAL_MOCK_AUTH)
                @test length(registries) == 1
                # BUG: function doesn't filter nothing values
                @test registries[1] === nothing
            end
            empty!(MOCK_JULIAHUB_STATE)
        end

        @testset "invalid uuid format" begin
            MOCK_JULIAHUB_STATE[:app_packages_registries] = [
                Dict("name" => "TestRegistry1", "uuid" => "not-a-uuid", "id" => 1),
                Dict("name" => "TestRegistry2", "uuid" => "1234", "id" => 2),
                Dict("name" => "TestRegistry3", "uuid" => "", "id" => 3),
            ]
            Mocking.apply(mocking_patch) do
                # tryparse returns nothing for invalid UUIDs, then Registry(nothing, name) throws
                @test_throws MethodError JuliaHub.Experimental.registries(DEFAULT_GLOBAL_MOCK_AUTH)
            end
            empty!(MOCK_JULIAHUB_STATE)
        end

        @testset "wrong data types" begin
            MOCK_JULIAHUB_STATE[:app_packages_registries] = [
                Dict("name" => 123, "uuid" => "23338594-aafe-5451-b93e-139f81909106", "id" => 1),
                Dict(
                    "name" => nothing, "uuid" => "23338594-aafe-5451-b93e-139f81909106", "id" => 2
                ),
            ]
            Mocking.apply(mocking_patch) do
                # Registry constructor expects String for name, throws MethodError for Int64/Nothing
                @test_throws MethodError JuliaHub.Experimental.registries(DEFAULT_GLOBAL_MOCK_AUTH)
            end
            empty!(MOCK_JULIAHUB_STATE)
        end
    end

    @testset "Edge cases" begin
        @testset "mixed valid and invalid registries" begin
            MOCK_JULIAHUB_STATE[:app_packages_registries] = [
                Dict(
                    "name" => "ValidRegistry",
                    "uuid" => "23338594-aafe-5451-b93e-139f81909106",
                    "id" => 1,
                ),
                Dict("name" => "InvalidRegistry", "id" => 2),  # missing uuid
                Dict(
                    "name" => "AnotherValid",
                    "uuid" => "bbcd6645-47a4-41f8-a415-d8fc8421bd34",
                    "id" => 3,
                ),
            ]
            Mocking.apply(mocking_patch) do
                registries = JuliaHub.Experimental.registries(DEFAULT_GLOBAL_MOCK_AUTH)
                @test length(registries) == 3
                # BUG: includes nothing in the middle
                @test registries[1] isa JuliaHub.Experimental.Registry
                @test registries[1].name == "ValidRegistry"
                @test registries[2] === nothing
                @test registries[3] isa JuliaHub.Experimental.Registry
                @test registries[3].name == "AnotherValid"
            end
            empty!(MOCK_JULIAHUB_STATE)
        end
    end
end
