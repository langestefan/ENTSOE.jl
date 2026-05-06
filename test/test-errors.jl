using EntsoE
using Test

@testset "Error type hierarchy" begin
    @test EntsoE.NetworkError(ErrorException("dns")) isa EntsoE.APIError
    @test EntsoE.ClientError(404, "not found") isa EntsoE.APIError
    @test EntsoE.ServerError(500, "boom") isa EntsoE.APIError
    @test EntsoE.AuthError(401, "nope") isa EntsoE.APIError
    @test EntsoE.RateLimitError(; retry_after = 5.0) isa EntsoE.APIError
    @test EntsoE.TimeoutError(:read) isa EntsoE.APIError
end

@testset "parse_retry_after" begin
    @test EntsoE.parse_retry_after("5") == 5.0
    @test EntsoE.parse_retry_after(" 12 ") == 12.0
    @test EntsoE.parse_retry_after("Wed, 21 Oct 2015 07:28:00 GMT") === nothing
    @test EntsoE.parse_retry_after("") === nothing
    @test EntsoE.parse_retry_after(nothing) === nothing
end

@testset "check_response 2xx returns nothing" begin
    for s in (200, 201, 204, 299)
        @test EntsoE.check_response(s, "") === nothing
    end
end

@testset "check_response classifies by status" begin
    @test_throws EntsoE.AuthError EntsoE.check_response(401, "")
    @test_throws EntsoE.AuthError EntsoE.check_response(403, "")
    @test_throws EntsoE.ClientError EntsoE.check_response(404, "missing")
    @test_throws EntsoE.ServerError EntsoE.check_response(503, "")
    @test_throws EntsoE.ClientError EntsoE.check_response(600, "weird")
end

@testset "check_response 429 surfaces RateLimitError" begin
    headers = Dict("Retry-After" => "7")
    err = try
        EntsoE.check_response(429, "", headers)
        nothing
    catch e
        e
    end
    @test err isa EntsoE.RateLimitError
    @test err.retry_after == 7.0
end
