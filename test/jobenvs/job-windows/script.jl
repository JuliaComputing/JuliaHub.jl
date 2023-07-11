import TOML, SHA

# Check for the appbundle file
datafile = joinpath(@__DIR__, "appbundle", "datafile.txt")
datafile_fallback = joinpath(@__DIR__, "datafile.txt")
datafile_hash, fallback = if isfile(datafile)
    bytes2hex(open(SHA.sha1, datafile)), false
elseif isfile(datafile_fallback)
    @warn "Using fallback datafile path" datafile_fallback
    bytes2hex(open(SHA.sha1, datafile_fallback)), true
else
    nothing, nothing
end

results = """
{
    "datafile_hash": "$datafile_hash",
    "datafile_fallback": $fallback,
    "iswindows": $(Sys.iswindows())
}
"""
@info "Storing RESULTS:\n$(results)"
ENV["RESULTS"] = results
