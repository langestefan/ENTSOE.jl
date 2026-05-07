# Julia API Reference

```@meta
CurrentModule = EntsoE
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
EntsoE.apply!
EntsoE.build_pre_request_hook
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
EntsoE.parse_retry_after
```

## Reliability

```@docs
RetryPolicy
with_retry
EntsoE.is_retryable
EntsoE.backoff_delay
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

## ENTSO-E conveniences

```@docs
EntsoEClient
entsoe_apis
entsoe_period
EIC
ENTSOE_BASE_URL
```
