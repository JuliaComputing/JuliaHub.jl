import DataStructures, JSON, TOML, SHA

projecttoml = joinpath(dirname(pathof(DataStructures)), "..", "Project.toml")
toml = TOML.parsefile(projecttoml)
datastructures_version = toml["version"]

# Check for the appbundle file
datafile = joinpath(pwd(), "appbundle", "datafile.txt")
datafile_hash = if isfile(datafile)
    bytes2hex(open(SHA.sha1, datafile))
end

results = Dict(
    "datastructures_version" => datastructures_version,
    "datafile_hash" => datafile_hash,
    "iswindows" => Sys.iswindows(),
)

@info "Storing RESULTS:\n$(results)"
ENV["RESULTS"] = JSON.json(results)
