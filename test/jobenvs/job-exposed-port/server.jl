using Oxygen, HTTP

const PORT = parse(Int, ENV["PORT"])
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
println(ENV["RESULTS"])
