using Distributed, JSON
@everywhere using Distributed
@everywhere fn() = (myid(), strip(read(`hostname`, String)))
fs = [i => remotecall(fn, i) for i in workers()]
vs = map(fs) do (i, future)
    myid, hostname = fetch(future)
    @info "$i: $myid, $hostname"
    (; myid, hostname)
end
ENV["RESULTS"] = JSON.json((; vs))
