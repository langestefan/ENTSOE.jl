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

Build a client and configure BrokenRecord against our committed
cassette directory. All three queries below go through the
named-argument convenience wrappers ([`day_ahead_prices`](@ref),
[`actual_total_load`](@ref),
[`installed_capacity_per_production_type`](@ref)), which already
parse the XML and accept `DateTime` arguments directly — no
hand-written parsing or `entsoe_period(...)` boilerplate per call.

```@example tutorial
using EntsoE
using CairoMakie
using Dates: DateTime

import BrokenRecord

CairoMakie.activate!(type = "png")

# BrokenRecord 0.1 sizes its per-thread STATE vector at module load
# via `map(1:nthreads(), ...)`. Julia 1.12 routinely runs tasks on
# `threadid()` values higher than `nthreads()` (the interactive
# thread pool), so any `playback` call hits a `BoundsError`. Pad the
# vector to cover every reachable thread.
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
nothing # hide
```

## Day-ahead electricity prices

[`day_ahead_prices`](@ref) wraps Market 12.1.D
(`documentType=A44`). It pre-fills both `in_Domain` and `out_Domain`
to the requested area, normalises the period bounds, and returns a
parsed `Vector{(time, value)}` straight away.

```@example tutorial
prices = BrokenRecord.playback("market_121d_day_ahead_prices_NL.yml") do
    day_ahead_prices(client, EIC.NL,
        DateTime("2024-09-01T22:00"),
        DateTime("2024-09-02T22:00"))
end
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

[`actual_total_load`](@ref) wraps Load 6.1.A
(`documentType=A65`, `processType=A16`). Quarter-hour resolution,
returned as `Vector{(time, value)}` in MW.

```@example tutorial
load = BrokenRecord.playback("load_61a_actual_total_load_NL.yml") do
    actual_total_load(client, EIC.NL,
        DateTime("2024-09-01T22:00"),
        DateTime("2024-09-02T22:00"))
end
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

[`installed_capacity_per_production_type`](@ref) wraps Generation
14.1.A. The returned rows are `(psr_type, capacity_mw)` — translate
the codes to labels with [`describe`](@ref) against the
[`PSR_TYPE`](@ref) table.

```@example tutorial
cap_rows = BrokenRecord.playback("generation_141a_installed_capacity_NL.yml") do
    installed_capacity_per_production_type(client, EIC.NL,
        DateTime("2023-12-31T23:00"),
        DateTime("2024-12-31T23:00"))
end
sort!(cap_rows, by = r -> -r.capacity_mw)
[(EntsoE.describe(PSR_TYPE, r.psr_type), round(r.capacity_mw; digits = 0))
 for r in cap_rows]
```

```@example tutorial
labels = [EntsoE.describe(PSR_TYPE, r.psr_type) for r in cap_rows]
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

## What changed since the last release of this page

Earlier versions of this tutorial shipped ~80 lines of inline
XML-walking code — `parse_timeseries`, `parse_installed_capacity`,
a `PSR_LABELS` dict — that callers had to copy into their own
projects. All of that is now part of the package:

- [`parse_timeseries`](@ref) /
  [`parse_timeseries_per_psr`](@ref) /
  [`parse_installed_capacity`](@ref) for the two common ENTSO-E
  document shapes.
- [`PSR_TYPE`](@ref), [`DOCUMENT_TYPE`](@ref),
  [`PROCESS_TYPE`](@ref), [`BUSINESS_TYPE`](@ref) for the standard
  code lists.
- The named-argument wrappers above (one per common endpoint) hide
  the magic codes and accept `DateTime` directly.

Drop down to the generated layer (`EntsoE.market121_d_energy_prices`,
…) only when you need an endpoint we haven't wrapped yet.

## Where to next

- The full set of generated wrapper functions is in the
  [REST API Reference](api/index.md) — each tag page lists every
  operation with its parameters and a Try-it-out playground.
- Browse the Julia-side names (helpers, types, generated functions
  with their docstrings) on the
  [Generated Reference](generated_reference.md) page.
- For very long historical queries, see
  [`query_split`](@ref) which chunks the period and concatenates
  results — ENTSO-E caps most endpoints at one year per request.
- See the cassette mechanism in `test/test-cassettes.jl` if you
  want to add fixtures for other endpoints.
