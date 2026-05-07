using ENTSOE
using Test
using Dates: DateTime

# BrokenRecord lets tests record an HTTP interaction once and replay it
# deterministically afterwards.
#
# Mode is decided by file existence (no env vars):
#
#   - Cassette file does NOT exist  → recording mode: real HTTP call,
#                                     request + response saved to disk.
#   - Cassette file exists          → playback mode: response replayed,
#                                     request shape verified against the
#                                     recorded one. No network is touched.
#
# Re-record a cassette by deleting its file (or the whole directory) and
# re-running the tests once on a machine with network + valid credentials.
#
# Token resolution for recording mode (playback mode never needs a token):
#
#   1. ENV["ENTSOE_API_TOKEN"]
#   2. <repo-root>/token.txt  (single-line, gitignored)
#
# All BrokenRecord setup (loading, STATE-padding, configure!) lives in
# `_brokenrecord_helpers.jl`; ditto for `test-queries.jl`,
# `test-parsing.jl`, `test-smoke.jl`.

include("_brokenrecord_helpers.jl")

const _TOKEN_FILE = joinpath(@__DIR__, "..", "token.txt")

function _resolve_token()
    tok = get(ENV, "ENTSOE_API_TOKEN", "")
    isempty(tok) || return strip(tok)
    isfile(_TOKEN_FILE) && return strip(read(_TOKEN_FILE, String))
    return ""
end

mkpath(_BROKENRECORD_CASSETTES_DIR)
const BR = _load_brokenrecord()

if BR === nothing
    @info "BrokenRecord not installed; skipping cassette tests. " *
        "`pkg> add BrokenRecord@0.1` in `test/` to enable."
else
    @testset "cassettes directory wired up" begin
        @test isdir(_BROKENRECORD_CASSETTES_DIR)
    end

    # Token resolution is a no-op in playback (BrokenRecord intercepts
    # HTTP before any auth check). Recording mode picks up env / token.txt.
    let token = _resolve_token()
        client = ENTSOEClient(isempty(token) ? "PLAYBACK" : String(token))
        apis = entsoe_apis(client)

        # Fixed historical period so the recorded response is deterministic.
        # 2024-09-01 22:00 UTC → 2024-09-02 22:00 UTC == calendar day
        # 2024-09-02 in CET/CEST, the standard "one trading day" window.
        start_p = entsoe_period(DateTime("2024-09-01T22:00"))
        stop_p = entsoe_period(DateTime("2024-09-02T22:00"))

        @testset "Load 6.1.A actual total load (NL, 2024-09-02)" begin
            xml, _ = Base.invokelatest(
                BR.playback,
                () -> ENTSOE.load61_a_actual_total_load(
                    apis.load,
                    "A65",          # documentType: System total load
                    "A16",          # processType: Realised
                    EIC.NL,         # outBiddingZone_Domain
                    start_p, stop_p,
                ),
                "load_61a_actual_total_load_NL.yml",
            )
            @test xml isa AbstractString
            @test occursin("<GL_MarketDocument", xml)
            @test occursin("A65", xml)   # documentType echoed in response
        end

        @testset "Generation 14.1.A installed capacity (NL, 2024)" begin
            year_start = entsoe_period(DateTime("2023-12-31T23:00"))
            year_end = entsoe_period(DateTime("2024-12-31T23:00"))
            xml, _ = Base.invokelatest(
                BR.playback,
                () -> ENTSOE.generation141_a_installed_capacity_per_production_type(
                    apis.generation,
                    "A68",          # documentType: Installed generation per type
                    "A33",          # processType: Year ahead
                    EIC.NL,
                    year_start, year_end,
                ),
                "generation_141a_installed_capacity_NL.yml",
            )
            @test xml isa AbstractString
            @test occursin("<GL_MarketDocument", xml)
        end

        @testset "Market 12.1.D day-ahead prices (NL, 2024-09-02)" begin
            xml, _ = Base.invokelatest(
                BR.playback,
                () -> ENTSOE.market121_d_energy_prices(
                    apis.market,
                    "A44",          # documentType: Price document
                    start_p, stop_p,
                    EIC.NL,         # in_Domain
                    EIC.NL,         # out_Domain
                ),
                "market_121d_day_ahead_prices_NL.yml",
            )
            @test xml isa AbstractString
            @test occursin("<Publication_MarketDocument", xml)
        end
    end
end
