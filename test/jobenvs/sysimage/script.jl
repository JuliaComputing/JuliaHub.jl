using UUIDs
Example_PkgId = Base.PkgId(UUID("7876af07-990d-54b4-ab0e-23690620f79a"), "Example")

in_sysimage::Bool = Base.in_sysimage(Example_PkgId)
loaded_modules_before_import::Bool = haskey(Base.loaded_modules, Example_PkgId)
import Example
loaded_modules_after_import::Bool = haskey(Base.loaded_modules, Example_PkgId)
hello::AbstractString = Example.hello("Sysimage")
domath::Integer = Example.domath(0)
ENV["RESULTS"] = """
{
    "in_sysimage": $(in_sysimage),
    "loaded_modules_before_import": $(loaded_modules_before_import),
    "loaded_modules_after_import": $(loaded_modules_after_import),
    "domath": $(domath),
    "hello": "$(hello)"
}
"""
@info ENV["RESULTS"]
