# Prepares a release commit on a branch called `release-x.y.z`, by bumping the
# patch / minor / major version, as specified.
#
# - Bumps the version in Project.toml
# - Finalizes the "## Unreleased" section in CHANGELOG.md, and regenerates the
#   changelog links (docs/changelog.jl).
# - Offers to create a `release: set version to X.Y.Z` commit
#
# Usage:
#
#   julia --project=docs docs/prepare-release.jl (patch|minor|major)
#
# But, in practice, use the `make release-(patch|minor|major)` Make commands.
using CommonMark
using Dates
using TOML

const REPO_ROOT = dirname(@__DIR__)
const PROJECT_TOML = joinpath(REPO_ROOT, "Project.toml")
const CHANGELOG_MD = joinpath(REPO_ROOT, "CHANGELOG.md")

function main(args)
    bump_type = parse_bump_type(args)
    check_git_preconditions()

    old_version = VersionNumber(TOML.parsefile(PROJECT_TOML)["version"])
    new_version = bump_version(old_version, bump_type)
    release_branch = "release-$(new_version)"
    if success(git(`rev-parse --verify --quiet refs/heads/$(release_branch)`))
        fatal("branch $(release_branch) already exists")
    end
    @info "Preparing release: $(old_version) -> $(new_version)"

    update_project_version(old_version, new_version)
    update_changelog(new_version)
    @info "Regenerating changelog links with docs/changelog.jl"
    include(joinpath(@__DIR__, "changelog.jl"))

    run(git(`--no-pager diff`))

    if !confirm_commit(release_branch)
        printstyled(stderr, """

            ╔═══════════════════════════════════════════════════════════════════╗
            ║ WARNING: nothing was committed, but Project.toml and CHANGELOG.md  ║
            ║ have been MODIFIED and left in your working tree!                  ║
            ║                                                                    ║
            ║ To undo:  git checkout -- Project.toml CHANGELOG.md                ║
            ╚═══════════════════════════════════════════════════════════════════╝
            """; color=:yellow, bold=true)
        exit(1)
    end

    run(git(`checkout -b $(release_branch)`))
    run(git(`add Project.toml CHANGELOG.md`))
    run(git(`commit -m "release: set version to $(new_version)"`))

    println("""

        Release commit created on branch $(release_branch). Next steps:

         1. Push the branch: git push -u origin $(release_branch)
         2. Open a PR against `main`.
         2. After the PR is merged, trigger a registration in the General registry.
        """)
end

git(args::Cmd) = `git -C $(REPO_ROOT) $(args)`

function parse_bump_type(args)
    if length(args) == 1 && args[1] in ("patch", "minor", "major")
        return args[1]
    end
    println(stderr, "Usage: julia --project=docs docs/prepare-release.jl (patch|minor|major)")
    exit(2)
end

function check_git_preconditions()
    branch = readchomp(git(`rev-parse --abbrev-ref HEAD`))
    if branch != "main"
        fatal("must be run on the main branch (currently on: $(branch))")
    end
    if !isempty(strip(read(git(`status --porcelain`), String)))
        fatal("working tree is not clean; commit or stash your changes first")
    end
end

function bump_version(v::VersionNumber, bump_type::AbstractString)
    if bump_type == "patch"
        VersionNumber(v.major, v.minor, v.patch + 1)
    elseif bump_type == "minor"
        VersionNumber(v.major, v.minor + 1, 0)
    else
        VersionNumber(v.major + 1, 0, 0)
    end
end

function update_project_version(old_version, new_version)
    content = read(PROJECT_TOML, String)
    old_line = "version = \"$(old_version)\""
    if !occursin(old_line, content)
        fatal("could not find '$(old_line)' in Project.toml")
    end
    write(PROJECT_TOML, replace(content, old_line => "version = \"$(new_version)\""; count=1))
end

# The text of a heading node, with inline markup (e.g. link brackets) stripped.
function heading_text(node::CommonMark.Node)
    io = IOBuffer()
    for (n, entering) in node
        entering && n.t isa CommonMark.Text && print(io, n.literal)
    end
    return strip(String(take!(io)))
end

# Locates the "## Unreleased" heading by parsing the changelog with CommonMark
# and replaces just that source line, leaving the rest of the file untouched.
function update_changelog(new_version)
    text = read(CHANGELOG_MD, String)
    parser = CommonMark.Parser()
    ast = parser(text)
    heading_line = nothing
    for (node, entering) in ast
        if entering && node.t isa CommonMark.Heading && node.t.level == 2 &&
            heading_text(node) == "Unreleased"
            heading_line = node.sourcepos[1][1]
            break
        end
    end
    if isnothing(heading_line)
        fatal("no '## Unreleased' section in CHANGELOG.md; write the release notes first")
    end
    lines = split(text, '\n')
    lines[heading_line] = "## Version [v$(new_version)] - $(Dates.today())"
    write(CHANGELOG_MD, join(lines, '\n'))
end

function confirm_commit(release_branch)
    printstyled("\nCommit these changes to branch $(release_branch)? [y/N] "; bold=true)
    answer = lowercase(strip(readline(stdin)))
    return answer in ("y", "yes")
end

function fatal(msg)
    printstyled(stderr, "ERROR: "; color=:red, bold=true)
    println(stderr, msg)
    exit(1)
end

main(ARGS)
