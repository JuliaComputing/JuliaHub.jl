```@meta
CurrentModule=JuliaHub
DocTestSetup = :(using JuliaHub)
```

# [Authentication API reference](@id authentication)

In order to talk to a JuliaHub instance, you need to have a valid authentication token.
JuliaHub reuses the Julia's built-in package server authentication tokens for this purpose.
By default, the authentication uses the `JULIA_PKG_SERVER` environment variable to determine which JuliaHub instance to connect to, but this can be overridden by passing an argument to [`authenticate`](@ref).

The [`authenticate`](@ref) function can be used to construct a token.
If a valid token is available in `~/.julia/servers`, it gets reused.
Otherwise, a browser window is opened, starting an interactive authentication procedure.

All the functions that require authentication accept an `auth` keyword argument.
However, JuliaHub.jl also stores the authentication token from the last [`authenticate`](@ref) call in a global variable and automatically uses that if `auth` is not provided, and also tries to authenticate automatically.
The current global authentication object can be accessed via the [`current_authentication()`](@ref) function.

See also: [authentication guide](../guides/authentication.md), [authentication section on `help.juliahub.com`](https://help.juliahub.com/juliahub/stable/ref/#authentication>), [PkgAuthentication](https://github.com/JuliaComputing/PkgAuthentication.jl/).

## Token expiration and refresh tokens

By default, JuliaHub access tokens expire in 24 hours.
However, the tokens usually also have a refresh token, which is valid for 30 days.
If the access token has expired, but there is a valid refresh token available, [`authenticate`](@ref) will automatically try to use that, to re-acquire an access token without starting an interactive authentication.

In JuliaHub job and cloud IDE environments, the authentication token on disk will be continuously kept up to date.
The [`reauthenticate!`](@ref) function can be used to reload the token from disk.

## Reference

```@docs
authenticate
Authentication
current_authentication
check_authentication
reauthenticate!
Secret
```

## Index

```@index
Pages = ["authentication.md"]
```
