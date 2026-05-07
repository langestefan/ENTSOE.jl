#!/usr/bin/env julia
# record_eu_prices_2025.jl
# ========================
#
# One-shot script: pull day-ahead prices for every European bidding
# zone we want to plot, average each month, and write a small JSON
# fixture that the GeoMakie tutorial loads at docs-build time.
#
# Year-long raw cassettes (~2 MB / zone × 24 zones ≈ 50 MB) are
# overkill for a tutorial — pre-aggregating gets us under 5 KB total
# and lets the docs build offline forever. The script is idempotent
# and re-runnable when 2026 data is final.
#
# Usage
# -----
#     julia --project=docs scripts/record_eu_prices_2025.jl
#
# Token is read from `ENV["ENTSOE_API_TOKEN"]` first, then from
# `<repo-root>/token.txt`.

using Pkg

const ROOT = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(ROOT; io = devnull)

using ENTSOE
using Dates: Dates, DateTime, month
using Statistics: mean
using JSON

const ZONES = [
    # (label,         iso2, eic_code)
    ("Netherlands",   "NL", EIC.NL),
    ("Belgium",       "BE", EIC.BE),
    ("Germany–Lux",   "DE", EIC.DE_LU),
    ("France",        "FR", EIC.FR),
    ("Spain",         "ES", EIC.ES),
    ("Portugal",      "PT", EIC.PT),
    ("Italy (North)", "IT", EIC.IT_NORTH),
    ("Switzerland",   "CH", EIC.CH),
    ("Austria",       "AT", EIC.AT),
    ("Czechia",       "CZ", EIC.CZ),
    ("Slovakia",      "SK", EIC.SK),
    ("Hungary",       "HU", EIC.HU),
    ("Slovenia",      "SI", EIC.SI),
    ("Croatia",       "HR", EIC.HR),
    ("Romania",       "RO", EIC.RO),
    ("Greece",        "GR", EIC.GR),
    ("Poland",        "PL", EIC.PL),
    ("Denmark (W)",   "DK", EIC.DK1),
    ("Finland",       "FI", EIC.FI),
    ("Sweden (S)",    "SE", EIC.SE3),
    ("Norway (S)",    "NO", EIC.NO2),
    ("Estonia",       "EE", EIC.EE),
    ("Latvia",        "LV", EIC.LV),
    ("Lithuania",     "LT", EIC.LT),
    ("Ireland (SEM)", "IE", EIC.IE_SEM),
]

# ENTSO-E periods are UTC, and a "calendar year in CET" is the
# convention this market uses (Dec 31 23:00 UTC → Dec 31 23:00 UTC).
const PERIOD_START = DateTime("2024-12-31T23:00")
const PERIOD_END   = DateTime("2025-12-31T23:00")
const YEAR         = 2025

function _resolve_token()
    tok = get(ENV, "ENTSOE_API_TOKEN", "")
    isempty(tok) || return strip(tok)
    isfile(joinpath(ROOT, "token.txt")) &&
        return strip(read(joinpath(ROOT, "token.txt"), String))
    return ""
end

function _monthly_means(rows)
    sums   = zeros(Float64, 12)
    counts = zeros(Int, 12)
    for r in rows
        m = month(r.time)
        sums[m]   += r.value
        counts[m] += 1
    end
    return [counts[m] == 0 ? NaN : sums[m] / counts[m] for m in 1:12]
end

function main()
    token = _resolve_token()
    isempty(token) && error(
        "no ENTSOE_API_TOKEN in env or `token.txt` — cannot record."
    )
    client = ENTSOEClient(String(token))

    out = Dict{String, Any}(
        "year"    => YEAR,
        "comment" => "Day-ahead clearing prices, EUR/MWh, monthly mean. " *
                     "Recorded $(Dates.format(Dates.now(), "yyyy-mm-dd")) " *
                     "by `scripts/record_eu_prices_2025.jl`.",
        "zones"   => Dict{String, Any}[],
    )

    for (label, iso2, eic) in ZONES
        @info "fetching $(label) ($(eic))"
        rows = try
            day_ahead_prices(client, eic, PERIOD_START, PERIOD_END)
        catch e
            if e isa ENTSOEAcknowledgement
                @warn "$(label) returned acknowledgement; skipping" reason = e.text
                continue
            end
            rethrow()
        end
        means = _monthly_means(rows)
        push!(
            out["zones"], Dict(
                "name"            => label,
                "iso2"            => iso2,
                "eic"             => String(eic),
                "monthly_eur_mwh" => means,
                "n_points"        => length(rows),
            )
        )
    end

    dst = joinpath(ROOT, "docs", "src", "assets", "eu_monthly_prices_2025.json")
    mkpath(dirname(dst))
    open(dst, "w") do io
        JSON.print(io, out, 2)
    end
    @info "wrote fixture" path = dst zones = length(out["zones"]) bytes = filesize(dst)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main()
end
