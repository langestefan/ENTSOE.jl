# ENTSOE.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://langestefan.github.io/ENTSOE.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://langestefan.github.io/ENTSOE.jl/dev/)
[![Build Status](https://github.com/langestefan/ENTSOE.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/langestefan/ENTSOE.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Documentation](https://github.com/langestefan/ENTSOE.jl/actions/workflows/Documentation.yml/badge.svg?branch=main)](https://github.com/langestefan/ENTSOE.jl/actions/workflows/Documentation.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/langestefan/ENTSOE.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/langestefan/ENTSOE.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![tested with JET.jl](https://img.shields.io/badge/%F0%9F%9B%A9%EF%B8%8F_tested_with-JET.jl-233f9a)](https://github.com/aviatesk/JET.jl)

A Julia client for the
[ENTSO-E Transparency Platform RESTful API](https://transparencyplatform.zendesk.com/hc/en-us/sections/12783116987028-Web-API)
— electricity market, generation, load, transmission, outage,
balancing, and master data for Europe.

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/langestefan/ENTSOE.jl")
```

You'll also need an API token. Register at
[transparency.entsoe.eu](https://transparency.entsoe.eu/) (free) and
e-mail the listed support address requesting access. Set
`ENV["ENTSOE_API_TOKEN"]` (or pass the token explicitly to `ENTSOEClient`).

## Quick start

```julia
using ENTSOE
using Dates

client = ENTSOEClient(ENV["ENTSOE_API_TOKEN"])

prices = day_ahead_prices(client, EIC.NL,
    DateTime("2024-09-01T22:00"),   # 2024-09-02 00:00 CET
    DateTime("2024-09-02T22:00"),   # 2024-09-03 00:00 CET
)

prices[1:3]
# 3-element Vector{@NamedTuple{time::DateTime, value::Float64}}:
#  (time = DateTime("2024-09-01T22:00"), value = 41.27)
#  (time = DateTime("2024-09-01T22:15"), value = 41.27)
#  (time = DateTime("2024-09-01T22:30"), value = 41.27)
```

Every wrapper accepts `DateTime`, `Date`, `ZonedDateTime`, or a raw
`Int64` `yyyymmddHHMM` for the period bounds — pick whichever you have
on hand. Periods are interpreted as **UTC**; the example above asks for
24 h starting at 2024-09-01 22:00 UTC, which is the local CET trading
day 2024-09-02.

## Named wrappers

The high-level functions below pre-fill the magic ENTSO-E codes
(`A44`, `A65`, `A68`, …) and parse the XML response into typed Julia
values. All return `Vector{NamedTuple}`; pass `parsed = false` to get
the raw XML string instead. They live in `src/conveniences/queries.jl`
and wrap the auto-generated functions in `src/api/`.

### Day-ahead prices

```julia
prices = day_ahead_prices(client, EIC.DE_LU,
    DateTime("2025-01-15"), DateTime("2025-01-16"))

# 96-element Vector{@NamedTuple{time::DateTime, value::Float64}}
# (15-min slots — German day-ahead is quarter-hourly)
prices[1]   # → (time = DateTime("2025-01-14T23:00"), value = 105.32)
```

### Realised total system load

```julia
load = actual_total_load(client, EIC.NL,
    DateTime("2024-09-01T22:00"), DateTime("2024-09-02T22:00"))

load[1]   # → (time = DateTime("2024-09-01T22:00"), value = 8624.0)  # MW
```

Day/week/month/year-ahead forecasts are also wrapped:
`day_ahead_load_forecast`, `week_ahead_load_forecast`,
`month_ahead_load_forecast`, `year_ahead_load_forecast` — same
signature.

### Actual generation per production type

```julia
gen = actual_generation_per_production_type(client, EIC.FR,
    DateTime("2025-03-10"), DateTime("2025-03-11"))

# rows tagged with PSR type:
gen[1]    # → (time = DateTime("2025-03-09T23:00"),
          #    psr_type = "B14",   # Nuclear
          #    value = 41320.0)    # MW

# Filter to one technology server-side:
solar = actual_generation_per_production_type(client, EIC.FR,
    DateTime("2025-03-10"), DateTime("2025-03-11");
    psr_type = "B16")    # B16 = Solar — see PSR_TYPE table below
```

### Installed capacity per production type

```julia
caps = installed_capacity_per_production_type(client, EIC.NL,
    DateTime("2024-12-31T23:00"), DateTime("2025-12-31T23:00"))

# 14-element Vector{@NamedTuple{psr_type::String, capacity_mw::Float64}}
caps[1]   # → (psr_type = "B01", capacity_mw = 580.0)   # Biomass

describe(PSR_TYPE, caps[1].psr_type)   # → "Biomass"
```

### Cross-border physical flows

```julia
# Hourly flow from Germany into the Netherlands (positive = imports)
flow = cross_border_physical_flows(client,
    EIC.NL, EIC.DE_LU,                 # in_area, out_area
    DateTime("2024-09-01"), DateTime("2024-09-02"))

flow[1]   # → (time = DateTime("2024-08-31T22:00"), value = 2143.0)  # MW
```

## Codes and identifiers

ENTSO-E codes everything as 2- or 3-character strings (`A44`,
`B19`, etc.). The package ships four code-list tables and helpers:

```julia
DOCUMENT_TYPE.A44               # "Price document"
PROCESS_TYPE.A16                # "Realised"
BUSINESS_TYPE.A33               # "Outage"
PSR_TYPE.B19                    # "Wind Onshore"

# Reverse lookup by fragment:
code_for(PSR_TYPE, "wind onshore")    # "B19"
code_for(DOCUMENT_TYPE, "price")      # "A44"
```

Bidding zones are
[EIC codes](https://www.entsoe.eu/data/energy-identification-codes-eic/)
— 16 ASCII chars. The most-used 33 are exposed as named-tuple fields:

```julia
EIC.NL          # "10YNL----------L"
EIC.DE_LU       # "10Y1001A1001A82H"
EIC.NO2         # "10YNO-2--------T"  (southern Norway)
```

For zones not in `EIC`, pass the raw 16-character string directly. The
extended `EIC_REGISTRY` table maps every ENTSO-E EIC to `(name, types)`
where `types` is a vector of `[:BZN, :CTA, :MBA, …]`. Pass
`validate = true` to any wrapper to assert the zone exists and is the
right type for the endpoint.

## Long periods (auto-split)

Most ENTSO-E endpoints reject single requests longer than one year. To
fetch 5 years of NL prices in one call, wrap with `query_split`:

```julia
prices = query_split(
    day_ahead_prices,
    client, EIC.NL,
    DateTime("2020-01-01"), DateTime("2025-01-01");
    window = Year(1),
)

length(prices)    # → 175296   (≈ 5 years × 8760 h × 4 quarter-hours)
```

Internally `query_split` calls `day_ahead_prices` once per yearly chunk
and concatenates the results. Some endpoints cap at one day rather than
one year (e.g. balancing energy bids); pass `window = Day(1)` there.

## "No data" responses

ENTSO-E returns HTTP 200 with an `<Acknowledgement_MarketDocument>` when
there's no matching data for a query. The wrappers detect this and
re-raise as a typed exception:

```julia
try
    day_ahead_prices(client, EIC.GR,
        DateTime("1999-01-01"), DateTime("1999-01-02"))
catch err
    err isa ENTSOEAcknowledgement || rethrow()
    @info "no data" err.reason_code err.text
end
# ┌ Info: no data
# │   err.reason_code = "999"
# └   err.text = "No matching data found for ..."
```

`query_split` catches `ENTSOEAcknowledgement` per chunk and continues
with the next window — so a multi-year request that's only partially
populated still returns whatever data exists.

## Reliability stack

`ENTSOEClient` is built on the package's underlying `Client`, so the
generic `with_defaults` middleware composes around any call:

```julia
result = with_defaults(;
    retry      = RetryPolicy(; max_attempts = 5, base_delay = 0.5),
    rate_limit = TokenBucket(; rate = 10.0, burst = 10.0),
    timeout    = 5.0,
) do
    day_ahead_prices(client, EIC.NL,
        DateTime("2024-09-01"), DateTime("2024-09-02"))
end
```

The default policy retries on `408`/`429`/`5xx` and honours
`Retry-After` headers. Any non-2xx response is mapped to a typed
exception by `check_response`:

| Status | Type |
| --- | --- |
| 401 / 403 | `AuthError` |
| 408 / 429 | `RateLimitError` (parses `Retry-After`) |
| Other 4xx | `ClientError` |
| 5xx | `ServerError` |
| Network / DNS / TLS | `NetworkError` |
| Timeout | `TimeoutError(:connect \| :read \| :total)` |

## Documentation

The full guide — including the
[2025 EU price heat-map tutorial](https://langestefan.github.io/ENTSOE.jl/dev/tutorial_eu_map)
and a per-tag interactive REST playground — lives at
[langestefan.github.io/ENTSOE.jl](https://langestefan.github.io/ENTSOE.jl).
Build it locally with:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
cd docs && npm install && npm run docs:dev
```

## Re-running codegen (maintainers only)

The OpenAPI spec is committed at `spec/openapi.json`, derived once from
ENTSO-E's official Postman collection. To rebuild `src/api/`:

```bash
julia --project gen/regenerate.jl
```

Requires Java 11+ and Node 18+. End users of the published package
never touch this step — `src/api/` is committed plain Julia. The
scheduled `.github/workflows/regen-check.yml` runs codegen weekly and
opens a PR if the upstream Postman collection has drifted.

## Architecture

Two layers, both Julia, both committed:

- **`src/api/`** — generated by
  [OpenAPI Generator](https://openapi-generator.tech/) (`julia-client`).
  77 functions, one per ENTSO-E operation. Returns
  `(xml::String, response)`. Never re-run at runtime.
- **`src/conveniences/`** — hand-written: `ENTSOEClient`, named-argument
  wrappers (`day_ahead_prices` etc.), parsers, code tables, EIC registry,
  `query_split`. Untouched by codegen.

See [`CLAUDE.md`](./CLAUDE.md) for the full layout including the
Postman→OpenAPI conversion script.
