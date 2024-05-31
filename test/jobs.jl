# We have to copy the test environment files to a temporary directory
# because PackageBundler needs write access to them.
JOBENVS = let tmp = tempname()
    cp(joinpath(@__DIR__, "jobenvs"), tmp)
    chmod(tmp, 0o777; recursive=true)
    tmp
end

@testset "JuliaHub.script" begin
    jobfile(path...) = joinpath(JOBENVS, "job1", path...)

    let s = JuliaHub.script(; code="1", project="name=1", manifest="name=1", artifacts="name=1")
        @test s.code == "1"
        @test s.environment.project_toml == "name=1"
        @test s.environment.manifest_toml == "name=1"
        @test s.environment.artifacts_toml == "name=1"
    end
    let s = JuliaHub.script(; code="1", project="name=1")
        @test s.code == "1"
        @test s.environment.project_toml == "name=1"
        @test s.environment.manifest_toml === nothing
        @test s.environment.artifacts_toml === nothing
        @test s.sysimage === false
    end
    let s = JuliaHub.script(; code="1", manifest="name=1", sysimage=true)
        @test s.code == "1"
        @test s.environment.manifest_toml === "name=1"
        @test s.sysimage === true
        @test JuliaHub._sysimage_manifest_sha(s.environment) ==
            "b3be53dd7b40e92821b39188b37a70bb81d47d1db3818703744544efece3538c"
    end
    @test_throws ArgumentError JuliaHub.script(; code="1", project=".")
    @test_throws ArgumentError JuliaHub.script(; code="1", artifacts=".")
    @test_throws ArgumentError JuliaHub.script(; code="1", project="name=1", sysimage=true)

    let s = JuliaHub.script(jobfile("script.jl"))
        @test s.code == read(jobfile("script.jl"), String)
        @test s.environment.project_toml === nothing
        @test s.environment.manifest_toml === nothing
        @test s.environment.artifacts_toml === nothing
        @test s.sysimage === false
    end
    manifest_sha = bytes2hex(SHA.sha256(read(jobfile("Manifest.toml"))))
    let s = JuliaHub.script(
            jobfile("script.jl");
            project_directory=jobfile(),
            sysimage=true,
        )
        @test s.code == read(jobfile("script.jl"), String)
        @test s.environment.project_toml == read(jobfile("Project.toml"), String)
        @test s.environment.manifest_toml == read(jobfile("Manifest.toml"), String)
        @test s.environment.artifacts_toml === nothing
        @test s.sysimage === true
        @test JuliaHub._sysimage_manifest_sha(s.environment) == manifest_sha
    end

    withproject(jobfile("Project.toml")) do
        s = JuliaHub.script"test()"
        @test s.code == "test()"
        @test s.environment.project_toml == read(jobfile("Project.toml"), String)
        @test s.environment.manifest_toml == read(jobfile("Manifest.toml"), String)
        @test s.environment.artifacts_toml === nothing
        @test s.sysimage === false

        s = JuliaHub.BatchJob(s; sysimage=true)
        @test s.code == "test()"
        @test s.environment.project_toml == read(jobfile("Project.toml"), String)
        @test s.environment.manifest_toml == read(jobfile("Manifest.toml"), String)
        @test s.environment.artifacts_toml === nothing
        @test s.sysimage === true
        @test JuliaHub._sysimage_manifest_sha(s.environment) == manifest_sha
    end

    withproject(jobfile("Project.toml")) do
        s = JuliaHub.script"test()"noenv
        @test s.code == "test()"
        @test s.environment.project_toml === nothing
        @test s.environment.manifest_toml === nothing
        @test s.environment.artifacts_toml === nothing
        @test s.sysimage === false
    end
end

function is_valid_julia_code(code::AbstractString)
    try
        ex = Meta.parse(code)
        if ex.head === :incomplete
            @error "Incomplete Julia expression in Julia code\n$(code)" ex
            return false
        end
    catch exception
        if isa(exception, Meta.ParseError)
            @error "Invalid Julia code\n$(code)" exception
            return false
        end
    end
    return true
end

@testset "JuliaHub.appbundle" begin
    driver_file_first_line = first(eachline(JuliaHub._APPBUNDLE_DRIVER_TEMPLATE_FILE))
    jobfile(path...) = joinpath(JOBENVS, "job1", path...)

    bundle = JuliaHub.appbundle(jobfile(), "script.jl")
    @test isfile(bundle.environment.tarball_path)
    @test startswith(bundle.code, driver_file_first_line)
    @test contains(bundle.code, "raw\"script.jl\"")
    @test is_valid_julia_code(bundle.code)

    bundle = JuliaHub.appbundle(jobfile(), "subdir/my-dependent-script-2.jl")
    @test isfile(bundle.environment.tarball_path)
    @test startswith(bundle.code, driver_file_first_line)
    @test contains(bundle.code, "raw\"subdir\"")
    @test contains(bundle.code, "raw\"my-dependent-script-2.jl\"")
    @test is_valid_julia_code(bundle.code)

    bundle = JuliaHub.appbundle(jobfile(); code="test()")
    @test isfile(bundle.environment.tarball_path)
    @test bundle.code == "test()"
    @test bundle.sysimage === false

    bundle = JuliaHub.appbundle(jobfile(); code="test()", sysimage=true)
    @test isfile(bundle.environment.tarball_path)
    @test bundle.code == "test()"
    @test bundle.sysimage === true
    @test JuliaHub._sysimage_manifest_sha(bundle.environment) ==
        "631fc619c1d04e525872df2779fa95a0dc47edd9558af629af88c493daa6300d"

    mktempdir() do path
        bigfile_path = joinpath(path, "bigfile")
        open(bigfile_path; write=true) do io
            chunk = '\0'^(2^20)
            for _ in 1:3000
                write(io, chunk)
            end
        end
        @test_throws JuliaHub.AppBundleSizeError JuliaHub.appbundle(path; code="")
        rm(bigfile_path; force=true)
    end

    # Testing relative paths to the appbundle directory
    cd(jobfile()) do
        bundle = JuliaHub.appbundle(".", "script.jl")
        @test isfile(bundle.environment.tarball_path)
        @test startswith(bundle.code, driver_file_first_line)
        @test contains(bundle.code, "raw\"script.jl\"")
        @test is_valid_julia_code(bundle.code)
    end

    # Deprecated case, where `codefile` comes from outside of the appbundle
    # directory. In that case, `codefile` gets attached directly as the driver
    # script.
    let bundle = @test_logs (:warn,) JuliaHub.appbundle(jobfile(), "../job-dist/script.jl")
        @test isfile(bundle.environment.tarball_path)
        @test bundle.code == read(jobfile("../job-dist/script.jl"), String)
    end
end

# We'll re-use this further down in job submission tests.
ns_cheapest = Mocking.apply(mocking_patch) do
    empty!(MOCK_JULIAHUB_STATE)
    JuliaHub.nodespec()
end

@testset "JuliaHub.nodespec/s()" begin
    empty!(MOCK_JULIAHUB_STATE)
    @testset "Cheapest" begin
        @test ns_cheapest.hasGPU === false
        @test ns_cheapest.vcores == 2
        @test ns_cheapest.mem == 8
        @test ns_cheapest.nodeClass == "m6"
    end

    Mocking.apply(mocking_patch) do
        nodes = JuliaHub.nodespecs()
        @test length(nodes) == 9
        @test nodes isa Vector{JuliaHub.NodeSpec}

        # JuliaHub.nodespec()
        let n = JuliaHub.nodespec()
            @test n.mem == 8
            @test n.vcores == 2
            @test !n.hasGPU
            @test n.priceHr == minimum(n.priceHr for n in nodes)
        end
        let n = JuliaHub.nodespec(; ncpu=2, memory=16)
            @test n.nodeClass == "r6"
            @test n.mem == 16
            @test n.vcores == 2
            @test !n.hasGPU
        end
        let n = JuliaHub.nodespec(; ncpu=4, memory=16)
            @test n.nodeClass == "m6"
            @test n.mem == 16
            @test n.vcores == 4
            @test !n.hasGPU
        end
        let n = JuliaHub.nodespec(; ncpu=4, memory=16, ngpu=1)
            @test n.nodeClass == "p2"
            @test n.mem == 61
            @test n.vcores == 4
            @test n.hasGPU
        end
        # Nodes with requirements that can't be met
        @test_throws JuliaHub.InvalidRequestError JuliaHub.nodespec(; ncpu=100, memory=5)
        @test_throws JuliaHub.InvalidRequestError JuliaHub.nodespec(;
            ncpu=100, memory=5, throw=true
        )
        @test JuliaHub.nodespec(; ncpu=100, memory=5, throw=false) === nothing
        @test_throws JuliaHub.InvalidRequestError JuliaHub.nodespec(; ncpu=4, memory=50_000)

        # Exact matching
        let n = JuliaHub.nodespec(; ncpu=1, memory=5)
            @test n.vcores == 2
            @test n.mem == 8
        end
        @test_throws JuliaHub.InvalidRequestError JuliaHub.nodespec(;
            ncpu=1, memory=5, exactmatch=true
        )
        @test JuliaHub.nodespec(; ncpu=1, memory=5, exactmatch=true, throw=false) === nothing
        let n = JuliaHub.nodespec(; ncpu=2, memory=8, exactmatch=true)
            @test n.vcores == 2
            @test n.mem == 8
        end

        # Test the `throw` argument by requesting unsupported multi-GPU nodes
        @test_throws JuliaHub.InvalidRequestError JuliaHub.nodespec(; ngpu=10)
        @test_throws JuliaHub.InvalidRequestError JuliaHub.nodespec(; ngpu=10, throw=true)
        @test @test_logs (:warn,) JuliaHub.nodespec(; ngpu=10, throw=false) === nothing
    end

    # Check that we ignore bad price information, and match node based on the GPU, CPU, and memory (in that order)
    MOCK_JULIAHUB_STATE[:nodespecs] = [
        #! format: off
        #  class,   gpu,  cpu,   mem, price,                                desc,  ?, memdisp,     ?,     ?, id
        [   "c1", false,  1.0,  16.0,  3.00, "3.5 GHz Intel Xeon Platinum 8375C", "",     "4", 90.50, 87.90,  2],
        [   "c2", false,  2.0,   8.0,  2.00, "3.5 GHz Intel Xeon Platinum 8375C", "",     "4", 95.10, 92.10,  3],
        [   "c8", false,  8.0,   4.0,  1.00, "3.5 GHz Intel Xeon Platinum 8375C", "",     "4", 98.50, 93.90,  4],
        #! format: on
    ]
    Mocking.apply(mocking_patch) do
        let n = JuliaHub.nodespec()
            @test n.nodeClass == "c1"
            @test n._id == 2
            @test n.vcores == 1
            @test n.mem == 16
            @test !n.hasGPU
        end
        let n = JuliaHub.nodespec(; ncpu=2)
            @test n.nodeClass == "c2"
            @test n._id == 3
            @test n.vcores == 2
            @test n.mem == 8
            @test !n.hasGPU
        end
        # Test sorting of JuliaHub.nodespecs()
        @test [n.nodeClass for n in JuliaHub.nodespecs()] == ["c1", "c2", "c8"]
    end
    # Cheap GPU node gets de-prioritised:
    push!(
        MOCK_JULIAHUB_STATE[:nodespecs],
        #! format: off
        #  class,   gpu,  cpu,   mem, price,                                desc,  ?, memdisp,     ?,     ?, id
        [ "c1g1",  true,  1.0,  16.0,  0.00, "3.5 GHz Intel Xeon Platinum 8375C", "",     "4", 90.50, 87.90,  5],
        #! format: on
    )
    Mocking.apply(mocking_patch) do
        let n = JuliaHub.nodespec()
            @test n.nodeClass == "c1"
            @test n._id == 2
            @test n.vcores == 1
            @test n.mem == 16
            @test !n.hasGPU
        end
        # Test sorting of JuliaHub.nodespecs()
        @test [n.nodeClass for n in JuliaHub.nodespecs()] == ["c1", "c2", "c8", "c1g1"]
    end
    # Low memory gets prioritized:
    push!(
        MOCK_JULIAHUB_STATE[:nodespecs],
        #! format: off
        #  class,   gpu,  cpu,   mem, price,                                desc,  ?, memdisp,     ?,     ?, id
        [ "c1m1", false,  1.0,   1.0, 99.99, "3.5 GHz Intel Xeon Platinum 8375C", "",     "4", 90.50, 87.90,  6],
        #! format: on
    )
    Mocking.apply(mocking_patch) do
        let n = JuliaHub.nodespec()
            @test n.nodeClass == "c1m1"
            @test n._id == 6
            @test n.vcores == 1
            @test n.mem == 1
            @test !n.hasGPU
        end
        # But we'll be forced to pick the GPU node here:
        let n = JuliaHub.nodespec(; ngpu=1)
            @test n.nodeClass == "c1g1"
            @test n._id == 5
            @test n.vcores == 1
            @test n.mem == 16
            @test n.hasGPU
        end
        # Test sorting of JuliaHub.nodespecs()
        @test [n.nodeClass for n in JuliaHub.nodespecs()] == ["c1m1", "c1", "c2", "c8", "c1g1"]
    end
    # However, for identical nodespecs, we disambiguate based on price:
    MOCK_JULIAHUB_STATE[:nodespecs] = [
        #! format: off
        # class,   gpu,  cpu,   mem, price,                                desc,  ?, memdisp,     ?,     ?, id
        [  "a1", false,  1.0,   1.0,  2.00, "3.5 GHz Intel Xeon Platinum 8375C", "",     "4", 90.50, 87.90,  2],
        [  "a2", false,  1.0,   1.0,  1.00, "3.5 GHz Intel Xeon Platinum 8375C", "",     "4", 95.10, 92.10,  3],
        [  "a3", false,  1.0,   1.0,  2.00, "3.5 GHz Intel Xeon Platinum 8375C", "",     "4", 98.50, 93.90,  4],
        #! format: on
    ]
    Mocking.apply(mocking_patch) do
        let n = JuliaHub.nodespec()
            @test n._id == 3
            @test n.nodeClass == "a2"
            @test n.vcores == 1
            @test n.mem == 1
            @test !n.hasGPU
        end
        # Test sorting of JuliaHub.nodespecs()
        let ns = JuliaHub.nodespecs()
            @test ns[1].nodeClass == "a2"
            # With identical spec and price, order is not guaranteed
            @test ns[2].nodeClass ∈ ("a1", "a3")
            @test ns[3].nodeClass ∈ ("a1", "a3")
        end
    end
    empty!(MOCK_JULIAHUB_STATE)
end

# This testset uses the show(::IO, ::JuliaHub.ComputeConfig) representation of ComputeConfig,
# makes sure it parses, and then also makes sure it parses into the same object (i.e. all
# fields are restored accurately).
function ComputeConfig_eval_tests(cc::JuliaHub.ComputeConfig)
    cc_expr = Meta.parse(string(cc))
    @test cc_expr.head == :call
    @test cc_expr.args[1] == :(JuliaHub.ComputeConfig)
    @test cc_expr.args[3].head == :call
    # Indirectly, we're also testing the parsing of the nodespec() function
    cc_eval = Mocking.apply(mocking_patch) do
        eval(cc_expr)
    end
    @test cc_eval isa JuliaHub.ComputeConfig
    for fieldname in fieldnames(JuliaHub.ComputeConfig)
        @test getfield(cc_eval, fieldname) == getfield(cc, fieldname)
    end
end

@testset "JuliaHub.ComputeConfig" begin
    let cc = JuliaHub.ComputeConfig(ns_cheapest)
        @test cc.nnodes_max === 1
        @test cc.nnodes_min === nothing
        @test cc.process_per_node === true
        @test cc.elastic === false
        ComputeConfig_eval_tests(cc)
    end
    let cc = JuliaHub.ComputeConfig(ns_cheapest; nnodes=5, elastic=true)
        @test cc.nnodes_max === 5
        @test cc.nnodes_min === nothing
        @test cc.process_per_node === true
        @test cc.elastic === true
        ComputeConfig_eval_tests(cc)
    end
    let cc = JuliaHub.ComputeConfig(ns_cheapest; nnodes=(10, 20))
        @test cc.nnodes_max === 20
        @test cc.nnodes_min === 10
        @test cc.process_per_node === true
        @test cc.elastic === false
        ComputeConfig_eval_tests(cc)
    end
    @test_throws ArgumentError JuliaHub.ComputeConfig(ns_cheapest; nnodes=-20)
    @test_throws ArgumentError JuliaHub.ComputeConfig(ns_cheapest; nnodes=(-5, 3))
    @test_throws ArgumentError JuliaHub.ComputeConfig(ns_cheapest; nnodes=(3, 2))
    @test_throws ArgumentError JuliaHub.ComputeConfig(ns_cheapest; nnodes=(4, 4))
    @test_throws ArgumentError JuliaHub.ComputeConfig(ns_cheapest; nnodes=(5, 10), elastic=true)
end

@testset "JuliaHub.JobStatus" begin
    empty!(JuliaHub._OTHER_JOB_STATES)

    s = JuliaHub.JobStatus("Completed")
    @test_throws JuliaHub.JuliaHubError JuliaHub.JobStatus("completed")
    @test_logs (:warn,) JuliaHub.JobStatus("BadJobState")
    @test_nowarn JuliaHub.JobStatus("BadJobState")

    @test s == s
    @test s == JuliaHub.JobStatus("Completed")
    @test JuliaHub.JobStatus("Completed") == s
    @test s != JuliaHub.JobStatus("Failed")
    @test JuliaHub.JobStatus("Failed") != s
    @test s != JuliaHub.JobStatus("BadJobState")
    @test JuliaHub.JobStatus("BadJobState") != s

    @test s == "Completed"
    @test s != "Failed"
    @test !(@test_logs (:error,) s == "completed")
    @test (@test_logs (:error,) s != "completed")
    @test !(@test_logs (:error,) s == "Completed ")

    @test "Completed" == s
    @test s != "Failed"
    @test !(@test_logs (:error,) "completed" == s)
    @test (@test_logs (:error,) "completed" != s)
    @test !(@test_logs (:error,) "Completed " == s)

    @test @test_logs (:error,) s != :Completed
    @test @test_logs (:error,) s != :completed
    @test !(@test_logs (:error,) s == :Failed)
    @test !(@test_logs (:error,) s == :Finished)
    @test !(@test_logs (:error,) :Completed == s)

    # AbstractString comparisons
    @test s == SubString("Completed", 1:9)
    @test SubString("Completed", 1:9) == s
    @test s != SubString("Failed", 1:6)
    @test SubString("Failed", 1:6) != s
    @test !(@test_logs (:error,) s == SubString("completed", 1:9))
    @test !(@test_logs (:error,) SubString("completed", 1:9) == s)

    local s_convert::JuliaHub.JobStatus
    s_convert = "Completed"
    @test s_convert === JuliaHub.JobStatus("Completed")
end

@testset "JuliaHub.submit_job/s()" begin
    Mocking.apply(mocking_patch) do
        s = JuliaHub.script"run()"
        let jc = JuliaHub.submit_job(s; dryrun=true)
            @test jc isa JuliaHub.WorkloadConfig
            @test jc.app isa JuliaHub.BatchJob
            @test jc.compute.node == ns_cheapest
            @test jc.compute.process_per_node === true
            @test jc.compute.nnodes_max == 1
            @test jc.compute.nnodes_min === nothing
            @test jc.timelimit == JuliaHub._DEFAULT_WorkloadConfig_timelimit
            @test jc.alias === nothing
            @test jc.project === nothing
            @test isempty(jc.env)
        end
        @test JuliaHub.submit_job(s) isa JuliaHub.Job
        # Test passing valid parameters
        kwargs_ns = (; ncpu=4, memory=16, ngpu=1)
        ns = JuliaHub.nodespec(; kwargs_ns...)
        @test ns != ns_cheapest
        kwargs_cc = (; process_per_node=false, nnodes=(3, 10))
        kwargs_rt = (;
            alias="test-job",
            project="e1d9d1d4-814c-4f0c-a3c1-5e063cd2b02b",
            env=Dict("MY_ARGUMENT" => "value"),
            timelimit=5,
        )
        kwargs = (; kwargs_ns..., kwargs_cc..., kwargs_rt...)
        let jc = JuliaHub.submit_job(s; kwargs..., dryrun=true)
            @test jc.compute.node == ns
            @test jc.compute.process_per_node === false
            @test jc.compute.nnodes_max == 10
            @test jc.compute.nnodes_min === 3
            @test jc.timelimit === Dates.Hour(5)
            @test jc.alias == kwargs.alias
            @test jc.project === UUIDs.UUID(kwargs.project)
            @test jc.env == kwargs.env
        end
        cc = JuliaHub.ComputeConfig(ns; kwargs_cc...)
        kwargs_rt = (; kwargs_rt..., timelimit=JuliaHub.Unlimited())
        let jc = JuliaHub.submit_job(s, cc; kwargs_rt..., dryrun=true)
            @test jc.compute.node == ns
            @test jc.compute.process_per_node === false
            @test jc.compute.nnodes_max == 10
            @test jc.compute.nnodes_min === 3
            @test jc.timelimit === JuliaHub.Unlimited()
            @test jc.alias == kwargs.alias
            @test jc.project === UUIDs.UUID(kwargs.project)
            @test jc.env == kwargs.env
        end
        @test JuliaHub.submit_job(s; kwargs...) isa JuliaHub.Job
        # Test argument validation
        @test_throws MethodError JuliaHub.submit_job(s, cc; kwargs...)
        @test_throws ArgumentError JuliaHub.submit_job(s, timelimit=-20)
        @test_throws ArgumentError JuliaHub.submit_job(s, project="123")
        @test_throws ArgumentError JuliaHub.submit_job(s; env=(; jobname="foo"), alias="bar")
        @test_logs (:warn,) JuliaHub.submit_job(s; env=(; jobname="foo"))
        # DEPRECATED: test the name -> alias deprecation logic
        @test_throws ArgumentError JuliaHub.submit_job(s, cc; name="foo", alias="bar")
        let jc = @test_logs (
                :warn,
                "The `name` argument to `submit_job` is deprecated and will be removed in 0.2.0",
            ) JuliaHub.submit_job(s, cc; name="foo", dryrun=true)
            @test jc isa JuliaHub.WorkloadConfig
            @test jc.alias == "foo"
        end
        # TODO: mocked tests that actually check that we submit the correct information
        # to the backend (e.g. by inspecting the returned Job object)
    end
end

@testset "JuliaHub.kill_job" begin
    empty!(MOCK_JULIAHUB_STATE)
    Mocking.apply(mocking_patch) do
        let j = JuliaHub.job("jr-novcmdtiz6")
            @test j.id == "jr-novcmdtiz6"
            @test j.status == "Completed"
        end
        let j = JuliaHub.kill_job("jr-novcmdtiz6")
            @test j isa JuliaHub.Job
            @test j.id == "jr-novcmdtiz6"
            @test j.status == "Stopped"
        end
        let j = JuliaHub.job("jr-novcmdtiz6")
            @test j.id == "jr-novcmdtiz6"
            @test j.status == "Stopped"
        end

        # Killing a non-existent job:
        @test_throws JuliaHub.InvalidRequestError JuliaHub.kill_job("jr-6gk4vuozhl")
    end
end

@testset "JuliaHub.extend_job" begin
    empty!(MOCK_JULIAHUB_STATE)
    Mocking.apply(mocking_patch) do
        let j = JuliaHub.extend_job("jr-cnp3trdmy1", 5)
            @test j isa JuliaHub.Job
            @test j.id == "jr-cnp3trdmy1"
        end
        let j = JuliaHub.extend_job("jr-cnp3trdmy1", Dates.Hour(5))
            @test j isa JuliaHub.Job
            @test j.id == "jr-cnp3trdmy1"
        end
        let j = JuliaHub.extend_job("jr-cnp3trdmy1", Dates.Day(1))
            @test j isa JuliaHub.Job
            @test j.id == "jr-cnp3trdmy1"
        end
        let j = @test_logs (:warn,) JuliaHub.extend_job("jr-cnp3trdmy1", Dates.Second(1))
            @test j isa JuliaHub.Job
            @test j.id == "jr-cnp3trdmy1"
        end
        # Errors
        @test_throws JuliaHub.InvalidRequestError JuliaHub.extend_job("this-job-does-not-exist", 1)
        @test_throws ArgumentError JuliaHub.extend_job("jr-cnp3trdmy1", 0)
        @test_throws ArgumentError JuliaHub.extend_job("jr-cnp3trdmy1", Dates.Hour(0))
        @test_throws ArgumentError JuliaHub.extend_job("jr-cnp3trdmy1", -10)
        @test_throws ArgumentError JuliaHub.extend_job("jr-cnp3trdmy1", Dates.Hour(-10))
        @test_throws ArgumentError JuliaHub.extend_job("jr-cnp3trdmy1", JuliaHub.Unlimited())
    end
end

@testset "JuliaHub.job" begin
    empty!(MOCK_JULIAHUB_STATE)
    Mocking.apply(mocking_patch) do
        @test JuliaHub.job("jr-eezd3arpcj") isa JuliaHub.Job
        @test JuliaHub.job("jr-eezd3arpcj"; throw=false) isa JuliaHub.Job
        @test_throws JuliaHub.InvalidRequestError JuliaHub.job("jr-nonexistent-id")
        @test JuliaHub.job("jr-nonexistent-id"; throw=false) === nothing

        let job = JuliaHub.job("jr-eezd3arpcj")
            @test JuliaHub.job("jr-eezd3arpcj") isa JuliaHub.Job
            @test JuliaHub.job("jr-eezd3arpcj"; throw=false) isa JuliaHub.Job
        end
        let job = JuliaHub.Job(
                Dict(
                    "jobname" => "jr-nonexistent-id",
                    "outputs" => "",
                    "status" => "Running",
                    "inputs" => nothing,
                    "jobname_alias" => nothing,
                    "submittimestamp" => nothing,
                    "starttimestamp" => nothing,
                    "endtimestamp" => nothing,
                ),
            )
            @test_throws JuliaHub.InvalidRequestError JuliaHub.job(job)
            @test JuliaHub.job(job; throw=false) === nothing
        end

        # Handling of invalid job files:
        MOCK_JULIAHUB_STATE[:jobs] = Dict(
            "jr-eezd3arpcj" => Dict{String, Any}(
                "files" => Any[
                    Dict{String, Any}(
                        "name" => "jr-eezd3arpcj-code.jl",
                        "hash" => Dict("algorithm" => nothing, "value" => nothing),
                        "upload_timestamp" => "2022-06-27T19:47:45.37875+00:00",
                        "size" => nothing,
                        "type" => "source",
                    ),
                    Dict(
                        "name" => "jr-eezd3arpcj-test",
                        "hash" => Dict{String, Any}("algorithm" => nothing, "value" => nothing),
                        "upload_timestamp" => "2022-06-27T19:47:45.37875+00:00",
                        "size" => nothing,
                        "type" => "result",
                    ),
                ],
            ),
        )
        let j = JuliaHub.job("jr-eezd3arpcj")
            @test j isa JuliaHub.Job
            @test length(j.files) == 2
            jf = JuliaHub.job_file(j, :source, "jr-eezd3arpcj-code.jl")
            @test jf.filename == "jr-eezd3arpcj-code.jl"
            @test jf.size == 0
            @test jf.hash === nothing
            @test JuliaHub.job_file(j, :source, "jr-eezd3arpcj-test") === nothing
            jf = JuliaHub.job_file(j, :result, "jr-eezd3arpcj-test")
            @test jf.filename == "jr-eezd3arpcj-test"
            @test jf.size == 0
            @test jf.hash === nothing
        end
    end
end

@testset "JuliaHub.download_job_file" begin
    empty!(MOCK_JULIAHUB_STATE)
    Mocking.apply(mocking_patch) do
        job = JuliaHub.job("jr-eezd3arpcj")
        @test length(job.files) == 4
        @test JuliaHub.job_files(job) == job.files
        @test length(JuliaHub.job_files(job, :input)) == 1
        @test length(JuliaHub.job_files(job, :source)) == 1
        @test length(JuliaHub.job_files(job, :project)) == 2
        @test @test_logs (:warn,) JuliaHub.job_files(job, :badcat) |> isempty

        # JuliaHub.job_file
        file = JuliaHub.job_file(job, :input, "code.jl")
        @test file isa JuliaHub.JobFile
        @test file.filename == "code.jl"
        @test file.type === :input
        # Requesting a non-existent file or category returns nothing
        @test JuliaHub.job_file(job, :input, "doesn't exist") === nothing
        @test @test_logs (:warn,) JuliaHub.job_file(job, :badcat, "code.jl") === nothing

        @test JuliaHub.download_job_file(file, tempname()) isa String
        @test JuliaHub.download_job_file(file, IOBuffer()) === nothing
    end
end

function logging_mocking_wrapper(f::Base.Callable, testset_name::AbstractString; legacy=false)
    global MOCK_JULIAHUB_STATE
    logengine = LogEngine(; kafkalogging=!legacy)
    MOCK_JULIAHUB_STATE[:logengine] = logengine
    try
        Mocking.apply(mocking_patch) do
            @testset "$testset_name" begin
                f(logengine)
            end
        end
    finally
        delete!(MOCK_JULIAHUB_STATE, :logengine)
    end
end

JuliaHub._OPTION_LoggingMode[] = JuliaHub._LoggingMode.AUTOMATIC
@testset "Job logs: legacy = $legacy" for legacy in [true, false]
    logging_mocking_wrapper("Basic logging"; legacy=legacy) do logengine
        @testset "Invalid requests" begin
            # Negative offsets are not allowed
            @test_throws ArgumentError JuliaHub.job_logs_buffered("jr-test1"; offset=-1)
            # First, just double check that a missing job 403s on the backend
            @test_throws JuliaHub.PermissionError JuliaHub.job_logs_buffered("jr-test1"; offset=0)
        end
        # Let's check that we are using the correct backend
        @testset "Dispatching on backend" begin
            auth = JuliaHub.current_authentication()
            # If the job is not present, then the Kafka backend will always be disabled
            @test JuliaHub._job_logging_api_version(auth, "jr-test1") == JuliaHub._LegacyLogging()
            # Let's add a finished job without any logs. Since these jobs are marked as finished,
            # we should not add logs to the "backend" after the buffer has been constructed.
            logengine.jobs["jr-test1"] = LogEngineJob([])
            # After the job is added, the expected backend depends on whether we're testing for legacy
            # of the Kafka backend.
            expected_backend = legacy ? JuliaHub._LegacyLogging() : JuliaHub._KafkaLogging()
            @test JuliaHub._job_logging_api_version(auth, "jr-test1") == expected_backend
            # Let's also test the override variable
            JuliaHub._OPTION_LoggingMode[] = JuliaHub._LoggingMode.FORCEKAFKA
            @test JuliaHub._job_logging_api_version(auth, "jr-test1") == JuliaHub._KafkaLogging()
            JuliaHub._OPTION_LoggingMode[] = JuliaHub._LoggingMode.NOKAFKA
            @test JuliaHub._job_logging_api_version(auth, "jr-test1") == JuliaHub._LegacyLogging()
            JuliaHub._OPTION_LoggingMode[] = JuliaHub._LoggingMode.AUTOMATIC
        end
        # Test the fetching of logs
        @testset "Zero logs" begin
            let lb = JuliaHub.job_logs_buffered("jr-test1"; offset=0)
                # Just one check to make sure that the returned buffer actually matches the backend
                # that we're trying to test.
                @test lb isa (legacy ? JuliaHub._LegacyLogsBuffer : JuliaHub.KafkaLogsBuffer)
                @test length(lb.logs) == 0
                @test JuliaHub.hasfirst(lb)
                @test JuliaHub.haslast(lb)
                # Because the first and last are found, these operations should succeed, but be no-ops.
                JuliaHub.job_logs_newer!(lb)
                JuliaHub.job_logs_older!(lb)
                @test length(lb.logs) == 0
                @test JuliaHub.hasfirst(lb)
                @test JuliaHub.haslast(lb)
            end
            # default offset=nothing
            # Note: we don't know if we have first or last message yet.
            # But we should after we try to update the newer and older.
            #
            # TODO: the 6.0 state here is not good
            let lb = JuliaHub.job_logs_buffered("jr-test1")
                @test length(lb.logs) == 0
                JuliaHub.job_logs_newer!(lb)
                @test length(lb.logs) == 0
                @test JuliaHub.haslast(lb)
            end
            let lb = JuliaHub.job_logs_buffered("jr-test1") # default offset=nothing
                @test length(lb.logs) == 0
                JuliaHub.job_logs_older!(lb)
                @test length(lb.logs) == 0
                @test JuliaHub.hasfirst(lb)
            end
            # Requesting a non-existent offset should throw an error
            @test_throws JuliaHub.InvalidRequestError JuliaHub.job_logs_buffered(
                "jr-test1"; offset=1
            )
            @test_throws JuliaHub.InvalidRequestError JuliaHub.job_logs_buffered(
                "jr-test1"; offset=1_000_000
            )
        end

        # Now, let's test with a single log message
        @testset "1 log message" begin
            logengine.jobs["jr-test1"].logs = ["SINGLE"]
            let lb = JuliaHub.job_logs_buffered("jr-test1"; offset=0)
                @test length(lb.logs) == 0
                # Since offset=0, getting older logs is a no-op
                JuliaHub.job_logs_older!(lb)
                @test length(lb.logs) == 0
                @test JuliaHub.hasfirst(lb)
                # Because the first and last are found, these operations should succeed, but be no-ops.
                JuliaHub.job_logs_newer!(lb; count=1)
                @test length(lb.logs) == 1
                @test lb.logs[1].message == "SINGLE"
                @test JuliaHub.hasfirst(lb)
                @test JuliaHub.haslast(lb)
            end
            # As there is only one log (offset=0), requesting offset=1 should throw
            @test_throws JuliaHub.InvalidRequestError JuliaHub.job_logs_buffered(
                "jr-test1"; offset=1
            )
            let lb = JuliaHub.job_logs_buffered("jr-test1")
                @test length(lb.logs) == 0
                JuliaHub.job_logs_newer!(lb; count=1)
                @test length(lb.logs) == 0
                @test JuliaHub.haslast(lb)
                JuliaHub.job_logs_older!(lb)
                @test length(lb.logs) == 1
                @test lb.logs[1].message == "SINGLE"
                @test JuliaHub.hasfirst(lb)
                @test JuliaHub.haslast(lb)
            end
            @test_throws JuliaHub.InvalidRequestError JuliaHub.job_logs_buffered(
                "jr-test1"; offset=2
            )
        end

        # Now let's try the case with a bunch of log messages, which will
        # require multiple fetches.
        @testset "Many log messages" begin
            logengine.jobs["jr-test1"].logs = ["LOG $i" for i = 1:25]
            # Starting from the top
            let lb = JuliaHub.job_logs_buffered("jr-test1"; offset=0)
                @test length(lb.logs) == 0
                @test JuliaHub.hasfirst(lb)
                @test !JuliaHub.haslast(lb)
                # Since offset=0, getting older logs is a no-op
                JuliaHub.job_logs_older!(lb)
                @test length(lb.logs) == 0
                @test JuliaHub.hasfirst(lb)
                @test !JuliaHub.haslast(lb)
                # Because the first and last are found, these operations should succeed, but be no-ops.
                JuliaHub.job_logs_newer!(lb; count=5)
                @test length(lb.logs) == 5
                @test lb.logs[1].message == "LOG 1"
                @test lb.logs[end].message == "LOG 5"
                @test JuliaHub.hasfirst(lb)
                @test !JuliaHub.haslast(lb)
                # Let's now fetch the next 19 logs one by one
                for i = 6:24
                    JuliaHub.job_logs_newer!(lb; count=1)
                    @test length(lb.logs) == i
                    @test lb.logs[1].message == "LOG 1"
                    @test lb.logs[end].message == "LOG $i"
                    @test JuliaHub.hasfirst(lb)
                    @test !JuliaHub.haslast(lb)
                end
                # And let's now fetch a bunch more, but we should only receive one.
                JuliaHub.job_logs_newer!(lb; count=100)
                @test length(lb.logs) == 25
                @test lb.logs[1].message == "LOG 1"
                @test lb.logs[end].message == "LOG 25"
                @test JuliaHub.hasfirst(lb)
                @test JuliaHub.haslast(lb)
            end
            # Starting from the end
            let lb = JuliaHub.job_logs_buffered("jr-test1")
                @test length(lb.logs) == 0
                @test !JuliaHub.hasfirst(lb)
                @test JuliaHub.haslast(lb) # because it's a finished job
                # Fetch 15 older logs
                JuliaHub.job_logs_older!(lb; count=15)
                @test length(lb.logs) == 15
                @test lb.logs[1].message == "LOG 11"
                @test lb.logs[end].message == "LOG 25"
                @test !JuliaHub.hasfirst(lb)
                @test JuliaHub.haslast(lb)
                # And another one..
                JuliaHub.job_logs_older!(lb; count=1)
                @test length(lb.logs) == 16
                @test lb.logs[1].message == "LOG 10"
                @test lb.logs[end].message == "LOG 25"
                @test !JuliaHub.hasfirst(lb)
                @test JuliaHub.haslast(lb)
                # And then all the way to the start
                JuliaHub.job_logs_older!(lb)
                @test length(lb.logs) == 25
                @test lb.logs[1].message == "LOG 1"
                @test lb.logs[end].message == "LOG 25"
                @test JuliaHub.hasfirst(lb)
                @test JuliaHub.haslast(lb)
                # newer! is still a no-op
                JuliaHub.job_logs_newer!(lb)
                JuliaHub.job_logs_newer!(lb; count=1)
                JuliaHub.job_logs_newer!(lb; count=1_000_000)
                @test length(lb.logs) == 25
                @test lb.logs[1].message == "LOG 1"
                @test lb.logs[end].message == "LOG 25"
                @test JuliaHub.hasfirst(lb)
                @test JuliaHub.haslast(lb)
            end
            # And starting from the middle. Conceptually, at the start, the cursor
            # should be just before offset=17, so the first newer log will be offset=17
            # log.. which is LOG 18, since the indexing starts at 1.
            let lb = JuliaHub.job_logs_buffered("jr-test1"; offset=17)
                @test length(lb.logs) == 0
                @test !JuliaHub.hasfirst(lb)
                @test !JuliaHub.haslast(lb) # because it's a finished job
                # Fetch older and newer longs mixedly
                JuliaHub.job_logs_older!(lb; count=1)
                @test length(lb.logs) == 1
                # Since we're moving backwards, we are fetching LOG 17 with older!
                @test lb.logs[1].message == "LOG 17"
                @test !JuliaHub.hasfirst(lb)
                @test !JuliaHub.haslast(lb)

                JuliaHub.job_logs_newer!(lb; count=3)
                @test length(lb.logs) == 4
                @test lb.logs[1].message == "LOG 17"
                @test lb.logs[end].message == "LOG 20"
                @test !JuliaHub.hasfirst(lb)
                @test !JuliaHub.haslast(lb)

                JuliaHub.job_logs_older!(lb; count=2)
                @test length(lb.logs) == 6
                @test lb.logs[1].message == "LOG 15"
                @test lb.logs[end].message == "LOG 20"
                @test !JuliaHub.hasfirst(lb)
                @test !JuliaHub.haslast(lb)
                # And now run all the way to the end, both ways
                JuliaHub.job_logs_older!(lb)
                @test length(lb.logs) == 20
                @test lb.logs[1].message == "LOG 1"
                @test lb.logs[end].message == "LOG 20"
                @test JuliaHub.hasfirst(lb)
                @test !JuliaHub.haslast(lb)

                JuliaHub.job_logs_newer!(lb)
                @test length(lb.logs) == 25
                @test lb.logs[1].message == "LOG 1"
                @test lb.logs[end].message == "LOG 25"
                @test JuliaHub.hasfirst(lb)
                @test JuliaHub.haslast(lb)
            end
            # Explicitly checking that offset=1 leads to LOG 2
            let lb = JuliaHub.job_logs_buffered("jr-test1"; offset=1)
                JuliaHub.job_logs_newer!(lb; count=1)
                @test length(lb.logs) == 1
                @test lb.logs[1].message == "LOG 2"
            end
            # Also checking that starting by moving forward makes sense at higher offset
            let lb = JuliaHub.job_logs_buffered("jr-test1"; offset=17)
                @test length(lb.logs) == 0
                @test !JuliaHub.hasfirst(lb)
                @test !JuliaHub.haslast(lb) # because it's a finished job
                JuliaHub.job_logs_newer!(lb; count=1)
                @test length(lb.logs) == 1
                @test lb.logs[1].message == "LOG 18"
                @test !JuliaHub.hasfirst(lb)
                @test !JuliaHub.haslast(lb)
            end
        end

        # Test that the callback gets called correctly
        @testset "Callback" begin
            logengine.jobs["jr-test1"].logs = ["LOG $i" for i = 1:25]
            cb_results = []
            lb = JuliaHub.job_logs_buffered(
                "jr-test1"; offset=6
            ) do buffer::JuliaHub.AbstractJobLogsBuffer,
            logs::AbstractVector{JuliaHub.JobLogMessage}
                push!(cb_results, (first(logs).message, length(logs), last(logs).message))
            end
            JuliaHub.job_logs_newer!(lb; count=12)
            JuliaHub.job_logs_older!(lb; count=1)
            JuliaHub.job_logs_newer!(lb)
            JuliaHub.job_logs_older!(lb)
            @test length(cb_results) == 4
            @test cb_results[1] == ("LOG 7", 12, "LOG 18")
            @test cb_results[2] == ("LOG 6", 13, "LOG 18")
            @test cb_results[3] == ("LOG 6", 20, "LOG 25")
            @test cb_results[4] == ("LOG 1", 25, "LOG 25")
            @test JuliaHub.hasfirst(lb)
            @test JuliaHub.haslast(lb)
        end
    end
end
JuliaHub._OPTION_LoggingMode[] = JuliaHub._LoggingMode.NOKAFKA
