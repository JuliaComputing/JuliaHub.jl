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

        MOCK_JULIAHUB_STATE[:internal_error_200] = true
        @test_throws JuliaHub.JuliaHubError JuliaHub.upload_project_dataset(
            dataset_noproject, @__FILE__
        )
        MOCK_JULIAHUB_STATE[:internal_error_200] = false
    end
end

# We'll restore the default (non-project) global auth
JuliaHub.__AUTH__[] = DEFAULT_GLOBAL_MOCK_AUTH

@testset "JuliaHub.project_deployment_specs()" begin
    empty!(MOCK_JULIAHUB_STATE)
    Mocking.apply(mocking_patch) do
        @testset "auth" begin
            JuliaHub.__AUTH__[] = project_auth_0
            @test_throws JuliaHub.ProjectNotSetError JuliaHub.project_deployment_specs()
            @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub.project_deployment_specs(;
                auth=project_auth_1
            )
            @test_throws ArgumentError JuliaHub.project_deployment_specs(
                "not-a-uuid"; auth=project_auth_2
            )
        end

        @testset "listing" begin
            JuliaHub.__AUTH__[] = project_auth_2
            specs = JuliaHub.project_deployment_specs()
            @test specs isa Vector{JuliaHub.ProjectDeploymentSpec}
            @test length(specs) == 2
            @test specs[1].id == 33
            @test specs[1].name == "Default"
            @test specs[1].project_id == project_auth_2.project_id
            @test specs[1].machine_type == "m64"
            @test specs[1].port == 8080
            @test specs[1].authentication == "me"
            @test specs[1].sysimage_build === false
            @test specs[1].default === false
            @test specs[2].id == 96
            @test specs[2].name == "Large"
            @test specs[2].description == ""
            @test specs[2].default === true
            @test specs[2].sysimage_build === true
            @test specs[2]._json["dnsPrefix"] == "myapp"
            # show methods
            @test sprint(show, specs[1]) == "JuliaHub.ProjectDeploymentSpec(33, \"Default\")"
            s = sprint(show, MIME"text/plain"(), specs[2])
            @test occursin("Large (id: 96) [default]", s)
            @test occursin("port: 9999", s)
            @test !occursin("description", s)
            s = sprint(show, MIME"text/plain"(), specs[1])
            @test occursin("description: Migrated", s)
            @test !occursin("[default]", s)

            # Explicit project references
            other_uuid = UUIDs.UUID("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
            specs = JuliaHub.project_deployment_specs(other_uuid)
            @test all(s -> s.project_id == other_uuid, specs)
            specs = JuliaHub.project_deployment_specs(string(other_uuid); auth=project_auth_2)
            @test all(s -> s.project_id == other_uuid, specs)
        end

        @testset "errors" begin
            JuliaHub.__AUTH__[] = project_auth_2
            MOCK_JULIAHUB_STATE[:project_deployment_specs_status] = 404
            @test_throws JuliaHub.InvalidRequestError JuliaHub.project_deployment_specs()
            MOCK_JULIAHUB_STATE[:project_deployment_specs_status] = 400
            e = try
                JuliaHub.project_deployment_specs()
            catch e
                e
            end
            @test e isa JuliaHub.InvalidRequestError
            @test occursin("only available for deployable projects", e.msg)
            MOCK_JULIAHUB_STATE[:project_deployment_specs_status] = 500
            @test_throws JuliaHub.JuliaHubError JuliaHub.project_deployment_specs()
            MOCK_JULIAHUB_STATE[:project_deployment_specs_status] = 403
            @test_throws JuliaHub.PermissionError JuliaHub.project_deployment_specs()
            delete!(MOCK_JULIAHUB_STATE, :project_deployment_specs_status)
            # Invalid JSON in the listing
            MOCK_JULIAHUB_STATE[:project_deployment_specs] = [Dict("name" => "no-spec-id")]
            @test_throws JuliaHub.JuliaHubError JuliaHub.project_deployment_specs()
            delete!(MOCK_JULIAHUB_STATE, :project_deployment_specs)
        end
    end
end

@testset "JuliaHub.deploy_project()" begin
    empty!(MOCK_JULIAHUB_STATE)
    Mocking.apply(mocking_patch) do
        @testset "auth" begin
            JuliaHub.__AUTH__[] = project_auth_0
            @test_throws JuliaHub.ProjectNotSetError JuliaHub.deploy_project()
            @test_throws JuliaHub.InvalidJuliaHubVersion JuliaHub.deploy_project(;
                auth=project_auth_1
            )
        end

        JuliaHub.__AUTH__[] = project_auth_2
        project_uuid = string(project_auth_2.project_id)

        @testset "default spec" begin
            job = JuliaHub.deploy_project()
            @test job isa JuliaHub.Job
            @test job.id == "jr-xf4tslavut"
            @test MOCK_JULIAHUB_STATE[:project_deployment_submitted] ==
                (; project_uuid, spec_id=96)
        end

        @testset "spec by id / name / object" begin
            job = JuliaHub.deploy_project(; spec=33)
            @test job.id == "jr-xf4tslavut"
            @test MOCK_JULIAHUB_STATE[:project_deployment_submitted].spec_id == 33

            job = JuliaHub.deploy_project(; spec="Default")
            @test MOCK_JULIAHUB_STATE[:project_deployment_submitted].spec_id == 33
            job = JuliaHub.deploy_project(; spec="Large")
            @test MOCK_JULIAHUB_STATE[:project_deployment_submitted].spec_id == 96

            specs = JuliaHub.project_deployment_specs()
            job = JuliaHub.deploy_project(; spec=specs[1])
            @test MOCK_JULIAHUB_STATE[:project_deployment_submitted].spec_id == 33
            # Explicit project reference, matching the spec object
            job = JuliaHub.deploy_project(project_auth_2.project_id; spec=specs[2])
            @test MOCK_JULIAHUB_STATE[:project_deployment_submitted] ==
                (; project_uuid, spec_id=96)

            # Spec object from a different project
            other_uuid = UUIDs.UUID("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
            @test_throws ArgumentError JuliaHub.deploy_project(other_uuid; spec=specs[1])
            # Invalid spec IDs
            @test_throws ArgumentError JuliaHub.deploy_project(; spec=0)
            @test_throws ArgumentError JuliaHub.deploy_project(; spec=-1)
            # Non-existent spec name / id
            e = try
                JuliaHub.deploy_project(; spec="Nonexistent")
            catch e
                e
            end
            @test e isa JuliaHub.InvalidRequestError
            @test occursin("'Default', 'Large'", e.msg)
            @test_throws JuliaHub.InvalidRequestError JuliaHub.deploy_project(; spec=12345)
        end

        @testset "no default spec" begin
            specs = mock_project_deployment_specs(project_uuid)
            # Two specs, neither default -> error
            MOCK_JULIAHUB_STATE[:project_deployment_specs] = map(specs) do spec
                merge(spec, Dict("default" => false))
            end
            e = try
                JuliaHub.deploy_project()
            catch e
                e
            end
            @test e isa JuliaHub.InvalidRequestError
            @test occursin("no default deployment specification", e.msg)
            # Explicitly picking one still works
            JuliaHub.deploy_project(; spec="Large")
            @test MOCK_JULIAHUB_STATE[:project_deployment_submitted].spec_id == 96
            # Exactly one (non-default) spec -> gets picked
            MOCK_JULIAHUB_STATE[:project_deployment_specs] = [
                merge(specs[1], Dict("default" => false))
            ]
            JuliaHub.deploy_project()
            @test MOCK_JULIAHUB_STATE[:project_deployment_submitted].spec_id == 33
            # No specs at all
            MOCK_JULIAHUB_STATE[:project_deployment_specs] = []
            e = try
                JuliaHub.deploy_project()
            catch e
                e
            end
            @test e isa JuliaHub.InvalidRequestError
            @test occursin("does not have any deployment specifications", e.msg)
            delete!(MOCK_JULIAHUB_STATE, :project_deployment_specs)
        end

        @testset "job not (yet) visible" begin
            # The submit endpoint returns a job name that the job endpoint does not know about
            MOCK_JULIAHUB_STATE[:project_deployment_jobname] = "jr-doesnotexist"
            JuliaHub._DEPLOY_PROJECT_JOB_TIMEOUT[] = 0.5
            try
                e = try
                    JuliaHub.deploy_project()
                catch e
                    e
                end
                @test e isa JuliaHub.JuliaHubError
                @test occursin("jr-doesnotexist", e.msg)
            finally
                JuliaHub._DEPLOY_PROJECT_JOB_TIMEOUT[] = 300.0
                delete!(MOCK_JULIAHUB_STATE, :project_deployment_jobname)
            end
            # But polling picks up the job if it appears in time
            MOCK_JULIAHUB_STATE[:project_deployment_jobname] = "jr-eezd3arpcj"
            job = JuliaHub.deploy_project()
            @test job.id == "jr-eezd3arpcj"
            delete!(MOCK_JULIAHUB_STATE, :project_deployment_jobname)
        end

        @testset "errors" begin
            MOCK_JULIAHUB_STATE[:project_deployment_specs_status] = 404
            @test_throws JuliaHub.InvalidRequestError JuliaHub.deploy_project()
            # Passing the spec ID does not require listing, so the submit status matters
            MOCK_JULIAHUB_STATE[:project_deployment_submit_status] = 404
            @test_throws JuliaHub.InvalidRequestError JuliaHub.deploy_project(; spec=96)
            MOCK_JULIAHUB_STATE[:project_deployment_submit_status] = 400
            e = try
                JuliaHub.deploy_project(; spec=96)
            catch e
                e
            end
            @test e isa JuliaHub.InvalidRequestError
            @test occursin("has no password set", e.msg)
            MOCK_JULIAHUB_STATE[:project_deployment_submit_status] = 500
            @test_throws JuliaHub.JuliaHubError JuliaHub.deploy_project(; spec=96)
            MOCK_JULIAHUB_STATE[:project_deployment_submit_status] = 403
            @test_throws JuliaHub.PermissionError JuliaHub.deploy_project(; spec=96)
            empty!(MOCK_JULIAHUB_STATE)
        end
    end
end
