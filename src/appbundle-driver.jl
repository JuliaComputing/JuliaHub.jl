# This in an automatically generated driver script generated by JuliaHub.jl
# when submitting an appbundle.
let
    path_components = [{PATH_COMPONENTS}]
    path = abspath(pwd(), path_components...)
    if !isfile(path)
        path_relative = joinpath(path_components...)
        error("""
        Unable to load requested script: $(path_relative)
         at $(path)""")
    end
    path
end |> include