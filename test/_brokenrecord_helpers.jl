# Shared BrokenRecord setup for every cassette-driven test in this
# directory (`test-cassettes.jl`, `test-queries.jl`, `test-parsing.jl`,
# `test-smoke.jl`). `runtests.jl` doesn't auto-include this file because
# the filename doesn't match `test-*.jl` — each consumer does
#
#     include("_brokenrecord_helpers.jl")
#     const BR = _load_brokenrecord()
#     if BR === nothing
#         @info "BrokenRecord not installed — skipping …"
#     else
#         …
#     end
#
# The same `Base.identify_package` lookup the inline boilerplate used
# is hidden inside `_load_brokenrecord`; it returns `nothing` so each
# test file can keep its own fallback without `try`/`catch`.

# `runtests.jl` `include`s every `test-*.jl` in `test/`, and several of
# them include this helper file. The first include creates the consts
# below; subsequent includes (for siblings in the same `Main` namespace)
# would error with "invalid redefinition of constant" — so the whole
# helper body is guarded.
if !@isdefined(_BROKENRECORD_HELPERS_LOADED)
    const _BROKENRECORD_HELPERS_LOADED = true
    const _BROKENRECORD_CASSETTES_DIR = joinpath(@__DIR__, "cassettes")

    """
        _pad_brokenrecord_state(BR)

    Extend `BR.STATE` so `BR.STATE[Threads.threadid()]` is always in bounds.

    BrokenRecord 0.1 sizes its per-thread state vector at module load via
    `map(1:nthreads(), …)`. From Julia 1.12 onwards `Threads.maxthreadid()`
    exceeds `Threads.nthreads()` because the runtime spawns a separate
    `:interactive` thread pool — any task that lands on those threads then
    hits a `BoundsError` from `STATE[threadid()]` inside `playback`. This
    helper pads the vector with empty NamedTuples shaped like the existing
    ones, leaving 1.10 untouched (`maxthreadid() == nthreads()` there).
    """
    function _pad_brokenrecord_state(BR)
        target = Base.Threads.maxthreadid()
        while length(BR.STATE) < target
            template = BR.STATE[1]
            push!(
                BR.STATE, (
                    responses = empty(template.responses),
                    ignore_headers = String[],
                    ignore_query = String[],
                )
            )
        end
        return nothing
    end

    """
        _configure_brokenrecord(BR; cassettes_dir = "<test/cassettes>")

    Apply the standard `ignore_headers`/`ignore_query` redaction across
    every test that replays a cassette. `securityToken` strips ENTSO-E's
    per-request auth from the recorded URL; the headers list strips
    credential-bearing and environment-dependent fields so cassettes
    replay across Julia / HTTP.jl versions.
    """
    function _configure_brokenrecord(
            BR; cassettes_dir = _BROKENRECORD_CASSETTES_DIR,
        )
        return Base.invokelatest(
            BR.configure!;
            path = cassettes_dir,
            ignore_headers = [
                "Authorization", "X-API-Key", "api_key", "X-Api-Key",
                "Cookie", "Set-Cookie", "Proxy-Authorization",
                "User-Agent", "Accept-Encoding",
            ],
            ignore_query = ["api_key", "token", "access_token", "securityToken"],
        )
    end

    """
        _load_brokenrecord(; cassettes_dir = "<test/cassettes>") -> Module | Nothing

    One-shot helper: locate BrokenRecord, load it via `Base.require`, pad
    its `STATE`, and apply the standard configure! call. Returns the
    BrokenRecord module on success, `nothing` when it isn't installed
    (test files use that to emit an `@info` skip and continue).
    """
    function _load_brokenrecord(; cassettes_dir = _BROKENRECORD_CASSETTES_DIR)
        id = Base.identify_package("BrokenRecord")
        id === nothing && return nothing
        BR = Base.require(id)
        Base.invokelatest(_pad_brokenrecord_state, BR)
        _configure_brokenrecord(BR; cassettes_dir = cassettes_dir)
        return BR
    end
end # if !@isdefined(_BROKENRECORD_HELPERS_LOADED)
