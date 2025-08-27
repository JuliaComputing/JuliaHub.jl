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

# These tests mainly exercise the Dataset() constructor, to ensure that it throws the
# correct error objects.
@testset "Dataset" begin
    d0 = () -> _dataset_json("test/test"; version_sizes=[42])
    let ds = JuliaHub.Dataset(d0())
        @test ds isa JuliaHub.Dataset
        @test ds.uuid == Base.UUID("3c4441bd-04bd-59f2-5426-70de923e67c2")
        @test ds.owner == "test"
        @test ds.name == "test"
        @test ds.description == "An example dataset"
        @test ds.tags == ["tag1", "tag2"]
        @test ds.dtype == "Blob"
        @test ds.size == 42
        @test length(ds.versions) == 1
        @test ds.versions[1].id == 1
        @test ds.versions[1].size == 42
    end

    # We don't verify dtype values (this list might expand in the future)
    let d = Dict(d0()..., "type" => "Unknown Dtype")
        ds = JuliaHub.Dataset(d)
        @test ds.dtype == "Unknown Dtype"
    end

    # If there are critical fields missing, it will throw
    @testset "required property: $(pname)" for pname in (
        "id", "owner", "name", "type", "description", "tags",
        "downloadURL", "lastModified", "credentials_url", "storage",
    )
        let d = Dict(d0()...)
            delete!(d, pname)
            e = @test_throws JuliaHub.JuliaHubError JuliaHub.Dataset(d)
            @test startswith(
                e.value.msg,
                "Invalid JSON returned by the server: `$pname` missing in the response.",
            )
        end
        # Replace the value with a value that's of incorrect type
        let d = Dict(d0()..., pname => missing)
            e = @test_throws JuliaHub.JuliaHubError JuliaHub.Dataset(d)
            @test startswith(
                e.value.msg,
                "Invalid JSON returned by the server: `$(pname)` of type `Missing`, expected",
            )
        end
    end
    # We also need to be able to parse the UUID into UUIDs.UUID
    let d = Dict(d0()..., "id" => "1234")
        @test_throws JuliaHub.JuliaHubError(
            "Invalid JSON returned by the server: `id` not a valid UUID string.\nServer returned '1234'."
        ) JuliaHub.Dataset(d)
    end
    # And correctly throw for invalid owner.username
    let d = Dict(d0()..., "owner" => nothing)
        @test_throws JuliaHub.JuliaHubError(
            "Invalid JSON returned by the server: `owner` of type `Nothing`, expected `<: Dict`."
        ) JuliaHub.Dataset(d)
    end

    # Missing versions list is okay though. We assume that there are no
    # versions then.
    let d = d0()
        delete!(d, "versions")
        ds = JuliaHub.Dataset(d)
        @test length(ds.versions) == 0
    end
    # But a bad type is not okay
    let d = Dict(d0()..., "versions" => 0)
        e = @test_throws JuliaHub.JuliaHubError JuliaHub.Dataset(d)
        @test startswith(
            e.value.msg, "Invalid JSON returned by the server: `versions` of type `Int64`"
        )
    end
end

@testset "JuliaHub.dataset(s)" begin
    empty!(MOCK_JULIAHUB_STATE)
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

            @test length(ds.versions) == 2
            @test ds.versions[1] isa JuliaHub.DatasetVersion
            @test ds.versions[1].id == 1
            @test ds.versions[1].size == 57
            @test ds.versions[2].id == 2
            @test ds.versions[2].size == 331

            # Test that .versions repr()-s to a valid array
            # and DatasetVersion reprs to a valid JuliaHub.dataset().versions[...]
            # call.
            let versions = eval(Meta.parse(string(ds.versions)))
                @test versions isa Vector{JuliaHub.DatasetVersion}
                @test length(versions) == 2
                @test versions == ds.versions
            end
            let expr = Meta.parse(string(ds.versions[1]))
                @test expr == :((JuliaHub.dataset(("username", "example-dataset"))).versions[1])
                version = eval(expr)
                @test version == ds.versions[1]
            end

            ds_updated = JuliaHub.dataset("example-dataset")
            @test ds_updated isa JuliaHub.Dataset
            @test ds_updated.name == ds.name
            @test ds_updated.owner == ds.owner
            @test ds_updated.dtype == ds.dtype
            @test ds_updated.description == ds.description

            @testset "propertynames()" begin
                expected = filter(
                    s -> !startswith(string(s), "_"),
                    fieldnames(JuliaHub.Dataset),
                )
                @test Set(propertynames(ds)) == Set(expected)
            end
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

            @test length(ds.versions) == 1
            @test ds.versions[1] isa JuliaHub.DatasetVersion
            @test ds.versions[1].id == 1
            @test ds.versions[1].size == 57
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

        # Test zero-version datasets
        MOCK_JULIAHUB_STATE[:dataset_version_sizes] = []
        let ds = JuliaHub.dataset("example-dataset")
            @test ds isa JuliaHub.Dataset
            @test ds.name == "example-dataset"
            @test ds.owner == "username"
            @test ds.dtype == "Blob"
            @test ds.description == "An example dataset"
            @test isempty(ds.versions)
        end

        MOCK_JULIAHUB_STATE[:datasets_erroneous] = ["bad-user/erroneous_dataset"]
        err_ds_warn = (
            :warn,
            "The JuliaHub GET /datasets response contains erroneous datasets. Omitting 1 entries.",
        )
        let datasets = @test_nowarn JuliaHub.datasets()
            @test length(datasets) == 2
        end
        let datasets = @test_logs err_ds_warn JuliaHub.datasets(; shared=true)
            @test length(datasets) == 3
        end
        let ds = @test_logs err_ds_warn JuliaHub.dataset("example-dataset")
            @test ds isa JuliaHub.Dataset
        end
        let ds = @test_logs err_ds_warn JuliaHub.dataset("example-dataset")
            @test ds isa JuliaHub.Dataset
            @test ds.owner == "username"
            @test ds.name == "example-dataset"
        end
        @test_logs err_ds_warn begin
            @test_throws JuliaHub.InvalidRequestError JuliaHub.dataset("erroneous_dataset")
        end
    end
end

@testset "JuliaHub.download_dataset" begin
    empty!(MOCK_JULIAHUB_STATE)
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
                    "local"; replace=true,
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
        # Dataset versions
        #! format: off
        @test JuliaHub.download_dataset("example-dataset", "local"; version=1) == joinpath(pwd(), "local")
        @test JuliaHub.download_dataset("example-dataset", "local"; version=2) == joinpath(pwd(), "local")
        @test JuliaHub.download_dataset(("anotheruser", "publicdataset"), "local"; version=1) == joinpath(pwd(), "local")
        @test_throws JuliaHub.InvalidRequestError JuliaHub.download_dataset("example-dataset", "local"; version=0)
        @test_throws JuliaHub.InvalidRequestError JuliaHub.download_dataset("example-dataset", "local"; version=3)
        @test_throws JuliaHub.InvalidRequestError JuliaHub.download_dataset(("anotheruser", "publicdataset"), "local"; version=2)
        MOCK_JULIAHUB_STATE[:dataset_version_sizes] = []
        @test_throws JuliaHub.InvalidRequestError JuliaHub.download_dataset("example-dataset", "local")
        #! format: on
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
        # Different options for `license` keyword
        @test JuliaHub.update_dataset("example-dataset"; license="MIT") isa JuliaHub.Dataset
        @test JuliaHub.update_dataset("example-dataset"; license=(:spdx, "MIT")) isa
            JuliaHub.Dataset
        @test JuliaHub.update_dataset("example-dataset"; license=(:fulltext, "...")) isa
            JuliaHub.Dataset
        # This should log a deprecation warning
        @test @test_logs (
            :warn,
            "Passing license=(:text, ...) is deprecated, use license=(:fulltext, ...) instead.",
        ) JuliaHub.update_dataset(
            "example-dataset"; license=(:text, "...")
        ) isa JuliaHub.Dataset
        @test_throws TypeError JuliaHub.update_dataset("example-dataset"; license=1234)
        @test_throws ArgumentError JuliaHub.update_dataset("example-dataset"; license=(:foo, ""))
        @test_throws TypeError JuliaHub.update_dataset(
            "example-dataset"; license=(:fulltext, 1234)
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

        # Different options for `license` keyword
        @test JuliaHub.upload_dataset(
            "example-dataset-license", @__FILE__; create=true, license="MIT"
        ) isa JuliaHub.Dataset
        @test JuliaHub.upload_dataset(
            "example-dataset-license", @__FILE__; replace=true, license=(:spdx, "MIT")
        ) isa JuliaHub.Dataset
        @test JuliaHub.upload_dataset(
            "example-dataset-license", @__FILE__; replace=true, license=(:fulltext, "...")
        ) isa JuliaHub.Dataset
        # This should log a deprecation warning
        @test @test_logs (
            :warn,
            "Passing license=(:text, ...) is deprecated, use license=(:fulltext, ...) instead.",
        ) JuliaHub.upload_dataset(
            "example-dataset-license", @__FILE__; replace=true, license=(:text, "...")
        ) isa JuliaHub.Dataset
        @test_throws TypeError JuliaHub.upload_dataset(
            "example-dataset-license", @__FILE__; replace=true, license=1234
        )
        @test_throws ArgumentError JuliaHub.upload_dataset(
            "example-dataset-license", @__FILE__; replace=true, license=(:foo, "")
        )
        @test_throws TypeError JuliaHub.upload_dataset(
            "example-dataset-license", @__FILE__; replace=true, license=(:fulltext, 1234)
        )

        # Make sure we throw a JuliaHubError when we encounter an internal backend error
        # that gets reported over a 200.
        @test JuliaHub.upload_dataset("example-dataset-200-error-1", @__FILE__) isa JuliaHub.Dataset
        MOCK_JULIAHUB_STATE[:internal_error_200] = true
        @test_throws JuliaHub.JuliaHubError JuliaHub.upload_dataset("example-dataset-200-error", @__FILE__)
        MOCK_JULIAHUB_STATE[:internal_error_200] = false
    end
    empty!(MOCK_JULIAHUB_STATE)
end
