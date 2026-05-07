using ENTSOE
using TOML
using Test

@testset "scaffold-info.toml" begin
    info_path = joinpath(pkgdir(ENTSOE), "scaffold-info.toml")
    @test isfile(info_path)
    info = TOML.parsefile(info_path)
    @test haskey(info, "spec_url")
    @test haskey(info, "spec_path")
    @test haskey(info, "generator_version")
    @test haskey(info, "generated_at")
    @test isfile(joinpath(pkgdir(ENTSOE), info["spec_path"]))
end
