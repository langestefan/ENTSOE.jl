```@meta
CurrentModule = ENTSOE
```

# Tutorial: five years of NL day-ahead prices

ENTSO-E caps most time-series endpoints at **one year per request**
— hand a multi-year window to [`day_ahead_prices`](@ref) directly and
the platform silently truncates. The package's
[`query_split`](@ref) helper chunks the period, calls the wrapper
once per chunk, skips empty windows automatically, and concatenates
the results.

This tutorial walks **2020 through 2024** of Dutch day-ahead prices
— five yearly cassettes pre-recorded under
`test/cassettes/tut_prices_NL_<year>.yml` and replayed offline.

## Setup

```@example multiyear
using ENTSOE
using CairoMakie
using Statistics: mean, median, quantile
using Dates

CairoMakie.activate!(type = "png")

include(joinpath(pkgdir(ENTSOE), "test", "_brokenrecord_helpers.jl"))
const BR = _load_brokenrecord()
client = ENTSOEClient("PLAYBACK")
nothing # hide
```

## One call, five chunks

`query_split` handles all the period-arithmetic:

```@example multiyear
prices = BR.playback("tut_prices_NL_2020_2024.yml") do
    query_split(
        day_ahead_prices,
        client, EIC.NL,
        DateTime("2019-12-31T23:00"),
        DateTime("2024-12-31T23:00");
        window = Year(1),
    )
end
length(prices), prices[1], prices[end]
```

Internally, the single call expanded into five
`day_ahead_prices(...)` — one per yearly window — and `vcat`'d the
resulting `StructVector`s. Each chunk is hourly (8 760-ish points),
so the whole window lands at ~44 k rows. BrokenRecord captured all
five HTTP responses in one cassette during recording; the playback
above replays them in the same order.

## Yearly distributions

With five years of hourly prices in one `StructVector`, the column
view (`prices.value`) is a plain `Vector{Float64}` and we can pivot
on year for a box plot. Years have different lengths (DST + the odd
incomplete chunk), so we materialise a long-form `(year, value)`
pair list rather than an equal-shape matrix:

```@example multiyear
years = year.(prices.time)

xs = Int[]
ys = Float64[]
for y in 2020:2024
    mask = years .== y
    append!(ys, prices.value[mask])
    append!(xs, fill(y, count(mask)))
end

fig = Figure(size = (820, 460))
ax = Axis(fig[1, 1];
    xlabel = "Year",
    ylabel = "EUR / MWh",
    title  = "NL day-ahead prices, 2020-2024 (hourly)",
)
boxplot!(ax, xs, ys;
    width = 0.6, mediancolor = :white, color = :steelblue,
)
ax.xticks = (2020:2024, string.(2020:2024))
fig
save(joinpath(@__DIR__, "assets", "tut_multiyear_box.png"), fig); nothing # hide
```

The picture matches the well-known story:

- **2020** — covid-quiet, very low prices (annual average around
  €30 / MWh).
- **2021–2022** — the gas crisis: 2021 ramps up, 2022 shows the
  highest medians by far, with a long upper tail.
- **2023–2024** — partial normalisation, but still well above the
  2020 baseline.

## Quick stats per year

`StructVector` columns are plain typed vectors — annual statistics
are one-liners:

```@example multiyear
function summarise(year_prices)
    p = year_prices
    return (
        mean      = round(mean(p);            digits = 2),
        median    = round(median(p);          digits = 2),
        p95       = round(quantile(p, 0.95);  digits = 2),
        max       = round(maximum(p);         digits = 2),
        negative  = count(<(0), p),
    )
end

[(year = y, summarise(prices.value[years .== y])...) for y in 2020:2024]
```

The `negative` column counts hours with a negative clearing price
— a signal of oversupply (windy + sunny + low demand). 2024 has the
most by far in this snapshot, which tracks NL's solar build-out.

## Monthly mean trace

```@example multiyear
ym = [(year(t), month(t)) for t in prices.time]
unique_ym = sort!(unique(ym))
monthly = [mean(prices.value[ym .== ym0]) for ym0 in unique_ym]

fig2 = Figure(size = (900, 320))
ax2 = Axis(fig2[1, 1];
    xlabel = "",
    ylabel = "EUR / MWh",
    title  = "NL day-ahead price — monthly mean",
)
lines!(ax2, 1:length(monthly), monthly; color = :firebrick, linewidth = 1.6)
ax2.xticks = (
    [findfirst(==((y, 1)), unique_ym) for y in 2020:2024],
    string.(2020:2024),
)
fig2
save(joinpath(@__DIR__, "assets", "tut_multiyear_monthly.png"), fig2); nothing # hide
```

## Where to next

- The same `query_split` pattern works for any wrapper whose first
  positional args end in `(start, stop)` — e.g.
  [`actual_total_load`](@ref), [`cross_border_physical_flows`](@ref),
  forecasts, generation per type. Pass `window = Day(1)` for
  endpoints with daily caps (a few balancing series).
- Empty chunks (`ENTSOEAcknowledgement` reason 999) are caught
  inside `query_split` and skipped — so a 5-year request that
  spans some incomplete months still returns whatever is available.
- The [response-format dispatch](julia_reference.md#Parsed-vs.-raw-—-the-`ResponseFormat`-dispatch)
  works through `query_split` too: pass `Raw()` as a trailing
  positional arg if you want each chunk's XML body, then aggregate
  yourself.
