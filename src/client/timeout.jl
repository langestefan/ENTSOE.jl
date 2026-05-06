"""
    with_timeout(fn, seconds; phase=:total) -> Any

Run `fn()` on a background task; throw [`TimeoutError`](@ref)`(phase)` if it
doesn't complete within `seconds`. `seconds = Inf` disables the timeout.

!!! warning
    Julia cannot forcibly cancel a running task, so the underlying work may
    continue past the timeout. For HTTP calls, prefer the transport-layer
    `connect_timeout` / `readtimeout` exposed by `OpenAPI.Clients.Client`.
"""
function with_timeout(fn::Function, seconds::Real; phase::Symbol = :total)
    if !isfinite(Float64(seconds))
        return fn()
    end
    task = @async fn()
    status = timedwait(() -> istaskdone(task), Float64(seconds); pollint = 0.01)
    status === :ok || throw(TimeoutError(phase))
    try
        return fetch(task)
    catch e
        # `fetch` wraps task exceptions in TaskFailedException — surface the
        # original so callers can write `@test_throws ErrorException ...`.
        e isa TaskFailedException && throw(e.task.result)
        rethrow()
    end
end
