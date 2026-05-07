using ENTSOE
using Test
using Dates: DateTime, Date
using TimeZones: ZonedDateTime, FixedTimeZone

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
    # ZonedDateTime → goes through the AbstractDateTime overload, then
    # internally converted to UTC via `entsoe_period`.
    cest = FixedTimeZone("CEST", 7200)
    zdt  = ZonedDateTime(DateTime("2024-09-02T00:00"), cest)
    @test ENTSOE._to_period(zdt) === Int64(202409012200)   # 22:00 UTC the prior day

    # Catch-all rejects unsupported types loudly.
    @test_throws ArgumentError ENTSOE._to_period("not a period")
    @test_throws ArgumentError ENTSOE._to_period(3.14)
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

        @testset "validate=true passes through for a known EIC" begin
            # Pair to the negative test above — drives the loop body in
            # `_query` to completion (line 59) and confirms validation
            # doesn't false-positive on a real bidding zone code.
            rows = Base.invokelatest(BR.playback,
                () -> day_ahead_prices(
                    client, EIC.NL,
                    DateTime("2024-09-01T22:00"),
                    DateTime("2024-09-02T22:00");
                    validate = true,
                ),
                "market_121d_day_ahead_prices_NL.yml",
            )
            @test !isempty(rows)
        end

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

        # ---------------------------------------------------------------
        # The remaining named-arg wrappers each get one cassette playback.
        # We keep assertions light — the point is to drive the wrapper
        # function and prove the parser handles the document shape.
        # ---------------------------------------------------------------

        local _start = DateTime("2024-09-01T22:00")
        local _stop  = DateTime("2024-09-02T22:00")

        @testset "day_ahead_load_forecast (Load 6.1.B cassette)" begin
            rows = Base.invokelatest(BR.playback,
                () -> day_ahead_load_forecast(client, EIC.NL, _start, _stop),
                "load_61b_day_ahead_forecast_NL.yml",
            )
            @test length(rows) == 96
            @test all(r.value > 1_000 for r in rows)   # MW
        end

        @testset "week_ahead_load_forecast (Load 6.1.C cassette)" begin
            rows = Base.invokelatest(BR.playback,
                () -> week_ahead_load_forecast(client, EIC.NL, _start, _stop),
                "load_61c_week_ahead_forecast_NL.yml",
            )
            # Week-ahead is typically just a min/max forecast for the
            # period, not a quarter-hour curve — small row count is fine.
            @test !isempty(rows)
        end

        @testset "month_ahead_load_forecast (Load 6.1.D cassette)" begin
            rows = Base.invokelatest(BR.playback,
                () -> month_ahead_load_forecast(client, EIC.NL, _start, _stop),
                "load_61d_month_ahead_forecast_NL.yml",
            )
            @test !isempty(rows)
        end

        @testset "year_ahead_load_forecast (Load 6.1.E cassette)" begin
            rows = Base.invokelatest(BR.playback,
                () -> year_ahead_load_forecast(client, EIC.NL,
                    DateTime("2023-12-31T23:00"),
                    DateTime("2024-12-31T23:00")),
                "load_61e_year_ahead_forecast_NL.yml",
            )
            @test !isempty(rows)
        end

        @testset "generation_forecast_day_ahead (Generation 14.1.C cassette)" begin
            rows = Base.invokelatest(BR.playback,
                () -> generation_forecast_day_ahead(client, EIC.NL, _start, _stop),
                "generation_141c_forecast_day_ahead_NL.yml",
            )
            @test length(rows) == 96
            @test all(r.value > 0 for r in rows)
        end

        @testset "wind_solar_forecast (Generation 14.1.D cassette)" begin
            rows = Base.invokelatest(BR.playback,
                () -> wind_solar_forecast(client, EIC.NL, _start, _stop),
                "generation_141d_wind_solar_forecast_NL.yml",
            )
            @test !isempty(rows)
            # Result is per-PSR — should see at least Solar (B16) and one
            # of the wind technologies.
            @test any(r.psr_type == "B16" for r in rows)
            @test any(r.psr_type in ("B18", "B19") for r in rows)
        end

        @testset "actual_generation_per_production_type (Generation 16.1.B/C cassette)" begin
            rows = Base.invokelatest(BR.playback,
                () -> actual_generation_per_production_type(
                    client, EIC.NL, _start, _stop),
                "generation_161bc_actual_per_psr_NL.yml",
            )
            @test !isempty(rows)
            # Many PSR types contributing on a normal day.
            psrs = unique(r.psr_type for r in rows)
            @test length(psrs) >= 4
            @test "B16" in psrs   # Solar always present in NL data
        end

        @testset "omi_other_market_information — first page is acknowledgement → throws" begin
            # NL B47 returns an acknowledgement (no OMI submitted for
            # that area on that day). With `max_pages = 1` our wrapper
            # sees the ack on iteration 0 and throws.
            err = nothing
            try
                Base.invokelatest(BR.playback,
                    () -> omi_other_market_information(
                        client, EIC.NL,
                        DateTime("2024-09-23T22:00"),
                        DateTime("2024-09-24T22:00");
                        document_type = "B47", page_size = 200, max_pages = 1,
                    ),
                    "omi_other_market_information_NL.yml",
                )
            catch e
                err = e
            end
            @test err isa ENTSOEAcknowledgement
            @test err.reason_code == "999"
        end

        @testset "cross_border_physical_flows (Transmission 12.1.G cassette)" begin
            rows = Base.invokelatest(BR.playback,
                () -> cross_border_physical_flows(
                    client, EIC.NL, EIC.DE_LU, _start, _stop),
                "transmission_121g_cross_border_NL_DE.yml",
            )
            @test !isempty(rows)
            # Hourly resolution, 24 h window.
            @test rows[1].time == _start
        end
    end
end
