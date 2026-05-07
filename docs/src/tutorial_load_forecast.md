```@meta
CurrentModule = ENTSOE
```

# Tutorial: forecast vs. realised load

How well did the day-ahead load forecast track reality for the
Netherlands during the week of **2024-09-02 → 2024-09-09**?
This tutorial pulls two parallel series:

- [`actual_total_load`](@ref) — Load 6.1.A, `processType=A16`
  ("Realised").
- [`day_ahead_load_forecast`](@ref) — Load 6.1.B,
  `processType=A01` ("Day ahead").

…lines them up, plots both on the same axes, and computes the mean
absolute percentage error (MAP).

## Setup

```@example loadtut
using ENTSOE
using CairoMakie
using Statistics: mean
using Dates

CairoMakie.activate!(type = "png")

include(joinpath(pkgdir(ENTSOE), "test", "_brokenrecord_helpers.jl"))
const BR = _load_brokenrecord()
client = ENTSOEClient("PLAYBACK")
nothing # hide
```

## Two parallel series

Both wrappers have the same shape — same area code, same period
arguments, same `(time, value)` `StructVector` return — so we can
hit them back-to-back. Realised load first:

```@example loadtut
actual = BR.playback("tut_load_actual_NL_week.yml") do
    actual_total_load(
        client, EIC.NL,
        DateTime("2024-09-01T22:00"),
        DateTime("2024-09-08T22:00"))
end
length(actual), actual[1], actual[end]
```

…and the day-ahead forecast for the same window:

```@example loadtut
forecast = BR.playback("tut_load_forecast_NL_week.yml") do
    day_ahead_load_forecast(
        client, EIC.NL,
        DateTime("2024-09-01T22:00"),
        DateTime("2024-09-08T22:00"))
end
length(forecast), forecast[1]
```

Realised load is published at quarter-hour resolution; the forecast
is hourly. To compare apples-to-apples we line up *on-the-hour*
points by stepping through `actual` in strides of 4 — column views
on `StructVector` make this trivial:

```@example loadtut
actual_h = (
    time  = actual.time[1:4:end],
    value = actual.value[1:4:end],
)
length(actual_h.value) == length(forecast.value)
```

## Forecast accuracy

```@example loadtut
err   = forecast.value .- actual_h.value         # MW
ape   = abs.(err) ./ actual_h.value .* 100        # absolute percent error per hour
map  = mean(ape)
bias  = mean(err) / mean(actual_h.value) * 100    # signed bias as a %

(map_pct = round(map; digits = 2),
 bias_pct = round(bias; digits = 2),
 worst_hour_idx = argmax(ape),
 worst_pct = round(maximum(ape); digits = 2))
```

A MAP around 2 % is solid for a system-wide load forecast; the
**signed bias** tells us whether the forecast over- or under-shoots
on average.

## Plotting

```@example loadtut
fig = Figure(size = (900, 460))

ax1 = Axis(fig[1, 1];
    ylabel = "GW",
    title  = "NL load — actual vs. day-ahead forecast (week 2024-09-02)",
)
lines!(ax1, 1:length(actual_h.value), actual_h.value ./ 1_000;
    color = :black, linewidth = 1.4, label = "Realised")
lines!(ax1, 1:length(forecast.value), forecast.value ./ 1_000;
    color = :firebrick, linewidth = 1.4, linestyle = :dash, label = "Day-ahead forecast")
axislegend(ax1; position = :rb, framevisible = false)

ax2 = Axis(fig[2, 1];
    ylabel = "Forecast − actual (MW)",
    xlabel = "UTC time",
)
hlines!(ax2, [0]; color = :gray70, linewidth = 0.5)
band!(ax2, 1:length(err), zero(err), err;
    color = (ifelse.(err .>= 0, (:firebrick, 0.4), (:seagreen, 0.4))))
lines!(ax2, 1:length(err), err; color = :black, linewidth = 0.6)

# Shared x-axis labels.
linkxaxes!(ax1, ax2)
ax2.xticks = (
    1:24:length(err),
    [Dates.format(actual_h.time[i], "E dd") for i in 1:24:length(err)],
)
hidexdecorations!(ax1; grid = false)
rowgap!(fig.layout, 1, 6)
fig
save(joinpath(@__DIR__, "assets", "tut_load_forecast.png"), fig); nothing # hide
```

What you read from this:

- **Daily diurnal pattern** is captured well by the forecast — the
  morning ramp and evening shoulder track within a few hundred MW.
- **Errors cluster at the peaks**, where small percentage errors
  translate to bigger MW gaps.
- The **signed-error band** in the bottom panel shows where the
  forecast leans too high (red) versus too low (green).

## Where to next

- For longer horizons, the same pattern works with
  [`week_ahead_load_forecast`](@ref) (Load 6.1.C),
  [`month_ahead_load_forecast`](@ref) (6.1.D), and
  [`year_ahead_load_forecast`](@ref) (6.1.E).
- For the *generation* side of the forecast accuracy story, see
  [`generation_forecast_day_ahead`](@ref) and
  [`wind_solar_forecast`](@ref).
- For full-history accuracy work spanning multiple years, chain
  [`query_split`](@ref) — see
  [the multi-year tutorial](tutorial_multiyear.md).
