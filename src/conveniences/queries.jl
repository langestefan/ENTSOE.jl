# Hand-written, named-argument convenience wrappers around the most
# heavily used generated query functions.
#
# Why these exist:
#
#   1. Codes pre-filled. The generated wrappers take `documentType`,
#      `processType`, etc. as raw strings — every caller has to remember
#      that day-ahead prices are `A44`, that "Realised" is `A16`, …. Each
#      function below pre-fills the constants of its operation, so users
#      don't need to.
#
#   2. Friendly date arguments. The generated layer accepts `period_start
#      :: Int64` only (yyyymmddHHMM). Each wrapper accepts any of
#      `DateTime`, `Date`, `ZonedDateTime`, or a raw `Integer` and
#      normalises via `entsoe_period`.
#
#   3. Acknowledgement detection. ENTSO-E returns a 200 with an
#      `<Acknowledgement_MarketDocument>` when there is no data; that
#      gets re-raised as an `EntsoEAcknowledgement <: APIError` (see
#      `check_acknowledgement`).
#
#   4. Optional parsing. By default the result is the parsed time-series
#      (`Vector{(time, value)}` or `(time, psr_type, value)` depending on
#      the document shape). Pass `parsed = false` to get back the raw
#      XML string instead, useful for debugging.
#
# These wrappers live entirely outside `src/api/`, so re-running
# `gen/regenerate.jl` against a refreshed spec leaves them untouched.

using Dates: Dates, DateTime, Date

# Internal: normalise any of the accepted period inputs to the Int64
# yyyymmddHHMM expected by the generated layer. Identity for already-
# integer inputs.
_to_period(t::Integer)::Int64               = Int64(t)
_to_period(t::DateTime)::Int64              = entsoe_period(t)
_to_period(t::Date)::Int64                  = entsoe_period(t)
_to_period(t::Dates.AbstractDateTime)::Int64 = entsoe_period(t)
# Catch-all: lets JET infer `_to_period(::Any) -> Int64` even though the
# wrapper signatures take `period_start::Any`. At runtime an unsupported
# type errors loudly here rather than silently propagating into the
# generated function as a mistyped `Int64` argument.
_to_period(t)::Int64 = throw(ArgumentError(
    "unsupported period type $(typeof(t)) — pass DateTime, Date, " *
        "ZonedDateTime, or an Int64 yyyymmddHHMM."
))

# Internal: every wrapper either parses the XML or returns it raw. The
# `parser` argument is a function `xml::String -> Any`. `parsed=false`
# short-circuits and returns the XML.
function _query(api_call::Function, parser;
                parsed::Bool = true,
                validate::Bool = false,
                eics = (),
            )
    if validate
        for code in eics
            validate_eic(code; type = :BZN)
        end
    end
    xml, _ = api_call()
    check_acknowledgement(xml)
    return parsed ? parser(xml) : xml
end

# ---------------------------------------------------------------------------
# Market

"""
    day_ahead_prices(client, area, period_start, period_end; parsed=true)

Day-ahead clearing prices (Market 12.1.D, `documentType=A44`).

`area` is used as both `in_Domain` and `out_Domain` (they're always the
same for an internal day-ahead price query). `period_start` /
`period_end` accept `DateTime`, `Date`, `ZonedDateTime`, or a raw
`Int64` `yyyymmddHHMM`. Returns `Vector{(time::DateTime, value::Float64)}`
in EUR/MWh; `parsed=false` returns the raw XML.

Throws an [`EntsoEAcknowledgement`](@ref) if ENTSO-E reports no
matching data.

# Example
```julia
using Dates
client = EntsoEClient(ENV["ENTSOE_API_TOKEN"])
prices = day_ahead_prices(client, EIC.NL,
                          DateTime("2024-09-01T22:00"),
                          DateTime("2024-09-02T22:00"))
```
"""
function day_ahead_prices(
        client::Client, area::AbstractString,
        period_start, period_end;
        parsed::Bool = true,
        validate::Bool = false,
    )
    apis = entsoe_apis(client)
    return _query(parse_timeseries; parsed = parsed,
                  validate = validate, eics = (area,)) do
        EntsoE.market121_d_energy_prices(
            apis.market, "A44",
            _to_period(period_start), _to_period(period_end),
            String(area), String(area),
        )
    end
end

# ---------------------------------------------------------------------------
# Load

# Single helper — every Load 6.1.* shares the same shape, only
# `processType` differs.
function _load_query(
        client::Client, process::AbstractString, area::AbstractString,
        period_start, period_end;
        parsed::Bool,
        validate::Bool,
        api_fn::Function,
    )
    apis = entsoe_apis(client)
    return _query(parse_timeseries; parsed = parsed,
                  validate = validate, eics = (area,)) do
        api_fn(
            apis.load, "A65", String(process), String(area),
            _to_period(period_start), _to_period(period_end),
        )
    end
end

"""
    actual_total_load(client, area, start, stop; parsed=true)

Realised total system load (Load 6.1.A, `documentType=A65`,
`processType=A16`). Quarter-hour resolution. Returns
`Vector{(time, value)}` with `value` in MW.
"""
actual_total_load(client::Client, area, start, stop;
                  parsed = true, validate = false) =
    _load_query(
        client, "A16", area, start, stop;
        parsed = parsed, validate = validate,
        api_fn = EntsoE.load61_a_actual_total_load,
    )

"""
    day_ahead_load_forecast(client, area, start, stop; parsed=true)

Day-ahead total load forecast (Load 6.1.B, `processType=A01`).
"""
day_ahead_load_forecast(client::Client, area, start, stop;
                        parsed = true, validate = false) =
    _load_query(
        client, "A01", area, start, stop;
        parsed = parsed, validate = validate,
        api_fn = EntsoE.load61_b_day_ahead_total_load_forecast,
    )

"""
    week_ahead_load_forecast(client, area, start, stop; parsed=true)

Week-ahead total load forecast (Load 6.1.C, `processType=A31`).
"""
week_ahead_load_forecast(client::Client, area, start, stop;
                         parsed = true, validate = false) =
    _load_query(
        client, "A31", area, start, stop;
        parsed = parsed, validate = validate,
        api_fn = EntsoE.load61_c_week_ahead_total_load_forecast,
    )

"""
    month_ahead_load_forecast(client, area, start, stop; parsed=true)

Month-ahead total load forecast (Load 6.1.D, `processType=A32`).
"""
month_ahead_load_forecast(client::Client, area, start, stop;
                          parsed = true, validate = false) =
    _load_query(
        client, "A32", area, start, stop;
        parsed = parsed, validate = validate,
        api_fn = EntsoE.load61_d_month_ahead_total_load_forecast,
    )

"""
    year_ahead_load_forecast(client, area, start, stop; parsed=true)

Year-ahead total load forecast (Load 6.1.E, `processType=A33`).
"""
year_ahead_load_forecast(client::Client, area, start, stop;
                         parsed = true, validate = false) =
    _load_query(
        client, "A33", area, start, stop;
        parsed = parsed, validate = validate,
        api_fn = EntsoE.load61_e_year_ahead_total_load_forecast,
    )

# ---------------------------------------------------------------------------
# Generation

"""
    installed_capacity_per_production_type(client, area, start, stop; parsed=true)

Year-ahead installed capacity per production type (Generation 14.1.A,
`documentType=A68`, `processType=A33`). For a calendar-year window
spanning Dec 31 23:00 → Dec 31 23:00. Returns
`Vector{(psr_type::String, capacity_mw::Float64)}`; `parsed=false`
returns the raw XML.

Map `psr_type` codes to labels via [`PSR_TYPE`](@ref) /
[`describe`](@ref): `describe(PSR_TYPE, "B16") == "Solar"`.
"""
function installed_capacity_per_production_type(
        client::Client, area::AbstractString,
        period_start, period_end;
        parsed::Bool = true,
        validate::Bool = false,
    )
    apis = entsoe_apis(client)
    return _query(parse_installed_capacity; parsed = parsed,
                  validate = validate, eics = (area,)) do
        EntsoE.generation141_a_installed_capacity_per_production_type(
            apis.generation, "A68", "A33", String(area),
            _to_period(period_start), _to_period(period_end),
        )
    end
end

"""
    generation_forecast_day_ahead(client, area, start, stop; parsed=true)

Day-ahead total generation forecast (Generation 14.1.C,
`documentType=A71`, `processType=A01`). Returns
`Vector{(time, value)}` in MW.
"""
function generation_forecast_day_ahead(
        client::Client, area::AbstractString,
        period_start, period_end;
        parsed::Bool = true,
        validate::Bool = false,
    )
    apis = entsoe_apis(client)
    return _query(parse_timeseries; parsed = parsed,
                  validate = validate, eics = (area,)) do
        EntsoE.generation141_c_generation_forecast_day_ahead(
            apis.generation, "A71", "A01", String(area),
            _to_period(period_start), _to_period(period_end),
        )
    end
end

"""
    wind_solar_forecast(client, area, start, stop; parsed=true, psr_type=nothing)

Wind & solar forecast, day-ahead (Generation 14.1.D,
`documentType=A69`, `processType=A01`). The returned document carries
one TimeSeries per technology — we parse with
[`parse_timeseries_per_psr`](@ref), so each row is tagged with its
`psr_type` (`B16` Solar, `B18` Wind Offshore, `B19` Wind Onshore).

Pass `psr_type="B19"` to filter at the API level (returns just that
technology).
"""
function wind_solar_forecast(
        client::Client, area::AbstractString,
        period_start, period_end;
        parsed::Bool = true,
        validate::Bool = false,
        psr_type::Union{Nothing, AbstractString} = nothing,
    )
    apis = entsoe_apis(client)
    return _query(parse_timeseries_per_psr; parsed = parsed,
                  validate = validate, eics = (area,)) do
        EntsoE.generation141_d_generation_forecasts_for_wind_and_solar(
            apis.generation, "A69", "A01", String(area),
            _to_period(period_start), _to_period(period_end);
            psr_type = psr_type === nothing ? nothing : String(psr_type),
        )
    end
end

"""
    actual_generation_per_production_type(client, area, start, stop;
                                           parsed=true, psr_type=nothing)

Realised generation broken down by production type (Generation
16.1.B/C, `documentType=A75`, `processType=A16`). One TimeSeries per
technology — parse rows are `(time, psr_type, value)` with `value` in
MW.

Pass `psr_type="B16"` to fetch a single technology server-side.
"""
function actual_generation_per_production_type(
        client::Client, area::AbstractString,
        period_start, period_end;
        parsed::Bool = true,
        validate::Bool = false,
        psr_type::Union{Nothing, AbstractString} = nothing,
    )
    apis = entsoe_apis(client)
    return _query(parse_timeseries_per_psr; parsed = parsed,
                  validate = validate, eics = (area,)) do
        EntsoE.generation161_b_c_actual_generation_per_production_type(
            apis.generation, "A75", "A16", String(area),
            _to_period(period_start), _to_period(period_end);
            psr_type = psr_type === nothing ? nothing : String(psr_type),
        )
    end
end

# ---------------------------------------------------------------------------
# Transmission

"""
    cross_border_physical_flows(client, in_area, out_area, start, stop; parsed=true)

Cross-border physical flows between two bidding zones (Transmission
12.1.G, `documentType=A11`). Returns hourly `Vector{(time, value)}` in
MW.

Note ENTSO-E's ordering: `in_area` is the receiving zone, `out_area`
is the sending zone — flows are positive when they go *from* `out_area`
*into* `in_area`.
"""
function cross_border_physical_flows(
        client::Client,
        in_area::AbstractString, out_area::AbstractString,
        period_start, period_end;
        parsed::Bool = true,
        validate::Bool = false,
    )
    apis = entsoe_apis(client)
    return _query(parse_timeseries; parsed = parsed,
                  validate = validate, eics = (in_area, out_area)) do
        EntsoE.transmission121_g_cross_border_physical_flows(
            apis.transmission, "A11",
            String(out_area), String(in_area),  # generated layer takes (out, in) — see api/apis/api_TransmissionApi.jl
            _to_period(period_start), _to_period(period_end),
        )
    end
end

# ---------------------------------------------------------------------------
# OMI — paginated

"""
    omi_other_market_information(client, control_area, start, stop;
                                  document_type="A95", page_size=200,
                                  max_pages=25, validate=false)

Walk the OMI ("Other Market Information") endpoint with automatic
offset-based pagination. Each call to the underlying generated
function returns up to `page_size` documents (ENTSO-E hard-caps OMI
queries at 5000 entries total — `max_pages * page_size` defaults to
exactly that).

Returns a `Vector{String}` of XML payloads, one per page. Stops when a
page comes back as an [`EntsoEAcknowledgement`](@ref) (no more data)
or when `max_pages` is reached.

```julia
xmls = omi_other_market_information(
    client, EIC.NL,
    DateTime("2024-09-01T22:00"), DateTime("2024-09-30T22:00"),
)
# Each entry is a separate <Anomalies_MarketDocument> chunk; users
# parse them however they need (often with `parse_timeseries` or the
# raw XML).
```
"""
function omi_other_market_information(
        client::Client, control_area::AbstractString,
        period_start, period_end;
        document_type::AbstractString = "A95",
        page_size::Int = 200,
        max_pages::Int = 25,
        validate::Bool = false,
    )
    validate && validate_eic(control_area; type = :CTA)
    apis = entsoe_apis(client)
    dt = String(document_type)::String
    ca = String(control_area)::String
    ps = _to_period(period_start)::Int64
    pe = _to_period(period_end)::Int64
    pages = String[]
    for i in 0:(max_pages - 1)
        offset = i * page_size
        xml, _ = EntsoEAPI.omi_other_market_information(
            apis.omi, dt, ca, ps, pe;
            offset = offset,
        )
        # End-of-pagination signal is an Acknowledgement reason 999.
        ack = parse_acknowledgement(xml)
        if ack !== nothing
            i == 0 && throw(ack)   # acknowledgement on the first page is real
            break
        end
        push!(pages, xml)
    end
    return pages
end
