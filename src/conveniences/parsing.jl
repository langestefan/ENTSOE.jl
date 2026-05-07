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
    parse_timeseries(xml) -> Vector{(time::DateTime, value::Float64)}

Walk every `<TimeSeries>/<Period>/<Point>` in the document and produce a
flat vector of `(time, value)` tuples. Picks `<quantity>` (load,
generation, capacity, balancing volumes) or `<price.amount>` (price
documents), whichever is present on the point.

Times are computed from `<timeInterval>/<start>` plus
`(position - 1) * resolution`, in UTC.

Returns an empty vector if the document has no usable TimeSeries —
typically because the API returned an
[`EntsoEAcknowledgement`](@ref). For typed handling of that case use a
pipeline that calls [`check_acknowledgement`](@ref) first.

# Example
```julia
using EntsoE, Dates

client = EntsoEClient(ENV["ENTSOE_API_TOKEN"])
apis   = entsoe_apis(client)
xml, _ = market121_d_energy_prices(
    apis.market, "A44",
    entsoe_period(DateTime("2024-09-01T22:00")),
    entsoe_period(DateTime("2024-09-02T22:00")),
    EIC.NL, EIC.NL,
)
prices = parse_timeseries(xml)
prices[1]   # → (time = DateTime("2024-09-01T22:00"), value = ...)
```
"""
function parse_timeseries(xml::AbstractString)
    rows = NamedTuple{(:time, :value), Tuple{DateTime, Float64}}[]
    doc = parsexml(xml)
    for ts in _named(root(doc), "TimeSeries"),
        period in _named(ts, "Period")

        ti      = _first_named(period, "timeInterval")
        ti      === nothing && continue
        start_node = _first_named(ti, "start")
        start_node === nothing && continue
        start   = _parse_entsoe_datetime(nodecontent(start_node))

        res_node = _first_named(period, "resolution")
        res_node === nothing && continue
        stride   = _resolution_minutes(nodecontent(res_node))

        for pt in _named(period, "Point")
            pos_node = _first_named(pt, "position")
            pos_node === nothing && continue
            pos = parse(Int, nodecontent(pos_node))
            vnode = something(_first_named(pt, "quantity"),
                              _first_named(pt, "price.amount"),
                              Some(nothing))
            vnode === nothing && continue
            push!(rows, (
                time  = start + Minute((pos - 1) * stride),
                value = parse(Float64, nodecontent(vnode)),
            ))
        end
    end
    return rows
end

"""
    parse_timeseries_per_psr(xml) -> Vector{(time, psr_type, value)}

Like [`parse_timeseries`](@ref), but additionally extracts the
`<MktPSRType>/<psrType>` from each `<TimeSeries>` and tags every point
with it. Useful for documents that split data per production type, like
14.1.D (wind & solar forecast) and 16.1.B/C (actual generation per
production type) — where one TimeSeries holds Solar, another Wind
Onshore, etc.

Points without a `<MktPSRType>` get `psr_type = ""`.

# Example
```julia
xml, _ = generation161_b_c_actual_generation_per_production_type(
    apis.generation, "A75", "A16", EIC.NL, start_p, stop_p,
)
rows = parse_timeseries_per_psr(xml)
solar = filter(r -> r.psr_type == "B16", rows)   # solar generation only
```
"""
function parse_timeseries_per_psr(xml::AbstractString)
    rows = NamedTuple{
        (:time, :psr_type, :value),
        Tuple{DateTime, String, Float64},
    }[]
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
            start  = _parse_entsoe_datetime(nodecontent(start_node))
            res_node = _first_named(period, "resolution")
            res_node === nothing && continue
            stride = _resolution_minutes(nodecontent(res_node))

            for pt in _named(period, "Point")
                pos_node = _first_named(pt, "position")
                pos_node === nothing && continue
                pos = parse(Int, nodecontent(pos_node))
                vnode = something(_first_named(pt, "quantity"),
                                  _first_named(pt, "price.amount"),
                                  Some(nothing))
                vnode === nothing && continue
                push!(rows, (
                    time     = start + Minute((pos - 1) * stride),
                    psr_type = psr,
                    value    = parse(Float64, nodecontent(vnode)),
                ))
            end
        end
    end
    return rows
end

"""
    parse_installed_capacity(xml) -> Vector{(psr_type, capacity_mw)}

Parse a 14.1.A "Installed Capacity per Production Type" document.
Returns one row per `<TimeSeries>` — each contains a single
`<MktPSRType>/<psrType>` (e.g. `"B16"` for Solar) and a `<Period>`
with one `<Point>` carrying the year-ahead declared capacity in MW.

The `psr_type` codes are documented in [`PSR_TYPE`](@ref); pass through
[`describe(PSR_TYPE, code)`](@ref describe) for human-readable labels.

# Example
```julia
xml, _ = generation141_a_installed_capacity_per_production_type(
    apis.generation, "A68", "A33", EIC.NL, year_start, year_end,
)
rows = parse_installed_capacity(xml)
rows[1]   # → (psr_type = "B14", capacity_mw = 485.0)  # Nuclear
```
"""
function parse_installed_capacity(xml::AbstractString)
    rows = NamedTuple{(:psr_type, :capacity_mw), Tuple{String, Float64}}[]
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
            push!(rows, (
                psr_type    = psr,
                capacity_mw = parse(Float64, nodecontent(qty)),
            ))
        end
    end
    return rows
end

# ---------------------------------------------------------------------------
# Acknowledgement detection (also used by `check_acknowledgement`).

"""
    EntsoEAcknowledgement(reason_code, text) <: APIError

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
struct EntsoEAcknowledgement <: APIError
    reason_code::String
    text::String
end

Base.show(io::IO, ack::EntsoEAcknowledgement) =
    print(io, "EntsoEAcknowledgement($(repr(ack.reason_code)): $(ack.text))")

Base.showerror(io::IO, ack::EntsoEAcknowledgement) =
    print(io, "EntsoEAcknowledgement: ENTSO-E returned reason code ",
          repr(ack.reason_code), " — ", ack.text)

"""
    parse_acknowledgement(xml) -> EntsoEAcknowledgement | nothing

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
    reason === nothing && return EntsoEAcknowledgement("", "")
    code_node = _first_named(reason, "code")
    text_node = _first_named(reason, "text")
    return EntsoEAcknowledgement(
        code_node === nothing ? "" : nodecontent(code_node),
        text_node === nothing ? "" : nodecontent(text_node),
    )
end

"""
    check_acknowledgement(xml) -> xml

Throw an [`EntsoEAcknowledgement`](@ref) if `xml` is an
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
    pkgid === nothing && throw(ArgumentError(
        "unzip_response needs ZipFile.jl. " *
            "Run `pkg> add ZipFile` to install."
    ))
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
