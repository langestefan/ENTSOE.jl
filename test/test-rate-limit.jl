using EntsoE
using Test

function _mock_clock(start::Real = 100.0)
    now = Ref(Float64(start))
    sleeps = Float64[]
    sleep_fn = function (s)
        push!(sleeps, Float64(s))
        now[] += Float64(s)
    end
    time_fn = () -> now[]
    return (; sleep_fn, time_fn, sleeps)
end

@testset "TokenBucket immediate acquire" begin
    clk = _mock_clock()
    b = EntsoE.TokenBucket(; rate = 10.0, burst = 5.0)
    EntsoE.acquire!(b; sleep_fn = clk.sleep_fn, time_fn = clk.time_fn)
    @test isempty(clk.sleeps)
    @test b.tokens ≈ 4.0
end

@testset "TokenBucket waits when empty" begin
    clk = _mock_clock()
    b = EntsoE.TokenBucket(; rate = 2.0, burst = 1.0)
    EntsoE.acquire!(b; sleep_fn = clk.sleep_fn, time_fn = clk.time_fn)
    EntsoE.acquire!(b; sleep_fn = clk.sleep_fn, time_fn = clk.time_fn)
    @test length(clk.sleeps) == 1
    @test clk.sleeps[1] ≈ 0.5
end

@testset "TokenBucket throws when timeout would expire" begin
    clk = _mock_clock()
    b = EntsoE.TokenBucket(; rate = 1.0, burst = 1.0)
    EntsoE.acquire!(b; sleep_fn = clk.sleep_fn, time_fn = clk.time_fn)
    @test_throws EntsoE.RateLimitError EntsoE.acquire!(
        b; timeout = 0.1, sleep_fn = clk.sleep_fn, time_fn = clk.time_fn,
    )
end

@testset "with_rate_limit runs fn after acquire" begin
    clk = _mock_clock()
    b = EntsoE.TokenBucket(; rate = 100.0, burst = 5.0)
    n = Ref(0)
    EntsoE.with_rate_limit(b, () -> n[] += 1;
                            sleep_fn = clk.sleep_fn, time_fn = clk.time_fn)
    @test n[] == 1
end
