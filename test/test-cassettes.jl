using EntsoE
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
# `ignore_query = ["securityToken"]` strips the token from the recorded
# request URL so secrets don't end up on disk. The cassette is therefore
# safe to commit.

const _CASSETTES_DIR = joinpath(@__DIR__, "cassettes")
const _TOKEN_FILE = joinpath(@__DIR__, "..", "token.txt")

function _resolve_token()
    tok = get(ENV, "ENTSOE_API_TOKEN", "")
    isempty(tok) || return strip(tok)
    isfile(_TOKEN_FILE) && return strip(read(_TOKEN_FILE, String))
    return ""
end

function _run_cassette_tests(BrokenRecord)
    BrokenRecord.configure!(;
        path = _CASSETTES_DIR,
        # Two reasons to ignore a header:
        # 1. Credential-bearing headers — strip from comparison so secrets
        #    don't end up on disk.
        # 2. Environment-dependent headers (User-Agent carries the Julia
        #    and HTTP.jl version; Accept-Encoding can flip on/off across
        #    HTTP.jl versions). Including these would make cassettes
        #    fail to replay on a different Julia minor version than the
        #    one used to record.
        ignore_headers = [
            "Authorization", "X-API-Key", "api_key",
            "X-Api-Key", "Cookie", "Set-Cookie",
            "Proxy-Authorization", "User-Agent",
            "Accept-Encoding",
        ],
        # `securityToken` is ENTSO-E's per-request auth (query string,
        # not header). MUST be stripped or the cassette leaks credentials.
        ignore_query = ["api_key", "token", "access_token", "securityToken"],
    )

    @testset "cassettes directory wired up" begin
        @test isdir(_CASSETTES_DIR)
    end

    # Building the client lazily — `_resolve_token()` returns "" in
    # playback mode if neither ENV nor token.txt is set, which is fine:
    # BrokenRecord intercepts the HTTP layer before the token would be
    # validated against ENTSO-E.
    token = _resolve_token()
    client = EntsoEClient(isempty(token) ? "PLAYBACK" : String(token))
    apis = entsoe_apis(client)

    # Fixed historical period so the recorded response is deterministic.
    # 2024-09-01 22:00 UTC → 2024-09-02 22:00 UTC == calendar day 2024-09-02
    # in CET/CEST, the standard "one trading day" window for these queries.
    start_p = entsoe_period(DateTime("2024-09-01T22:00"))
    stop_p  = entsoe_period(DateTime("2024-09-02T22:00"))

    @testset "Load 6.1.A actual total load (NL, 2024-09-02)" begin
        xml, _ = BrokenRecord.playback("load_61a_actual_total_load_NL.yml") do
            EntsoE.load61_a_actual_total_load(
                apis.load,
                "A65",          # documentType: System total load
                "A16",          # processType: Realised
                EIC.NL,         # outBiddingZone_Domain
                start_p, stop_p,
            )
        end
        @test xml isa AbstractString
        @test occursin("<GL_MarketDocument", xml)
        @test occursin("A65", xml)   # documentType echoed in response
    end

    @testset "Generation 14.1.A installed capacity (NL, 2024)" begin
        # Aggregated installed capacity by production type for a year.
        year_start = entsoe_period(DateTime("2023-12-31T23:00"))
        year_end   = entsoe_period(DateTime("2024-12-31T23:00"))
        xml, _ = BrokenRecord.playback("generation_141a_installed_capacity_NL.yml") do
            EntsoE.generation141_a_installed_capacity_per_production_type(
                apis.generation,
                "A68",          # documentType: Installed generation per type
                "A33",          # processType: Year ahead
                EIC.NL,
                year_start, year_end,
            )
        end
        @test xml isa AbstractString
        @test occursin("<GL_MarketDocument", xml)
    end

    @testset "Market 12.1.D day-ahead prices (NL, 2024-09-02)" begin
        xml, _ = BrokenRecord.playback("market_121d_day_ahead_prices_NL.yml") do
            # Argument order matches the codegen signature: documentType,
            # period bounds, then domains.
            EntsoE.market121_d_energy_prices(
                apis.market,
                "A44",          # documentType: Price document
                start_p, stop_p,
                EIC.NL,         # in_Domain
                EIC.NL,         # out_Domain
            )
        end
        @test xml isa AbstractString
        @test occursin("<Publication_MarketDocument", xml)
    end

    return nothing
end

# BrokenRecord 0.1 sizes its per-thread STATE vector at module load via
# `map(1:nthreads(), ...)`. Julia 1.12 routinely runs tasks on `threadid()`
# values higher than `nthreads()` (the interactive thread pool), so any
# `playback` call hits a `BoundsError` from `STATE[threadid()]`. Pad the
# vector to cover every reachable thread before running. The fields and
# types come from the existing entry so we never get type mismatches.
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
        @info "BrokenRecord not installed; skipping cassette tests. " *
            "`pkg> add BrokenRecord@0.1` in `test/` to enable."
    else
        BrokenRecord = Base.require(id)
        Base.invokelatest(_pad_brokenrecord_state, BrokenRecord)
        mkpath(_CASSETTES_DIR)
        Base.invokelatest(_run_cassette_tests, BrokenRecord)
    end
end
