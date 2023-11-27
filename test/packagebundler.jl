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

@testset let bundle = "bundle.standard"
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

@testset let bundle = "bundle.noproject-throw"
    bundle_env = joinpath(pkg1, bundle)
    out = tempname()
    @test_throws "Could not find project at" JuliaHub._PackageBundler.bundle(
        bundle_env;
        output=out,
        verbose=false,
        # using default allownoenv=false
    )
end

@testset let bundle = "bundle.noproject"
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
@testset let bundle = "bundle.nomanifest"
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

@testset let bundle = "bundle.noenv-throw"
    bundle_env = joinpath(pkg1, bundle)
    out = tempname()
    @test_throws "Could not find project at" JuliaHub._PackageBundler.bundle(
        bundle_env;
        output=out,
        verbose=false,
        # using default allownoenv=false
    )
end

@testset let bundle = "bundle.noenv"
    bundle_env = joinpath(pkg1, bundle)
    out = tempname()
    @test_logs (:warn,) JuliaHub._PackageBundler.bundle(
        bundle_env;
        output=out,
        verbose=false,
        allownoenv=true
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
