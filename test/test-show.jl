using ENTSOE
using OpenAPI
using Test

Base.@kwdef mutable struct _ShowFixture <: OpenAPI.APIModel
    id::Union{Nothing,Int} = nothing
    name::Union{Nothing,String} = nothing
    tags::Union{Nothing,Vector{String}} = nothing
end

@testset "Pretty-print skips nothing fields" begin
    out = sprint(show, MIME"text/plain"(), _ShowFixture(; id = 7, name = "alice"))
    @test occursin("_ShowFixture:", out)
    @test occursin("id: 7", out)
    @test occursin("name: \"alice\"", out)
    @test !occursin("tags:", out)
end

@testset "Pretty-print summarises vectors" begin
    out = sprint(show, MIME"text/plain"(), _ShowFixture(; tags = ["a", "b", "c"]))
    @test occursin("tags: [3 items]", out)

    empty_out = sprint(show, MIME"text/plain"(), _ShowFixture(; tags = String[]))
    @test occursin("tags: []", empty_out)

    one_out = sprint(show, MIME"text/plain"(), _ShowFixture(; tags = ["only"]))
    @test occursin("tags: [1 item]", one_out)
end
