pkg1 = joinpath(@__DIR__, "fixtures", "ignorefiles", "Pkg1")
if !isdir(joinpath(pkg1, ".git"))
    mkdir(joinpath(pkg1, ".git")) # can't check in sub-repos
    touch(joinpath(pkg1, ".git", "test"))
end

bundle_env = joinpath(pkg1, "bin")

out = tempname()
JuliaHub._PackageBundler.bundle(
    bundle_env;
    output=out,
    verbose=false,
)
dir = mktempdir()
run(`tar -xf $out -C $dir`)

@test isfile(joinpath(dir, "bin", "Manifest.toml"))
@test isfile(joinpath(dir, "bin", "Project.toml"))
@test isfile(joinpath(dir, "bin", "run.jl"))
@test isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg1", "src", "Pkg1.jl"))
@test isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg2", "src", "Pkg2.jl"))
@test isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg3", "src", "Pkg3.jl"))

@test !isdir(joinpath(dir, "bin", ".bundle", "dev", "Pkg2", "test", "blah"))
@test !isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg2", "test", "blah", "test"))
@test !isdir(joinpath(dir, "bin", ".bundle", "dev", "Pkg2", "test", "blub"))
@test !isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg2", "test", "blub", "test"))

@test isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg3", "src", "bar"))
@test !isdir(joinpath(dir, "bin", ".bundle", "dev", "Pkg3", "test", "bar"))
@test !isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg3", "test", "bar", "test"))

@test !isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg3", "src", "foo"))
@test !isdir(joinpath(dir, "bin", ".bundle", "dev", "Pkg3", "test", "foo"))
@test !isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg3", "test", "foo", "test"))
@test isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg3", "src", "fooo"))
@test isdir(joinpath(dir, "bin", ".bundle", "dev", "Pkg3", "test", "fooo"))
@test isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg3", "test", "fooo", "test"))

@test !isdir(joinpath(dir, "bin", ".bundle", "dev", "Pkg1", ".git")) # always ignored
@test !isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg1", ".git", "test")) # always ignored
@test !isfile(joinpath(dir, "bin", ".bundle", "dev", "Pkg1", "README.md")) # in .juliabundleignore
