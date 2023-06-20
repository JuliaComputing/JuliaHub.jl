```@meta
CurrentModule=JuliaHub
```

# JuliaHub.jl

The [JuliaHub.jl](https://github.com/JuliaComputing/JuliaHub.jl) package offers a programmatic Julia interface to the [JuliaHub platform](https://juliahub.com).

With JuliaHub.jl you can do things such as start JuliaHub jobs, access job outputs, and manage your datasets, programmatically, directly in the REPL or in your Julia script.
It can also be used in JuliaHub jobs to interact with the platform (to upload datasets, for example).

If you are unfamiliar with JuliaHub.jl, you may want to start out by reading through the [package's Getting Started tutorial](@ref getting-started).
If you want to know in detail how to programmatically work with a particular JuliaHub feature, you may want to skim through the applicable how-to guide:

```@contents
Pages = Main.PAGES_GUIDES
Depth = 1:1
```

Finally, detailed explanations and API references of JuliaHub.jl features and functions are available in the reference section of the manual:

```@contents
Pages = Main.PAGES_REFERENCE
Depth = 1:1
```

!!! tip "JuliaHub platform documentation"

    The documentation here focuses on working with the JuliaHub.jl Julia library.
    See the [main JuliaHub documentation](https://help.juliahub.com/juliahub/stable/) to learn more about the JuliaHub platform, and see product (e.g. JuliaSim) documentation for product-specific questions.

!!! note "Enterprise use"

    JuliaHub.jl works with both [juliahub.com](https://juliahub.com) and private enterprise instances.
    For enterprise users: the instance URL can be passed to the [`authenticate`](@ref) function either directly via an argument, or via the `JULIA_PKG_SERVER` environment variable.
