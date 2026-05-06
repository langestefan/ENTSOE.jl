using EntsoE
using OpenAPI
using Test

@testset "Generated module surface" begin
    @test isdefined(EntsoE, :EntsoEAPI)
    api_mod = getfield(EntsoE, :EntsoEAPI)
    public = filter(n -> n !== :EntsoEAPI, names(api_mod; all = false))
    @test !isempty(public)
end

@testset "API model types" begin
    api_mod = getfield(EntsoE, :EntsoEAPI)
    model_types = [
        getfield(api_mod, n) for n in names(api_mod; all = false)
        if isdefined(api_mod, n) &&
           getfield(api_mod, n) isa Type &&
           getfield(api_mod, n) !== api_mod &&
           getfield(api_mod, n) <: OpenAPI.APIModel
    ]
    # ENTSO-E's spec returns `application/xml` as a plain `String` for every
    # operation — there are no response/request schemas, so no `APIModel`
    # subtypes get generated. When that's the case there's nothing to assert
    # here; just record it.
    if isempty(model_types)
        @info "No APIModel subtypes generated — spec has no response schemas."
    else
        for T in model_types
            @test_nowarn try
                T()
            catch e
                e isa Union{ArgumentError, MethodError, UndefKeywordError} || rethrow()
            end
        end
    end
end

@testset "API set types accept Client" begin
    api_mod = getfield(EntsoE, :EntsoEAPI)
    api_sets = [
        getfield(api_mod, n) for n in names(api_mod; all = false)
        if isdefined(api_mod, n) &&
           getfield(api_mod, n) isa Type &&
           getfield(api_mod, n) <: OpenAPI.APIClientImpl
    ]
    @test !isempty(api_sets)
    inner = OpenAPI.Clients.Client("https://example.test")
    for T in api_sets
        @test T(inner) isa T
    end
end
