
"""
    struct NodeSpec

Stores information about a compute node that can be allocated for JuliaHub jobs. The
list of all available node specifications can be accessed with [`nodespecs`](@ref),
or specific ones searched with [`nodespec`](@ref).

```jldoctest
julia> JuliaHub.nodespec()
Node: 3.5 GHz Intel Xeon Platinum 8375C
 - GPU: no
 - vCores: 2
 - Memory: 8 Gb
 - Price: 0.17 \$/hr
```

They can be used to contruct explicit compute configuration objects when submitting JuliaHub jobs.

See also: [`submit_job`](@ref), [`ComputeConfig`](@ref).
"""
struct NodeSpec
    nodeClass::String
    hasGPU::Bool
    vcores::Int
    mem::Int
    priceHr::Float64
    desc::String
    memDisplay::String
    _id::Int

    function NodeSpec(n::Vector)
        @assert length(n) >= 6
        nodeclass = n[1]
        gpu = n[2]
        ncpu = _nodespec_int_idx(n, 3; name="vcores")
        mem = _nodespec_int_idx(n, 4; name="mem")
        nodespec_id = _nodespec_int_idx(n, 11; name="id")
        price = n[5]
        description = n[6]
        memdisplay = n[8] # ???
        new(nodeclass, gpu, ncpu, mem, price, description, memdisplay, nodespec_id)
    end
end

function _nodespec_int_idx(xs::Vector, idx::Integer; name::AbstractString)
    try
        Int(xs[idx])
    catch e
        e isa InexactError || rethrow(e)
        throw(JuliaHubError("Invalid non-integer `$name` value at $idx for node spec: $(xs)"))
    end
end

function Base.show(io::IO, node::NodeSpec)
    print(io, "JuliaHub.nodespec(")
    print(io, "#= $(node.nodeClass): $(node.desc), $(node.priceHr)/hr =#")
    print(io, "; ncpu=$(node.vcores), memory=$(node.mem), ngpu=$(node.hasGPU), exactmatch=true)")
end

function Base.show(io::IO, ::MIME"text/plain", node::NodeSpec)
    printstyled(io, "Node: "; bold=true)
    println(io, node.desc)
    printstyled(io, " - GPU: "; bold=true)
    println(io, node.hasGPU ? "yes" : "no")
    printstyled(io, " - vCores: "; bold=true)
    println(io, node.vcores)
    printstyled(io, " - Memory: "; bold=true)
    println(io, node.mem, " Gb")
    printstyled(io, " - Price: "; bold=true)
    print(io, node.priceHr, " \$/hr")
end

"""
    JuliaHub.nodespecs(; auth::Authentication) -> Vector{NodeSpec}

Query node specifications available on the current server, returning a list of
[`NodeSpec`](@ref) objects.
"""
function nodespecs(; auth::Authentication=__auth__())
    r = _api_nodespecs(auth)
    if r.status == 200
        try
            json = JSON.parse(String(r.body); dicttype=Dict)
            if json["success"]
                nodes = [
                    NodeSpec(n) for n in json["node_specs"]
                ]
                # We'll sort the list using the same logic that _nodespec_smallest uses, so that
                # the result would not depend in backend response ordering. But whether the list
                # is sort, or based on what criteria is not documented, and is considered to be
                # an implementation detail.
                return sort(nodes; by=_nodespec_cmp_by)
            end
        catch err
            throw(JuliaHubError("Unexpected answer received."))
        end
    end
    return _throw_invalidresponse(r)
end

_api_nodespecs(auth::Authentication) =
    _restcall(auth, :GET, "app", "config", "nodespecs", "info")

"""
    JuliaHub.nodespec(
        [nodes::Vector{NodeSpec}];
        ncpu::Integer=1, ngpu::Integer=false, memory::Integer=1,
        exactmatch::Bool=false, throw::Bool=true,
        [auth::Authentication]
    ) -> Union{NodeSpec, Nothing}

Finds the node matching the specified node parameters. Throws an [`InvalidRequestError`](@ref)
if it is unable to find a node with the specific parameters. However, if `throw` is set to
`false`, it will return `nothing` instead in that situation.

By default, it searches for the smallest node that has the at least the specified parameters
(prioritizing GPU count, CPU count, and memory in this order when deciding).
If `exactmatch` is set to `true`, it only returns a node specification if it can find one that
matches the parameters exactly.

A list of nodes (e.g. from [`nodespecs`](@ref)) can also be passed, so that the function
does not have to query the server for the list. When this method is used, it is not necessary
to pass `auth`.
"""
function nodespec end

# These values are re-used in submit_job
const _DEFAULT_NodeSpec_ncpu = 1
const _DEFAULT_NodeSpec_ngpu = 0
const _DEFAULT_NodeSpec_memory = 1

nodespec(; auth::Authentication=__auth__(), kwargs...) =
    nodespec(nodespecs(; auth); kwargs...)

function nodespec(
    nodes::Vector{NodeSpec};
    ncpu::Integer=_DEFAULT_NodeSpec_ncpu,
    ngpu::Integer=_DEFAULT_NodeSpec_ngpu,
    memory::Integer=_DEFAULT_NodeSpec_memory,
    exactmatch::Bool=false,
    throw::Bool=true,
    # auth is actually unused, since we only need it to call nodespecs()
    # in the other method; but it's valid to pass here too
    auth::Union{Authentication, Nothing}=nothing,
)
    ncpu < 1 && Base.throw(ArgumentError("ncpu must be >= 1"))
    ngpu < 0 && Base.throw(ArgumentError("ngpu must be >= 0"))
    memory < 1 && Base.throw(ArgumentError("memory must be >= 1"))
    if ngpu >= 2
        return _throw_or_nothing(; msg="JuliaHub.jl does not support multi-GPU nodes", throw) do msg
            @warn msg
        end
    end
    has_gpu = ngpu != 0
    if exactmatch
        _nodespec_exact(nodes; ncpu, memory, gpu=has_gpu, throw)
    else
        _nodespec_smallest(nodes; ncpu, memory, gpu=has_gpu, throw)
    end
end

function _nodespec_exact(
    nodes::Vector{NodeSpec}; ncpu::Integer, memory::Integer, gpu::Bool, throw::Bool
)
    nodematches =
        n::NodeSpec ->
            (gpu && n.hasGPU || !gpu && !n.hasGPU) && (ncpu == n.vcores) && (memory == n.mem)
    idxs = findall(nodematches, nodes)
    if isempty(idxs)
        return _throw_or_nothing(;
            msg="Unable to find a nodespec: ncpu=$ncpu memory=$memory gpu=$gpu",
            throw,
        )
    end
    if length(idxs) > 1
        @warn "Multiple node specs matching exact match query, picking an arbitrary one." ncpu memory gpu nodes = nodes[idxs]
    end
    return nodes[first(idxs)]
end

function _nodespec_smallest(
    nodes::Vector{NodeSpec}; ncpu::Integer, memory::Integer, gpu::Bool, throw::Bool
)
    # Note: while JuliaHub.nodespecs() does return a sorted list, we can not assume that
    # here, since the user can pass their own list which might not be sorted.
    nodes = sort(nodes; by=_nodespec_cmp_by)
    idx = findfirst(nodes) do n
        # !gpu || n.hasGPU <=> gpu => n.hasGPU
        (!gpu || n.hasGPU) && (n.vcores >= ncpu) && (n.mem >= memory)
    end
    if isnothing(idx)
        return _throw_or_nothing(;
            msg="Unable to find a nodespec with at least: ncpu=$ncpu memory=$memory gpu=$gpu",
            throw,
        )
    else
        return nodes[idx]
    end
end

# This representation of a NodeSpec is used when comparing them to find the "smallest".
# Node's hourly price is just used to disambiguate if there are two nodes that are
# otherwise equal (in terms of GPU, CPU and memory numbers).
_nodespec_cmp_by(n::NodeSpec) = (n.hasGPU, n.vcores, n.mem, n.priceHr)
