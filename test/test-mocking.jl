using ENTSOE
using Test

# Mocking.jl lets tests intercept low-level HTTP calls so error paths that
# are tedious to produce against a real server (forced 503, malformed JSON,
# specific Retry-After values) become deterministic. Patch points are
# scoped to a `Mocking.apply` block.

let id = Base.identify_package("Mocking")
    if id === nothing
        @info "Mocking not installed; skipping mocked-HTTP tests. " *
            "`pkg> add Mocking@0.8` in `test/` to enable."
    else
        @testset "Mocking is loadable" begin
            Mocking = Base.require(id)
            @test Mocking isa Module
        end

        # Add concrete mocked tests below. Example skeleton:
        #
        # using HTTP, Mocking
        # Mocking.activate()
        # @testset "503 maps to ServerError after retry" begin
        #     patch = @patch HTTP.request(args...; kwargs...) =
        #         HTTP.Response(503, ["Retry-After" => "0"])
        #     apply(patch) do
        #         @test_throws ENTSOE.ServerError some_endpoint(client)
        #     end
        # end
    end
end
