using ENTSOE
using OpenAPI
using Test

@testset "Client construction" begin
    c = ENTSOE.Client("https://example.test/api")
    @test c isa ENTSOE.Client
    @test c.base_url == "https://example.test/api"
    @test c.auth isa ENTSOE.NoAuth
    @test c.inner isa OpenAPI.Clients.Client
end

@testset "Client with auth" begin
    c = ENTSOE.Client("https://example.test"; auth = ENTSOE.BearerToken("abc"))
    @test c.auth isa ENTSOE.BearerToken
    @test c.auth.token == "abc"
end
