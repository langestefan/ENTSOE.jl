using ENTSOE
using Test
using Dates: DateTime, Date

# Unit tests for the named-argument query layer in
# `src/conveniences/queries.jl`. Live calls are exercised via
# BrokenRecord cassettes (already recorded for Load 6.1.A,
# Generation 14.1.A, Market 12.1.D) — that proves the wrapper produces
# the same wire format the generated layer does.

@testset "validate=true rejects unknown EICs at the wrapper boundary" begin
    # Off by default — bad EIC sails through (would 200 with an
    # acknowledgement at runtime, but we never reach the network here
    # because there's no client config and we want a fast-fail test).
    # With validate=true the wrapper throws *before* hitting the
    # network or constructing API state.
    client = ENTSOEClient("PLAYBACK")
    @test_throws ArgumentError day_ahead_prices(
        client, "10YNOT-A-CODE---",
        DateTime("2024-09-01T22:00"), DateTime("2024-09-02T22:00");
        validate = true,
    )
end

@testset "_to_period overloads" begin
    # `Int` round-trip.
    @test ENTSOE._to_period(Int64(202409012200)) === Int64(202409012200)
    # DateTime → yyyymmddHHMM.
    @test ENTSOE._to_period(DateTime("2024-09-01T22:00")) === Int64(202409012200)
    # Date → midnight on that date.
    @test ENTSOE._to_period(Date("2024-09-02")) === Int64(202409020000)
end

# Pad BrokenRecord state for Julia 1.12 thread-safety (same workaround as
# in test-cassettes.jl). Without this, calling `playback` from a worker
# thread hits a `BoundsError` in BrokenRecord 0.1.
function _pad_brokenrecord_state(BR)
    target = Base.Threads.maxthreadid()
    while length(BR.STATE) < target
        template = BR.STATE[1]
        push!(BR.STATE, (
            responses = empty(template.responses),
            ignore_headers = String[],
            ignore_query = String[],
        ))
    end
    return nothing
end

let id = Base.identify_package("BrokenRecord")
    if id === nothing
        @info "BrokenRecord not installed; skipping query-wrapper live tests."
    else
        BR = Base.require(id)
        Base.invokelatest(_pad_brokenrecord_state, BR)
        Base.invokelatest(BR.configure!;
            path = joinpath(@__DIR__, "cassettes"),
            ignore_headers = ["Authorization", "User-Agent",
                              "Accept-Encoding"],
            ignore_query   = ["securityToken"],
        )

        client = ENTSOEClient("PLAYBACK")

        @testset "actual_total_load (Load 6.1.A cassette)" begin
            rows = Base.invokelatest(BR.playback,
                () -> actual_total_load(
                    client, EIC.NL,
                    DateTime("2024-09-01T22:00"),
                    DateTime("2024-09-02T22:00"),
                ),
                "load_61a_actual_total_load_NL.yml",
            )
            @test length(rows) == 96     # 24h × 4 (PT15M)
            @test rows[1].time == DateTime("2024-09-01T22:00")
            @test rows[1].value > 1_000  # NL load is always thousands of MW
        end

        @testset "day_ahead_prices (Market 12.1.D cassette)" begin
            rows = Base.invokelatest(BR.playback,
                () -> day_ahead_prices(
                    client, EIC.NL,
                    DateTime("2024-09-01T22:00"),
                    DateTime("2024-09-02T22:00"),
                ),
                "market_121d_day_ahead_prices_NL.yml",
            )
            @test !isempty(rows)
            @test rows[1].time == DateTime("2024-09-01T22:00")
            # NL day-ahead prices range from negative tens to a few hundred
            # EUR/MWh — anything thousands is a parse error.
            @test all(-1_000 < r.value < 1_000 for r in rows)
        end

        @testset "installed_capacity_per_production_type (cassette)" begin
            rows = Base.invokelatest(BR.playback,
                () -> installed_capacity_per_production_type(
                    client, EIC.NL,
                    DateTime("2023-12-31T23:00"),
                    DateTime("2024-12-31T23:00"),
                ),
                "generation_141a_installed_capacity_NL.yml",
            )
            @test !isempty(rows)
            # Every row should carry a known PSR-type code.
            @test all(haskey(PSR_TYPE, Symbol(r.psr_type)) for r in rows)
            # Solar is one of the largest categories in NL.
            solar = filter(r -> r.psr_type == "B16", rows)
            @test !isempty(solar)
            @test solar[1].capacity_mw > 1_000
        end

        @testset "parsed=false returns raw XML" begin
            xml = Base.invokelatest(BR.playback,
                () -> day_ahead_prices(
                    client, EIC.NL,
                    DateTime("2024-09-01T22:00"),
                    DateTime("2024-09-02T22:00");
                    parsed = false,
                ),
                "market_121d_day_ahead_prices_NL.yml",
            )
            @test xml isa AbstractString
            @test occursin("<Publication_MarketDocument", xml)
        end
    end
end
