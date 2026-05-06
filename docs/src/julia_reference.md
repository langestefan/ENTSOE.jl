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
```

## Reliability

```@docs
RetryPolicy
with_retry
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
