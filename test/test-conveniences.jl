using ENTSOE
using OpenAPI
using Test
using Dates: DateTime, Date
using TimeZones: ZonedDateTime, FixedTimeZone

@testset "entsoe_period" begin
    @test entsoe_period(DateTime("2023-08-23T22:00")) === 202308232200
    @test entsoe_period(DateTime("2023-08-23T22:00:33")) === 202308232200  # seconds dropped
    @test entsoe_period(Date("2023-08-23")) === 202308230000

    cest = FixedTimeZone("CEST", 7200)
    @test entsoe_period(ZonedDateTime(DateTime("2023-08-24T00:00"), cest)) === 202308232200
    @test entsoe_period(ZonedDateTime(DateTime("2023-08-23T22:00"), FixedTimeZone("UTC", 0))) ===
        202308232200
end

@testset "EIC table (curated)" begin
    @test EIC.NL == "10YNL----------L"
    @test EIC.DE_LU == "10Y1001A1001A82H"
    @test all(length(v) == 16 for v in EIC)
    @test all(startswith(v, "10Y") for v in EIC)
end

@testset "EIC_REGISTRY (full)" begin
    # Curated entries should all be present in the full registry.
    for code in EIC
        @test is_known_eic(code)
        @test !isempty(lookup_eic(code))
    end

    # NL → 1 entry of type BZN/CTA/CTY/LFA/LFB/MBA/SCA.
    nl = lookup_eic("10YNL----------L")
    @test length(nl) == 1
    @test nl[1].name == "NL"
    @test :BZN in nl[1].types

    # SEM-Ireland: multiple aliases under one EIC.
    sem = lookup_eic("10Y1001A1001A59C")
    @test length(sem) >= 2
    @test any(e -> e.name == "IE(SEM)", sem)

    # Unknown code → empty vector / false.
    @test lookup_eic("10YNOT-A-CODE---") == []
    @test !is_known_eic("10YNOT-A-CODE---")

    # eics_of_type returns sorted, contains NL for BZN.
    bzn = eics_of_type(:BZN)
    @test "10YNL----------L" in bzn
    @test issorted(bzn)
    @test length(bzn) > 50   # ENTSO-E has 70-ish bidding zones currently.
end

@testset "set_config / get_config / no-arg ENTSOEClient" begin
    # Snapshot original config so we can restore at the end.
    orig = get_config()
    saved = (
        token = orig.token, endpoint_url = orig.endpoint_url,
        validate_eic = orig.validate_eic,
    )

    try
        # set_config returns the (mutated) global.
        cfg = set_config(;
            token = "TEST-TOKEN-XYZ",
            endpoint_url = "https://iop-web-api.tp.entsoe.eu/api",
            validate_eic = true
        )
        @test cfg.token == "TEST-TOKEN-XYZ"
        @test cfg.endpoint_url == "https://iop-web-api.tp.entsoe.eu/api"
        @test cfg.validate_eic == true
        @test get_config() === cfg     # singleton

        # No-arg ENTSOEClient picks up the global.
        client = ENTSOEClient()
        @test client.base_url == "https://iop-web-api.tp.entsoe.eu/api"

        # Token can also come from ENV when both config and arg are empty.
        set_config(; token = "")
        withenv("ENTSOE_API_TOKEN" => "ENV-PROVIDED-TOKEN") do
            c2 = ENTSOEClient()
            @test c2 isa Client
        end

        # And errors when neither is set.
        withenv("ENTSOE_API_TOKEN" => nothing) do
            @test_throws ArgumentError ENTSOEClient()
        end
    finally
        # Restore.
        set_config(;
            token = saved.token,
            endpoint_url = saved.endpoint_url,
            validate_eic = saved.validate_eic
        )
    end
end

@testset "validate_eic" begin
    # Known code, no type filter — passes silently.
    @test validate_eic("10YNL----------L") === nothing
    # Known code with correct type filter.
    @test validate_eic("10YNL----------L"; type = :BZN) === nothing

    # Unknown code throws ArgumentError with a helpful message.
    err = try
        validate_eic("10YNOT-A-CODE---"); nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("unknown EIC", err.msg)
    @test occursin("10YNOT-A-CODE---", err.msg)

    # Known code missing the requested type tag rejects.
    err2 = try
        validate_eic("BY"; type = :BZN); nothing
    catch e
        e
    end
    @test err2 isa ArgumentError
    @test occursin("does not carry type", err2.msg)
    @test occursin(":BZN", err2.msg)
end

@testset "code lists" begin
    # Spot-check a representative code from each list — these are the ones
    # used in the cassette tests / tutorial.
    @test DOCUMENT_TYPE.A44 == "Price document"
    @test DOCUMENT_TYPE.A65 == "System total load"
    @test DOCUMENT_TYPE.A68 == "Installed generation per type"
    @test PROCESS_TYPE.A16 == "Realised"
    @test PROCESS_TYPE.A33 == "Year ahead"
    @test BUSINESS_TYPE.A33 == "Outage"
    @test PSR_TYPE.B16 == "Solar"
    @test PSR_TYPE.B19 == "Wind Onshore"
    # All keys are 3-character A/B + two digits — sanity check.
    @test all(occursin(r"^[AB]\d\d$", String(k)) for k in keys(PSR_TYPE))
    @test all(occursin(r"^[AB]\d\d$", String(k)) for k in keys(DOCUMENT_TYPE))
end

@testset "describe / code_for" begin
    @test ENTSOE.describe(DOCUMENT_TYPE, "A44") == "Price document"
    @test ENTSOE.describe(DOCUMENT_TYPE, :A44) == "Price document"
    @test_throws KeyError ENTSOE.describe(DOCUMENT_TYPE, "ZZZ")

    # Substring, case-insensitive.
    @test ENTSOE.code_for(PSR_TYPE, "wind onshore") == "B19"
    @test ENTSOE.code_for(DOCUMENT_TYPE, "price document") == "A44"
    @test_throws KeyError ENTSOE.code_for(PSR_TYPE, "unobtanium")
    # "wind" matches both Onshore and Offshore — should error on ambiguity.
    @test_throws ErrorException ENTSOE.code_for(PSR_TYPE, "wind")
end

@testset "ENTSOEClient construction" begin
    client = ENTSOEClient("TEST-TOKEN-XYZ")
    @test client isa Client
    @test client.base_url == ENTSOE_BASE_URL
    @test client.inner isa OpenAPI.Clients.Client
    @test client.inner.root == ENTSOE_BASE_URL

    # Custom base_url is honored.
    other = ENTSOEClient("T"; base_url = "https://example.test/api")
    @test other.base_url == "https://example.test/api"
end

@testset "entsoe_apis" begin
    apis = entsoe_apis(ENTSOEClient("T"))
    expected = (
        :balancing, :generation, :load, :market, :master_data, :omi,
        :outages, :transmission,
    )
    @test keys(apis) === expected
    @test apis.market isa MarketApi
    @test apis.balancing isa BalancingApi
    @test apis.generation isa GenerationApi
end

@testset "pre_request_hook injects securityToken" begin
    client = ENTSOEClient("MY-SECRET-TOKEN")
    rt = Dict{Regex, Type}(r"^200$" => String)

    # Op declares the SecurityToken scheme — token must be injected.
    ctx = OpenAPI.Clients.Ctx(client.inner, "GET", rt, "/dummy", ["SecurityToken"])
    client.inner.pre_request_hook(ctx)
    @test ctx.query["securityToken"] == "MY-SECRET-TOKEN"

    # Op does not declare SecurityToken — query stays empty.
    ctx2 = OpenAPI.Clients.Ctx(client.inner, "GET", rt, "/dummy", String[])
    client.inner.pre_request_hook(ctx2)
    @test !haskey(ctx2.query, "securityToken")

    # Stage-2 hook (resource/body/headers) is a pass-through.
    res, body, hdr = client.inner.pre_request_hook(
        "/whatever", nothing, Dict{String, String}("X" => "Y"),
    )
    @test res == "/whatever"
    @test body === nothing
    @test hdr == Dict("X" => "Y")
end
