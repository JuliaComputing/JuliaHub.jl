import JET, JuliaHub
using Test

jet_mode = Symbol(get(ENV, "JULIAHUB_TEST_JET", "typo"))
@info "Running JET.jl in mode=:$(jet_mode)"

@testset "JET" begin
    JET.test_package("JuliaHub"; target_defined_modules=true, mode=jet_mode)
end
