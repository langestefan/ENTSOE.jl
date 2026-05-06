# Getting Started

## Installation

```julia
using Pkg
Pkg.add("EntsoE")
```

## Constructing a Client

```julia
using EntsoE

client = Client("https://api.example.com"; auth = NoAuth())
```

Available auth strategies:

| Type | When to use |
|---|---|
| [`NoAuth`](@ref) | public APIs |
| [`BearerToken`](@ref) | OAuth2/JWT bearer-token APIs |
| [`APIKey`](@ref) | header-based API-key APIs (configurable header name) |
| [`BasicAuth`](@ref) | HTTP basic auth |

## Reliability primitives

The hand-written overlay ships retry, rate-limit, and timeout helpers. Wrap a
call to compose them:

```julia
result = with_retry(; policy = RetryPolicy(; max_attempts = 3)) do
    with_timeout(5.0) do
        # ... call a generated endpoint here ...
    end
end
```

## Pagination

```julia
for item in paginate_offset((offset, limit) -> list_things(client; offset, limit))
    @show item
end
```

See [`paginate_cursor`](@ref), [`paginate_offset`](@ref), [`paginate_pagenum`](@ref).
