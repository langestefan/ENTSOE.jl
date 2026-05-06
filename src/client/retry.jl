const DEFAULT_RETRYABLE_STATUSES = Set([408, 429, 500, 502, 503, 504])

"""
    RetryPolicy(; max_attempts=5,
                  base_delay=0.5,
                  max_delay=30.0,
                  retryable_statuses=DEFAULT_RETRYABLE_STATUSES,
                  retry_on_network_error=true)

Exponential-backoff-with-full-jitter retry configuration. Used by
[`with_retry`](@ref).
"""
struct RetryPolicy
    max_attempts::Int
    base_delay::Float64
    max_delay::Float64
    retryable_statuses::Set{Int}
    retry_on_network_error::Bool
end
RetryPolicy(;
    max_attempts::Integer = 5,
    base_delay::Real = 0.5,
    max_delay::Real = 30.0,
    retryable_statuses::AbstractSet{<:Integer} = DEFAULT_RETRYABLE_STATUSES,
    retry_on_network_error::Bool = true,
) = RetryPolicy(
    Int(max_attempts),
    Float64(base_delay),
    Float64(max_delay),
    Set{Int}(Int.(retryable_statuses)),
    retry_on_network_error,
)

"""
    backoff_delay(policy, attempt; jitter=rand)

Return the seconds to sleep before retrying. Implements exponential backoff
with full jitter, capped at `policy.max_delay`. `jitter` is a 0-arg function
returning a value in `[0, 1)`; override in tests for determinism.
"""
function backoff_delay(p::RetryPolicy, attempt::Integer; jitter = rand)
    capped = min(p.base_delay * 2.0^(attempt - 1), p.max_delay)
    return capped * jitter()
end

"""
    is_retryable(policy, err) -> Bool

Decide whether a thrown exception should trigger another attempt under
`policy`. Honors `retryable_statuses` for `ClientError`/`ServerError`/
`RateLimitError`, and `retry_on_network_error` for `NetworkError`.
"""
function is_retryable(p::RetryPolicy, err::APIError)
    if err isa NetworkError
        return p.retry_on_network_error
    elseif err isa Union{ClientError,ServerError,AuthError}
        return err.status in p.retryable_statuses
    elseif err isa RateLimitError
        return err.status in p.retryable_statuses
    elseif err isa TimeoutError
        return true
    end
    return false
end
is_retryable(::RetryPolicy, ::Exception) = false

"""
    with_retry(fn; policy=RetryPolicy(), sleep_fn=Base.sleep, jitter=rand) -> Any

Run `fn()` under the retry policy. Returns the first non-retryable result.
For `RateLimitError`, the longer of `backoff_delay` and the server-supplied
`retry_after` is used. `sleep_fn` and `jitter` are injectable so tests can
avoid real sleeps and assert exact delays.
"""
function with_retry(
    fn::Function;
    policy::RetryPolicy = RetryPolicy(),
    sleep_fn = Base.sleep,
    jitter = rand,
)
    last_err = nothing
    for attempt in 1:policy.max_attempts
        try
            return fn()
        catch e
            last_err = e
            (e isa APIError && is_retryable(policy, e)) || rethrow()
            attempt < policy.max_attempts || rethrow()
            delay = backoff_delay(policy, attempt; jitter = jitter)
            if e isa RateLimitError && e.retry_after !== nothing
                delay = max(delay, e.retry_after)
            end
            sleep_fn(delay)
        end
    end
    # Unreachable: the loop body either returns or rethrows.
    rethrow(last_err)
end
