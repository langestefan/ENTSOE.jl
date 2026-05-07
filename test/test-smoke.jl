using ENTSOE
using Test

# Broad coverage smoke test. For every one of the 77 ENTSO-E operations
# in the spec, we keep a recorded HTTP cassette under `test/cassettes/`
# named after the generated function (e.g.
# `load61_a_actual_total_load.yml`), plus a manifest entry in
# `test/_smoke_descriptors.jl` listing the function and the canonical
# example arguments published by ENTSO-E in their Postman collection.
#
# These coexist with the descriptive-name cassettes used by
# `test-cassettes.jl` and `test-queries.jl` (e.g.
# `load_61a_actual_total_load_NL.yml`) — different parameter sets,
# different purposes (content assertions vs pure coverage), same dir.
#
# Replay (always offline) drives every generated `EntsoEAPI` operation
# through its full code path — `set_param` setup, kwarg handling,
# `OpenAPI.Clients.exec` round-trip, response parsing — pushing the
# coverage of `src/api/apis/` far above what the targeted cassette
# tests in `test-cassettes.jl` and `test-queries.jl` reach.
#
# Nothing here is asserted about the *content* of the response; many
# endpoints legitimately return an `<Acknowledgement_MarketDocument>`
# for the canonical Postman parameters (the data Postman cites isn't
# always still on the platform). Either kind of response counts as
# successful playback — we only require that the wrapper executed
# without throwing a non-acknowledgement error.
#
# To re-record (or add a new endpoint), follow the procedure in
# `scripts/regenerate_smoke_cassettes.jl`.

include("_brokenrecord_helpers.jl")
include("_smoke_descriptors.jl")

let BR = _load_brokenrecord()
    if BR === nothing
        @info "BrokenRecord not installed; skipping smoke replay tests."
    else
        # Single client + apis instance shared across all replays.
        client = ENTSOEClient("PLAYBACK")
        apis = entsoe_apis(client)

        @testset "Smoke (replay all $(length(SMOKE_DESCRIPTORS)) endpoints)" begin
            for d in SMOKE_DESCRIPTORS
                api = getfield(apis, d.api_field)
                fn = getfield(ENTSOE.ENTSOEAPI, d.fn::Symbol)
                # Most cassettes are YAML; a few endpoints return
                # `application/zip` whose bytes don't roundtrip through
                # YAML cleanly, so they were recorded as BSON instead.
                # BrokenRecord picks the storage backend from
                # `DEFAULTS[:extension]`, so flip per-cassette.
                base = String(d.fn)
                ext = isfile(joinpath(_BROKENRECORD_CASSETTES_DIR, base * ".bson")) ? "bson" : "yml"
                cassette = base * "." * ext
                Base.invokelatest(BR.configure!; extension = ext)
                @testset "$(d.fn)" begin
                    # Generated functions return `(xml, response)` directly
                    # — they don't auto-throw on
                    # `<Acknowledgement_MarketDocument>`. The cassette
                    # may have captured any of:
                    #   - a 200 with parsed XML  → `xml::String`
                    #   - a 200 with an acknowledgement document
                    #     → `xml::String` (just shorter)
                    #   - a 4xx the recording session got back (some of
                    #     ENTSO-E's example parameters are stale and the
                    #     platform returns an error) → `xml === nothing`
                    # In all three cases the wrapper executed end-to-end,
                    # which is the coverage we need; the per-endpoint
                    # response *content* is the named-arg wrappers' job
                    # (covered in `test-queries.jl`). Just assert we got
                    # *some* tuple back without throwing.
                    rv = Base.invokelatest(
                        BR.playback,
                        () -> fn(api, d.positional...; d.kwargs...),
                        cassette,
                    )
                    @test rv isa Tuple
                    @test length(rv) == 2
                end
            end
        end
    end
end
