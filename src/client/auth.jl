using Base64: base64encode
using TOML: TOML

"""
    Auth

Abstract supertype for authentication strategies. Concrete subtypes are
applied to outgoing requests via `apply!` and composed into a
`pre_request_hook` for `OpenAPI.Clients.Client` by `build_pre_request_hook`.
"""
abstract type Auth end

"""
    NoAuth()

Pass-through auth: leaves request headers untouched.
"""
struct NoAuth <: Auth end

"""
    BearerToken(token)

Sets `Authorization: Bearer <token>`.
"""
struct BearerToken <: Auth
    token::String
end

"""
    APIKey(key; header="X-API-Key")

Sets `<header>: <key>`. Works for any header-based API-key scheme.
"""
struct APIKey <: Auth
    key::String
    header::String
end
APIKey(key::AbstractString; header::AbstractString = "X-API-Key") =
    APIKey(String(key), String(header))

"""
    BasicAuth(username, password)

Sets `Authorization: Basic <base64(user:pass)>`.
"""
struct BasicAuth <: Auth
    username::String
    password::String
end

"""
    apply!(auth::Auth, headers::Dict{String,String}) -> Nothing

Inject credentials into the outgoing request headers.
"""
apply!(::NoAuth, ::Dict{String,String}) = nothing

function apply!(a::BearerToken, headers::Dict{String,String})
    headers["Authorization"] = "Bearer " * a.token
    return nothing
end

function apply!(a::APIKey, headers::Dict{String,String})
    headers[a.header] = a.key
    return nothing
end

function apply!(a::BasicAuth, headers::Dict{String,String})
    creds = base64encode(a.username * ":" * a.password)
    headers["Authorization"] = "Basic " * creds
    return nothing
end

"""
    build_pre_request_hook(auth) -> Function

Build the `pre_request_hook` accepted by `OpenAPI.Clients.Client`. The hook
implements both required signatures: a `Ctx`-only pass-through and a
`(resource, body, headers)` form that calls `apply!` on `auth`.
"""
function build_pre_request_hook(auth::Auth)
    hook(ctx) = ctx
    function hook(resource::AbstractString, body, headers::Dict{String,String})
        apply!(auth, headers)
        return resource, body, headers
    end
    return hook
end

"""
    resolve_credentials(T::Type{<:Auth}; env_prefix="ENTSOE") -> T

Build an [`Auth`](@ref) of type `T` from the first available source:

  1. Environment variables prefixed with `env_prefix` (e.g. `\$(env_prefix)_TOKEN`,
     `\$(env_prefix)_API_KEY`, `\$(env_prefix)_USERNAME` + `\$(env_prefix)_PASSWORD`).
  2. `~/.config/entsoe/credentials.toml` keyed under the auth
     type — e.g. `[bearer] token = "…"`, `[apikey] key = "…" header = "…"`,
     `[basic] username = "…" password = "…"`.

Throws an `ArgumentError` listing all attempted sources if no credentials are
found. Use this when constructing a `Client`:

```julia
client = Client("https://api.example.com"; auth = resolve_credentials(BearerToken))
```
"""
function resolve_credentials end

const _DEFAULT_ENV_PREFIX = "ENTSOE"
const _CREDENTIALS_FILE =
    joinpath(get(ENV, "XDG_CONFIG_HOME", joinpath(homedir(), ".config")),
             "entsoe", "credentials.toml")

_load_credentials_file(path::AbstractString = _CREDENTIALS_FILE) =
    isfile(path) ? TOML.parsefile(path) : Dict{String,Any}()

function resolve_credentials(::Type{BearerToken}; env_prefix::AbstractString = _DEFAULT_ENV_PREFIX)
    token = get(ENV, "$(env_prefix)_TOKEN", nothing)
    token === nothing || return BearerToken(token)
    cfg = get(_load_credentials_file(), "bearer", Dict{String,Any}())
    haskey(cfg, "token") && return BearerToken(String(cfg["token"]))
    throw(ArgumentError(
        "No bearer token found. Set `$(env_prefix)_TOKEN` or add " *
        "`[bearer] token = \"…\"` to $(_CREDENTIALS_FILE).",
    ))
end

function resolve_credentials(::Type{APIKey}; env_prefix::AbstractString = _DEFAULT_ENV_PREFIX)
    key = get(ENV, "$(env_prefix)_API_KEY", nothing)
    if key !== nothing
        header = get(ENV, "$(env_prefix)_API_KEY_HEADER", "X-API-Key")
        return APIKey(key; header = header)
    end
    cfg = get(_load_credentials_file(), "apikey", Dict{String,Any}())
    haskey(cfg, "key") && return APIKey(String(cfg["key"]);
                                        header = String(get(cfg, "header", "X-API-Key")))
    throw(ArgumentError(
        "No API key found. Set `$(env_prefix)_API_KEY` (and optionally " *
        "`$(env_prefix)_API_KEY_HEADER`) or add `[apikey] key = \"…\"` to " *
        "$(_CREDENTIALS_FILE).",
    ))
end

function resolve_credentials(::Type{BasicAuth}; env_prefix::AbstractString = _DEFAULT_ENV_PREFIX)
    user = get(ENV, "$(env_prefix)_USERNAME", nothing)
    pass = get(ENV, "$(env_prefix)_PASSWORD", nothing)
    user !== nothing && pass !== nothing && return BasicAuth(user, pass)
    cfg = get(_load_credentials_file(), "basic", Dict{String,Any}())
    haskey(cfg, "username") && haskey(cfg, "password") &&
        return BasicAuth(String(cfg["username"]), String(cfg["password"]))
    throw(ArgumentError(
        "No basic-auth credentials found. Set `$(env_prefix)_USERNAME` and " *
        "`$(env_prefix)_PASSWORD`, or add `[basic] username = \"…\" password = \"…\"` " *
        "to $(_CREDENTIALS_FILE).",
    ))
end
