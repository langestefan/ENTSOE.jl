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
response. Pass `parsed = false` to skip parsing and get back the raw
XML string.

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
