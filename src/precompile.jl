precompile(JuliaHub.authenticate, ())
precompile(JuliaHub.authenticate, (Nothing,))
precompile(JuliaHub.authenticate, (String,))
precompile(JuliaHub.authenticate, (String, String))

precompile(JuliaHub.datasets, ())
precompile(JuliaHub.datasets, (String,))
precompile(JuliaHub.dataset, (Dataset,))
precompile(JuliaHub.dataset, (String,))
precompile(JuliaHub.dataset, (Tuple{String,String},))

precompile(JuliaHub.jobs, ())
precompile(JuliaHub.job, (Job,))
precompile(JuliaHub.job, (String,))

precompile(JuliaHub.batchimages, ())
precompile(JuliaHub.batchimages, (String,))
precompile(JuliaHub.appbundle, (String,))
precompile(JuliaHub.appbundle, (String, String))
precompile(JuliaHub.submit_job, (WorkloadConfig,))

# Precompile the basic show() methods for all public types
for sym in JuliaHub._find_public_names()
    t = getfield(@__MODULE__, sym)
    if isa(t, DataType)
        precompile(Base.show, (Base.TTY, MIME"text/plain", t))
        precompile(Base.show, (Base.TTY, MIME"text/plain", Vector{t}))
    end
end
