```@meta
CurrentModule = EntsoE
```

# Tutorial: a Dutch electricity day in three plots

This page walks through three queries against the
[ENTSO-E Transparency Platform API](https://transparencyplatform.zendesk.com/hc/en-us/sections/12783116987028-Web-API)
and plots the results with
[CairoMakie](https://docs.makie.org/stable/explanations/backends/cairomakie).

The HTTP traffic is **served from cassettes** under
`test/cassettes/`, recorded once with a real API token. That means
this page builds offline, on every CI run, with no credentials —
exactly the same data every time. To re-record (e.g. against a
different date), delete the relevant `.yml` and re-run the test
suite once with `ENTSOE_API_TOKEN` (or `token.txt`) set.

We focus on **the Netherlands on 2 September 2024** (a normal
shoulder-season weekday) for the time-series plots, and **NL
calendar-year 2024** for the installed-capacity bar chart.

## Setup

The setup block stays the same throughout the page: build a client,
configure BrokenRecord against our committed cassette directory,
and define a couple of XML parsing helpers that lift ENTSO-E's
`<TimeSeries>` documents into vectors of `(time, value)` /
`(production_type, capacity)` rows.

```@example tutorial
using EntsoE
using CairoMakie
using EzXML
using Dates: DateTime, Minute, Day

import BrokenRecord

CairoMakie.activate!(type = "png")

# BrokenRecord 0.1 sizes its per-thread STATE vector at module load
# via `map(1:nthreads(), ...)`. Julia 1.12 routinely runs tasks on
# `threadid()` values higher than `nthreads()` (the interactive thread
# pool), so any `playback` call hits a `BoundsError`. Pad the vector
# to cover every reachable thread.
let target = Base.Threads.maxthreadid()
    while length(BrokenRecord.STATE) < target
        template = BrokenRecord.STATE[1]
        push!(BrokenRecord.STATE, (
            responses = empty(template.responses),
            ignore_headers = String[],
            ignore_query = String[],
        ))
    end
end

const CASSETTES_DIR = joinpath(pkgdir(EntsoE), "test", "cassettes")

BrokenRecord.configure!(;
    path = CASSETTES_DIR,
    ignore_headers = ["Authorization", "X-API-Key", "User-Agent",
                      "Accept-Encoding"],
    ignore_query   = ["securityToken"],
)

# Token is irrelevant in playback mode — the HTTP layer is
# intercepted before the request reaches ENTSO-E. Any non-empty
# string lets `EntsoEClient` build a valid client.
client = EntsoEClient("PLAYBACK")
apis   = entsoe_apis(client)

nothing # hide
```

ENTSO-E always returns XML. There's no schema in the spec (every
operation's success type is `String`), so we parse it ourselves.
Two small helpers cover the two shapes used below — a generic
`<Period>`-with-`<Point>` time series and the installed-capacity
shape (one TimeSeries per production type):

```@example tutorial
"""
Find immediate child elements with this local name (namespace-agnostic).
"""
_named(el, name) = [c for c in elements(el) if nodename(c) == name]
_first(el, name) = (children = _named(el, name);
                    isempty(children) ? nothing : first(children))

# Map an ISO-8601 duration like `PT15M`, `PT60M`, `P1Y` to minutes.
function _resolution_minutes(s)
    s == "PT15M" && return 15
    s == "PT30M" && return 30
    s == "PT60M" && return 60
    s == "P1Y"   && return 60 * 24 * 365
    error("unsupported resolution: $s")
end

"""
    parse_timeseries(xml) -> Vector{(time, value)}

Walk every `<TimeSeries>/<Period>/<Point>` and produce a flat list
of `(::DateTime, ::Float64)` tuples. Picks `<quantity>` (load /
generation / capacity) or `<price.amount>` (price documents),
whichever is present.
"""
function parse_timeseries(xml::AbstractString)
    rows = NamedTuple{(:time, :value), Tuple{DateTime, Float64}}[]
    doc = parsexml(xml)
    for ts in _named(root(doc), "TimeSeries"),
        period in _named(ts, "Period")

        ti      = _first(period, "timeInterval")
        # ISO timestamps end in `Z` (`2024-09-01T22:00Z`); DateTime
        # accepts the prefix only.
        start   = DateTime(nodecontent(_first(ti, "start"))[1:16])
        stride  = _resolution_minutes(nodecontent(_first(period, "resolution")))
        for pt in _named(period, "Point")
            pos   = parse(Int, nodecontent(_first(pt, "position")))
            vnode = something(_first(pt, "quantity"),
                              _first(pt, "price.amount"))
            push!(rows, (
                time  = start + Minute((pos - 1) * stride),
                value = parse(Float64, nodecontent(vnode)),
            ))
        end
    end
    return rows
end

"""
    parse_installed_capacity(xml) -> Vector{(psr_type, capacity_mw)}

For 14.1.A "Installed Capacity per Production Type": one TimeSeries
per fuel/technology code with a single Point holding the year-ahead
declared capacity in MW.
"""
function parse_installed_capacity(xml::AbstractString)
    rows = NamedTuple{(:psr_type, :capacity_mw), Tuple{String, Float64}}[]
    doc = parsexml(xml)
    for ts in _named(root(doc), "TimeSeries")
        psrwrap = _first(ts, "MktPSRType")
        psrwrap === nothing && continue
        psr = nodecontent(_first(psrwrap, "psrType"))
        for pt in elements(_first(ts, "Period"))
            nodename(pt) == "Point" || continue
            qty = _first(pt, "quantity")
            qty === nothing && continue
            push!(rows, (
                psr_type    = psr,
                capacity_mw = parse(Float64, nodecontent(qty)),
            ))
        end
    end
    return rows
end

# A tiny dictionary of the ENTSO-E `psrType` codes we expect to see
# for NL — full list is on the Transparency Platform docs.
const PSR_LABELS = Dict(
    "B01" => "Biomass",
    "B04" => "Fossil Gas",
    "B05" => "Fossil Hard coal",
    "B09" => "Geothermal",
    "B10" => "Hydro Pumped Storage",
    "B11" => "Hydro Run-of-river",
    "B12" => "Hydro Reservoir",
    "B14" => "Nuclear",
    "B15" => "Other renewable",
    "B16" => "Solar",
    "B17" => "Waste",
    "B18" => "Wind Offshore",
    "B19" => "Wind Onshore",
    "B20" => "Other",
)

nothing # hide
```

Two date constants used by the time-series plots — same window
the cassettes were recorded with:

```@example tutorial
const PERIOD_START = entsoe_period(DateTime("2024-09-01T22:00"))
const PERIOD_END   = entsoe_period(DateTime("2024-09-02T22:00"))
nothing # hide
```

## Day-ahead electricity prices

Market document **12.1.D** publishes day-ahead clearing prices
(`documentType = A44`). For NL the auction is in EUR/MWh, hourly
resolution, 24 points per delivery day.

```@example tutorial
prices_xml, _ = BrokenRecord.playback("market_121d_day_ahead_prices_NL.yml") do
    EntsoE.market121_d_energy_prices(
        apis.market,
        "A44",
        PERIOD_START, PERIOD_END,
        EIC.NL, EIC.NL,
    )
end

prices = parse_timeseries(prices_xml)
length(prices), prices[1], prices[end]
```

```@example tutorial
fig = Figure(size = (900, 380))
ax = Axis(fig[1, 1];
    xlabel = "UTC time",
    ylabel = "EUR / MWh",
    title  = "NL day-ahead prices — delivery day 2024-09-02",
)
lines!(ax, [p.time for p in prices], [p.value for p in prices];
    color = :tomato, linewidth = 2)
hlines!(ax, [0.0]; color = (:black, 0.3), linestyle = :dot)
fig
```

The dip into negative territory in the early afternoon is the
characteristic shape of a sunny shoulder-season day on a grid with
a lot of solar — wholesale price sags as PV output peaks.

## Actual total load

Load document **6.1.A** (`documentType = A65`, `processType = A16`)
gives quarter-hour realised consumption per bidding zone in MAW
(megaampere-watts — i.e. MW).

```@example tutorial
load_xml, _ = BrokenRecord.playback("load_61a_actual_total_load_NL.yml") do
    EntsoE.load61_a_actual_total_load(
        apis.load,
        "A65", "A16",
        EIC.NL,
        PERIOD_START, PERIOD_END,
    )
end

load = parse_timeseries(load_xml)
length(load), load[1], load[end]
```

```@example tutorial
fig = Figure(size = (900, 380))
ax = Axis(fig[1, 1];
    xlabel = "UTC time",
    ylabel = "MW",
    title  = "NL actual total load — delivery day 2024-09-02",
)
lines!(ax, [p.time for p in load], [p.value for p in load];
    color = :steelblue, linewidth = 1.6)
fig
```

The double-hump morning + evening peak is the typical
working-day shape; valley around 02:00–04:00 UTC, ramp-up from
~06:00 as the country wakes up.

## Installed capacity by production type

Generation document **14.1.A** (`documentType = A68`,
`processType = A33` — year-ahead) returns each technology's
installed nameplate capacity. The cassette is for calendar year 2024:

```@example tutorial
cap_xml, _ = BrokenRecord.playback("generation_141a_installed_capacity_NL.yml") do
    EntsoE.generation141_a_installed_capacity_per_production_type(
        apis.generation,
        "A68", "A33",
        EIC.NL,
        entsoe_period(DateTime("2023-12-31T23:00")),
        entsoe_period(DateTime("2024-12-31T23:00")),
    )
end

cap_rows = parse_installed_capacity(cap_xml)
sort!(cap_rows, by = r -> -r.capacity_mw)
[(get(PSR_LABELS, r.psr_type, r.psr_type), round(r.capacity_mw; digits = 0))
 for r in cap_rows]
```

```@example tutorial
labels = [get(PSR_LABELS, r.psr_type, r.psr_type) for r in cap_rows]
mw     = [r.capacity_mw for r in cap_rows]
fig = Figure(size = (900, 480))
ax = Axis(fig[1, 1];
    xlabel = "MW",
    ylabel = "production type",
    title  = "NL installed capacity by production type — 2024",
    yticks = (1:length(labels), labels),
    yreversed = true,
)
barplot!(ax, 1:length(mw), mw;
    direction = :x, color = :seagreen, strokecolor = :black, strokewidth = 0.5)
fig
```

Solar and onshore wind dominate by nameplate, but the
capacity-factor story is very different — that's where the load
and generation timeseries endpoints come in.

## Combined view: load and price on the same window

Plotting load and price on twin axes for the same 24-hour window
shows how Dutch wholesale prices respond inversely to net load
(solar peak → low residual demand → low price → and vice versa
in the evening peak).

```@example tutorial
fig = Figure(size = (900, 460))
ax1 = Axis(fig[1, 1];
    xlabel = "UTC time",
    ylabel = "MW (load)",
    ylabelcolor = :steelblue,
    title  = "NL load vs day-ahead price — 2024-09-02",
)
ax2 = Axis(fig[1, 1];
    ylabel = "EUR / MWh",
    yaxisposition = :right,
    ylabelcolor = :tomato,
)
hidespines!(ax2)
hidexdecorations!(ax2)

lines!(ax1, [p.time for p in load], [p.value for p in load];
    color = :steelblue, linewidth = 1.6, label = "load")
lines!(ax2, [p.time for p in prices], [p.value for p in prices];
    color = :tomato, linewidth = 2, label = "price")
hlines!(ax2, [0.0]; color = (:black, 0.3), linestyle = :dot)

axislegend(ax1; position = :lt)
fig
```

## Where to next

- The full set of generated wrapper functions is in the
  [REST API Reference](api/index.md) — each tag page lists every
  operation with its parameters and a Try-it-out playground.
- Browse the Julia-side names (helpers, types, generated functions
  with their docstrings) on the
  [Generated Reference](generated_reference.md) page.
- See the cassette mechanism in `test/test-cassettes.jl` if you
  want to add fixtures for other endpoints.
