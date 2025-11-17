function _api_add_project(auth, name)
    body = Dict(
        "name" => name,
        "product_id" => 1,
        "is_simple_mode" => false,
        "instance_default_role" => "No Access",
    )
    r = JuliaHub._restcall(
        auth,
        :POST,
        ("api", "v1", "projects", "add"),
        JSON.json(body);
        headers=["Content-Type" => "application/json"],
    )
    if r.status != 200
        error("Invalid response (/add): $(r.status)\n$(r.body)")
    end
    return r.json["project_id"]
end

function _create_project(auth, name)
    project_id = _api_add_project(auth, name)
    r = JuliaHub._restcall(
        auth,
        :POST,
        ("api", "v1", "projects", "create", project_id),
        nothing;
        headers=["Content-Type" => "application/json"],
    )
    if r.status != 200
        error("Invalid response (/create): $(r.status)\n$(r.body)")
    end
    return (;
        name,
        project_id,
    )
end

function _attach_dataset(auth, project_id, dataset_id; action="attach", writable=false)
    body = [
        Dict(
            "dataset" => dataset_id,
            "action" => action,
            "writable" => writable,
        ),
    ]
    r = JuliaHub._restcall(
        auth,
        :PATCH,
        ("api", "v1", "projects", "datasets", project_id),
        JSON.json(body);
        headers=["Content-Type" => "application/json"],
    )
    if r.status != 200
        error("Invalid response (/datasets): $(r.status)\n$(r.body)")
    end
    return nothing
end

# Create the projects and datasets
@info "Test project data with prefix: $TEST_PREFIX"
@testset "create project" begin
    global project = _create_project(auth, "$(TEST_PREFIX) Datasets")
    @test isempty(JuliaHub.project_datasets(project.project_id; auth))
end

# Upload a dataset, attach that to the project, and upload a new version to it.
project_dataset_name = "$(TEST_PREFIX)_Project"
try
    @testset "upload a test dataset" begin
        global project_dataset = JuliaHub.upload_dataset(
            project_dataset_name, joinpath(TESTDATA, "hi.txt");
            description="some blob", tags=["x", "y", "z"],
            auth,
        )
        @test project_dataset.project === nothing
        @test length(project_dataset.versions) == 1
        # TODO: add this properly to DatasetVersion?
        @test !haskey(project_dataset._json["versions"][1], "project")
        @test project_dataset._json["versions"][1]["uploader"]["username"] == auth.username

        # The authentication object we use does not have a project associated with it
        @test_throws JuliaHub.ProjectNotSetError JuliaHub.upload_project_dataset(
            project_dataset, joinpath(TESTDATA, "hi.txt")
        )
        # .. so we need to pass it explicitly. However, at this point, the project
        # is not attached. So uploading a new version will fail.
        t = @test_throws JuliaHub.InvalidRequestError JuliaHub.upload_project_dataset(
            project_dataset, joinpath(TESTDATA, "hi.txt"); project=project.project_id
        )
        @test startswith(
            t.value.msg,
            "Unable to upload to dataset ($(auth.username), $(project_dataset.name))",
        )
        @test occursin(project_dataset.name, t.value.msg)
        @test occursin("code: 403", t.value.msg)
    end

    @testset "attach dataset to project (non-writable)" begin
        _attach_dataset(auth, project.project_id, string(project_dataset.uuid))

        let datasets = JuliaHub.project_datasets(project.project_id; auth)
            @test length(datasets) == 1
            @test datasets[1].name == project_dataset_name
            @test datasets[1].uuid == project_dataset.uuid
            @test datasets[1].project isa JuliaHub.DatasetProjectLink
            @test datasets[1].project.uuid === UUIDs.UUID(project.project_id)
            @test datasets[1].project.is_writable === false
            @test length(datasets[1].versions) == 1
        end

        t = @test_throws JuliaHub.InvalidRequestError JuliaHub.upload_project_dataset(
            project_dataset, joinpath(TESTDATA, "hi.txt"); project=project.project_id
        )
        @test startswith(
            t.value.msg,
            "Unable to upload to dataset ($(auth.username), $(project_dataset.name))",
        )
        @test occursin(project_dataset.name, t.value.msg)
        @test occursin("code: 403", t.value.msg)
    end

    @testset "attach dataset to project (writable)" begin
        # Mark the dataset writable
        _attach_dataset(auth, project.project_id, string(project_dataset.uuid); writable=true)

        let datasets = JuliaHub.project_datasets(project.project_id; auth)
            @test length(datasets) == 1
            @test datasets[1].name == project_dataset_name
            @test datasets[1].uuid == project_dataset.uuid
            @test datasets[1].project isa JuliaHub.DatasetProjectLink
            @test datasets[1].project.uuid === UUIDs.UUID(project.project_id)
            @test datasets[1].project.is_writable === true
            @test length(datasets[1].versions) == 1
        end

        dataset = JuliaHub.upload_project_dataset(
            project_dataset, joinpath(TESTDATA, "hi.txt"); project=project.project_id
        )
        @test dataset.name == project_dataset_name
        @test dataset.uuid == project_dataset.uuid
        @test dataset.project isa JuliaHub.DatasetProjectLink
        @test dataset.project.uuid === UUIDs.UUID(project.project_id)
        @test dataset.project.is_writable === true

        @test length(dataset.versions) == 2
        @test dataset._json["versions"][1]["project"] === nothing
        @test dataset._json["versions"][1]["uploader"]["username"] == auth.username
        @test dataset._json["versions"][2]["project"] == project.project_id
        @test dataset._json["versions"][2]["uploader"]["username"] == auth.username
    end

    @testset "project_dataset" begin
        @test_throws JuliaHub.ProjectNotSetError JuliaHub.project_dataset(project_dataset; auth)
        let dataset = JuliaHub.project_dataset(
                project_dataset; project=project.project_id, auth
            )
            @test dataset.name == project_dataset_name
            @test dataset.uuid == project_dataset.uuid
            @test dataset.project isa JuliaHub.DatasetProjectLink
            @test dataset.project.uuid === UUIDs.UUID(project.project_id)
            @test dataset.project.is_writable === true

            @test length(dataset.versions) == 2
            @test dataset._json["versions"][1]["project"] === nothing
            @test dataset._json["versions"][1]["uploader"]["username"] == auth.username
            @test dataset._json["versions"][2]["project"] == project.project_id
            @test dataset._json["versions"][2]["uploader"]["username"] == auth.username
        end
    end
finally
    _delete_test_dataset(auth, project_dataset_name)
end
