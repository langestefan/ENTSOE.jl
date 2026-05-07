# XML response parsing for ENTSO-E documents.
#
# Every Transparency Platform endpoint returns `application/xml` — the
# generated wrapper functions hand it back as a `String`. This file lifts
# the most common shapes into Julia data structures.
#
# We don't try to model the full IEC 62325 schema (200+ document types,
# many revisions). Instead we walk the DOM with EzXML and extract the
# fields that almost every TimeSeries document carries. Users who need
# field access we don't expose can still drop down to EzXML directly via
# `parsexml(xml)` — the strings we return are unmodified.

using EzXML: EzXML, parsexml, root, elements, nodename, nodecontent
using Dates: Dates, DateTime, Minute
using StructArrays: StructArray, StructArrays

# ---------------------------------------------------------------------------
# Internal helpers — DOM walking with namespace-agnostic name matching.
# ENTSO-E XML uses default-namespaced documents, which makes XPath queries
# clunky; `nodename` strips the prefix so a plain comparison works.

_named(el::EzXML.Node, name::AbstractString) =
    [c for c in elements(el) if nodename(c) == name]

function _first_named(el::EzXML.Node, name::AbstractString)
    for c in elements(el)
        nodename(c) == name && return c
    end
    return nothing
end

# Resolve the most common ISO-8601 durations the API uses to whole minutes.
# These are the only resolutions ENTSO-E currently emits; anything else
# is a spec change and we'd rather fail loud than silently misalign.
function _resolution_minutes(s::AbstractString)
    s == "PT15M"  && return 15
    s == "PT30M"  && return 30
    s == "PT60M"  && return 60
    s == "PT1H"   && return 60
    s == "P1D"    && return 60 * 24
    s == "P7D"    && return 60 * 24 * 7
    s == "P1M"    && return 60 * 24 * 30   # nominal
    s == "P1Y"    && return 60 * 24 * 365  # nominal
    error("unsupported ENTSO-E resolution `$s`; please open an issue")
end

# ENTSO-E ISO timestamps look like `2024-09-01T22:00Z`. Drop the trailing
# `Z` (`DateTime` is naive, parsed values are always interpreted as UTC).
_parse_entsoe_datetime(s::AbstractString) = DateTime(s[1:min(end, 16)])

# ---------------------------------------------------------------------------
# Public parsers

"""
    parse_timeseries(xml) -> StructVector{@NamedTuple{time::DateTime, value::Float64}}

Walk every `<TimeSeries>/<Period>/<Point>` in the document and produce a
[Tables.jl](https://github.com/JuliaData/Tables.jl)-compatible
[`StructVector`](https://github.com/JuliaArrays/StructArrays.jl) with
two columns:

- `time`  — `DateTime` (UTC) computed from `<timeInterval>/<start>` plus
  `(position - 1) * resolution`
- `value` — `Float64` from `<quantity>` (load, generation, capacity,
  balancing volumes) or `<price.amount>` (price documents), whichever
  the point carries.

The result indexes like a `Vector{NamedTuple}` (`prices[1].value`) and
also exposes columns directly (`prices.value`, `prices.time` —
`Vector{Float64}` / `Vector{DateTime}`). It plumbs straight into
DataFrames (`DataFrame(prices)`) and any other Tables.jl consumer.

Returns an empty `StructVector` if the document has no usable TimeSeries
— typically because the API returned an
[`ENTSOEAcknowledgement`](@ref). For typed handling of that case use a
pipeline that calls [`check_acknowledgement`](@ref) first.

# Example
```julia
using ENTSOE, Dates

client = ENTSOEClient(ENV["ENTSOE_API_TOKEN"])
prices = day_ahead_prices(client, EIC.NL,
    DateTime("2024-09-01T22:00"), DateTime("2024-09-02T22:00"))

prices[1]      # → (time = DateTime("2024-09-01T22:00"), value = 91.24)
prices.value   # Vector{Float64} of all 24 prices
mean(prices.value)
DataFrame(prices)
```
"""
function parse_timeseries(xml::AbstractString)
    times = DateTime[]
    values = Float64[]
    doc = parsexml(xml)
    for ts in _named(root(doc), "TimeSeries"),
            period in _named(ts, "Period")

        ti = _first_named(period, "timeInterval")
        ti === nothing && continue
        start_node = _first_named(ti, "start")
        start_node === nothing && continue
        start = _parse_entsoe_datetime(nodecontent(start_node))

        res_node = _first_named(period, "resolution")
        res_node === nothing && continue
        stride = _resolution_minutes(nodecontent(res_node))

        for pt in _named(period, "Point")
            pos_node = _first_named(pt, "position")
            pos_node === nothing && continue
            pos = parse(Int, nodecontent(pos_node))
            vnode = something(
                _first_named(pt, "quantity"),
                _first_named(pt, "price.amount"),
                Some(nothing)
            )
            vnode === nothing && continue
            push!(times, start + Minute((pos - 1) * stride))
            push!(values, parse(Float64, nodecontent(vnode)))
        end
    end
    return StructArray((time = times, value = values))
end

"""
    parse_timeseries_per_psr(xml) -> StructVector{@NamedTuple{time::DateTime, psr_type::String, value::Float64}}

Like [`parse_timeseries`](@ref), but additionally extracts the
`<MktPSRType>/<psrType>` from each `<TimeSeries>` and tags every point
with it. Useful for documents that split data per production type, like
14.1.D (wind & solar forecast) and 16.1.B/C (actual generation per
production type) — where one TimeSeries holds Solar, another Wind
Onshore, etc.

Points without a `<MktPSRType>` get `psr_type = ""`.

The return value is a Tables.jl-compatible `StructVector` — index
rows (`rows[1]`), or pull a column (`rows.value`, `rows.psr_type`).

# Example
```julia
rows = actual_generation_per_production_type(client, EIC.NL,
    DateTime("2024-09-01T22:00"), DateTime("2024-09-02T22:00"))

# Pivot a column out:
solar_only = rows[rows.psr_type .== "B16"]
solar_only.value
```
"""
function parse_timeseries_per_psr(xml::AbstractString)
    times = DateTime[]
    psr_types = String[]
    values = Float64[]
    doc = parsexml(xml)
    for ts in _named(root(doc), "TimeSeries")
        psrwrap = _first_named(ts, "MktPSRType")
        psr = if psrwrap === nothing
            ""
        else
            n = _first_named(psrwrap, "psrType")
            n === nothing ? "" : nodecontent(n)
        end
        for period in _named(ts, "Period")
            ti = _first_named(period, "timeInterval")
            ti === nothing && continue
            start_node = _first_named(ti, "start")
            start_node === nothing && continue
            start = _parse_entsoe_datetime(nodecontent(start_node))
            res_node = _first_named(period, "resolution")
            res_node === nothing && continue
            stride = _resolution_minutes(nodecontent(res_node))

            for pt in _named(period, "Point")
                pos_node = _first_named(pt, "position")
                pos_node === nothing && continue
                pos = parse(Int, nodecontent(pos_node))
                vnode = something(
                    _first_named(pt, "quantity"),
                    _first_named(pt, "price.amount"),
                    Some(nothing)
                )
                vnode === nothing && continue
                push!(times, start + Minute((pos - 1) * stride))
                push!(psr_types, psr)
                push!(values, parse(Float64, nodecontent(vnode)))
            end
        end
    end
    return StructArray((time = times, psr_type = psr_types, value = values))
end

"""
    parse_installed_capacity(xml) -> StructVector{@NamedTuple{psr_type::String, capacity_mw::Float64}}

Parse a 14.1.A "Installed Capacity per Production Type" document.
Returns one row per `<TimeSeries>` — each contains a single
`<MktPSRType>/<psrType>` (e.g. `"B16"` for Solar) and a `<Period>`
with one `<Point>` carrying the year-ahead declared capacity in MW.

Tables.jl-compatible `StructVector`. Pull a column directly with
`rows.capacity_mw` (`Vector{Float64}`) or `rows.psr_type`
(`Vector{String}`); convert with `DataFrame(rows)`.

The `psr_type` codes are documented in [`PSR_TYPE`](@ref); pass through
[`describe(PSR_TYPE, code)`](@ref describe) for human-readable labels.

# Example
```julia
rows = installed_capacity_per_production_type(client, EIC.NL,
    DateTime("2024-12-31T23:00"), DateTime("2025-12-31T23:00"))

rows[1]              # → (psr_type = "B01", capacity_mw = 580.0)
rows.capacity_mw     # 14-element Vector{Float64}
sum(rows.capacity_mw)
```
"""
function parse_installed_capacity(xml::AbstractString)
    psr_types = String[]
    caps = Float64[]
    doc = parsexml(xml)
    for ts in _named(root(doc), "TimeSeries")
        psrwrap = _first_named(ts, "MktPSRType")
        psrwrap === nothing && continue
        psr_node = _first_named(psrwrap, "psrType")
        psr_node === nothing && continue
        psr = nodecontent(psr_node)

        period = _first_named(ts, "Period")
        period === nothing && continue
        for pt in _named(period, "Point")
            qty = _first_named(pt, "quantity")
            qty === nothing && continue
            push!(psr_types, psr)
            push!(caps, parse(Float64, nodecontent(qty)))
        end
    end
    return StructArray((psr_type = psr_types, capacity_mw = caps))
end

# ---------------------------------------------------------------------------
# Acknowledgement detection (also used by `check_acknowledgement`).

"""
    ENTSOEAcknowledgement(reason_code, text) <: APIError

Parsed `<Acknowledgement_MarketDocument>` payload — *also* a throwable
[`APIError`](@ref). ENTSO-E returns a 200 response containing this
document when there is no data for the requested query (also when the
query is ill-formed but well-typed). The official reason codes live in
the IEC 62325 reason-code list — the most commonly seen ones are:

  - `999` — "No matching data found" (your query was valid; the
    Transparency Platform just has nothing for that period / area).
  - `113` — "Not Authorized" (token rejected).
  - `400`–`499` — assorted client-side issues (bad parameter, …).

Use [`parse_acknowledgement`](@ref) for the non-throwing variant and
[`check_acknowledgement`](@ref) when you want it raised as an error.
"""
struct ENTSOEAcknowledgement <: APIError
    reason_code::String
    text::String
end

Base.show(io::IO, ack::ENTSOEAcknowledgement) =
    print(io, "ENTSOEAcknowledgement($(repr(ack.reason_code)): $(ack.text))")

Base.showerror(io::IO, ack::ENTSOEAcknowledgement) =
    print(
    io, "ENTSOEAcknowledgement: ENTSO-E returned reason code ",
    repr(ack.reason_code), " — ", ack.text
)

"""
    parse_acknowledgement(xml) -> ENTSOEAcknowledgement | nothing

If the document root is `<Acknowledgement_MarketDocument>`, parse out
the first `<Reason>` element's `<code>` and `<text>` and return them.
Otherwise return `nothing`.

This is the low-level form. Most callers want
[`check_acknowledgement`](@ref) instead, which throws — turning silent
"no data" responses into typed errors.
"""
function parse_acknowledgement(xml::AbstractString)
    doc = parsexml(xml)
    nodename(root(doc)) == "Acknowledgement_MarketDocument" || return nothing
    reason = _first_named(root(doc), "Reason")
    reason === nothing && return ENTSOEAcknowledgement("", "")
    code_node = _first_named(reason, "code")
    text_node = _first_named(reason, "text")
    return ENTSOEAcknowledgement(
        code_node === nothing ? "" : nodecontent(code_node),
        text_node === nothing ? "" : nodecontent(text_node),
    )
end

"""
    check_acknowledgement(xml) -> xml

Throw an [`ENTSOEAcknowledgement`](@ref) if `xml` is an
`<Acknowledgement_MarketDocument>`; otherwise return the input string
unchanged. Designed to be chained inline:

```julia
xml = check_acknowledgement(xml)
rows = parse_timeseries(xml)
```

Equivalent to:

```julia
ack = parse_acknowledgement(xml)
ack === nothing || throw(ack)
```
"""
function check_acknowledgement(xml::AbstractString)
    ack = parse_acknowledgement(xml)
    ack === nothing || throw(ack)
    return xml
end

# ---------------------------------------------------------------------------
# ZIP-response handling.

"""
    unzip_response(zip_bytes) -> Vector{Pair{String, Vector{UInt8}}}

ENTSO-E sometimes returns very large queries (especially outage and
master-data exports) as a `application/zip` body containing multiple
XML files. Pass the raw response bytes (`Vector{UInt8}`) and get back
a list of `name => contents` pairs.

`String(contents)` then yields the XML for each entry, ready to feed
into [`parse_timeseries`](@ref) or any other parser.

```julia
using HTTP

resp = HTTP.get(url; query = q, status_exception = false)
if startswith(HTTP.header(resp, "Content-Type", ""), "application/zip")
    members = unzip_response(resp.body)
    for (name, bytes) in members
        rows = parse_timeseries(String(bytes))
        # …
    end
end
```

Uses the stdlib `ZipFile` (via `Pkg`) — no extra deps. If the bytes
aren't a valid ZIP, errors propagate from `ZipFile`.
"""
function unzip_response(zip_bytes::Vector{UInt8})
    # Lazy-import: `ZipFile.jl` isn't a hard dep of this package; we
    # ask the user to install it on demand. This keeps `application/xml`
    # users (the 95% case) from paying the dependency cost.
    pkgid = Base.identify_package("ZipFile")
    pkgid === nothing && throw(
        ArgumentError(
            "unzip_response needs ZipFile.jl. " *
                "Run `pkg> add ZipFile` to install."
        )
    )
    ZipFile = Base.require(pkgid)
    return Base.invokelatest(_unzip_response_impl, ZipFile, zip_bytes)
end

function _unzip_response_impl(ZipFile, zip_bytes)
    out = Pair{String, Vector{UInt8}}[]
    reader = ZipFile.Reader(IOBuffer(zip_bytes))
    try
        for entry in reader.files
            push!(out, entry.name => read(entry))
        end
    finally
        close(reader)
    end
    return out
end
