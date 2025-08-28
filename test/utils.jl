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
        "Custom interpolation 2=2\nHTTP connection to JuliaHub failed (HTTP.Exceptions.ConnectError)"
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
    @test JuliaHub._localtz() isa Dates.TimeZone
    @test isassigned(JuliaHub._LOCAL_TZ)
    @test JuliaHub._localtz() === JuliaHub._LOCAL_TZ[]
    let t = JuliaHub._parse_tz("2022-10-12T05:30:31.1+00:00")
        @test t isa TimeZones.ZonedDateTime
        @test t.timezone == JuliaHub._localtz()
        @test Dates.millisecond(t) == 100
    end
    let t = JuliaHub._parse_tz("2022-10-12T05:30:31.12+00:00")
        @test t isa TimeZones.ZonedDateTime
        @test t.timezone == JuliaHub._localtz()
        @test Dates.millisecond(t) == 120
    end
    let t = JuliaHub._parse_tz("2022-10-12T05:30:31.123+00:00")
        @test t isa TimeZones.ZonedDateTime
        @test t.timezone == JuliaHub._localtz()
        @test Dates.millisecond(t) == 123
    end
    @test_throws JuliaHub.JuliaHubError JuliaHub._parse_tz("2022-10-12T05:30:31.+00:00")
    let t = JuliaHub._parse_tz("2022-10-12T05:30:31+00:00")
        @test t isa TimeZones.ZonedDateTime
        @test t.timezone == JuliaHub._localtz()
        @test Dates.millisecond(t) == 0
    end
    @test_throws JuliaHub.JuliaHubError JuliaHub._parse_tz("")
    @test_throws JuliaHub.JuliaHubError JuliaHub._parse_tz("bad-string")
end

@testset "_get_json_convert" begin
    @test JuliaHub._get_json_convert(
        Dict("id" => "123e4567-e89b-12d3-a456-426614174000"), "id", UUIDs.UUID
    ) == UUIDs.UUID("123e4567-e89b-12d3-a456-426614174000")
    # Error cases:
    @test_throws JuliaHub.JuliaHubError(
        "Invalid JSON returned by the server: `id` not a valid UUID string.\nServer returned '123'."
    ) JuliaHub._get_json_convert(
        Dict("id" => "123"), "id", UUIDs.UUID
    )
    @test_throws JuliaHub.JuliaHubError(
        "Invalid JSON returned by the server: `id` of type `Int64`, expected `<: String`."
    ) JuliaHub._get_json_convert(
        Dict("id" => 123), "id", UUIDs.UUID
    )
    @test_throws JuliaHub.JuliaHubError(
        "Invalid JSON returned by the server: `id` missing in the response.\nKeys present: _id_missing\njson: Dict{String, String} with 1 entry:\n  \"_id_missing\" => \"123e4567-e89b-12d3-a456-426614174000\""
    ) JuliaHub._get_json_convert(
        Dict("_id_missing" => "123e4567-e89b-12d3-a456-426614174000"), "id", UUIDs.UUID
    )
end

@testset "_max_appbundle_dir_size" begin
    # We check here that the `.juliabundleignore` is honored by making
    # sure that the calculated total file size of the Pkg3/ directory is
    dir = joinpath(@__DIR__, "fixtures", "ignorefiles", "Pkg3")

    appbundle_files = String[]
    JuliaHub._walk_appbundle_files(dir) do filepath
        push!(appbundle_files, relpath(filepath, dir))
    end
    @test sort(appbundle_files) == [
        ".gitignore", ".juliabundleignore", "Project.toml", "README.md",
        joinpath("src", "Pkg3.jl"), joinpath("src", "bar"), joinpath("src", "fooo"),
        joinpath("test", "fooo", "test"), joinpath("test", "runtests.jl"),
    ]

    # The files that are not meant to be included in the /Pkg3/ bundle here are
    # all 50 byte files. Should they should show up in the total size here.
    @test JuliaHub._max_appbundle_dir_size(dir) == (405, true)
end
