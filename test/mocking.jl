# This contains the shared mocking setup for the offline test suite, but is also
# re-used in docs/make.jl to make the doctest outputs consistent.
import Mocking, JSON, SHA, URIs, UUIDs

# Development note: you can MITM the REST calls and save the raw API responses
# with the following Mocking setup:
#=
Mocking.activate()
const RESTRESPONSES = Vector{JuliaHub._RESTResponse}()
mitmpatch = Mocking.@patch function JuliaHub._rest_request_mockable(args...; kwargs...)
    method, url, headers, payload = args
    @info "JuliaHub._rest_request($method, $url)" typeof(payload) kwargs
    r = JuliaHub._rest_request_http(args...; kwargs...)
    push!(RESTRESPONSES, r)
    return r
end

Mocking.apply(mitmpatch) do
    JuliaHub. ...
end
=#

# Set up a mock authentication so that the __auth__() fallbacks would work and use this.
const MOCK_USERNAME = "username"
mockauth(server_uri) = JuliaHub.Authentication(
    server_uri, JuliaHub._MISSING_API_VERSION, MOCK_USERNAME, JuliaHub.Secret("")
)
JuliaHub.__AUTH__[] = mockauth(URIs.URI("https://juliahub.example.org"))

# The following Mocking.jl patches _rest_request, so the the rest calls would have fixed
# reponses.
Mocking.activate()
const MOCK_JULIAHUB_STATE = Dict{Symbol, Any}()
jsonresponse(status) = d -> JuliaHub._RESTResponse(status, JSON.json(d))
mocking_patch = [
    Mocking.@patch(
        JuliaHub._rest_request_mockable(args...; kwargs...) = _restcall_mocked(args...; kwargs...)
    ),
    Mocking.@patch(
        JuliaHub._restput_mockable(args...; kwargs...) = _restput_mocked(args...; kwargs...)
    ),
    Mocking.@patch(
        JuliaHub._rclone(args...; kwargs...) = print(
            get(MOCK_JULIAHUB_STATE, :stdout_stream, stdout),
            """
            Transferred:       86.767 KiB / 86.767 KiB, 100%, 0 B/s, ETA -
            Transferred:            1 / 1, 100%
            Elapsed time:         2.1s
            """,
        )
    ),
    Mocking.@patch(
        JuliaHub._get_dataset_credentials(
            ::JuliaHub.Authentication, ::JuliaHub.Dataset
        ) = Dict(
            "vendor" => "aws",
            "credentials" => Dict(
                "access_key_id" => "",
                "secret_access_key" => "",
                "session_token" => "",
            ),
        )
    ),
    Mocking.@patch(
        JuliaHub._download_job_file(
            ::JuliaHub.Authentication, file::JuliaHub.JobFile, ::IO
        ) = nothing
    ),
    Mocking.@patch(
        function JuliaHub._authenticate(server_uri; kwargs...)
            return mockauth(server_uri)
        end
    ),
    Mocking.@patch(
        JuliaHub._get_authenticated_user_legacy_gql_request(
            ::AbstractString, ::JuliaHub.Secret
        ) = _auth_legacy_gql_mocked()
    ),
    Mocking.@patch(
        JuliaHub._get_authenticated_user_api_v1_request(::AbstractString, ::JuliaHub.Secret) =
            _auth_apiv1_mocked()
    )
]
uuidhash(s::AbstractString) = only(reinterpret(UUIDs.UUID, SHA.sha1(s)[1:16]))
function _restput_mocked(url::AbstractString, headers, input)
    return JuliaHub._RESTResponse(200, "")
end
const MOCK_JULIAHUB_DEFAULT_JOB_FILES = Any[
    Dict{String, Any}(
        "name" => "code.jl",
        "upload_timestamp" => "2023-03-15T07:56:49.953077+00:00",
        "hash" => Dict{String, Any}(
            "algorithm" => "sha2_256",
            "value" => "ab5df625bc76dbd4e163bed2dd888df828f90159bb93556525c31821b6541d46",
        ),
        "size" => 3,
        "type" => "input",
    ),
    Dict{String, Any}(
        "name" => "code.jl",
        "upload_timestamp" => "2023-03-15T07:58:48.189668+00:00",
        "hash" => Dict{String, Any}(
            "algorithm" => "sha2_256",
            "value" => "ab5df625bc76dbd4e163bed2dd888df828f90159bb93556525c31821b6541d46",
        ),
        "size" => 3,
        "type" => "source",
    ),
    Dict{String, Any}(
        "name" => "Project.toml",
        "upload_timestamp" => "2023-03-15T07:58:49.022829+00:00",
        "hash" => Dict{String, Any}(
            "algorithm" => "sha2_256",
            "value" => "c69a99cf893c7f02ea477636a8a7228e1ff47b8553111ca8415da429b5d95eab",
        ),
        "size" => 244,
        "type" => "project",
    ),
    Dict{String, Any}(
        "name" => "Manifest.toml",
        "upload_timestamp" => "2023-03-15T07:58:49.473898+00:00",
        "hash" => Dict{String, Any}(
            "algorithm" => "sha2_256",
            "value" => "288ee7fdceed4ec6cf963fb34dc169c0867621ce658f27587a204d4f8935bfd2",
        ),
        "size" => 9056,
        "type" => "project",
    ),
]
function _restcall_mocked(method, url, headers, payload; query)
    GET_JOB_REGEX = r"api/rest/jobs/([a-z0-9-]+)"
    DATASET_REGEX = r"user/datasets/([A-Za-z0-9%-]+)"
    DATASET_VERSIONS_REGEX = r"user/datasets/([A-Za-z0-9%-]+)/versions"
    # MOCK_JULIAHUB_STATE[:existing_datasets], if set, must be mutable (i.e. Vector), since
    # new dataset creation requests will push! to it.
    #
    # This state value is also used by the dataset listing, new version upload etc. requests
    # to determine whether this is an existing dataset or not.
    #
    # The name is used to determine dataset's properties:
    #
    #   - the username portion gets set as the 'owner' of the dataset
    #   - if the name contains 'blobtree', it is a BlobTree, otherwise it's Blob
    #   - if the name contains 'public', the visiblity will be 'public', otherwise 'private'
    existing_datasets = get(
        MOCK_JULIAHUB_STATE,
        :existing_datasets,
        [
            "username/example-dataset",
            "anotheruser/publicdataset",
            "username/blobtree/example",
        ],
    )
    # List of jobs the user has:
    job_names = [
        "jr-eezd3arpcj", "jr-novcmdtiz6", "jr-3eka6z321p", "jr-5exwlvljs7", "jr-llchhg0xct",
        "jr-5d2yxejvc6", "jr-cnp3trdmy1", "jr-ec4ye5icgy", "jr-xmuknbuf2j", "jr-cyfoos5edc",
        "jr-dom7xcnv8m", "jr-21ihczwnyt", "jr-7yazbcdj8l", "jr-tfiy0pffus", "jr-d82mefwcri",
        "jr-z220bl0pml", "jr-5zsbtcy3ap", "jr-j10rlmisjm", "jr-urmdxygsmv", "jr-sohgy4uawv",
        "jr-9ulf0p3kbl", "jr-wd6q2e0lqa", "jr-tc8d5gcman", "jr-jf8tci86vq", "jr-slqqhqnqdn",
        "jr-fohmpfbzag", "jr-uelbume7nf", "jr-2ack2zwemw", "jr-euvxvncfku", "jr-xf4tslavut",
    ]
    function mock_job(i)
        jobs_overrides = get(MOCK_JULIAHUB_STATE, :jobs, Dict{String, Any}())
        jobname = job_names[i]
        merge(
            Dict{String, Any}(
                "id" => 8147 + i,
                "jobname" => jobname,
                "status" => "Completed",
                "submittimestamp" => "2023-03-15T07:56:50.974+00:00",
                "starttimestamp" => "2023-03-15T07:56:51.251+00:00",
                "endtimestamp" => "2023-03-15T07:56:59.000+00:00",
                "inputs" => "{}",
                "outputs" => "{}",
                "files" => MOCK_JULIAHUB_DEFAULT_JOB_FILES,
            ),
            get(jobs_overrides, jobname, Dict{String, Any}()),
        )
    end
    # "Check" authentication
    if get(MOCK_JULIAHUB_STATE, :invalid_authentication, false)
        return JuliaHub._RESTResponse(401, "Invalid authentication")
    end
    # Allow mocking for different API versions
    apiv = get(MOCK_JULIAHUB_STATE, :api_version, JuliaHub._MISSING_API_VERSION)
    # Mocked versions of the different endpoints:
    if (method == :GET) && endswith(url, "app/config/nodespecs/info")
        Dict(
            "message" => "", "success" => true,
            "node_specs" => [
                #! format: off
                ["m6", false, 4.0, 16.0, 0.33, "3.5 GHz Intel Xeon Platinum 8375C", "", "4", 90.5, 87.9, 2],
                ["m6", false, 8.0, 32.0, 0.65, "3.5 GHz Intel Xeon Platinum 8375C", "", "4", 95.1, 92.1, 3],
                ["m6", false, 32.0, 128.0, 2.4, "3.5 GHz Intel Xeon Platinum 8375C", "", "4", 98.5, 93.9, 4],
                ["r6", false, 2.0, 16.0, 0.22, "3.5 GHz Intel Xeon Platinum 8375C", "", "8", 81.5, 89.8, 5],
                ["r6", false, 4.0, 32.0, 0.42, "3.5 GHz Intel Xeon Platinum 8375C", "", "8", 90.5, 92.1, 6],
                ["m6", false, 2.0, 8.0, 0.17, "3.5 GHz Intel Xeon Platinum 8375C", "", "4", 81.5, 83.25, 7],
                ["r6", false, 8.0, 64.0, 1.3, "3.5 GHz Intel Xeon Platinum 8375C", "", "8", 95.1, 94.25, 9],
                ["p2", true, 4.0, 61.0, 1.4, "Intel Xeon E5-2686 v4 (Broadwell)", "", "K80", 90.25, 88.09, 8],
                ["p3", true, 8.0, 61.0, 4.5, "Intel Xeon E5-2686 v4 (Broadwell)", "", "V100", 95.03, 88.09, 1],
                #! format: on
            ],
        ) |> jsonresponse(200)
    elseif (method == :GET) && endswith(url, "app/packages/registries")
        Dict(
            "success" => true, "message" => "",
            "registries" => [
                #! format: off
                Dict("name" => "General", "uuid" => "23338594-aafe-5451-b93e-139f81909106", "id" => 1),
                Dict("name" => "JuliaComputingRegistry", "uuid" => "bbcd6645-47a4-41f8-a415-d8fc8421bd34", "id" => 266),
                #! format: on
            ],
        ) |> jsonresponse(200)
    elseif (method == :GET) && endswith(url, "app/applications/default")
        r = if apiv >= v"0.0.1"
            Dict{String, Any}(
                "defaultApps" => Any[
                    Dict{String, Any}(
                        "name" => "Base Product",
                        "image_group" => "base_only",
                        "compute_type_name" => "batch",
                        "input_type_name" => "userinput",
                        "product_name" => "baseproduct",
                        "appType" => "batchjob",
                    ),
                    Dict{String, Any}(
                        "name" => "Extra Product",
                        "image_group" => "base_and_opt",
                        "compute_type_name" => "batch",
                        "input_type_name" => "userinput",
                        "product_name" => "extra-images",
                        "appType" => "batchjob",
                    ),
                ],
                "defaultUserAppArgs" => [],
            )

        else
            Dict(
                "defaultApps" => Any[
                #! format: off
                Dict("visible" => true, "name" => "Linux Desktop", "appArgs" => Any[Dict("key" => "authentication", "label" => "Authentication", "default" => true, "required" => true, "description" => "Enable authentication for your Linux Desktop instance", "type" => "boolean", "tests" => Any[]), Dict("key" => "authorization", "label" => "Authorization", "options" => Any[Dict("key" => "me", "text" => "Allow only my account"), Dict("key" => "anyone", "text" => "Allow any logged in user")], "default" => "me", "required" => true, "depends" => Dict("key" => "authentication", "operator" => "eq", "value" => true, "type" => "condition"), "description" => "Choose who can access your Linux Desktop instance", "type" => "choice", "tests" => Any[]), Dict("key" => "password", "label" => "Password", "required" => true, "depends" => Dict("operator" => "or", "params" => Any[Dict("key" => "authentication", "operator" => "eq", "value" => false, "type" => "condition"), Dict("operator" => "and", "params" => Any[Dict("key" => "authentication", "operator" => "eq", "value" => true, "type" => "condition"), Dict("key" => "authorization", "operator" => "eq", "value" => "anyone", "type" => "condition")], "type" => "logical")], "type" => "logical"), "description" => "Set a password to securely access your Linux Desktop instance", "type" => "password", "tests" => Any[Dict("max" => 32, "min" => 8, "type" => "length", "errorMessage" => "Password must be between 8 and 32 characters"), Dict("regex" => ".*[a-z].*", "type" => "match", "errorMessage" => "Password must contain at least one lower case letter"), Dict("regex" => ".*[A-Z].*", "type" => "match", "errorMessage" => "Password must contain at least one upper case letter"), Dict("regex" => ".*[0-9].*", "type" => "match", "errorMessage" => "Password must contain at least one digit")])], "schedulerspec" => Dict("match_taints" => Dict("juliarun-job-name" => "defaultapp")), "description" => "Access a Linux desktop environment with Julia installed", "appType" => "vnc"),
                Dict("visible" => true, "name" => "Julia IDE", "appArgs" => Any[Dict("key" => "authentication", "label" => "Authentication", "default" => true, "required" => true, "description" => "Enable authentication for your Julia IDE instance", "type" => "boolean", "tests" => Any[]), Dict("key" => "authorization", "label" => "Authorization", "options" => Any[Dict("key" => "me", "text" => "Allow only my account"), Dict("key" => "anyone", "text" => "Allow any logged in user")], "default" => "me", "required" => true, "depends" => Dict("key" => "authentication", "operator" => "eq", "value" => true, "type" => "condition"), "description" => "Choose who can access your Julia IDE instance", "type" => "choice", "tests" => Any[]), Dict("key" => "password", "label" => "Password", "required" => true, "depends" => Dict("operator" => "or", "params" => Any[Dict("key" => "authentication", "operator" => "eq", "value" => false, "type" => "condition"), Dict("operator" => "and", "params" => Any[Dict("key" => "authentication", "operator" => "eq", "value" => true, "type" => "condition"), Dict("key" => "authorization", "operator" => "eq", "value" => "anyone", "type" => "condition")], "type" => "logical")], "type" => "logical"), "description" => "Set a password to securely access your Julia IDE instance", "type" => "password", "tests" => Any[Dict("max" => 32, "min" => 8, "type" => "length", "errorMessage" => "Password must be between 8 and 32 characters"), Dict("regex" => ".*[a-z].*", "type" => "match", "errorMessage" => "Password must contain at least one lower case letter"), Dict("regex" => ".*[A-Z].*", "type" => "match", "errorMessage" => "Password must contain at least one upper case letter"), Dict("regex" => ".*[0-9].*", "type" => "match", "errorMessage" => "Password must contain at least one digit")])], "schedulerspec" => Dict("match_taints" => Dict("juliarun-job-name" => "defaultapp")), "description" => "The full power of Julia in the cloud", "appType" => "codeserver"),
                Dict("visible" => true, "name" => "Pluto", "appArgs" => Any[Dict("key" => "authentication", "label" => "Authentication", "default" => true, "required" => true, "description" => "Enable authentication for your Pluto instance", "type" => "boolean", "tests" => Any[]), Dict("key" => "authorization", "label" => "Authorization", "options" => Any[Dict("key" => "me", "text" => "Allow only my account"), Dict("key" => "anyone", "text" => "Allow any logged in user")], "default" => "me", "required" => true, "depends" => Dict("key" => "authentication", "operator" => "eq", "value" => true, "type" => "condition"), "description" => "Choose who can access your Pluto instance", "type" => "choice", "tests" => Any[]), Dict("key" => "password", "label" => "Password", "required" => true, "depends" => Dict("operator" => "or", "params" => Any[Dict("key" => "authentication", "operator" => "eq", "value" => false, "type" => "condition"), Dict("operator" => "and", "params" => Any[Dict("key" => "authentication", "operator" => "eq", "value" => true, "type" => "condition"), Dict("key" => "authorization", "operator" => "eq", "value" => "anyone", "type" => "condition")], "type" => "logical")], "type" => "logical"), "description" => "Set a password to securely access your Pluto instance", "type" => "password", "tests" => Any[Dict("max" => 32, "min" => 8, "type" => "length", "errorMessage" => "Password must be between 8 and 32 characters"), Dict("regex" => ".*[a-z].*", "type" => "match", "errorMessage" => "Password must contain at least one lower case letter"), Dict("regex" => ".*[A-Z].*", "type" => "match", "errorMessage" => "Password must contain at least one upper case letter"), Dict("regex" => ".*[0-9].*", "type" => "match", "errorMessage" => "Password must contain at least one digit")])], "schedulerspec" => Dict("match_taints" => Dict("juliarun-job-name" => "defaultapp")), "description" => "Run Pluto notebooks in the cloud", "appType" => "pluto"),
                Dict("visible" => true, "name" => "Windows Workstation", "appArgs" => Any[Dict("key" => "authentication", "label" => "Authentication", "default" => true, "required" => true, "description" => "Enable authentication for your Windows Workstation instance", "type" => "boolean", "tests" => Any[]), Dict("key" => "authorization", "label" => "Authorization", "options" => Any[Dict("key" => "me", "text" => "Allow only my account"), Dict("key" => "anyone", "text" => "Allow any logged in user")], "default" => "me", "required" => true, "depends" => Dict("key" => "authentication", "operator" => "eq", "value" => true, "type" => "condition"), "description" => "Choose who can access your Windows Workstation instance", "type" => "choice", "tests" => Any[]), Dict("key" => "password", "label" => "Password", "required" => true, "depends" => Dict("operator" => "or", "params" => Any[Dict("key" => "authentication", "operator" => "eq", "value" => false, "type" => "condition"), Dict("operator" => "and", "params" => Any[Dict("key" => "authentication", "operator" => "eq", "value" => true, "type" => "condition"), Dict("key" => "authorization", "operator" => "eq", "value" => "anyone", "type" => "condition")], "type" => "logical")], "type" => "logical"), "description" => "Set a password to securely access your Windows Workstation instance", "type" => "password", "tests" => Any[Dict("max" => 32, "min" => 8, "type" => "length", "errorMessage" => "Password must be between 8 and 32 characters"), Dict("regex" => ".*[a-z].*", "type" => "match", "errorMessage" => "Password must contain at least one lower case letter"), Dict("regex" => ".*[A-Z].*", "type" => "match", "errorMessage" => "Password must contain at least one upper case letter"), Dict("regex" => ".*[0-9].*", "type" => "match", "errorMessage" => "Password must contain at least one digit")])], "schedulerspec" => Dict("match_taints" => Dict()), "description" => "Windows desktop with pre-installed applications", "appType" => "winworkstation"),
                #! format: on
                ],
                "defaultUserAppArgs" => Any[],
            )
        end
        r |> jsonresponse(200)
    elseif (method == :GET) && endswith(url, "app/applications/info")
        Any[
            Dict(
                "name" => "RegisteredPackageApp",
                "uuid" => "db8b4d46-bfad-4aa5-a5f8-40df1e9542e5",
                "registrymap" => Any[Dict("status" => true, "id" => "1")],
            ),
            Dict(
                "name" => "CustomDashboardApp",
                "uuid" => "539b0f2a-a771-427e-a3ea-5fa1ee615c0c",
                "registrymap" => Any[Dict("status" => true, "id" => "266")],
            ),
        ] |> jsonresponse(200)
    elseif (method == :GET) && endswith(url, "app/applications/myapps")
        #! format: off
        Any[
            Dict(
                "name" => "ExampleApp.jl",
                "repourl" => "https://github.com/JuliaHubExampleOrg/ExampleApp.jl",
            ),
        ] |> jsonresponse(200)
        #! format: on
    elseif (method == :POST) && endswith(url, "juliaruncloud/submit_job")
        jobname = "jr-xf4tslavut"
        Dict("message" => "", "success" => true, "jobname" => jobname) |> jsonresponse(200)
    elseif (method == :GET) && endswith(url, "jobs/appbundle_upload_url")
        Dict{String, Any}(
            "message" => Dict{String, Any}(
                "upload_url" => "..."
            ),
            "success" => true
        ) |> jsonresponse(200)
    elseif (method == :GET) && occursin(GET_JOB_REGEX, url)
        jobname = match(GET_JOB_REGEX, url)[1]
        idx = findfirst(isequal(jobname), job_names)
        jobs = isnothing(idx) ? [] : [mock_job(idx)]
        Dict("details" => jobs) |> jsonresponse(200)
    elseif (method == :GET) && endswith(url, "juliaruncloud/get_jobs")
        njobs = get(query, :limit, 20)
        jobs_overrides = get(MOCK_JULIAHUB_STATE, :jobs, Dict{Int, Any}())
        jobs = [mock_job(i) for i = 1:njobs]
        jobs |> jsonresponse(200)
    elseif (method == :GET) && endswith(url, "juliaruncloud/kill_job")
        idx = findfirst(isequal(query.jobname), job_names)
        if isnothing(idx)
            JuliaHub._RESTResponse(403, "User does not have access to this job")
        else
            jobs_overrides = get!(MOCK_JULIAHUB_STATE, :jobs, Dict{String, Any}())
            job_info = get!(jobs_overrides, query.jobname, Dict{String, Any}())
            job_info["status"] = "Stopped"
            Dict{String, Any}(
                "status" => true,
                "message" => "Job $(query.jobname) stopped successfully"
            ) |> jsonresponse(200)
        end
    elseif (method == :POST) && endswith(url, "juliaruncloud/extend_job_time_limit")
        payload = JSON.parse(payload)
        idx = findfirst(isequal(payload["jobname"]), job_names)
        if isnothing(idx)
            JuliaHub._RESTResponse(403, "User does not have access to this job")
        else
            Dict("message" => "", "success" => true) |> jsonresponse(200)
        end
    elseif (method == :GET) && endswith(url, "datasets")
        dataset_params = get(MOCK_JULIAHUB_STATE, :dataset_params, Dict())
        #! format: off
        shared = Dict(
            "groups" => Any[],
                "storage" => Dict(
                    "bucket_region" => "us-east-1",
                    "bucket" => "datasets-bucket",
                    "prefix" => "datasets",
                    "vendor" => "aws",
                ),
                "description" => get(dataset_params, "description", "An example dataset"),
                "version" => "v1",
                "versions" => Any[
                    Dict(
                        "version" => 1,
                        "blobstore_path" => "u1",
                        "size" => 57,
                        "date" => "2022-10-12T05:39:42.906+00:00",
                    )
                ],
                "size" => 57,
                "tags" => get(dataset_params, "tags", ["tag1", "tag2"]),
                "license" => (
                    "name" => "MIT License",
                    "spdx_id" => "MIT",
                    "text" => nothing,
                    "url" => "https://opensource.org/licenses/MIT",
                ),
                "lastModified" => "2022-10-12T05:39:42.906",
                "downloadURL" => "",
                "credentials_url" => "...",
        )
        #! format: on
        datasets = []
        for dataset_full_id in existing_datasets
            username, dataset = split(dataset_full_id, '/'; limit=2)
            push!(datasets,
                Dict(
                    "id" => string(uuidhash(dataset_full_id)),
                    "name" => dataset,
                    "owner" => Dict(
                        "username" => username,
                        "type" => "User",
                    ),
                    "type" => occursin("blobtree", dataset) ? "BlobTree" : "Blob",
                    "visibility" => occursin("public", dataset) ? "public" : "private",
                    shared...,
                ),
            )
        end
        datasets |> jsonresponse(200)
    elseif (method == :DELETE) && endswith(url, DATASET_REGEX)
        dataset = URIs.unescapeuri(match(DATASET_REGEX, url)[1])
        if "username/$(dataset)" ∈ existing_datasets
            deleteat!(
                existing_datasets, findfirst(isequal("username/$(dataset)"), existing_datasets)
            )
            Dict{String, Any}(
                "name" => dataset,
                "repo_id" => "df039a60-0ccc-40a7-ad31-82040a74a12a"
            ) |> jsonresponse(200)
        else
            return JuliaHub._RESTResponse(404, "Dataset $(dataset) does not exist.")
        end
    elseif (method == :PATCH) && endswith(url, DATASET_REGEX)
        dataset = URIs.unescapeuri(match(DATASET_REGEX, url)[1])
        if "username/$(dataset)" ∈ existing_datasets
            if haskey(MOCK_JULIAHUB_STATE, :dataset_params)
                merge!(MOCK_JULIAHUB_STATE[:dataset_params], JSON.parse(payload))
            end
            Dict{String, Any}(
                "name" => dataset,
                "repo_id" => "df039a60-0ccc-40a7-ad31-82040a74a12a"
            ) |> jsonresponse(200)
        else
            return JuliaHub._RESTResponse(404, "Dataset $(dataset) does not exist.")
        end
    elseif (method == :POST) && endswith(url, "/user/datasets")
        payload = JSON.parse(payload)
        dataset, type = payload["name"], payload["type"]
        if "$(MOCK_USERNAME)/$(dataset)" in existing_datasets
            JuliaHub._RESTResponse(409, "Dataset $(dataset) exists")
        else
            push!(existing_datasets, "$(MOCK_USERNAME)/$(dataset)")
            Dict("repo_id" => string(UUIDs.uuid4())) |> jsonresponse(200)
        end
    elseif (method == :POST) && endswith(url, DATASET_VERSIONS_REGEX)
        dataset = URIs.unescapeuri(match(DATASET_VERSIONS_REGEX, url)[1])
        if isnothing(payload)
            if "$(MOCK_USERNAME)/$(dataset)" in existing_datasets
                Dict{String, Any}(
                    "location" => Dict{String, Any}(
                        "bucket" => "",
                        "region" => "",
                        "prefix" => "",
                    ),
                    "upload_type" => "S3",
                    "credentials" => Dict{String, Any}(
                        "session_token" => "...",
                        "secret_access_key" => "...",
                        "expiry" => "2023-03-17T22:07:33",
                        "access_key_id" => "...",
                    ),
                    "dataset_type" => occursin("blobtree", dataset) ? "BlobTree" : "Blob",
                    "vendor" => "aws",
                    "upload_id" => "50976fae-6bf5-4423-a84c-6d41c2662cdf",
                ) |> jsonresponse(200)
            else
                JuliaHub._RESTResponse(404, "Dataset $(dataset) does not exist")
            end
        else
            payload = JSON.parse(payload)
            @assert payload["action"] == "close"
            dataset = payload["name"]
            Dict{String, Any}(
                "size_bytes" => 8124,
                "dataset_id" => "c1488c3f-0910-4f73-9c40-14f3c7a8696b",
                "commit_time" => "2023-03-17T10:07:35.506",
                "version" => "v1",
            ) |> jsonresponse(200)
        end
    elseif (method == :GET) && endswith(url, "/juliaruncloud/get_logs")
        logengine = get(MOCK_JULIAHUB_STATE, :logengine, nothing)
        if isnothing(logengine)
            JuliaHub._RESTResponse(500, "MOCK_JULIAHUB_STATE[:logengine] not set up")
        else
            serve_legacy(logengine, Dict(query))
        end
    elseif in(method, (:HEAD, :GET)) && endswith(url, "/juliaruncloud/get_logs_v2")
        logengine = get(MOCK_JULIAHUB_STATE, :logengine, nothing)
        if isnothing(logengine)
            JuliaHub._RESTResponse(500, "MOCK_JULIAHUB_STATE[:logengine] not set up")
        elseif !logengine.kafkalogging
            JuliaHub._RESTResponse(404, "MOCK_JULIAHUB_STATE[:logengine]: Kafka disabled")
        else
            serve_kafka(logengine, method, Dict(query))
        end
    elseif (method == :GET) && endswith(url, "/juliaruncloud/product_image_groups")
        Dict(
            "image_groups" => Dict(
                "base_and_opt" => [
                    Dict(
                        "display_name" => "Stable", "type" => "base-cpu",
                        "image_key_name" => "stable-cpu",
                    ),
                    Dict(
                        "display_name" => "Stable", "type" => "base-gpu",
                        "image_key_name" => "stable-gpu",
                    ),
                    Dict(
                        "display_name" => "Dev", "type" => "option-cpu",
                        "image_key_name" => "dev-cpu",
                    ),
                    Dict(
                        "display_name" => "Dev", "type" => "option-gpu",
                        "image_key_name" => "dev-gpu",
                    ),
                ],
                "base_only" => [
                    Dict(
                        "display_name" => "Stable", "type" => "base-cpu",
                        "image_key_name" => "stable-cpu",
                    ),
                    Dict(
                        "display_name" => "Stable", "type" => "base-gpu",
                        "image_key_name" => "stable-gpu",
                    ),
                ],
            ),
        ) |> jsonresponse(200)
    else
        error("Unmocked REST call: $method $url")
    end
end


# Mocking for the logging endpoints
mutable struct LogEngineJob
    isrunning::Bool
    logs::Vector{String}
    LogEngineJob(logs; isrunning=false) = new(isrunning, collect(logs))
end

Base.@kwdef mutable struct LogEngine
    jobs::Dict{String, LogEngineJob} = Dict()
    kafkalogging::Bool = false
    # The real legacy endpoint has a limit of 10k. Similarly, for the real
    # kafka endpoint this is determined by the max_bytes of the response,
    # so it can actually vary.
    max_response_size::Int = 10
end

function serve_kafka(logengine::LogEngine, method::Symbol, query::Dict)
    jobname = get(query, "jobname", nothing)
    job = get(logengine.jobs, jobname, nothing)
    # If the client is doing a HEAD request, then we immediately return the
    # approriate empty response.
    if method == :HEAD
        if isnothing(jobname)
            return JuliaHub._RESTResponse(400, "")
        elseif isnothing(job)
            return JuliaHub._RESTResponse(404, "")
        else
            return JuliaHub._RESTResponse(200, "")
        end
    end
    # Error handing for the GET requests (like for HEAD, but with a body)
    if isnothing(jobname)
        return JuliaHub._RESTResponse(400, "jobname is missing")
    elseif isnothing(job)
        return JuliaHub._RESTResponse(404, "No such job $jobname")
    end
    # Return the normal response
    offset = get(query, "offset", nothing)
    # We'll construct the full list of logs for the job, including the meta message
    # at the end if necessary.
    logs::Vector{Any} = map(enumerate(job.logs)) do (i, log)
        # Make the indexing start from 0, to match the Kafka offset logic
        (i - 1, log)
    end
    # We'll add the meta=bottom message, if needed.
    if !job.isrunning
        push!(logs, (length(logs), :bottom))
    end
    logs = if isnothing(offset)
        start = max(1, length(logs) - logengine.max_response_size + 1)
        logs[start:end]
    elseif offset + 1 <= length(logs)
        start = offset + 1
        stop = min(start + logengine.max_response_size - 1, length(logs))
        logs[start:stop]
    else
        [] # For out of range offsets we just return an empty list of logs
    end
    start_timestamp = Dates.now()
    logs = map(logs) do (i, log)
        value = if isa(log, Symbol)
            Dict("meta" => string(log))
        else
            Dict(
                "timestamp" =>
                    JuliaHub._log_legacy_datetime_to_ms(start_timestamp + Dates.Second(i)),
                "log" => Dict(
                    "message" => String(log),
                    "keywords" => Dict(
                        "typeof(logger)" => "LoggingExtras...",
                        "jrun_hostname" => "jr-ecogm4cccn-x5z4g",
                        "jrun_worker_id" => 1,
                        "jrun_thread_id" => 1,
                        "jrun_time" => start_timestamp,
                        "jrun_process_id" => 27,
                    ),
                    "metadata" => Dict(
                        "line" => 141,
                        "id" => "Main_JuliaRunJob_53527a33",
                        "_module" => "Main.JuliaRunJob",
                        "filepath" => "/opt/juliahub/master_startup.jl",
                        "group" => "master_startup",
                        "level" => "Info",
                        "steam" => "stdout",
                    ),
                ),
            )
        end
        Dict("offset" => i, "value" => value)
    end
    logs_json = JSON.json(Dict("consumer_id" => 1234, "logs" => logs))
    return JuliaHub._RESTResponse(200, logs_json)
end

function serve_legacy(logengine::LogEngine, query::Dict)
    jobname = get(query, "jobname", nothing)
    job = get(logengine.jobs, jobname, nothing)
    if isnothing(jobname)
        return JuliaHub._RESTResponse(400, "jobname missing")
    elseif isnothing(job)
        return JuliaHub._RESTResponse(403, "\"User does not have access to this job.\"")
    end
    # Check a few inconsequential query parameters
    haskey(query, "log_output_type") || @warn "Query parameter 'log_output_type' missing"
    haskey(query, "log_out_type") || @warn "Query parameter 'log_out_type' missing"
    # Get the other (optional) query parameters
    if haskey(query, "nentries")
        return JuliaHub._RESTResponse(500, "nentries unimplemented in mock endpoint")
    end
    start_time = get(query, "start_time", nothing)
    end_time = get(query, "end_time", nothing)
    event_id = get(query, "event_id", nothing)
    if !isnothing(start_time) && !isnothing(end_time)
        return JuliaHub._RESTResponse(400, "both start_time and end_time provided")
    end
    # We'll construct the full list of logs for the job, including the meta messages.
    # Note: we may need to push objects to other types into this array too.
    logs::Vector{Any} = vcat(
        (0, :top),
        collect(enumerate(job.logs)),
    )
    if !job.isrunning
        # Note: length(logs) = length(job.logs) + 1, so the index is correctly
        # last(logs)[1] + 1
        push!(logs, (length(logs), :bottom))
    end
    # Construct the response. If event_id wasn't passed, then we return the last N logs.
    # If it was passed, we return the logs before or after the reference log.
    logs = if isnothing(event_id)
        # Not sure if the real endpoint is this strict, but we should not be passign
        # start/end_time without event_id.
        if !isnothing(start_time) || !isnothing(end_time)
            JuliaHub._RESTResponse(400, "start_time / end_time provided, but not event_id")
        end
        nlogs_to_return = min(length(logs), logengine.max_response_size)
        logs = logs[(end - nlogs_to_return + 1):end]
        @assert length(logs) == nlogs_to_return
        logs
    else
        if !isnothing(start_time) && !isnothing(end_time)
            return JuliaHub._RESTResponse(400, "event_id provided, but no start_time or end_time")
        end
        # If event_id is passed, it should be an integer index
        event_id = parse(Int, event_id)
        logs_start, logs_end = if isnothing(end_time)
            # If start_time was passed, we return from event_id onwards
            logs_start = max(event_id + 2, 1)
            logs_end = min(event_id + logengine.max_response_size + 1, length(logs))
            logs_start, logs_end
        else
            # If end_time was passed, we return up to event_id
            logs_start = max(event_id - logengine.max_response_size + 1, 1)
            logs_end = min(event_id, length(logs))
            logs_start, logs_end
        end
        logs[logs_start:logs_end]
    end
    start_timestamp = Dates.now()
    logs = map(logs) do (i, log)
        if isa(log, Symbol)
            Dict("message" => "", "_meta" => true, "end" => string(log))
        else
            Dict(
                "message" => String(log),
                "timestamp" => start_timestamp + Dates.Second(i),
                "keywords" => Dict(
                    "typeof(logger)" => "LoggingExtras...",
                    "jrun_hostname" => "jr-ecogm4cccn-x5z4g",
                    "jrun_worker_id" => 1,
                    "jrun_thread_id" => 1,
                    "jrun_time" => start_timestamp,
                    "jrun_process_id" => 27,
                ),
                "metadata" => Dict(
                    "line" => 141,
                    "id" => "Main_JuliaRunJob_53527a33",
                    "_module" => "Main.JuliaRunJob",
                    "filepath" => "/opt/juliahub/master_startup.jl",
                    "group" => "master_startup",
                    "level" => "Info",
                ),
                "eventId" => string(i),
            )
        end
    end
    return JuliaHub._RESTResponse(200, string('"', escape_string(JSON.json(logs)), '"'))
end

# Authentication mocking
function _auth_legacy_gql_mocked()
    global MOCK_JULIAHUB_STATE
    if get(MOCK_JULIAHUB_STATE, :auth_gql_fail, false)
        return JuliaHub._RESTResponse(500, "auth_gql_fail = true")
    end
    return Dict{String, Any}(
        "data" => Dict{String, Any}(
            "users" => Any[Dict{String, Any}(
                "name" => "Test User",
                "firstname" => "Test",
                "id" => 42,
                "username" => "username",
                "info" => Any[Dict{String, Any}(
                    "email" => "testuser@example.org"
                )],
            )],
        ),
    ) |> jsonresponse(200)
end

function _auth_apiv1_mocked()
    global MOCK_JULIAHUB_STATE, MOCK_USERNAME
    status = get(MOCK_JULIAHUB_STATE, :auth_v1_status, 200)
    if status != 200
        return JuliaHub._RESTResponse(status, "auth_v1_status override")
    end
    d = Dict{String, Any}(
        "timezone" => Dict{String, Any}("abbreviation" => "Etc/UTC", "utc_offset" => "+00:00"),
        "api_version" => "0.0.1",
    )
    username = get(MOCK_JULIAHUB_STATE, :auth_v1_username, MOCK_USERNAME)
    if !isnothing(username)
        d["username"] = username
    end
    d |> jsonresponse(200)
end
