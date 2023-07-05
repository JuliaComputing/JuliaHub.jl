import JET, JuliaHub
using Test

@testset "JET" begin
    JET.test_package("JuliaHub"; target_defined_modules=true, mode=:typo)
end
