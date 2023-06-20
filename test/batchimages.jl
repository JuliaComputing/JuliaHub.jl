@testset "_parse_image_group_entry_type" begin
    @test JuliaHub._parse_image_group_entry_type(Dict("type" => "base-cpu")) ==
        (; isdefault=true, gpu=false)
    @test JuliaHub._parse_image_group_entry_type(Dict("type" => "base-gpu")) ==
        (; isdefault=true, gpu=true)
    @test JuliaHub._parse_image_group_entry_type(Dict("type" => "option-cpu")) ==
        (; isdefault=false, gpu=false)
    @test JuliaHub._parse_image_group_entry_type(Dict("type" => "option-gpu")) ==
        (; isdefault=false, gpu=true)
    # Erroneous cases which also print a warning message
    @test_logs (:warn,) @test JuliaHub._parse_image_group_entry_type(
        Dict("type" => "base-foo")
    ) === nothing
    @test_logs (:warn,) @test JuliaHub._parse_image_group_entry_type(
        Dict("type" => "option-foo")
    ) === nothing
    @test_logs (:warn,) @test JuliaHub._parse_image_group_entry_type(
        Dict("type" => "base-zpu")
    ) === nothing
    @test_logs (:warn,) @test JuliaHub._parse_image_group_entry_type(
        Dict("type" => "")
    ) === nothing
    @test_logs (:warn,) @test JuliaHub._parse_image_group_entry_type(
        Dict("type" => "base_gpu")
    ) === nothing
end

@testset "_group_images" begin
    image_groups = JuliaHub._group_images(
        [
            Dict(
                "display_name" => "Stable", "type" => "base-cpu",
                "image_key_name" => "stable-cpu"
            ),
            Dict(
                "display_name" => "Stable", "type" => "base-gpu",
                "image_key_name" => "stable-gpu"
            ),
            Dict(
                "display_name" => "Dev", "type" => "option-cpu", "image_key_name" => "dev-cpu"
            ),
            Dict(
                "display_name" => "Dev", "type" => "option-gpu", "image_key_name" => "dev-gpu"
            ),
        ]; image_group="")
    @test length(image_groups) == 2

    @test image_groups[1].first == "Stable"
    @test image_groups[1].second.cpu == "stable-cpu"
    @test image_groups[1].second.gpu == "stable-gpu"
    @test image_groups[1].second.isdefault === true
    @test image_groups[1].second.error === false

    @test image_groups[2].first == "Dev"
    @test image_groups[2].second.cpu == "dev-cpu"
    @test image_groups[2].second.gpu == "dev-gpu"
    @test image_groups[2].second.isdefault === false
    @test image_groups[2].second.error === false
end

@testset "_product_image_groups" begin
    auth = JuliaHub.current_authentication()
    Mocking.apply(mocking_patch) do
        image_groups = JuliaHub._product_image_groups(auth)
        @test image_groups isa Dict
        @test keys(image_groups) == Set(("base_and_opt", "base_only"))
        @test length(image_groups["base_only"]) == 1
        @test length(image_groups["base_and_opt"]) == 2
    end
end

@testset "_batchimages_62" begin
    MOCK_JULIAHUB_STATE[:api_version] = v"0.0.1"
    auth = JuliaHub.current_authentication()
    Mocking.apply(mocking_patch) do
        images = JuliaHub._batchimages_62(auth)
        @test length(images) == 3
        @test all(isequal(JuliaHub.BatchImage), typeof.(images))
    end
    empty!(MOCK_JULIAHUB_STATE)
end

#= TODO: mock the legacy juliaruncloud/get_image_options endpoint
@testset "batchimages ($(JuliaHub._MISSING_API_VERSION))" begin
    auth = JuliaHub.current_authentication()
    auth._api_version = JuliaHub._MISSING_API_VERSION
    Mocking.apply(mocking_patch) do
        images = JuliaHub.batchimages(; auth)
        @show images
    end
end
=#

@testset "batchimages (0.0.1)" begin
    apiv = v"0.0.1"
    MOCK_JULIAHUB_STATE[:api_version] = apiv
    auth = JuliaHub.current_authentication()
    auth._api_version = apiv
    Mocking.apply(mocking_patch) do
        images = JuliaHub.batchimages(; auth)
        @test length(images) === 3
        let prods_images = [(i.product, i.image) for i in images]
            @test ("baseproduct", "Stable") in prods_images
            @test ("extra-images", "Stable") in prods_images
            @test ("extra-images", "Dev") in prods_images
        end
        images = JuliaHub.batchimages("baseproduct"; auth)
        @test length(images) == 1
        images = JuliaHub.batchimages("extra-images"; auth)
        @test length(images) == 2
        @test JuliaHub.batchimages("no-product"; auth) |> isempty

        let image = JuliaHub.batchimage("baseproduct", "Stable"; auth)
            @test image.product == "baseproduct"
            @test image.image == "Stable"
            @test image._cpu_image_key == "stable-cpu"
            @test image._gpu_image_key == "stable-gpu"
        end
        let image = JuliaHub.batchimage("extra-images", "Stable"; auth)
            @test image.product == "extra-images"
            @test image.image == "Stable"
            @test image._cpu_image_key == "stable-cpu"
            @test image._gpu_image_key == "stable-gpu"
        end
        let image = JuliaHub.batchimage("extra-images", "Dev"; auth)
            @test image.product == "extra-images"
            @test image.image == "Dev"
            @test image._cpu_image_key == "dev-cpu"
            @test image._gpu_image_key == "dev-gpu"
        end
        @test_throws JuliaHub.InvalidRequestError JuliaHub.batchimage(
            "no-such-product", "..."; auth
        )
        @test JuliaHub.batchimage("no-such-product", "..."; throw=false, auth) === nothing

        # Test picking default images
        let image = JuliaHub.batchimage("baseproduct")
            @test image.product == "baseproduct"
            @test image.image == "Stable"
            @test image._cpu_image_key == "stable-cpu"
            @test image._gpu_image_key == "stable-gpu"
        end
        let image = JuliaHub.batchimage("extra-images")
            @test image.product == "extra-images"
            @test image.image == "Stable"
            @test image._cpu_image_key == "stable-cpu"
            @test image._gpu_image_key == "stable-gpu"
        end
        @test_throws JuliaHub.InvalidRequestError JuliaHub.batchimage("no-such-product")
        @test JuliaHub.batchimage("no-such-product"; throw=false) === nothing
    end
    empty!(MOCK_JULIAHUB_STATE)
end
