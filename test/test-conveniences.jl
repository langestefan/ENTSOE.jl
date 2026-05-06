using EntsoE
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

@testset "EIC table" begin
    @test EIC.NL == "10YNL----------L"
    @test EIC.DE_LU == "10Y1001A1001A82H"
    @test all(length(v) == 16 for v in EIC)
    @test all(startswith(v, "10Y") for v in EIC)
end

@testset "EntsoEClient construction" begin
    client = EntsoEClient("TEST-TOKEN-XYZ")
    @test client isa Client
    @test client.base_url == ENTSOE_BASE_URL
    @test client.inner isa OpenAPI.Clients.Client
    @test client.inner.root == ENTSOE_BASE_URL

    # Custom base_url is honored.
    other = EntsoEClient("T"; base_url = "https://example.test/api")
    @test other.base_url == "https://example.test/api"
end

@testset "entsoe_apis" begin
    apis = entsoe_apis(EntsoEClient("T"))
    expected = (:balancing, :generation, :load, :market, :master_data, :omi,
                :outages, :transmission)
    @test keys(apis) === expected
    @test apis.market isa MarketApi
    @test apis.balancing isa BalancingApi
    @test apis.generation isa GenerationApi
end

@testset "pre_request_hook injects securityToken" begin
    client = EntsoEClient("MY-SECRET-TOKEN")
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
