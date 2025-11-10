using Oxygen, HTTP

# Environment variable name `PORT` was used in older JuliaHub environments
# and has been replaced with `JULIAHUB_APP_PORT` in newer environments 
const PORT = parse(Int, get(ENV, "JULIAHUB_APP_PORT", ENV["PORT"]))
const NREQUESTS = Ref{Int}(0)

function results_json()
    input = get(ENV, "TEST_INPUT", nothing)
    input_escaped = if isnothing(input)
        "null"
    else
        string('"', replace(input, '"' => "\\\""), '"')
    end
    return """
    {
        "success": true,
        "port": $(PORT),
        "input": $(input_escaped),
        "nrequests": $(NREQUESTS[])
    }
    """
end

@get "/" function (req::HTTP.Request)
    NREQUESTS[] += 1
    return results_json()
end

@info "Starting server..." PORT
serve(; host="0.0.0.0", port=PORT)

@info "Exiting the server"
ENV["RESULTS"] = results_json()
if haskey(ENV, "JULIAHUB_RESULTS_SUMMARY_FILE")
    open(ENV["JULIAHUB_RESULTS_SUMMARY_FILE"], "w") do io
        write(io, ENV["RESULTS"])
    end
end
println(ENV["RESULTS"])
