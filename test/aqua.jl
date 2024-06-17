import Aqua
import JuliaHub
using Test

@testset "Aqua" begin
    Aqua.test_all(
        JuliaHub;
        # These ambiguities are introduced by InlineStrings
        # https://github.com/JuliaStrings/InlineStrings.jl/issues/71
        ambiguities=(;
            exclude=[
                Base.rstrip,
                Base.lstrip,
                Base.unsafe_convert,
                Base.Sort.defalg,
            ],
        ),
        # Aqua detects missing standard library compat entries, but setting these
        # is problematic if we want to support 1.6
        # https://discourse.julialang.org/t/psa-compat-requirements-in-the-general-registry-are-changing/104958
        deps_compat=(; broken=true, check_extras=false),
    )
end
