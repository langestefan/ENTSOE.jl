using Documenter, DocumenterVitepress
using EntsoE

const SPEC_SRC = joinpath(pkgdir(EntsoE), "spec", "openapi.json")
const HAS_SPEC = isfile(SPEC_SRC)

# Bundle the committed OpenAPI spec into Vitepress's `public/` so the
# vitepress-openapi components can fetch it from the deployed site.
if HAS_SPEC
    SPEC_DST = joinpath(@__DIR__, "src", "public", "openapi.json")
    mkpath(dirname(SPEC_DST))
    cp(SPEC_SRC, SPEC_DST; force = true)
end

# The per-tag REST reference pages live as committed source under
# `docs/src/api/<Tag>.md` — written once at scaffold time by
# OpenAPITemplate's `VitepressDocs` plugin, refreshed by
# `gen/regenerate.jl` when the spec changes. We don't regenerate them on
# every docs build (would churn files in a source tree). Just glob them.
function _api_pages(api_dir::AbstractString)
    isdir(api_dir) || return Any[]
    pages = Any[]
    for file in sort!(readdir(api_dir))
        endswith(file, ".md") || continue
        file == "index.md" && continue   # hand-written REST overview
        title = titlecase(splitext(file)[1])
        push!(pages, title => "api/$file")
    end
    return pages
end

const API_PAGES = _api_pages(joinpath(@__DIR__, "src", "api"))

const PAGES = Any[
    "Home" => "index.md",
    "Getting Started" => "getting_started.md",
    "Tutorial" => "tutorial.md",
    "Guides" => Any[
        "Recorded HTTP tests" => "cassette_testing.md",
    ],
    "Julia API Reference" => "julia_reference.md",
]
if HAS_SPEC
    push!(PAGES, "Generated Reference" => "generated_reference.md")
end
if !isempty(API_PAGES)
    push!(PAGES, "REST API Reference" => Any[
        "Overview" => "api/index.md",
        API_PAGES...,
    ])
end

makedocs(;
    modules = [EntsoE],
    sitename = "EntsoE.jl",
    authors = "langestefan",
    format = MarkdownVitepress(;
        repo = "github.com/langestefan/EntsoE.jl",
        devbranch = "main",
        devurl = "dev",
        build_vitepress = true,
    ),
    pages = PAGES,
    warnonly = true,
)

DocumenterVitepress.deploydocs(;
    repo = "github.com/langestefan/EntsoE.jl",
    devbranch = "main",
    push_preview = true,
)
