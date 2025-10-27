using Distributed, JSON, JuliaHubDistributed

JuliaHubDistributed.start()
JuliaHubDistributed.wait_for_workers()

@everywhere using Distributed
@everywhere fn() = (myid(), strip(read(`hostname`, String)))
fs = [i => remotecall(fn, i) for i in workers()]
vs = map(fs) do (i, future)
    myid, hostname = fetch(future)
    @info "$i: $myid, $hostname"
    (; myid, hostname)
end
ENV["RESULTS"] = JSON.json((; vs))
if haskey(ENV, "JULIAHUB_RESULTS_SUMMARY_FILE")
    open(ENV["JULIAHUB_RESULTS_SUMMARY_FILE"], "w") do io
        write(io, ENV["RESULTS"])
    end
end