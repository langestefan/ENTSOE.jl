"""
    Client(base_url::AbstractString; auth::Auth = NoAuth(), kwargs...)

Ergonomic wrapper around `OpenAPI.Clients.Client`. Composes an [`Auth`](@ref)
strategy into the inner client's `pre_request_hook`. Extra `kwargs` are
forwarded verbatim to `OpenAPI.Clients.Client`.

For retry / rate-limit / timeout / logging, compose the call with
[`with_defaults`](@ref) or [`default_middleware`](@ref) — the `Client`
itself stays minimal so users can pick their own stack per call.
"""
struct Client
    inner::OpenAPI.Clients.Client
    auth::Auth
    base_url::String
end

function Client(base_url::AbstractString; auth::Auth = NoAuth(), kwargs...)
    url = String(base_url)
    inner = OpenAPI.Clients.Client(
        url;
        pre_request_hook = build_pre_request_hook(auth),
        kwargs...,
    )
    return Client(inner, auth, url)
end
