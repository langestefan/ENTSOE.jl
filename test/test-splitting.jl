using ENTSOE
using Test
using Dates: DateTime, Date, Year, Day, Month

@testset "split_period basics" begin
    chunks = ENTSOE.split_period(
        DateTime("2022-01-01"), DateTime("2025-01-01");
        window = Year(1),
    )
    @test length(chunks) == 3
    @test chunks[1] == (DateTime("2022-01-01"), DateTime("2023-01-01"))
    @test chunks[3] == (DateTime("2024-01-01"), DateTime("2025-01-01"))
end

@testset "split_period — partial last window" begin
    chunks = ENTSOE.split_period(
        DateTime("2024-01-01"), DateTime("2024-04-15");
        window = Month(1),
    )
    @test length(chunks) == 4
    @test chunks[end] == (DateTime("2024-04-01"), DateTime("2024-04-15"))
end

@testset "split_period — accepts integer endpoints" begin
    chunks = ENTSOE.split_period(
        202401010000, 202402010000;
        window = Day(7),
    )
    @test length(chunks) == 5  # 4 weeks + 3 trailing days
    @test chunks[1] == (DateTime("2024-01-01"), DateTime("2024-01-08"))
end

@testset "split_period — start == stop" begin
    @test ENTSOE.split_period(DateTime("2024-01-01"), DateTime("2024-01-01")) == []
end

@testset "split_period — invalid range" begin
    @test_throws ArgumentError ENTSOE.split_period(
        DateTime("2024-02-01"), DateTime("2024-01-01"),
    )
end

@testset "_to_datetime — unsupported types reject loudly" begin
    @test_throws ArgumentError ENTSOE._to_datetime("not a date")
    @test_throws ArgumentError ENTSOE._to_datetime(3.14)
end

@testset "query_split — concatenates chunk results" begin
    # Mock query_fn: returns one row per call labelling the chunk.
    history = Tuple{DateTime, DateTime}[]
    fake_query(client, area, s, e; extra = "") = begin
        push!(history, (s, e))
        [(time = s, value = 1.0, area = area, extra = extra)]
    end
    rows = ENTSOE.query_split(
        fake_query, "client_stub", "10YNL----------L",
        DateTime("2024-01-01"), DateTime("2024-04-01");
        window = Month(1),
        extra = "kw",
    )
    @test length(history) == 3
    @test length(rows) == 3
    @test rows[1].extra == "kw"
    @test history[1] == (DateTime("2024-01-01"), DateTime("2024-02-01"))
end

@testset "query_split — skips acknowledgement chunks" begin
    # First chunk produces data, second chunk's window has none →
    # should be skipped (not propagated as an error).
    fake_query(client, area, s, e) = begin
        s == DateTime("2024-01-01") && return [(value = 42.0,)]
        throw(ENTSOEAcknowledgement("999", "No matching data found"))
    end
    rows = ENTSOE.query_split(
        fake_query, "client_stub", "10YNL----------L",
        DateTime("2024-01-01"), DateTime("2024-03-01");
        window = Month(1),
    )
    @test length(rows) == 1
    @test rows[1].value == 42.0
end

@testset "query_split — propagates non-acknowledgement errors" begin
    fake_query(client, area, s, e) = error("upstream went boom")
    @test_throws ErrorException ENTSOE.query_split(
        fake_query, "client_stub", "10YNL----------L",
        DateTime("2024-01-01"), DateTime("2024-03-01");
        window = Month(1),
    )
end
