module JuliaHub
import Base64
import Dates
import HTTP
import JSON
import Mocking
import Pkg
import PkgAuthentication
import Rclone_jll
import SHA
import TimeZones
import TOML
import URIs
using UUIDs: UUIDs, UUID

# We cache the local timezone in a global, so that we don't have to call
# TimeZones.localzone() every time we do a TZ operation. However, we only
# populate this when we actually call _localtz(). We used to do this in __init_,
# but that caused a noticeable startup lag.
const _LOCAL_TZ = Ref{Dates.TimeZone}()

include("utils.jl")
include("authentication.jl")
include("restapi.jl")
include("userinfo.jl")
include("applications.jl")
include("batchimages.jl")
include("datasets.jl")
include("node.jl")
include("jobsubmission.jl")
include("PackageBundler/PackageBundler.jl")
include("jobs/jobs.jl")
include("jobs/request.jl")
include("jobs/logging.jl")
include("jobs/logging-kafka.jl")
include("jobs/logging-legacy.jl")
include("projects.jl")

# JuliaHub.jl follows the convention that all private names are
# prefixed with an underscore.
function _find_public_names()
    return filter(names(@__MODULE__; all=true)) do s
        # We don't need to check or mark public the main module itself
        (s == :JuliaHub) && return false
        startswith(string(s), "_") && return false
        # Internal functions and types, prefixed by _
        startswith(string(s), "_") && return false
        # Internal macros, prefixed by _
        startswith(string(s), "@_") && return false
        # Strange generated functions
        startswith(string(s), "#") && return false
        # Some core functions that are not relevant for the package
        s in [:eval, :include] && return false
        return true
    end
end
macro _mark_names_public()
    if !Base.isdefined(Base, :ispublic)
        return nothing
    end
    public_names = _find_public_names()
    return esc(Expr(:public, public_names...))
end
@_mark_names_public

end
