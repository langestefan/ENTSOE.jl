# Module-level configuration — a small global mirror of the per-call
# arguments most users want to set once for a whole script.
#
# This is *opt-in*: code that explicitly passes a token to
# `EntsoEClient(token)` continues to work unchanged. The global only
# kicks in when the no-arg `EntsoEClient()` form is used, or when a
# field is left to the default.

"""
    EntsoEConfig

Holds the global default token, endpoint URL, and whether named-argument
wrappers should run [`validate_eic`](@ref) by default. Construct via
[`set_config`](@ref); read via [`get_config`](@ref).

Defaults:

  - `token` — empty (the no-arg [`EntsoEClient`](@ref) constructor will
    fall back to `ENV["ENTSOE_API_TOKEN"]` if both this and the
    explicit arg are unset).
  - `endpoint_url` — `ENTSOE_BASE_URL`
    (`https://web-api.tp.entsoe.eu/api`).
  - `validate_eic` — `false`. Passing `validate_eic = true` to
    `set_config` makes every named-arg wrapper validate the EIC by
    default; the per-call `validate = …` keyword still overrides.
"""
mutable struct EntsoEConfig
    token::String
    endpoint_url::String
    validate_eic::Bool
end

const _CONFIG = Ref(EntsoEConfig("", ENTSOE_BASE_URL, false))

"""
    set_config(; token=nothing, endpoint_url=nothing, validate_eic=nothing) -> EntsoEConfig

Update the global [`EntsoEConfig`](@ref). Any keyword left as
`nothing` keeps its current value. Returns the new (mutated) config.

```julia
EntsoE.set_config(; token = ENV["ENTSOE_API_TOKEN"], validate_eic = true)
client = EntsoEClient()      # picks up the global token
prices = day_ahead_prices(client, EIC.NL,
                          DateTime("2024-09-01T22:00"),
                          DateTime("2024-09-02T22:00"))
```
"""
function set_config(;
        token::Union{Nothing, AbstractString} = nothing,
        endpoint_url::Union{Nothing, AbstractString} = nothing,
        validate_eic::Union{Nothing, Bool} = nothing,
    )
    cfg = _CONFIG[]
    token        === nothing || (cfg.token        = String(token))
    endpoint_url === nothing || (cfg.endpoint_url = String(endpoint_url))
    validate_eic === nothing || (cfg.validate_eic = validate_eic)
    return cfg
end

"""
    get_config() -> EntsoEConfig

Return the current global [`EntsoEConfig`](@ref).
"""
get_config() = _CONFIG[]

"""
    EntsoEClient()

Convenience no-arg form: builds a client using the token and endpoint
from [`get_config`](@ref). Token resolution order:

  1. `get_config().token`
  2. `ENV["ENTSOE_API_TOKEN"]`

Throws if neither is set.
"""
function EntsoEClient()
    cfg = get_config()
    tok = cfg.token
    isempty(tok) && (tok = get(ENV, "ENTSOE_API_TOKEN", ""))
    isempty(tok) && throw(ArgumentError(
        "no token configured: call EntsoE.set_config(; token = …) " *
            "or set ENV[\"ENTSOE_API_TOKEN\"], or pass it explicitly to " *
            "EntsoEClient(token)."
    ))
    return EntsoEClient(tok; base_url = cfg.endpoint_url)
end
