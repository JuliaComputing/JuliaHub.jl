@testset "Utilities" begin
    let xs = JuliaHub._validate_iterable_argument(String, Any["a", "b"]; argument="test")
        @test xs isa Vector{String}
        @test xs == ["a", "b"]
    end
    let s = "1234567890", xs = [SubString(s, 1:4), SubString(s, 4:8)]
        ys = JuliaHub._validate_iterable_argument(String, xs; argument="test")
        @test ys isa Vector{String}
        @test ys == ["1234", "45678"]
    end
    let xs = JuliaHub._validate_iterable_argument(String, ("a", "b"); argument="test")
        @test xs isa Vector{String}
        @test xs == ["a", "b"]
    end
    let xs = JuliaHub._validate_iterable_argument(String, (string(i) for i = 1:3); argument="test")
        @test xs isa Vector{String}
        @test xs == ["1", "2", "3"]
    end
    @test_throws ArgumentError JuliaHub._validate_iterable_argument(
        String, [1, 2, 3]; argument="test"
    )
end

@testset "JuliaHub.dataset(s)" begin
    Mocking.apply(mocking_patch) do
        let dss = JuliaHub.datasets()
            @test dss isa Vector{JuliaHub.Dataset}
            @test length(dss) == 2
        end
        let dss = JuliaHub.datasets(; shared=true)
            @test dss isa Vector{JuliaHub.Dataset}
            @test length(dss) == 3
        end
        let dss = JuliaHub.datasets("username")
            @test dss isa Vector{JuliaHub.Dataset}
            @test length(dss) == 2
        end
        let dss = JuliaHub.datasets("anotheruser")
            @test dss isa Vector{JuliaHub.Dataset}
            @test length(dss) == 1
            @test first(dss).name == "publicdataset"
        end

        let ds = JuliaHub.dataset("example-dataset")
            @test ds isa JuliaHub.Dataset
            @test ds.name == "example-dataset"
            @test ds.owner == "username"
            @test ds.dtype == "Blob"
            @test ds.description == "An example dataset"

            ds_updated = JuliaHub.dataset("example-dataset")
            @test ds_updated isa JuliaHub.Dataset
            @test ds_updated.name == ds.name
            @test ds_updated.owner == ds.owner
            @test ds_updated.dtype == ds.dtype
            @test ds_updated.description == ds.description
        end
        let ds = JuliaHub.dataset(("username", "example-dataset"); throw=false)
            @test ds isa JuliaHub.Dataset
            @test ds.name == "example-dataset"
            @test ds.dtype == "Blob"
            @test ds.description == "An example dataset"
        end
        let ds = JuliaHub.dataset(("username", "blobtree/example"))
            @test ds isa JuliaHub.Dataset
            @test ds.name == "blobtree/example"
            @test ds.dtype == "BlobTree"
            @test ds.description == "An example dataset"
        end
        @test_throws JuliaHub.InvalidRequestError JuliaHub.dataset("doesnt-exist")
        @test_throws JuliaHub.InvalidRequestError JuliaHub.dataset("doesn't-exist")
        @test JuliaHub.dataset("doesn't-exist"; throw=false) === nothing

        @test_throws JuliaHub.InvalidRequestError JuliaHub.dataset("publicdataset")
        # For datasets not owned by the user, the username must be specified
        @test_throws JuliaHub.InvalidRequestError JuliaHub.dataset(("username", "publicdataset"))
        let ds = JuliaHub.dataset(("anotheruser", "publicdataset"))
            @test ds isa JuliaHub.Dataset
            @test ds.owner == "anotheruser"
            @test ds.name == "publicdataset"
            @test ds.dtype == "Blob"
        end
    end
end

@testset "JuliaHub.download_dataset" begin
    # The mocked _rclone() prints, so we can override it here.
    MOCK_JULIAHUB_STATE[:stdout_stream] = devnull
    Mocking.apply(mocking_patch) do
        @test JuliaHub.download_dataset("example-dataset", "local") == joinpath(pwd(), "local")
        @test JuliaHub.download_dataset(("username", "example-dataset"), "local") ==
            joinpath(pwd(), "local")
        @test JuliaHub.download_dataset(("anotheruser", "publicdataset"), "local") ==
            joinpath(pwd(), "local")
        # Downloading BlobTree datasets actually creates the destination directory
        # outside of the rclone() call. So this test mutates the disk and we'll do it
        # in a temporary directory.
        mktempdir() do path
            cd(path) do
                @test JuliaHub.download_dataset(("username", "blobtree/example"), "local") ==
                    joinpath(pwd(), "local")
                @test isdir(joinpath(pwd(), "local"))
                @test_throws ArgumentError JuliaHub.download_dataset(
                    ("username", "blobtree/example"), "local"
                )
                @test_logs (:warn,) JuliaHub.download_dataset(
                    ("username", "blobtree/example"), "local"; replace=true
                )
                rm("local"; recursive=true)
                @test_logs min_level = Logging.Warn JuliaHub.download_dataset(
                    ("username", "blobtree/example"), "local"; replace=true
                )
                @test isdir(joinpath(pwd(), "local"))
                @test_logs (:warn,) JuliaHub.download_dataset(
                    ("username", "blobtree/example"),
                    "local"; replace=true
                )
                @test isdir(joinpath(pwd(), "local"))
            end
        end
        # Various invalid user/dataset combinations:
        @test_throws JuliaHub.InvalidRequestError JuliaHub.download_dataset(
            ("username", "publicdataset"), "local"
        )
        @test_throws JuliaHub.InvalidRequestError JuliaHub.download_dataset(
            ("anotheruser", "example-dataset"), "local"
        )
        @test_throws JuliaHub.InvalidRequestError JuliaHub.download_dataset(
            "publicdataset", "local"
        )
        @test_throws JuliaHub.InvalidRequestError JuliaHub.download_dataset(
            ("username", "dont-exist"), "local"
        )
        @test_throws JuliaHub.InvalidRequestError JuliaHub.download_dataset(
            "dont-exist", "local"
        )
    end
    delete!(MOCK_JULIAHUB_STATE, :stdout_stream)
end

@testset "JuliaHub.delete_dataset" begin
    Mocking.apply(mocking_patch) do
        @test JuliaHub.delete_dataset("example-dataset") === nothing
        @test JuliaHub.delete_dataset(("username", "example-dataset")) === nothing
        @test JuliaHub.delete_dataset("blobtree/example") === nothing
        @test_throws JuliaHub.InvalidRequestError JuliaHub.delete_dataset("no-such-dataset")
        @test JuliaHub.delete_dataset("no-such-dataset"; force=true) === nothing
        # The backend does not support modifying other users' datasets
        @test_throws JuliaHub.PermissionError JuliaHub.delete_dataset((
            "anotheruser", "publicdataset"
        ))
    end
end

@testset "JuliaHub.update_dataset" begin
    Mocking.apply(mocking_patch) do
        @test JuliaHub.update_dataset("example-dataset") isa JuliaHub.Dataset
        @test JuliaHub.update_dataset("example-dataset"; description="...") isa JuliaHub.Dataset
        @test JuliaHub.update_dataset(
            ("username", "example-dataset"); description="...", tags=["asd", "foo"]
        ) isa JuliaHub.Dataset
        # Iterables are okay for tags
        @test JuliaHub.update_dataset(
            "example-dataset"; tags=("foo", "bar")
        ) isa JuliaHub.Dataset
        @test JuliaHub.update_dataset(
            "example-dataset"; tags=(string(i) for i = 1:4), groups=("foo", "bar")
        ) isa JuliaHub.Dataset
        # Non-existant datasets throw:
        @test_throws JuliaHub.InvalidRequestError JuliaHub.update_dataset("doesnt-exist")
        # Invalid arguments
        @test_throws ArgumentError JuliaHub.update_dataset(
            "example-dataset"; tags=[1, 2, 3]
        )
        @test_throws ArgumentError JuliaHub.update_dataset(
            "example-dataset"; groups=[1, 2, 3]
        )
        @test_throws TypeError JuliaHub.update_dataset(
            "example-dataset"; description=42
        )
    end
end

@testset "JuliaHub.upload_dataset" begin
    MOCK_JULIAHUB_STATE[:existing_datasets] = []
    MOCK_JULIAHUB_STATE[:stdout_stream] = devnull
    Mocking.apply(mocking_patch) do
        @test_throws JuliaHub.PermissionError JuliaHub.upload_dataset(
            ("anotheruser", "example-dataset"), @__DIR__
        )
        # Mock-upload a Blob-type dataset:
        @assert !("username/example-dataset" in MOCK_JULIAHUB_STATE[:existing_datasets])
        @test JuliaHub.upload_dataset("example-dataset", @__FILE__) isa JuliaHub.Dataset
        @assert "username/example-dataset" in MOCK_JULIAHUB_STATE[:existing_datasets]
        @test_throws JuliaHub.InvalidRequestError JuliaHub.upload_dataset(
            "example-dataset", @__FILE__
        )
        # Same, but for blobtrees:
        @assert !("username/example-blobtree" in MOCK_JULIAHUB_STATE[:existing_datasets])
        @test JuliaHub.upload_dataset("example-blobtree", @__DIR__) isa JuliaHub.Dataset
        @assert "username/example-blobtree" in MOCK_JULIAHUB_STATE[:existing_datasets]
        @test_throws JuliaHub.InvalidRequestError JuliaHub.upload_dataset(
            "example-blobtree", @__DIR__
        )
        @test JuliaHub.upload_dataset(
            "example-blobtree", @__DIR__; update=true
        ) isa JuliaHub.Dataset
        # dataset exists & the type is wrong:
        @test_throws JuliaHub.InvalidRequestError JuliaHub.upload_dataset(
            "example-blobtree", @__FILE__; update=true
        )
        @test_throws JuliaHub.InvalidRequestError JuliaHub.upload_dataset(
            "example-dataset", @__DIR__; update=true
        )
        # can't set update and replace true at the same time
        @test_throws ArgumentError JuliaHub.upload_dataset(
            "example-dataset", @__DIR__; update=true, replace=true
        )
        # simple replace calls (note: we can't test dtype changing because the
        # the mocking logic uses dataset name for that).
        @test JuliaHub.upload_dataset("example-dataset", @__FILE__; replace=true) isa
            JuliaHub.Dataset
        @test JuliaHub.upload_dataset("example-blobtree", @__DIR__; replace=true) isa
            JuliaHub.Dataset

        # No creation if 'create=false'
        @test_throws ArgumentError JuliaHub.upload_dataset(
            "example-dataset-2", @__FILE__; create=false
        ) isa JuliaHub.Dataset
        @assert !("username/example-dataset-2" in MOCK_JULIAHUB_STATE[:existing_datasets])
        @test_throws JuliaHub.InvalidRequestError JuliaHub.upload_dataset(
            "example-dataset-2", @__FILE__; create=false, update=true
        ) isa JuliaHub.Dataset

        # @test JuliaHub.upload_dataset(
        #     "existing-dataset", @__FILE__; update=true) isa JuliaHub.Dataset
    end
    empty!(MOCK_JULIAHUB_STATE)
end
