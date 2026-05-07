#!/usr/bin/env julia
# Record every cassette referenced by `docs/src/tutorial_*.md`.
#
# Run once with a valid token:
#
#   ENTSOE_API_TOKEN=…  julia --project scripts/record_tutorial_cassettes.jl
#
# Re-running overwrites every cassette listed below. Skip individual
# tutorials by filtering `TUTORIAL_TARGETS` at the bottom of the file.
#
# Cassettes land in `test/cassettes/` so the docs build (which goes
# through `_brokenrecord_helpers.jl` like the test suite) can find
# them without extra plumbing.

using Pkg
# `BrokenRecord` is in the test/ environment, not the main project.
# Activate `test/` (with the package itself dev'd in) so we can `using
# ENTSOE` and `using BrokenRecord` together.
Pkg.activate(joinpath(@__DIR__, "..", "test"))
Pkg.develop(PackageSpec(; path = joinpath(@__DIR__, "..")))

using ENTSOE
using Dates: DateTime

# ---------------------------------------------------------------------------
# Reuse the test suite's BrokenRecord helper for STATE-padding +
# `configure!` so cassettes are written with the same options the
# test/playback path expects.
const REPO_ROOT = joinpath(@__DIR__, "..")
include(joinpath(REPO_ROOT, "test", "_brokenrecord_helpers.jl"))
const BR = _load_brokenrecord()
BR === nothing &&
    error("BrokenRecord is not installed — `pkg> add BrokenRecord@0.1` first.")

const TOKEN = let env_tok = get(ENV, "ENTSOE_API_TOKEN", "")
    if !isempty(env_tok)
        env_tok
    elseif isfile(joinpath(REPO_ROOT, "token.txt"))
        strip(read(joinpath(REPO_ROOT, "token.txt"), String))
    else
        error("No ENTSOE_API_TOKEN env var and no token.txt — set one first.")
    end
end

const CLIENT = ENTSOEClient(TOKEN)

# ---------------------------------------------------------------------------
# A "target" is one cassette's filename plus the no-arg closure that
# produces it. We record by replaying with `BR.playback(thunk, name)`
# while the cassette doesn't yet exist; BrokenRecord then *records*
# the live response and writes the YAML. Removing existing cassettes
# first guarantees a fresh recording even if a stale one is on disk.

struct Target
    cassette::String
    thunk::Function
end

function _record!(t::Target)
    dst = joinpath(REPO_ROOT, "test", "cassettes", t.cassette)
    isfile(dst) && rm(dst)   # force fresh record
    @info "Recording" cassette = t.cassette
    return BR.playback(t.thunk, t.cassette)
end

# ---------------------------------------------------------------------------
# Tutorial 1 — Generation mix over a Dutch day (2024-09-02)

const T1_TARGETS = [
    Target(
        "tut_gen_mix_NL_2024_09_02.yml",
        () -> actual_generation_per_production_type(
            CLIENT, EIC.NL,
            DateTime("2024-09-01T22:00"),
            DateTime("2024-09-02T22:00"),
            Raw(),   # store the XML — the tutorial parses it itself
        ),
    ),
]

# ---------------------------------------------------------------------------
# Tutorial 2 — Cross-border flows NL ↔ DE for a week (2024-09-02 .. 09)

const T2_TARGETS = [
    Target(
        "tut_flows_DE_to_NL_week.yml",
        () -> cross_border_physical_flows(
            CLIENT, EIC.NL, EIC.DE_LU,
            DateTime("2024-09-01T22:00"),
            DateTime("2024-09-08T22:00"),
            Raw(),
        ),
    ),
    Target(
        "tut_flows_NL_to_DE_week.yml",
        () -> cross_border_physical_flows(
            CLIENT, EIC.DE_LU, EIC.NL,
            DateTime("2024-09-01T22:00"),
            DateTime("2024-09-08T22:00"),
            Raw(),
        ),
    ),
]

# ---------------------------------------------------------------------------
# Tutorial 3 — Day-ahead load forecast vs. realised, NL one week

const T3_TARGETS = [
    Target(
        "tut_load_actual_NL_week.yml",
        () -> actual_total_load(
            CLIENT, EIC.NL,
            DateTime("2024-09-01T22:00"),
            DateTime("2024-09-08T22:00"),
            Raw(),
        ),
    ),
    Target(
        "tut_load_forecast_NL_week.yml",
        () -> day_ahead_load_forecast(
            CLIENT, EIC.NL,
            DateTime("2024-09-01T22:00"),
            DateTime("2024-09-08T22:00"),
            Raw(),
        ),
    ),
]

# ---------------------------------------------------------------------------
# Tutorial 4 — Multi-year NL day-ahead prices via `query_split`. ENTSO-E
# caps day-ahead price queries at one year; we record the five yearly
# chunks the tutorial then chains together.

const T4_TARGETS = [
    Target(
        # One cassette holds all 5 yearly responses — BrokenRecord captures
        # every HTTP call inside the thunk in order, so a single playback
        # in the tutorial replays the full `query_split` chain.
        "tut_prices_NL_2020_2024.yml",
        () -> query_split(
            day_ahead_prices,
            CLIENT, EIC.NL,
            DateTime("2019-12-31T23:00"),
            DateTime("2024-12-31T23:00");
            window = Dates.Year(1),
        ),
    ),
]

# ---------------------------------------------------------------------------
# Tutorial 5 — Renewables share map. One day of `actual_generation_per_
# production_type` per zone, projected onto a GeoMakie plot.

const T5_ZONES = (
    (:DE_LU, EIC.DE_LU),
    (:FR, EIC.FR),
    (:ES, EIC.ES),
    (:NL, EIC.NL),
    (:IT_NORTH, EIC.IT_NORTH),
    (:PL, EIC.PL),
)

const T5_DAY_START = DateTime("2024-06-14T22:00")   # 2024-06-15 00:00 CET
const T5_DAY_END = DateTime("2024-06-15T22:00")

const T5_TARGETS = [
    Target(
            "tut_renewables_$(name)_2024_06_15.yml",
            () -> actual_generation_per_production_type(
                CLIENT, eic, T5_DAY_START, T5_DAY_END, Raw(),
            ),
        ) for (name, eic) in T5_ZONES
]

# ---------------------------------------------------------------------------

const TUTORIAL_TARGETS = vcat(
    T1_TARGETS, T2_TARGETS, T3_TARGETS, T4_TARGETS, T5_TARGETS,
)

@info "Recording $(length(TUTORIAL_TARGETS)) tutorial cassettes"
for t in TUTORIAL_TARGETS
    try
        _record!(t)
    catch err
        @error "Recording failed" cassette = t.cassette exception = (err, catch_backtrace())
    end
end
@info "Done."
