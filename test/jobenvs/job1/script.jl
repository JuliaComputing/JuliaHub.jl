import DataStructures, JSON, TOML, SHA

projecttoml = joinpath(dirname(pathof(DataStructures)), "..", "Project.toml")
toml = TOML.parsefile(projecttoml)
datastructures_version = toml["version"]

# Check for the appbundle file
datafile = joinpath(@__DIR__, "datafile.txt")
datafile_hash = if isfile(datafile)
    bytes2hex(open(SHA.sha1, datafile))
end

# Try to load dependencies with relative paths:
script_include_success = try
    include("my-dependent-script.jl")
    include("subdir/my-dependent-script-2.jl")
    true
catch e
    e isa SystemError || rethrow()
    @error "Unable to load"
    false
end

results = Dict(
    "datastructures_version" => datastructures_version,
    "datafile_hash" => datafile_hash,
    "iswindows" => Sys.iswindows(),
    "scripts" => Dict(
        "include_success" => script_include_success,
        "script_1" => isdefined(Main, :MY_DEPENDENT_SCRIPT_1),
        "script_2" => isdefined(Main, :MY_DEPENDENT_SCRIPT_2),
    ),
)

@info "Storing RESULTS:\n$(results)"
ENV["RESULTS"] = JSON.json(results)
