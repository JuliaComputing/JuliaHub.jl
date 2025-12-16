import JET, JuliaHub
using Test

jet_mode = get(ENV, "JULIAHUB_TEST_JET", "typo")
@info "Running JET.jl in mode=:$(jet_mode)"

# The following filter is used when jet_mode == "custom-filtering"
struct JuliaHubReportFilter end
function JET.configured_reports(::JuliaHubReportFilter, reports::Vector{JET.InferenceErrorReport})
    filter(reports) do report
        # This is necessary since a custom `report_config` overrides `target_defined_modules` setting
        occursin("JuliaHub", string(last(report.vst).linfo.def.module)) || return false
        # We'll ignore all the union split errors, since they are generally actually valid cases
        # where simply an isnothing() check is not being inferred correctly
        if isa(report, JET.MethodErrorReport) && report.union_split > 1
            return false
        end
        # We also ignore the _restput_mockable() error in restapi.jl, since JET seems to
        # assume that kwargs... must be non-empty
        contains(string(report.vst[end].linfo.def.name), "_restput_mockable") && return false
        return true
    end
end

@testset "JET" begin
    if jet_mode == "custom-filtering"
        JET.test_package(
            "JuliaHub"; report_config=JuliaHubReportFilter(),
            toplevel_logger=nothing,
        )
    else
        JET.test_package(
            "JuliaHub"; target_defined_modules=true, mode=Symbol(jet_mode), toplevel_logger=nothing
        )
    end
end
