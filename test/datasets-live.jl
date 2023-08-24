import HTTP, JSON, JuliaHub
function _get_user_groups_rest(auth::JuliaHub.Authentication)
    r = HTTP.get(
        JuliaHub._url(auth, "user", "groups"),
        JuliaHub._authheaders(auth),
    )
    r.status == 200 && return JSON.parse(String(r.body))
    JuliaHub._throw_invalidresponse(r)
end
function _get_user_groups_gql(auth::JuliaHub.Authentication)
    userinfo_gql = read(joinpath(@__DIR__, "userInfo.gql"), String)
    r = JuliaHub._gql_request(auth, userinfo_gql)
    r.status == 200 || error("Invalid response from GQL ($(r.status))\n$(r.body)")
    user = only(r.json["data"]["users"])
    [g["group"]["name"] for g in user["groups"]]
end
function _get_user_groups(auth::JuliaHub.Authentication)
    rest_exception = try
        _get_user_groups_rest(auth)
    catch e
        @debug "Failed to fetch user groups via REST API" exception = (e, catch_backtrace())
        e, catch_backtrace()
    end
    try
        _get_user_groups_gql(auth)
    catch e
        @error "Unable to determine valid user groups"
        @error "> REST API failure" exception = rest_exception
        @error "> GQL query failure" exception = (e, catch_backtrace())
        return String[]
    end
end


TESTDATA = joinpath(@__DIR__, "testdata")
PREFIX = "JuliaHubTest_$(TESTID)"
@info "Uploading test data with prefix: $PREFIX"
blobname, treename = "$(PREFIX)_Blob", "$(PREFIX)_Tree"
weirdnames = string.("$(PREFIX)_", ["foo/bar/baz", "Δεδομένα", "Δε-δο-μέ/να"])
deletename = "$(PREFIX)_Blob"

existing_datasets = JuliaHub.datasets(; auth)
@test existing_datasets isa Array

let username = "nonexistentpseudouser", testdata = joinpath(TESTDATA, "hi.txt")
    @test_throws JuliaHub.PermissionError JuliaHub.delete_dataset((username, "dataset"))
    @test_throws JuliaHub.PermissionError JuliaHub.upload_dataset(
        (username, "dataset"), testdata; description="..."
    )
    @test_throws JuliaHub.PermissionError JuliaHub.upload_dataset(
        (username, "dataset"), testdata; create=false, update=true
    )
    @test_throws JuliaHub.PermissionError JuliaHub.update_dataset(
        (username, "dataset"); description="..."
    )
end

try
    @test JuliaHub.datasets(; shared=true) isa Array
    @test JuliaHub.datasets(; auth) isa Array
    @test JuliaHub.datasets(auth.username) isa Array
    @test isempty(JuliaHub.datasets("nonexistentpseudouser"))

    # The datasets generated by these tests should all have a unique prefix
    @test isempty(list_datasets_prefix(PREFIX))

    JuliaHub.upload_dataset(
        blobname, joinpath(TESTDATA, "hi.txt");
        description="some blob", tags=["x", "y", "z"],
        auth
    )
    datasets = list_datasets_prefix(PREFIX; auth)
    @test length(datasets) == 1
    blob_dataset = only(filter(d -> d.name == blobname, datasets))
    @test blob_dataset.description == "some blob"
    @test blob_dataset.tags == ["x", "y", "z"]
    @test blob_dataset.size == 11
    @test blob_dataset.dtype == "Blob"

    JuliaHub.upload_dataset(
        (auth.username, blobname), joinpath(TESTDATA, "hi.txt"); create=false, update=true
    )
    datasets, _ = JuliaHub._get_datasets(; auth)
    blob_dataset_json = only(filter(d -> d["name"] == blobname, datasets))
    @test length(blob_dataset_json["versions"]) == 2

    JuliaHub.upload_dataset(
        (auth.username, treename), TESTDATA;
        description="some tree", tags=["a", "b", "c"]
    )
    datasets = list_datasets_prefix(PREFIX; auth)
    tree_dataset = only(filter(d -> d.name == treename, datasets))
    @test length(datasets) == 2
    @test tree_dataset.description == "some tree"
    @test tree_dataset.tags == ["a", "b", "c"]
    @test tree_dataset.size == 11 + 256
    @test tree_dataset.dtype == "BlobTree"

    JuliaHub.upload_dataset(treename, TESTDATA; auth, create=false, update=true)
    datasets, _ = JuliaHub._get_datasets(; auth)
    tree_dataset_json = only(filter(d -> d["name"] == treename, datasets))
    @test length(tree_dataset_json["versions"]) == 2

    @test_throws JuliaHub.InvalidRequestError JuliaHub.dataset(
        ("nonexistentpseudouser", blobname); auth
    )
    @test_throws JuliaHub.InvalidRequestError JuliaHub.dataset(("nonexistentpseudouser", blobname))

    # Accessing datasets
    let dataset = JuliaHub.dataset(blobname; auth)
        @test dataset.name == blobname
        @test dataset.dtype == "Blob"
        mktempdir() do path
            data_path = joinpath(path, "data")
            JuliaHub.download_dataset(dataset, data_path; auth)
            @test isfile(data_path)
            @test read(data_path) == read(joinpath(TESTDATA, "hi.txt"))
            # Check the replace option, false by default
            @test_throws ArgumentError JuliaHub.download_dataset(dataset, data_path; auth)
            @test_logs (:warn,) JuliaHub.download_dataset(dataset, data_path; replace=true, auth)
            @test_logs min_level = Logging.Warn JuliaHub.download_dataset(
                dataset, data_path; replace=true, quiet=true, auth
            )
            @test read(data_path) == read(joinpath(TESTDATA, "hi.txt"))
            let data_directory_path = joinpath(path, "data-directory")
                mkpath(data_directory_path)
                @assert isdir(data_directory_path)
                @test_throws ArgumentError JuliaHub.download_dataset(
                    dataset, data_directory_path; auth
                )
                @test isdir(data_directory_path)
                @test_logs (:warn,) JuliaHub.download_dataset(
                    dataset, data_directory_path; replace=true, auth
                )
                @test isfile(data_directory_path)
                @test read(data_directory_path) == read(joinpath(TESTDATA, "hi.txt"))
            end
        end
        mktempdir() do path
            data_path = joinpath(path, "data")
            JuliaHub.download_dataset(dataset.name, data_path; auth)
            @test isfile(data_path)
            @test read(data_path) == read(joinpath(TESTDATA, "hi.txt"))
        end
    end
    let dataset = JuliaHub.dataset((auth.username, treename); auth)
        @test dataset.name == treename
        @test dataset.dtype == "BlobTree"
        mktempdir() do path
            data_path = joinpath(path, "data")
            JuliaHub.download_dataset(dataset, data_path; auth)
            @test isdir(data_path)
            @test Pkg.GitTools.tree_hash(data_path) == Pkg.GitTools.tree_hash(TESTDATA)
        end
        mktempdir() do path
            data_path = joinpath(path, "data")
            JuliaHub.download_dataset(dataset.name, data_path; auth)
            @test isdir(data_path)
            @test Pkg.GitTools.tree_hash(data_path) == Pkg.GitTools.tree_hash(TESTDATA)
        end
    end

    # Upload datasets with weird names
    for datasetname in weirdnames
        JuliaHub.upload_dataset(datasetname, joinpath(TESTDATA, "hi.txt"); auth)
        JuliaHub.upload_dataset(
            datasetname, joinpath(TESTDATA, "hi.txt"); auth, create=false, update=true
        )
        dataset = JuliaHub.dataset(datasetname; auth)
        @test dataset.name == datasetname
        @test dataset.dtype == "Blob"
        @test length(dataset.versions) == 2
    end

    # Updating metadata
    dataset = JuliaHub.dataset(blobname; auth)
    @test dataset.description == "some blob"
    @test dataset.tags == ["x", "y", "z"]
    @test dataset._json["groups"] == []
    @test dataset._json["visibility"] == "private"
    @test dataset._json["license"] == Dict{String, Any}(
        "name" => "Other",
        "spdx_id" => "NOASSERTION",
        "text" => "All rights reserved",
        "url" => nothing,
    )
    # No-op
    JuliaHub.update_dataset(dataset.name; auth)
    dataset = JuliaHub.dataset(blobname; auth)
    @test dataset.description == "some blob"
    @test dataset.tags == ["x", "y", "z"]
    @test dataset._json["groups"] == []
    @test dataset._json["visibility"] == "private"
    @test dataset._json["license"] == Dict{String, Any}(
        "name" => "Other",
        "spdx_id" => "NOASSERTION",
        "text" => "All rights reserved",
        "url" => nothing,
    )
    # Single item update
    JuliaHub.update_dataset(
        (auth.username, dataset.name); auth, description="new description"
    )
    dataset = JuliaHub.dataset(blobname; auth)
    @test dataset.description == "new description"
    @test dataset.tags == ["x", "y", "z"]
    @test dataset._json["groups"] == []
    @test dataset._json["visibility"] == "private"
    @test dataset._json["license"] == Dict{String, Any}(
        "name" => "Other",
        "spdx_id" => "NOASSERTION",
        "text" => "All rights reserved",
        "url" => nothing,
    )
    # Multi-item update
    new_groups = string.(JuliaHub._get_user_groups(auth))
    JuliaHub.update_dataset(
        dataset.name; auth, groups=new_groups, tags=["foo", "bar"], visibility="public"
    )
    dataset = JuliaHub.dataset(blobname; auth)
    @test dataset.description == "new description"
    @test dataset.tags == ["foo", "bar"]
    @test Set(dataset._json["groups"]) == Set(new_groups)
    @test dataset._json["visibility"] == "public"
    @test dataset._json["license"] == Dict{String, Any}(
        "name" => "Other",
        "spdx_id" => "NOASSERTION",
        "text" => "All rights reserved",
        "url" => nothing,
    )
    # License updates
    JuliaHub.update_dataset(dataset.name; auth, license="MIT")
    dataset = JuliaHub.dataset(blobname; auth)
    @test dataset._json["license"] == Dict{String, Any}(
        "name" => "MIT License",
        "spdx_id" => "MIT",
        "text" => nothing,
        "url" => "https://opensource.org/licenses/MIT",
    )
    JuliaHub.update_dataset(
        dataset.name; auth, license=(:text, "hello license my old friend")
    )
    dataset = JuliaHub.dataset(blobname; auth)
    @test dataset._json["license"] == Dict{String, Any}(
        "name" => "Other",
        "spdx_id" => "NOASSERTION",
        "text" => "hello license my old friend",
        "url" => nothing,
    )

    # delete_dataset tests; also test a few of the upload_dataset arg combinations
    @test JuliaHub.upload_dataset(deletename, TESTDATA; auth, create=true, replace=true) isa
        JuliaHub.Dataset
    @test JuliaHub.delete_dataset((auth.username, deletename); auth) === nothing
    @test JuliaHub.upload_dataset(deletename, TESTDATA; auth, create=true) isa JuliaHub.Dataset
    @test JuliaHub.delete_dataset(deletename; auth) === nothing
    @test JuliaHub.upload_dataset(deletename, TESTDATA; auth, create=true, update=true) isa
        JuliaHub.Dataset
    @test JuliaHub.delete_dataset(deletename) === nothing
    # deleting a non-existing errors by default
    @test_throws JuliaHub.InvalidRequestError JuliaHub.delete_dataset(deletename)
    @test JuliaHub.delete_dataset(deletename; force=true) === nothing

finally
    for dataset in (blobname, treename, deletename, weirdnames...)
        try
            @info "Deleting dataset: $dataset"
            JuliaHub.delete_dataset(dataset; auth)
        catch err
            if isa(err, JuliaHub.InvalidRequestError)
                println("$dataset not deleted: $(err)")
            else
                @warn "Failed to delete dataset '$dataset'" exception = (err, catch_backtrace())
                if err isa JuliaHub.JuliaHubError && !isnothing(err.exception)
                    @info "JuliaHubError inner exception" exception = err.exception
                end
            end
        end
    end
end
@test isempty(list_datasets_prefix(PREFIX; auth))
