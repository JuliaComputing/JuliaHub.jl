```@meta
CurrentModule=JuliaHub
```

# Exceptions

JuliaHub.jl is designed in a way that the only errors it should throw under normal circumstances are subtypes of [`JuliaHubException`](@ref) (in addition to standard `ArgumentError`s and `MethodError`s etc. from invalid function calls).
Any unhandled errors from JuliaHub.jl or its dependencies should be considered a bug.

!!! tip "Debugging JuliaHub.jl issues"

    You can also enable debug logging for `JuliaHub`, which will make JuliaHub.jl print out additional debug messages, by setting the `JULIA_DEBUG` environment variable:

    ```julia
    ENV["JULIA_DEBUG"]="JuliaHub"
    ```


```@docs
JuliaHubException
AuthenticationError
InvalidAuthentication
InvalidRequestError
JuliaHubConnectionError
JuliaHubError
PermissionError
ProjectNotSetError
InvalidJuliaHubVersion
```

## Index

```@index
Pages = ["exceptions.md"]
```
