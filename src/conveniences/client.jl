using OpenAPI: OpenAPI

const ENTSOE_BASE_URL = "https://web-api.tp.entsoe.eu/api"

"""
    EntsoEClient(token; base_url=ENTSOE_BASE_URL, kwargs...) -> Client

Build a `Client` wired with ENTSO-E's `securityToken` query-parameter auth.
Every operation in the generated API declares the `SecurityToken` security
requirement, and this client's `pre_request_hook` injects the token into the
query string for those operations.

The generated `<Group>Api` constructors take an `OpenAPI.Clients.Client`, so
unwrap with `.inner` before constructing them — or use [`entsoe_apis`](@ref)
which does that for you and returns one API per ENTSO-E group:

```julia
using EntsoE
client = EntsoEClient(ENV["ENTSOE_API_TOKEN"])
apis = entsoe_apis(client)

start = entsoe_period(Dates.DateTime("2023-08-23T22:00"))
stop  = entsoe_period(Dates.DateTime("2023-08-24T22:00"))
xml, _ = market121_d_energy_prices(apis.market, "A44", EIC.NL, EIC.NL, start, stop)
```

Extra keyword arguments are forwarded verbatim to `OpenAPI.Clients.Client`
(useful for `timeout`, `httplib`, etc.).
"""
function EntsoEClient(
        token::AbstractString;
        base_url::AbstractString = ENTSOE_BASE_URL,
        kwargs...,
    )
    inner = OpenAPI.Clients.Client(
        String(base_url);
        pre_request_hook = _entsoe_pre_request_hook(String(token)),
        kwargs...,
    )
    return Client(inner, NoAuth(), String(base_url))
end

# Build a `pre_request_hook` with both signatures expected by `OpenAPI.Clients`:
# the `(ctx::Ctx)` form runs before the URL is assembled and is where we inject
# `securityToken` into `ctx.query` for any op that declares the SecurityToken
# scheme. The `(resource, body, headers)` form is a no-op pass-through.
function _entsoe_pre_request_hook(token::String)
    function hook(ctx::OpenAPI.Clients.Ctx)
        "SecurityToken" in ctx.auth && (ctx.query["securityToken"] = token)
        return ctx
    end
    function hook(
            resource_path::AbstractString, body, headers::Dict{String, String},
        )
        return resource_path, body, headers
    end
    return hook
end

"""
    entsoe_apis(c::Client) -> NamedTuple

One API instance per ENTSO-E group, ready to pass to the generated query
functions:

```julia
apis = entsoe_apis(client)
apis.market         # MarketApi
apis.load           # LoadApi
apis.generation     # GenerationApi
# ... balancing, master_data, omi, outages, transmission
```
"""
function entsoe_apis(c::Client)
    return (
        balancing    = BalancingApi(c.inner),
        generation   = GenerationApi(c.inner),
        load         = LoadApi(c.inner),
        market       = MarketApi(c.inner),
        master_data  = MasterDataApi(c.inner),
        omi          = OMIApi(c.inner),
        outages      = OutagesApi(c.inner),
        transmission = TransmissionApi(c.inner),
    )
end
