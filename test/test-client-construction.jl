using EntsoE
using OpenAPI
using Test

@testset "Client construction" begin
    c = EntsoE.Client("https://example.test/api")
    @test c isa EntsoE.Client
    @test c.base_url == "https://example.test/api"
    @test c.auth isa EntsoE.NoAuth
    @test c.inner isa OpenAPI.Clients.Client
end

@testset "Client with auth" begin
    c = EntsoE.Client("https://example.test"; auth = EntsoE.BearerToken("abc"))
    @test c.auth isa EntsoE.BearerToken
    @test c.auth.token == "abc"
end
