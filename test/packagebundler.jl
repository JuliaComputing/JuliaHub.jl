import Tar

# We have to copy the test environment files to a temporary directory
# because PackageBundler needs write access to them.
TMP_FIXTURES = let tmp = tempname()
    cp(joinpath(@__DIR__, "fixtures"), tmp)
    chmod(tmp, 0o777; recursive=true)
    tmp
end

pkg1 = joinpath(TMP_FIXTURES, "ignorefiles", "Pkg1")
if !isdir(joinpath(pkg1, ".git"))
    mkdir(joinpath(pkg1, ".git")) # can't check in sub-repos
    touch(joinpath(pkg1, ".git", "test"))
end

@testset "bundle.standard" begin
    bundle = "bundle.standard"
    bundle_env = joinpath(pkg1, bundle)
    out = tempname()
    JuliaHub._PackageBundler.bundle(
        bundle_env;
        output=out,
        verbose=false,
    )
    dir = mktempdir()
    Tar.extract(out, dir)

    @test isfile(joinpath(dir, bundle, "Manifest.toml"))
    @test isfile(joinpath(dir, bundle, "Project.toml"))
    @test isfile(joinpath(dir, bundle, "run.jl"))
    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", "src", "Pkg1.jl"))
    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "src", "Pkg2.jl"))
    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "Pkg3.jl"))

    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blah"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blah", "test"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blub"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blub", "test"))

    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "bar"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "bar"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "bar", "test"))

    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "foo"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "foo"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "foo", "test"))
    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "fooo"))
    @test isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "fooo"))
    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "fooo", "test"))

    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", ".git")) # always ignored
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", ".git", "test")) # always ignored
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", "README.md")) # in .juliabundleignore
end

@testset "bundle.noproject-throw" begin
    bundle = "bundle.noproject-throw"
    bundle_env = joinpath(pkg1, bundle)
    out = tempname()
    expected_error = (VERSION > v"1.8") ? "Could not find project at" : ErrorException
    @test_throws expected_error JuliaHub._PackageBundler.bundle(
        bundle_env;
        output=out,
        verbose=false,
        # using default allownoenv=false
    )
end

@testset "bundle.noproject" begin
    bundle = "bundle.noproject"
    bundle_env = joinpath(pkg1, bundle)
    out = tempname()
    JuliaHub._PackageBundler.bundle(
        bundle_env;
        output=out,
        verbose=false,
        allownoenv=true,
    )
    dir = mktempdir()
    Tar.extract(out, dir)

    @test isfile(joinpath(dir, bundle, "Manifest.toml"))
    @test isfile(joinpath(dir, bundle, "Project.toml"))
    @test isfile(joinpath(dir, bundle, "run.jl"))
    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", "src", "Pkg1.jl"))
    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "src", "Pkg2.jl"))
    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "Pkg3.jl"))

    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blah"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blah", "test"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blub"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blub", "test"))

    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "bar"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "bar"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "bar", "test"))

    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "foo"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "foo"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "foo", "test"))
    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "fooo"))
    @test isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "fooo"))
    @test isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "fooo", "test"))

    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", ".git")) # always ignored
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", ".git", "test")) # always ignored
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", "README.md")) # in .juliabundleignore
end

# This test does not include any of the `Pkg*` packages as dependencies (since we can't
# resolve them based on the Project.toml alone).
@testset "bundle.nomanifest" begin
    bundle = "bundle.nomanifest"
    bundle_env = joinpath(pkg1, bundle)
    out = tempname()
    # Using match_mode=:any, since it's possible for the Pkg operations to produce other additional
    # log messages, breaking the tests.
    @test_logs (:warn,) match_mode = :any JuliaHub._PackageBundler.bundle(
        bundle_env;
        output=out,
        verbose=false,
    )
    dir = mktempdir()
    Tar.extract(out, dir)

    @test isfile(joinpath(dir, bundle, "Manifest.toml"))
    @test isfile(joinpath(dir, bundle, "Project.toml"))
    @test isfile(joinpath(dir, bundle, "run.jl"))

    # None of the dependencies will be copied over in this test.
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", "src", "Pkg1.jl"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "src", "Pkg2.jl"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "Pkg3.jl"))

    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blah"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blah", "test"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blub"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blub", "test"))

    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "bar"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "bar"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "bar", "test"))

    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "foo"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "foo"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "foo", "test"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "fooo"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "fooo"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "fooo", "test"))

    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", ".git")) # always ignored
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", ".git", "test")) # always ignored
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", "README.md")) # in .juliabundleignore
end

@testset "bundle.noenv-throw" begin
    bundle = "bundle.noenv-throw"
    bundle_env = joinpath(pkg1, bundle)
    out = tempname()
    expected_error = (VERSION > v"1.8") ? "Could not find project at" : ErrorException
    @test_throws expected_error JuliaHub._PackageBundler.bundle(
        bundle_env;
        output=out,
        verbose=false,
        # using default allownoenv=false
    )
end

@testset "bundle.noenv" begin
    bundle = "bundle.noenv"
    bundle_env = joinpath(pkg1, bundle)
    out = tempname()
    # Using match_mode=:any, since it's possible for the Pkg operations to produce other additional
    # log messages, breaking the tests.
    @test_logs (:warn,) match_mode = :any JuliaHub._PackageBundler.bundle(
        bundle_env;
        output=out,
        verbose=false,
        allownoenv=true,
    )
    dir = mktempdir()
    Tar.extract(out, dir)

    @test isfile(joinpath(dir, bundle, "Manifest.toml"))
    @test isfile(joinpath(dir, bundle, "Project.toml"))
    @test isfile(joinpath(dir, bundle, "run.jl"))

    # None of the dependencies will be copied over in this test.
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", "src", "Pkg1.jl"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "src", "Pkg2.jl"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "Pkg3.jl"))

    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blah"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blah", "test"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blub"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg2", "test", "blub", "test"))

    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "bar"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "bar"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "bar", "test"))

    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "foo"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "foo"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "foo", "test"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "src", "fooo"))
    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "fooo"))
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg3", "test", "fooo", "test"))

    @test !isdir(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", ".git")) # always ignored
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", ".git", "test")) # always ignored
    @test !isfile(joinpath(dir, bundle, ".bundle", "dev", "Pkg1", "README.md")) # in .juliabundleignore
end

@testset "bundle.standard (relative path)" begin
    bundle = "bundle.standard"
    bundle_env = joinpath(pkg1, bundle)
    out = tempname()
    cd(bundle_env) do
        JuliaHub._PackageBundler.bundle(
            ".";
            output=out,
            verbose=false,
        )
    end
    @test isfile(out)
end

@testset "path_filterer" begin
    @testset "subdirectory" begin
        dir = joinpath(@__DIR__, "fixtures", "ignorefiles")
        pred = JuliaHub._PackageBundler.path_filterer(dir)
        @test pred(joinpath(dir, "Pkg3", "README.md"))

        @test pred(joinpath(dir, "Pkg3", "src", "bar"))
        @test !pred(joinpath(dir, "Pkg3", "src", "foo"))
        @test pred(joinpath(dir, "Pkg3", "src", "fooo"))

        @test !pred(joinpath(dir, "Pkg3", "test", "bar"))
        @test !pred(joinpath(dir, "Pkg3", "test", "foo"))
        @test pred(joinpath(dir, "Pkg3", "test", "fooo", "test"))

        # Note: even though the test/foo and test/bar directories are
        # excluded, the predicate function does not return false if you
        # check for file within the directories.
        @test pred(joinpath(dir, "Pkg3", "test", "bar", "test"))
        @test pred(joinpath(dir, "Pkg3", "test", "foo", "test"))
    end
    @testset "toplevel" begin
        dir = joinpath(@__DIR__, "fixtures", "ignorefiles", "Pkg3")
        pred = JuliaHub._PackageBundler.path_filterer(dir)
        @test pred(joinpath(dir, "README.md"))

        @test pred(joinpath(dir, "src", "bar"))
        @test !pred(joinpath(dir, "src", "foo"))
        @test pred(joinpath(dir, "src", "fooo"))

        @test !pred(joinpath(dir, "test", "bar"))
        @test !pred(joinpath(dir, "test", "foo"))
        @test pred(joinpath(dir, "test", "fooo", "test"))

        # Note: even though the test/foo and test/bar directories are
        # excluded, the predicate function does not return false if you
        # check for file within the directories.
        @test pred(joinpath(dir, "test", "bar", "test"))
        @test pred(joinpath(dir, "test", "foo", "test"))
    end
end
