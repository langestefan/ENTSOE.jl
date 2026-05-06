using Test

# Tag-style filter: when `OPENAPI_SKIP_LINTING=1`, skip the `test-linting.jl`
# file (which loads Aqua/JET). Default behavior includes it; if the deps are
# not installed, the file's own probes detect-and-skip with an `@info` message.
const _SKIP_LINTING = get(ENV, "OPENAPI_SKIP_LINTING", "0") == "1"

#=
Don't add your tests to runtests.jl. Instead, create files named

    test-title-for-my-test.jl

The file will be automatically included inside a `@testset` with title "Title For My Test".
=#
for (root, dirs, files) in walkdir(@__DIR__)
    for file in files
        m = match(r"^test-(.*)\.jl$", file)
        m === nothing && continue
        if _SKIP_LINTING && file == "test-linting.jl"
            @info "Skipping linting tests (OPENAPI_SKIP_LINTING=1)."
            continue
        end
        title = titlecase(replace(m.captures[1], "-" => " "))
        @testset "$title" begin
            include(joinpath(root, file))
        end
    end
end
