# We'll construct 3 Authentication objects that we can use
# later in the tests.
empty!(MOCK_JULIAHUB_STATE)
project_auth_0 = DEFAULT_GLOBAL_MOCK_AUTH
project_auth_1 = mockauth(
    URIs.URI("https://juliahub.example.org"); api_version=v"0.0.1",
    project_id=UUIDs.UUID("00000000-0000-0000-0000-000000000001"),
)
project_auth_2 = mockauth(
    URIs.URI("https://juliahub.example.org"); api_version=v"0.2.0",
    project_id=UUIDs.UUID("00000000-0000-0000-0000-000000000002"),
)
@testset "project_auth_*" begin
    let auth = project_auth_0
        @test auth.project_id === nothing
        @test auth._api_version === v"0.0.0-legacy"
        @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub._assert_projects_enabled(auth)
    end
    let auth = project_auth_1
        @test auth.project_id === UUIDs.UUID("00000000-0000-0000-0000-000000000001")
        @test auth._api_version === v"0.0.1"
        @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub._assert_projects_enabled(auth)
    end
    let auth = project_auth_2
        @test auth.project_id === UUIDs.UUID("00000000-0000-0000-0000-000000000002")
        @test auth._api_version === v"0.2.0"
        @test JuliaHub._assert_projects_enabled(auth) === nothing
    end
end

@testset "_project_uuid()" begin
    ref_uuid = UUIDs.UUID("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    @testset "project_auth_0" begin
        @test_throws JuliaHub.ProjectNotSetError JuliaHub._project_uuid(project_auth_0, nothing)
        @test_throws ArgumentError JuliaHub._project_uuid(project_auth_0, "1234")
        JuliaHub._project_uuid(project_auth_0, string(ref_uuid)) === ref_uuid
        JuliaHub._project_uuid(project_auth_0, ref_uuid) === ref_uuid
    end
    @testset "project_auth_1" begin
        @test JuliaHub._project_uuid(project_auth_1, nothing) === project_auth_1.project_id
        @test_throws ArgumentError JuliaHub._project_uuid(project_auth_1, "1234")
        JuliaHub._project_uuid(project_auth_1, string(ref_uuid)) === ref_uuid
        JuliaHub._project_uuid(project_auth_1, ref_uuid) === ref_uuid
    end
end

# We'll use the project_datasets() function to test the auth fallback and
# auth handling.
@testset "JuliaHub.project_datasets()" begin
    empty!(MOCK_JULIAHUB_STATE)
    Mocking.apply(mocking_patch) do
        @testset "auth" begin
            JuliaHub.__AUTH__[] = project_auth_0
            @test_throws JuliaHub.ProjectNotSetError JuliaHub.project_datasets()
            @test_throws JuliaHub.ProjectNotSetError JuliaHub.project_datasets(;
                auth=project_auth_0
            )
            @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub.project_datasets(;
                auth=project_auth_1
            )
            @test JuliaHub.project_datasets(; auth=project_auth_2) isa Vector{JuliaHub.Dataset}

            JuliaHub.__AUTH__[] = project_auth_1
            @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub.project_datasets()
            @test_throws JuliaHub.ProjectNotSetError JuliaHub.project_datasets(;
                auth=project_auth_0
            )
            @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub.project_datasets(;
                auth=project_auth_1
            )
            @test JuliaHub.project_datasets(; auth=project_auth_2) isa Vector{JuliaHub.Dataset}

            JuliaHub.__AUTH__[] = project_auth_2
            @test JuliaHub.project_datasets() isa Vector{JuliaHub.Dataset}
            @test_throws JuliaHub.ProjectNotSetError JuliaHub.project_datasets(;
                auth=project_auth_0
            )
            @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub.project_datasets(;
                auth=project_auth_1
            )
            @test JuliaHub.project_datasets(; auth=project_auth_2) isa Vector{JuliaHub.Dataset}
        end

        @testset "default project" begin
            datasets = JuliaHub.project_datasets()
            @test length(datasets) === 3
            @testset "dataset: $(dataset.name)" for dataset in datasets
                @test dataset isa JuliaHub.Dataset
                @test dataset.project isa JuliaHub.DatasetProjectLink
                @test dataset.project.uuid === project_auth_2.project_id
                @test dataset.project.is_writable === false
            end
        end

        # These tests that we send project_auth_1.project_id to the backend
        @testset "explicit project" begin
            datasets = JuliaHub.project_datasets(
                project_auth_1.project_id;
                auth=project_auth_2,
            )
            @test length(datasets) === 3
            @testset "dataset: $(dataset.name)" for dataset in datasets
                @test dataset isa JuliaHub.Dataset
                @test dataset.project isa JuliaHub.DatasetProjectLink
                @test dataset.project.uuid === project_auth_1.project_id
                @test dataset.project.is_writable === false
            end

            # Automatic parsing of string project_ids
            datasets = JuliaHub.project_datasets(
                string(project_auth_1.project_id);
                auth=project_auth_2,
            )
            @test length(datasets) === 3
            @testset "dataset: $(dataset.name)" for dataset in datasets
                @test dataset isa JuliaHub.Dataset
                @test dataset.project isa JuliaHub.DatasetProjectLink
                @test dataset.project.uuid === project_auth_1.project_id
                @test dataset.project.is_writable === false
            end

            @test_throws ArgumentError datasets = JuliaHub.project_datasets("foo")
        end

        # show() methods on Dataset objects that print as project_dataset()-s
        JuliaHub.__AUTH__[] = project_auth_2
        @testset "show methods" begin
            datasets = JuliaHub.project_datasets(project_auth_1.project_id)
            @test length(datasets) === 3
            let ex = Meta.parse(string(datasets[1]))
                @test ex.head == :call
                @test ex.args[1] == :(JuliaHub.project_dataset)

                ds = eval(ex)
                @test ds isa JuliaHub.Dataset
                @test ds == datasets[1]
                @test ds != datasets[2]
            end
            let datasets_eval = eval(Meta.parse(string(datasets)))
                @test datasets_eval isa Vector{JuliaHub.Dataset}
                @test length(datasets_eval) == length(datasets)
                @test datasets_eval == datasets
            end
        end
    end
end

@testset "JuliaHub.project_dataset()" begin
    empty!(MOCK_JULIAHUB_STATE)
    Mocking.apply(mocking_patch) do
        @testset "auth" begin
            JuliaHub.__AUTH__[] = project_auth_0
            @test_throws JuliaHub.ProjectNotSetError JuliaHub.project_dataset("example-dataset")
            @test_throws JuliaHub.ProjectNotSetError JuliaHub.project_dataset("example-dataset";
                auth=project_auth_0,
            )
            @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub.project_dataset("example-dataset";
                auth=project_auth_1,
            )
            @test JuliaHub.project_dataset("example-dataset"; auth=project_auth_2) isa
                JuliaHub.Dataset

            JuliaHub.__AUTH__[] = project_auth_1
            @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub.project_dataset("example-dataset")
            @test_throws JuliaHub.ProjectNotSetError JuliaHub.project_dataset("example-dataset";
                auth=project_auth_0,
            )
            @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub.project_dataset("example-dataset";
                auth=project_auth_1,
            )
            @test JuliaHub.project_dataset("example-dataset"; auth=project_auth_2) isa
                JuliaHub.Dataset

            JuliaHub.__AUTH__[] = project_auth_2
            @test JuliaHub.project_dataset("example-dataset") isa JuliaHub.Dataset
            @test_throws JuliaHub.ProjectNotSetError JuliaHub.project_dataset("example-dataset";
                auth=project_auth_0,
            )
            @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub.project_dataset("example-dataset";
                auth=project_auth_1,
            )
            @test JuliaHub.project_dataset("example-dataset"; auth=project_auth_2) isa
                JuliaHub.Dataset
        end

        @testset "datasets" begin
            let dataset = JuliaHub.project_dataset("example-dataset")
                @test dataset.name == "example-dataset"
                @test dataset.owner == "username"
                @test dataset.dtype == "Blob"
                @test dataset.description == "An example dataset"

                @test dataset.project isa JuliaHub.DatasetProjectLink
                @test dataset.project.uuid === project_auth_2.project_id
                @test dataset.project.is_writable === false
            end

            let dataset = JuliaHub.project_dataset(("anotheruser", "publicdataset"))
                @test dataset.name == "publicdataset"
                @test dataset.owner == "anotheruser"
                @test dataset.dtype == "Blob"
                @test dataset.description == "An example dataset"

                @test dataset.project isa JuliaHub.DatasetProjectLink
                @test dataset.project.uuid === project_auth_2.project_id
                @test dataset.project.is_writable === false
            end

            dataset_noproject = JuliaHub.dataset("example-dataset")
            @test dataset_noproject.project === nothing
            let dataset = JuliaHub.project_dataset(dataset_noproject)
                @test dataset.name == "example-dataset"
                @test dataset.owner == "username"
                @test dataset.dtype == "Blob"
                @test dataset.description == "An example dataset"

                @test dataset.project isa JuliaHub.DatasetProjectLink
                @test dataset.project.uuid === project_auth_2.project_id
                @test dataset.project.is_writable === false
            end

            @test_throws JuliaHub.InvalidRequestError JuliaHub.project_dataset("no-such-dataset")
        end
    end
end

@testset "JuliaHub.upload_project_dataset()" begin
    Mocking.apply(mocking_patch) do
        @test JuliaHub.upload_project_dataset("example-dataset", @__FILE__) isa JuliaHub.Dataset
        @test JuliaHub.upload_project_dataset(("anotheruser", "publicdataset"), @__FILE__) isa
            JuliaHub.Dataset
        @test_throws JuliaHub.InvalidRequestError JuliaHub.upload_project_dataset(
            ("non-existent-user", "example-dataset"), @__FILE__
        ) isa JuliaHub.Dataset
        @test_throws JuliaHub.InvalidRequestError JuliaHub.upload_project_dataset(
            "no-such-dataset", @__FILE__
        )
        dataset_noproject = JuliaHub.dataset("example-dataset")
        @test dataset_noproject.project === nothing
        dataset = JuliaHub.upload_project_dataset(dataset_noproject, @__FILE__)
        @test dataset isa JuliaHub.Dataset
        @test dataset.project isa JuliaHub.DatasetProjectLink
        @test dataset.project.uuid === project_auth_2.project_id
        @test dataset.project.is_writable === false
        @test JuliaHub.upload_project_dataset(dataset_noproject, @__FILE__) isa JuliaHub.Dataset
    end
end

# We'll restore the default (non-project) global auth
JuliaHub.__AUTH__[] = DEFAULT_GLOBAL_MOCK_AUTH
