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
import UUIDs

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

function __init__()
    # We'll only attempt to determine the local timezone once, when the package loads,
    # and store the result in a global. This way all timestamps will have consistent timezones
    # even if something in the environment changes.
    _LOCAL_TZ[] = _localtz()
end

end
