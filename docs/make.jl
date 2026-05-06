using Documenter, DocumenterVitepress
using JSON
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

# Walk the spec at build time and emit one markdown page per tag with each
# operation as an `##`-level subsection. This lets VitePress's right-hand
# outline list every endpoint, which is impossible with a single
# `<OASpec />` blob (Vue-rendered headings don't make it into the outline).
function _api_pages(spec_path::AbstractString, src_dir::AbstractString)
    isfile(spec_path) || return Any[]
    spec = JSON.parsefile(spec_path)
    paths = get(spec, "paths", Dict())
    tag_descriptions = Dict(t["name"] => get(t, "description", "")
                            for t in get(spec, "tags", Any[]))
    grouped = Dict{String,Vector{NamedTuple}}()
    for (path, methods) in paths
        for (method, op) in methods
            method in ("get", "post", "put", "delete", "patch", "head", "options") || continue
            tag = isempty(get(op, "tags", String[])) ? "default" : op["tags"][1]
            push!(get!(grouped, tag, NamedTuple[]),
                  (method = uppercase(method),
                   path = path,
                   summary = get(op, "summary", "$(uppercase(method)) $path"),
                   description = get(op, "description", ""),
                   operationId = get(op, "operationId", "")))
        end
    end

    api_dir = joinpath(src_dir, "api")
    mkpath(api_dir)
    pages = Any[]
    for tag in sort!(collect(keys(grouped)))
        ops = sort!(grouped[tag], by = o -> (o.path, o.method))
        body = IOBuffer()
        println(body, "# ", titlecase(tag))
        println(body)
        desc = get(tag_descriptions, tag, "")
        isempty(desc) || (println(body, desc); println(body))
        for op in ops
            isempty(op.operationId) && continue
            println(body, "## ", op.summary)
            println(body)
            println(body, "`", op.method, " ", op.path, "`")
            println(body)
            println(body, "```@raw html")
            println(body, "<OAOperation operationId=\"", op.operationId, "\" />")
            println(body, "```")
            println(body)
        end
        write(joinpath(api_dir, "$tag.md"), take!(body))
        push!(pages, titlecase(tag) => "api/$tag.md")
    end
    return pages
end

const API_PAGES = HAS_SPEC ? _api_pages(SPEC_SRC, joinpath(@__DIR__, "src")) : Any[]

const PAGES = Any[
    "Home" => "index.md",
    "Getting Started" => "getting_started.md",
    "Guides" => Any[
        "Recorded HTTP tests" => "cassette_testing.md",
    ],
    "Julia API Reference" => "julia_reference.md",
]
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
