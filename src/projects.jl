# Experimental function to fetch datasets associated with a project.
#
#=
using JuliaHub
auth = JuliaHub.authenticate("<hostname>")
ds = JuliaHub._project_datasets(auth, "<project uuid>")
=#

function _project_datasets(auth::Authentication, project_uuid::AbstractString)
    project_uuid = tryparse(UUIDs.UUID, project_uuid)
    if isnothing(project_uuid)
        throw(ArgumentError("project_uuid must be a UUID, got '$(project_uuid)'"))
    end
    return _project_datasets(auth, project_uuid)
end

function _project_datasets(auth::Authentication, project_uuid::UUIDs.UUID)
    r = JuliaHub._restcall(
        auth, :GET, ("datasets",), nothing;
        query = (; project = string(project_uuid))
    )
    if r.status == 400
        throw(InvalidRequestError("Unable to fetch datasets for project '$(project_uuid)' ($(r.body))"))
    elseif r.status != 200
        JuliaHub._throw_invalidresponse(r; msg="Unable to fetch datasets.")
    end
    datasets, _ = JuliaHub._parse_response_json(r, Vector)
    return _parse_dataset_list(datasets)
end
