# Julia API Reference

```@meta
CurrentModule = ENTSOE
```

## Client

```@docs
Client
```

## Auth

```@docs
Auth
NoAuth
BearerToken
APIKey
BasicAuth
resolve_credentials
ENTSOE.apply!
ENTSOE.build_pre_request_hook
```

## Errors

```@docs
APIError
NetworkError
ClientError
ServerError
AuthError
RateLimitError
TimeoutError
check_response
ENTSOE.parse_retry_after
```

## Reliability

```@docs
RetryPolicy
with_retry
ENTSOE.is_retryable
ENTSOE.backoff_delay
TokenBucket
acquire!
with_rate_limit
with_timeout
with_logging
redact_headers
DefaultMiddleware
default_middleware
with_defaults
```

## Pagination

```@docs
paginate_cursor
paginate_offset
paginate_pagenum
```

## Pretty printing

```@docs
Base.show(::IO, ::MIME"text/plain", ::T) where T <: OpenAPI.APIModel
```

## ENTSO-E client + period

```@docs
ENTSOEClient
entsoe_apis
entsoe_period
ENTSOE_BASE_URL
```

## Module configuration

```@docs
ENTSOEConfig
set_config
get_config
```

## EIC codes

```@docs
EIC
EIC_REGISTRY
lookup_eic
is_known_eic
eics_of_type
validate_eic
```

## Code lists (DocumentType / ProcessType / …)

```@docs
DOCUMENT_TYPE
PROCESS_TYPE
BUSINESS_TYPE
PSR_TYPE
ENTSOE.describe
ENTSOE.code_for
```

## XML response parsing

```@docs
parse_timeseries
parse_timeseries_per_psr
parse_installed_capacity
parse_acknowledgement
check_acknowledgement
ENTSOEAcknowledgement
unzip_response
```

## Named-argument query wrappers

These are thin wrappers around the generated operation functions that
pre-fill the standard `documentType` / `processType` codes, accept
`DateTime` / `Date` / `ZonedDateTime` directly, and parse the XML
response into a typed `StructVector`.

### Parsed vs. raw — the `ResponseFormat` dispatch

Every wrapper accepts an **optional trailing positional argument** of
type [`ResponseFormat`](@ref) that selects the return shape:

```julia
prices     = day_ahead_prices(client, EIC.NL, t1, t2)            # default
prices2    = day_ahead_prices(client, EIC.NL, t1, t2, Parsed())  # explicit
prices_xml = day_ahead_prices(client, EIC.NL, t1, t2, Raw())     # bypass parser
```

| Trailing argument | Return type            | When you'd use it                                                                                          |
| ----------------- | ---------------------- | ---------------------------------------------------------------------------------------------------------- |
| *(none)*          | `StructVector{<row>}`  | Default. Tables.jl-compatible, drop into `DataFrame`/plot directly.                                        |
| [`Parsed()`](@ref)| `StructVector{<row>}`  | Same as the default — useful when you want to make the choice explicit at the call site.                   |
| [`Raw()`](@ref)   | `String`               | Skip the parser. Hand the XML to `EzXML`/`XML.jl` yourself, archive the body, debug a parse mismatch, etc. |

The dispatch is on the singleton types `Parsed`/`Raw` (subtypes of
`ResponseFormat`), so each variant has a **concrete inferred return
type**:

```julia
julia> Base.return_types(day_ahead_prices,
           Tuple{Client, String, DateTime, DateTime, Raw})
1-element Vector{Any}:
 String

julia> Base.return_types(day_ahead_prices,
           Tuple{Client, String, DateTime, DateTime})   # default → Parsed
1-element Vector{Any}:
 StructVector{@NamedTuple{time::DateTime, value::Float64}, …}
```

No `Union` widening, no `Any` — downstream code can specialize on the
returned type.

```@docs
ResponseFormat
Parsed
Raw
```

### Wrappers

```@docs
day_ahead_prices
actual_total_load
day_ahead_load_forecast
week_ahead_load_forecast
month_ahead_load_forecast
year_ahead_load_forecast
installed_capacity_per_production_type
generation_forecast_day_ahead
wind_solar_forecast
actual_generation_per_production_type
cross_border_physical_flows
```

The OMI endpoint paginates server-side; our wrapper handles the
offset loop:

```@docs
omi_other_market_information(::ENTSOE.Client, ::AbstractString, ::Any, ::Any)
```

## Request splitting

ENTSO-E caps most endpoints at "one year per request". For longer
windows, [`query_split`](@ref) chunks the period and concatenates
results.

```@docs
split_period
query_split
```
