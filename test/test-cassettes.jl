using EntsoE
using Test

# BrokenRecord lets tests record an HTTP interaction once and replay it
# deterministically afterwards.
#
# Mode is decided by file existence (no env vars):
#
#   - Cassette file does NOT exist  → recording mode: real HTTP call,
#                                     request + response saved to disk.
#   - Cassette file exists          → playback mode: response replayed,
#                                     request shape verified against the
#                                     recorded one. No network is touched.
#
# Re-record a cassette by deleting its file (or the whole directory) and
# re-running the tests once on a machine with network + valid credentials.
#
# Storage: BrokenRecord defaults to `.yml` (human-readable, diffable).
# Pass `extension="bson"` for binary BSON if cassettes get large; both
# work the same way at the call site.
#
# `path = "test/cassettes"` is a VCR-style convention; BrokenRecord's own
# docs suggest `test/fixtures` — pick whichever you prefer and update
# `mkpath` and `_run_cassette_tests` together.

const _CASSETTES_DIR = joinpath(@__DIR__, "cassettes")

# All BrokenRecord interaction lives inside this function. Loading
# BrokenRecord at runtime via `Base.require` advances the Julia world,
# so any `BrokenRecord.*` call has to be reached via a function invocation
# (`Base.invokelatest`) — bare calls inside the same scope would fail with
# `MethodError: ... method too new to be called from this world context`.
function _run_cassette_tests(BrokenRecord)
    BrokenRecord.configure!(;
        path = _CASSETTES_DIR,
        # Strip credential-bearing fields before they hit disk. Header
        # matching is case-sensitive, so list common case variants of
        # the same name (`api_key` vs `X-API-Key`).
        ignore_headers = ["Authorization", "X-API-Key", "api_key",
                          "X-Api-Key", "Cookie", "Set-Cookie",
                          "Proxy-Authorization"],
        ignore_query = ["api_key", "token", "access_token"],
    )

    @testset "cassettes directory wired up" begin
        @test isdir(_CASSETTES_DIR)
    end

    # Add concrete cassette tests below. Recommended pattern (block
    # syntax — matches BrokenRecord's `playback(f, name)` API):
    #
    # @testset "list pets (cassette)" begin
    #     pets = BrokenRecord.playback("list_pets.yml") do
    #         list_pets(EntsoE.Client("https://api.example.com";
    #                                  auth = EntsoE.NoAuth()))
    #     end
    #     @test !isempty(pets)
    # end
    #
    # First run records `test/cassettes/list_pets.yml`; subsequent runs
    # replay it.
    return nothing
end

let id = Base.identify_package("BrokenRecord")
    if id === nothing
        @info "BrokenRecord not installed; skipping cassette tests. " *
            "`pkg> add BrokenRecord@0.1` in `test/` to enable."
    else
        BrokenRecord = Base.require(id)
        mkpath(_CASSETTES_DIR)
        Base.invokelatest(_run_cassette_tests, BrokenRecord)
    end
end
