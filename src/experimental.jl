"""
    module Experimental

Home for experimental JuliaHub.jl APIs.

!!! warning "Unstable APIs"

    These APIs are considered highly unstable.
    Both JuliaHub platform version changes, and also JuliaHub.jl package changes may break these APIs at any time.
    Depend on them at your own peril.
"""
module Experimental

using UUIDs: UUIDs

const _DOCS_EXPERIMENTAL_API = """
!!! warning "Unstable API"
    This API is not part of the public API and does not adhere to semantic versioning.

    This APIs is considered highly unstable.
    Both JuliaHub platform version changes, and also JuliaHub.jl package changes may break it at any time.
    Depend on it at your own peril.
"""

"""
    struct Registry

Represents a Julia package registry on JuliaHub.

$(_DOCS_EXPERIMENTAL_API)
"""
struct Registry
    uuid::UUIDs.UUID
    name::String
end

function registries end
function register_package end

end
