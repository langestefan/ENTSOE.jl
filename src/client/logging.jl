using Logging: Logging, @logmsg

const _SECRET_HEADERS = (
    "authorization", "x-api-key", "api_key", "cookie",
    "set-cookie", "proxy-authorization",
)

"""
    redact_headers(headers) -> Dict{String,String}

Return a copy of `headers` with values for sensitive entries replaced by
`"[redacted]"`. Header names are matched case-insensitively. Used by
[`with_logging`](@ref); also useful when surfacing headers in error
messages.
"""
function redact_headers(headers::AbstractDict)
    out = Dict{String, String}()
    for (k, v) in headers
        out[String(k)] = lowercase(String(k)) in _SECRET_HEADERS ? "[redacted]" : String(v)
    end
    return out
end

"""
    with_logging(fn; level=Logging.Info, label="api-call") -> Any

Wrap `fn()` in begin/end log records at `level`. Captures the elapsed time
and outcome (`:ok` / `:error`); re-throws any exception unchanged. Useful
as the outermost link in a [`default_middleware`](@ref) stack.
"""
function with_logging(fn::Function; level = Logging.Info, label::AbstractString = "api-call")
    t0 = time()
    @logmsg level "$label: begin"
    try
        result = fn()
        @logmsg level "$label: ok ($(round((time() - t0) * 1000; digits = 1)) ms)"
        return result
    catch err
        @logmsg level "$label: error after $(round((time() - t0) * 1000; digits = 1)) ms — $(typeof(err))"
        rethrow()
    end
end
