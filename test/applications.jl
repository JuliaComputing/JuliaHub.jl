@testset "JuliaHub._api_registries" begin
    Mocking.apply(mocking_patch) do
        registries = JuliaHub._api_registries(JuliaHub.__auth__())
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

@testset "JuliaHub.application(s) API errors" begin
    MOCK_JULIAHUB_STATE[:applications_error_entries] = true
    Mocking.apply(mocking_patch) do
        # We have one erroneous entry for each category
        @test_logs (:warn,) (:warn,) (:warn,) @test length(JuliaHub.applications()) == 7
        @test_logs (:warn,) @test length(JuliaHub.applications(:default)) == 4
        @test_logs (:warn,) @test length(JuliaHub.applications(:package)) == 2
        @test_logs (:warn,) @test length(JuliaHub.applications(:user)) == 1
        let app = @test_logs (:warn,) JuliaHub.application(:default, "Linux Desktop")
            @test app isa JuliaHub.DefaultApp
            @test app.name == "Linux Desktop"
        end
        @test_logs (:warn,) @test_throws JuliaHub.InvalidRequestError JuliaHub.application(
            :default, "no-such-app"
        )
        @test_logs (:warn,) @test_throws JuliaHub.InvalidRequestError JuliaHub.application(
            :package, "BrokenRegisteredPackage"
        )
        @test_logs (:warn,) @test JuliaHub.application(:default, "no-such-app"; throw=false) ===
            nothing
    end
    empty!(MOCK_JULIAHUB_STATE)
end

@testset "Empty user/registered apps" begin
    MOCK_JULIAHUB_STATE[:app_packages_registries] = []
    MOCK_JULIAHUB_STATE[:app_applications_info] = []
    MOCK_JULIAHUB_STATE[:app_applications_myapps] = []
    Mocking.apply(mocking_patch) do
        @test length(JuliaHub.applications()) == 4
        @test length(JuliaHub.applications(:default)) == 4
        @test length(JuliaHub.applications(:package)) == 0
        @test length(JuliaHub.applications(:user)) == 0
    end
    empty!(MOCK_JULIAHUB_STATE)
end

TEST_SUBMIT_APPS = [
    (:default, "Pluto", JuliaHub.DefaultApp),
    (:package, "RegisteredPackageApp", JuliaHub.PackageApp),
    (:user, "ExampleApp.jl", JuliaHub.UserApp),
]
@testset "Submit app: :$cat / $apptype" for (cat, name, apptype) in TEST_SUBMIT_APPS
    Mocking.apply(mocking_patch) do
        app = JuliaHub.application(cat, name)
        @test isa(app, apptype)
        @test app.name == name
        j = JuliaHub.submit_job(app)
        @test j isa JuliaHub.Job
        @test j.status == "Completed"
    end
end

# A DefaultApp whose product needs product_name to resolve correctly server-side (e.g.
# IQOQ - see the "IQOQ Test" mock fixture in mocking.jl) must have it threaded through
# job submission, not silently dropped. compute_type_name="cloudstation-ide" with
# input_type_name="image" mirrors IQOQ's real product config: not classified as a batch
# app (so it shows up here, as an ordinary application), but still product-tracked.
@testset "_job_submit_args(ApplicationJob) threads product_name" begin
    apiv = v"0.0.1"
    MOCK_JULIAHUB_STATE[:api_version] = apiv
    auth = JuliaHub.current_authentication()
    auth._api_version = apiv
    Mocking.apply(mocking_patch) do
        app = JuliaHub.application(:default, "IQOQ Test"; auth)
        @test isa(app, JuliaHub.DefaultApp)

        c = JuliaHub.submit_job(app; auth, dryrun=true)
        args = JuliaHub._job_submit_args(auth, c, c.app, JuliaHub._JobSubmission1)
        @test args.product_name == "iqoq"
    end
    empty!(MOCK_JULIAHUB_STATE)
end
