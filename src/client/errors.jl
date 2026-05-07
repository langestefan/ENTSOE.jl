"""
    APIError

Abstract supertype for all errors raised by this client.
"""
abstract type APIError <: Exception end

"""
    NetworkError(cause)

Wraps an underlying transport-layer exception (DNS failure, connection reset,
TLS handshake error, etc.).
"""
struct NetworkError <: APIError
    cause::Exception
end

"""
    ClientError(status, body, parsed=nothing)

A 4xx response — caller error. `parsed` may be `nothing` or the JSON-decoded
body, depending on `Content-Type`.
"""
struct ClientError <: APIError
    status::Int
    body::String
    parsed::Any
end
ClientError(status::Integer, body::AbstractString) = ClientError(Int(status), String(body), nothing)

"""
    ServerError(status, body, parsed=nothing)

A 5xx response — server-side failure.
"""
struct ServerError <: APIError
    status::Int
    body::String
    parsed::Any
end
ServerError(status::Integer, body::AbstractString) = ServerError(Int(status), String(body), nothing)

"""
    AuthError(status, message)

A 401 / 403 response — authentication or authorization failure.
"""
struct AuthError <: APIError
    status::Int
    message::String
end

"""
    RateLimitError(status=429; retry_after=nothing, body="")

A 429 response. `retry_after` is the parsed `Retry-After` header value in
seconds, or `nothing` when absent / unparsable.
"""
struct RateLimitError <: APIError
    status::Int
    retry_after::Union{Nothing, Float64}
    body::String
end
RateLimitError(; status::Integer = 429, retry_after = nothing, body::AbstractString = "") =
    RateLimitError(Int(status), retry_after === nothing ? nothing : Float64(retry_after), String(body))

"""
    TimeoutError(phase::Symbol)

Request exceeded the configured timeout. `phase` is `:connect`, `:read`, or
`:total`.
"""
struct TimeoutError <: APIError
    phase::Symbol
end

"""
    parse_retry_after(header) -> Union{Float64,Nothing}

Parse a `Retry-After` header value. Supports the `seconds` form only — HTTP
date form returns `nothing`.
"""
function parse_retry_after(header::AbstractString)
    s = strip(String(header))
    isempty(s) && return nothing
    n = tryparse(Float64, s)
    return n === nothing ? nothing : n
end
parse_retry_after(::Nothing) = nothing

"""
    check_response(status, body, headers=Dict()) -> Nothing

Throw the appropriate [`APIError`](@ref) subtype based on the HTTP status.
Returns `nothing` for 2xx responses.
"""
function check_response(
        status::Integer,
        body::AbstractString,
        headers::AbstractDict = Dict{String, String}(),
    )
    s = Int(status)
    if 200 <= s < 300
        return nothing
    elseif s == 401 || s == 403
        throw(AuthError(s, String(body)))
    elseif s == 429
        retry_after = parse_retry_after(get(headers, "Retry-After", nothing))
        throw(RateLimitError(; status = s, retry_after = retry_after, body = String(body)))
    elseif 400 <= s < 500
        throw(ClientError(s, String(body)))
    elseif 500 <= s < 600
        throw(ServerError(s, String(body)))
    else
        throw(ClientError(s, String(body)))
    end
end
