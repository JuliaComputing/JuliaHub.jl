using JuliaHub
using Documenter, DocumenterMermaid

# Timestamp printing is dependent on the timezone, so we force a specific (non-UTC)
# timezone to make sure that the doctests don't fail because of timezone differences.
ENV["TZ"] = "America/New_York"

DocMeta.setdocmeta!(
    JuliaHub, :DocTestSetup,
    quote
        using JuliaHub
        empty!(Main.MOCK_JULIAHUB_STATE)
    end;
    recursive=true,
)

# Patching of the API responses. Also sets JuliaHub.__AUTH__.
include("../test/mocking.jl")
# The following setup function is reused in both at-setup blocks, but also in
# doctestsetup.
function setup_job_results_file!()
    Main.MOCK_JULIAHUB_STATE[:jobs] = Dict(
        "jr-eezd3arpcj" => Dict(
            "outputs" => """
            {"result_variable": 1234, "another_result": "value"}
            """,
            "files" => vcat(
                Main.MOCK_JULIAHUB_DEFAULT_JOB_FILES,
                Dict{String, Any}(
                    "name" => "outdir.tar.gz",
                    "upload_timestamp" => "2023-03-15T07:59:29.473898+00:00",
                    "hash" => Dict{String, Any}(
                        "algorithm" => "sha2_256",
                        "value" => "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                    ),
                    "size" => 632143,
                    "type" => "result",
                ),
            ),
        ),
    )
end

# These lists are reused in the makedocs, but also in the at-contents
# blocks on the src/index.md page.
const PAGES_GUIDES = [
    "guides/authentication.md",
    "guides/datasets.md",
    "guides/jobs.md",
]
const PAGES_REFERENCE = [
    "reference/authentication.md",
    "reference/job-submission.md",
    "reference/jobs.md",
    "reference/datasets.md",
    "reference/exceptions.md",
]
Mocking.apply(mocking_patch) do
    makedocs(;
        sitename="JuliaHub.jl",
        modules=[JuliaHub],
        authors="JuliaHub Inc.",
        format=Documenter.HTML(;
            canonical="https://help.juliahub.com/julia-api/stable",
            edit_link="main"
        ),
        pages=[
            "Home" => "index.md",
            "Getting Started" => "getting-started.md",
            "Guides" => PAGES_GUIDES,
            "Reference" => PAGES_REFERENCE,
            Documenter.hide("internal.md"),
        ],
        doctest=if in("--fix-doctests", ARGS)
            :fix
        elseif in("--doctest", ARGS)
            :only
        else
            true
        end,
    )
end

deploydocs(; repo="github.com/JuliaComputing/JuliaHub.jl")
