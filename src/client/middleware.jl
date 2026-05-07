"""
    DefaultMiddleware(; retry, rate_limit, timeout, log_label)

Bundle of reliability primitives composed by [`default_middleware`](@ref) and
[`with_defaults`](@ref). Each field is `nothing` to disable that link in
the chain.
"""
Base.@kwdef struct DefaultMiddleware
    retry::Union{Nothing, RetryPolicy} = RetryPolicy()
    rate_limit::Union{Nothing, TokenBucket} = nothing
    timeout::Union{Nothing, Float64} = nothing
    log_label::Union{Nothing, String} = "api-call"
end

"""
    default_middleware(; kwargs...) -> DefaultMiddleware

Build a sensible reliability stack. Forward to [`with_defaults`](@ref) to
execute a callable under it.

```julia
mw = default_middleware(; rate_limit = TokenBucket(; rate = 5, burst = 10),
                         timeout = 10.0)
result = with_defaults(mw) do
    list_pets(client)
end
```
"""
default_middleware(; kwargs...) = DefaultMiddleware(; kwargs...)

"""
    with_defaults(fn, mw::DefaultMiddleware) -> Any
    with_defaults(fn; kwargs...) -> Any

Run `fn()` under the configured middleware stack. Order, top-down:

  1. Logging (outermost — sees all attempts and outcomes)
  2. Retry (re-runs everything below on retryable errors)
  3. Rate limit (waits for a token)
  4. Timeout (innermost — bounds a single attempt)

Disable any link by setting it to `nothing`.
"""
function with_defaults(fn::Function, mw::DefaultMiddleware)
    inner = fn
    if mw.timeout !== nothing
        inner_with_timeout = inner
        inner = () -> with_timeout(inner_with_timeout, mw.timeout)
    end
    if mw.rate_limit !== nothing
        bucket = mw.rate_limit
        inner_with_rl = inner
        inner = () -> with_rate_limit(bucket, inner_with_rl)
    end
    if mw.retry !== nothing
        policy = mw.retry
        inner_with_retry = inner
        inner = () -> with_retry(inner_with_retry; policy = policy)
    end
    if mw.log_label !== nothing
        label = mw.log_label
        inner_with_log = inner
        inner = () -> with_logging(inner_with_log; label = label)
    end
    return inner()
end
with_defaults(fn::Function; kwargs...) = with_defaults(fn, default_middleware(; kwargs...))
