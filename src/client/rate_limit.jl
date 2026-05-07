"""
    TokenBucket(; rate=10.0, burst=10.0)

Token-bucket rate limiter. `rate` is tokens added per second; `burst` is the
maximum reservoir size (and the initial fill).
"""
mutable struct TokenBucket
    rate::Float64
    burst::Float64
    tokens::Float64
    last_refill::Float64
    lock::ReentrantLock
end

function TokenBucket(; rate::Real = 10.0, burst::Real = 10.0)
    r = Float64(rate); b = Float64(burst)
    # `last_refill = NaN` is a sentinel meaning "uninitialised" — the first
    # `acquire!` will seed it from its `time_fn`, so a mocked clock and the
    # bucket's notion of time stay consistent.
    return TokenBucket(r, b, b, NaN, ReentrantLock())
end

"""
    acquire!(bucket; tokens=1.0, timeout=Inf, sleep_fn=Base.sleep, time_fn=time)

Block until `tokens` tokens are available, or throw [`RateLimitError`](@ref)
if the wait would exceed `timeout` seconds. `time_fn` and `sleep_fn` are
injectable for testing.
"""
function acquire!(
        b::TokenBucket;
        tokens::Real = 1.0,
        timeout::Real = Inf,
        sleep_fn = Base.sleep,
        time_fn = time,
    )
    need = Float64(tokens)
    deadline = time_fn() + Float64(timeout)
    return lock(b.lock) do
        while true
            now = time_fn()
            if isnan(b.last_refill)
                b.last_refill = now
            end
            elapsed = now - b.last_refill
            if elapsed > 0
                b.tokens = min(b.burst, b.tokens + elapsed * b.rate)
                b.last_refill = now
            end
            if b.tokens >= need
                b.tokens -= need
                return nothing
            end
            wait_secs = (need - b.tokens) / b.rate
            if time_fn() + wait_secs > deadline
                throw(RateLimitError(; status = 429, retry_after = wait_secs))
            end
            sleep_fn(wait_secs)
        end
    end
end

"""
    with_rate_limit(bucket, fn; kwargs...) -> Any

Acquire from `bucket` then run `fn()`. Extra kwargs are forwarded to
[`acquire!`](@ref).
"""
function with_rate_limit(bucket::TokenBucket, fn::Function; kwargs...)
    acquire!(bucket; kwargs...)
    return fn()
end
