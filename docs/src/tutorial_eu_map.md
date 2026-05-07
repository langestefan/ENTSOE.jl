```@meta
CurrentModule = ENTSOE
```

# Tutorial: 2025 day-ahead prices across Europe (animated map)

A second walkthrough — this one fans out across most of Europe and
animates the **monthly mean day-ahead clearing price** for every
bidding zone in our `EIC` table over calendar year 2025.

The data was pulled once with the live API (one year-long
[`day_ahead_prices`](@ref) call per zone) and pre-aggregated into a
small JSON fixture committed to the repo at
`docs/src/assets/eu_monthly_prices_2025.json`. The script that
produced it is `scripts/record_eu_prices_2025.jl`; re-run it with a
valid token when 2026 closes out and the fixture refreshes itself.

Pre-aggregation is a deliberate scope choice — a year of quarter-hour
prices is ~2 MB raw per zone, and we have 25 zones; baking the
12-number monthly summary keeps the docs build offline, fast, and
small (~12 KB).

## Loading the fixture

```@example eu_map
using ENTSOE
using JSON

const FIXTURE = joinpath(pkgdir(ENTSOE), "docs", "src", "assets",
                         "eu_monthly_prices_2025.json")
data = JSON.parsefile(FIXTURE)
year = data["year"]
zones = data["zones"]
(year = year, zone_count = length(zones))
```

A peek at one entry — Netherlands, January through December (EUR/MWh):

```@example eu_map
nl = zones[findfirst(z -> z["name"] == "Netherlands", zones)]
[(month = m, price = round(nl["monthly_eur_mwh"][m]; digits = 1))
 for m in 1:12]
```

## How the recording happens (illustration)

The aggregation script's core loop is short — lift this snippet into
your own code if you need year-long data for any zone:

```julia
using ENTSOE, Dates, Statistics

client = ENTSOEClient(ENV["ENTSOE_API_TOKEN"])
rows   = day_ahead_prices(client, EIC.NL,
            DateTime("2024-12-31T23:00"),
            DateTime("2025-12-31T23:00"))

# Group by calendar month → mean. ENTSO-E timestamps are UTC; the
# script uses CET (Dec 31 23:00 UTC = Jan 1 00:00 CET) to match the
# market's natural calendar.
monthly = let sums = zeros(12), counts = zeros(Int, 12)
    for r in rows
        m = month(r.time)
        sums[m] += r.value; counts[m] += 1
    end
    [sums[m] / counts[m] for m in 1:12]
end
```

The fixture is the same shape: one entry per zone, one mean per month.

## Setting up the map

We use [GeoMakie](https://geo.makie.org/stable/) to draw country
polygons (Natural Earth Admin-0 dataset) projected with Lambert
Conformal Conic, and color each by its monthly mean price. Zones
that overlap one country (DE_LU spans both Germany and Luxembourg,
DK1 only Western Denmark, NO2/SE3 only southern halves) are coloured
on the country polygon — close enough for a tutorial.

```@example eu_map
using GeoMakie, WGLMakie, Bonito
using GeoMakie: NaturalEarth

WGLMakie.activate!()

# `exportable = true` inlines every JS / CSS asset into the rendered
# HTML so the `App()` block below works on the static documentation
# site without a running Julia process. `offline = true` tells Bonito
# not to even try to open a WebSocket back to a server. Bonito tries
# to auto-detect this for known platforms (Documenter included), but
# spelling it out keeps things deterministic across rebuilds.
Page(; exportable = true, offline = true)

# Natural Earth medium-detail country polygons. Cached after first
# fetch — subsequent runs are fast.
countries_fc = NaturalEarth.naturalearth("admin_0_countries", 50)
length(countries_fc)
```

Now build a lookup `iso2 -> price[12]` from the fixture:

```@example eu_map
price_by_iso = Dict{String, Vector{Float64}}()
for z in zones
    price_by_iso[z["iso2"]] = Float64.(z["monthly_eur_mwh"])
end
sort(collect(keys(price_by_iso)))
```

For each country polygon, decide whether it's one of our zones — we
match on Natural Earth's two-letter ISO code (`:ISO_A2_EH`, falling
back to `:ISO_A2`; the GeoJSON properties are `Symbol`-keyed).

For label *positions* a bounding-box centroid would be wrong for
several countries — France includes Réunion and French Guiana, ES/PT
include the Canaries and Azores, Norway includes Svalbard, the
Netherlands includes Bonaire — so their bbox centres fall in the
ocean. Easier and more reliable: a small hand-picked table of mainland
visual-centre coordinates, one per ISO code. Anywhere on land that
reads well at the chosen projection works.

```@example eu_map
const LABEL_COORDS = Dict(
    "AT" => (14.0, 47.5),  "BE" => ( 4.5, 50.5),  "CH" => ( 8.2, 46.8),
    "CZ" => (15.5, 49.8),  "DE" => (10.5, 51.0),  "DK" => ( 9.5, 55.7),
    "EE" => (25.5, 58.7),  "ES" => (-3.7, 40.4),  "FI" => (26.0, 64.0),
    "FR" => ( 2.5, 46.5),  "GR" => (22.0, 39.0),  "HR" => (15.5, 45.1),
    "HU" => (19.0, 47.2),  "IE" => (-8.0, 53.4),  "IT" => (12.5, 42.5),
    "LT" => (24.0, 55.3),  "LV" => (24.6, 56.8),  "NL" => ( 5.5, 52.2),
    "NO" => ( 9.5, 61.5),  "PL" => (19.0, 52.0),  "PT" => (-8.0, 39.5),
    "RO" => (25.0, 45.9),  "SE" => (16.5, 62.5),  "SI" => (14.6, 46.1),
    "SK" => (19.5, 48.7),
)

function _country_iso2(feature)
    p = feature.properties
    for key in (:ISO_A2_EH, :ISO_A2)
        v = get(p, key, nothing)
        v === nothing && continue
        v isa AbstractString && v != "-99" && return String(v)
    end
    return ""
end

plotted_geoms   = []
plotted_iso     = String[]
plotted_centers = Tuple{Float64, Float64}[]
for feat in countries_fc
    iso = _country_iso2(feat)
    haskey(price_by_iso, iso) || continue
    haskey(LABEL_COORDS, iso)  || continue
    push!(plotted_geoms, feat.geometry)
    push!(plotted_iso, iso)
    push!(plotted_centers, LABEL_COORDS[iso])
end

(plotted = length(plotted_geoms),)
```

## The interactive map

The map below is rendered with WGLMakie + Bonito. A slider at the top
lets you scrub through the year — every priced country re-colors and
re-labels in place as you drag. Behind the scenes each per-country
colour and label is `lift`-ed from the slider's value, so the only
mutation per frame is `slider.value[] = new_month` — Makie's reactive
graph does the rest.

For *static* docs (no Julia process behind the page) we wrap the
returned DOM in [`Bonito.record_states`](https://simondanisch.github.io/Bonito.jl/stable/interactions.html).
That utility plays the slider through every value once at build time,
captures the observables that depend on it, and bakes the mapping into
the page so the JavaScript can switch states locally without a server.
Every per-country colour and label here `lift`s from the *same*
observable (`slider.value`), which is the case `record_states` handles
correctly.

```@example eu_map
const COLORMAP = :magma           # dark for low, bright for high
const PRICE_RANGE = (40.0, 160.0) # EUR/MWh — clamps the colour scale
const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

App() do session
    # Use `Bonito.Slider` (not `StylableSlider`): it implements the
    # widget interface required by `record_states` (`is_widget`,
    # `value_range`, `to_watch`). `StylableSlider` doesn't, so its
    # state changes wouldn't be recorded into the static page. The
    # `style` kwarg is splatted onto the underlying `<input>` so
    # `width: 100%` makes it stretch across the figure.
    slider = Bonito.Slider(1:12; style = "width: 100%; height: 1.4em;")
    month  = slider.value     # ::Observable{Int}

    title = lift(m -> "$year-$(lpad(m, 2, '0')) — " *
                      "$(MONTH_NAMES[m]) day-ahead price (EUR/MWh)",
                 month)

    fig = Figure(size = (720, 640))
    ax  = GeoAxis(fig[1, 1];
        dest   = "+proj=lcc +lat_1=35 +lat_2=65 +lat_0=50 +lon_0=10",
        limits = ((-15, 35), (34, 72)),
        title  = title,
        # Hide the lat/lon graticule. The horizontal parallels otherwise
        # slice straight through the price labels — a 50°N line cutting
        # through "146" reads as the third digit being chopped in half.
        xgridvisible = false, ygridvisible = false)

    # Backdrop: every European country in light grey.
    for feat in countries_fc
        poly!(ax, feat.geometry;
            color = :grey85, strokecolor = :white, strokewidth = 0.4)
    end
    # Foreground: priced zones, colour lifted from the slider.
    for (i, iso) in enumerate(plotted_iso)
        c = lift(m -> price_by_iso[iso][m], month)
        poly!(ax, plotted_geoms[i];
            color = c, colormap = COLORMAP, colorrange = PRICE_RANGE,
            strokecolor = :white, strokewidth = 0.6)
    end
    # Price labels — white text over a thin black outline. We use a
    # regular (non-bold) weight intentionally: bold combined with a
    # stroke double-weights every glyph, which makes three-digit
    # labels (100+) look cramped because adjacent strokes nearly
    # touch. Regular weight + stroke keeps the contrast against the
    # coloured polygons without crushing the digit spacing.
    for (i, iso) in enumerate(plotted_iso)
        lbl = lift(m -> string(round(Int, price_by_iso[iso][m])), month)
        text!(ax, plotted_centers[i]...;
            text = lbl, align = (:center, :center),
            fontsize = 14, color = :white,
            strokewidth = 1.0, strokecolor = :black,
            overdraw = true)
    end
    Colorbar(fig[1, 2];
        colormap = COLORMAP, colorrange = PRICE_RANGE, label = "EUR / MWh")

    # Bonito layout: slider (wide, with month-name caption) on top,
    # the WGLMakie figure below. The slider container fills the
    # available width via flex so it stretches to the figure width
    # rather than rendering as the StylableSlider default ~120 px.
    caption = lift(m -> "Month: $(MONTH_NAMES[m]) ($(year))", month)
    slider_row = DOM.div(
        DOM.div(slider; style = "flex: 1 1 auto; min-width: 0;"),
        DOM.span(caption;
            style = "margin-left: 1em; font-weight: 600; " *
                    "white-space: nowrap; min-width: 11em;");
        style = "display: flex; align-items: center; " *
                "width: 100%; max-width: 720px; " *
                "gap: 0.75em; padding: 0.5em 0 1em;",
    )
    # `record_states` walks the slider through every position once
    # at build-time and bakes the resulting observable values into
    # the page. With it the slider drags interactively in the static
    # HTML; without it the page boots but nothing reacts to drags.
    return Bonito.record_states(session, DOM.div(slider_row, fig))
end
```

## What it shows

A few patterns jump out month-to-month:

- **Winter peak (Jan–Feb)**. Continental Europe sits at €110–€150
  through the deep cold; Iberia is markedly cheaper as solar already
  contributes meaningfully.
- **Spring trough (Apr–Jun)**. Hydro, wind and solar overlap; prices
  drop into the €60–€80 band almost everywhere south of the Alps,
  while the Nordics slip into single-digit territory.
- **Summer rebound (Jul–Aug)**. South-east Europe (RO, GR, BG) pushes
  back up as cooling demand kicks in and hydro reservoirs draw down.
- **Autumn climb (Sep–Dec)**. Heating returns; CWE and the Iberian
  peninsula re-converge in the €80–€120 range by year-end.

The colour bar is clamped at €40–€160 so the seasonal swing dominates
the visual; outliers (single-digit Nordic months, occasional triple-
digit spikes in southeast Europe) saturate to the ends rather than
crushing the rest of the map.

## Where to next

- The "first-tutorial" walkthrough — [`tutorial.md`](tutorial.md) —
  drills into the day-ahead query for one zone (NL) and parses the
  full quarter-hour timeseries.
- For more zones than the 25 we cover here, edit the `ZONES` table
  in `scripts/record_eu_prices_2025.jl` and re-run; the JSON fixture
  picks up the additions automatically.
- See [`day_ahead_prices`](@ref) and the
  [REST API reference](api/index.md) for every endpoint we wrap.
