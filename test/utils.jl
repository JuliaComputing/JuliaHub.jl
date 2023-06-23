using Test

@testset "@_httpcatch" begin
    throw_connecterror() = throw(HTTP.Exceptions.ConnectError("", nothing))
    @test JuliaHub.@_httpcatch(nothing) === nothing
    @test JuliaHub.@_httpcatch(nothing, msg = "...") === nothing
    msgortype(x) =
        VERSION >= v"1.8" ? "JuliaHubConnectionError: $x" : JuliaHub.JuliaHubConnectionError
    @test_throws msgortype("HTTP connection to JuliaHub failed (HTTP.Exceptions.ConnectError)") JuliaHub.@_httpcatch(
        throw_connecterror()
    )
    @test_throws msgortype(
        "Custom message\nHTTP connection to JuliaHub failed (HTTP.Exceptions.ConnectError)"
    ) JuliaHub.@_httpcatch(
        throw_connecterror(), msg = "Custom message"
    )
    @test_throws msgortype(
        "Custom interpolation 2=2\nHTTP connection to JuliaHub failed (HTTP.Exceptions.ConnectError)",
    ) JuliaHub.@_httpcatch(
        throw_connecterror(), msg = "Custom interpolation $(1+1)=2"
    )
end

@testset "JuliaHub._print_indented" begin
    _print_indented(s; indent) = sprint(
        (args...) -> JuliaHub._print_indented(args...; indent=indent),
        io -> print(io, s),
    )
    @test _print_indented(""; indent=0) == ""
    @test _print_indented(""; indent=1) == ""
    @test _print_indented(""; indent=10) == ""

    @test _print_indented("x"; indent=0) == "x"
    @test _print_indented("x"; indent=1) == " x"
    @test _print_indented("x"; indent=3) == "   x"

    @test _print_indented(" "; indent=0) == " "
    @test _print_indented(" "; indent=1) == "  "
    @test _print_indented(" "; indent=3) == "    "

    @test _print_indented("x\ny"; indent=0) == "x\ny"
    @test _print_indented("x\ny"; indent=1) == " x\n y"
    @test _print_indented("x\ny"; indent=3) == "   x\n   y"

    @test _print_indented("x\ny\n"; indent=0) == "x\ny\n"
    @test _print_indented("x\ny\n"; indent=1) == " x\n y\n"
    @test _print_indented("x\ny\n"; indent=3) == "   x\n   y\n"

    @test _print_indented("x\n\ny\n"; indent=0) == "x\n\ny\n"
    @test _print_indented("x\n\ny\n"; indent=1) == " x\n\n y\n"
    @test _print_indented("x\n\ny\n"; indent=3) == "   x\n\n   y\n"
end

@testset "_parse_tz" begin
    let t = JuliaHub._parse_tz("2022-10-12T05:30:31.1+00:00")
        @test t isa TimeZones.ZonedDateTime
        @test t.timezone == TimeZones.localzone()
        @test Dates.millisecond(t) == 100
    end
    let t = JuliaHub._parse_tz("2022-10-12T05:30:31.12+00:00")
        @test t isa TimeZones.ZonedDateTime
        @test t.timezone == TimeZones.localzone()
        @test Dates.millisecond(t) == 120
    end
    let t = JuliaHub._parse_tz("2022-10-12T05:30:31.123+00:00")
        @test t isa TimeZones.ZonedDateTime
        @test t.timezone == TimeZones.localzone()
        @test Dates.millisecond(t) == 123
    end
    @test_throws JuliaHub.JuliaHubError JuliaHub._parse_tz("2022-10-12T05:30:31.+00:00")
    let t = JuliaHub._parse_tz("2022-10-12T05:30:31+00:00")
        @test t isa TimeZones.ZonedDateTime
        @test t.timezone == TimeZones.localzone()
        @test Dates.millisecond(t) == 0
    end
    @test_throws JuliaHub.JuliaHubError JuliaHub._parse_tz("")
    @test_throws JuliaHub.JuliaHubError JuliaHub._parse_tz("bad-string")
end
