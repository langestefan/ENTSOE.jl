#!/usr/bin/env julia
# emit_api_pages — walk an OpenAPI spec and write one `<Tag>.md` per tag.
#
# This file is single-sourced. OpenAPITemplate's plugin code includes it to
# get `emit_api_pages` in its own namespace, and the same file is copied
# verbatim into user packages as `gen/emit_api_pages.jl` (called from
# `gen/regenerate.jl` whenever the spec changes, or runnable as a script).
#
# Usage as a script:
#     julia --project gen/emit_api_pages.jl <spec.json> <dst_dir>
#
# Output: one markdown file per OpenAPI tag, with a `# <Tag>` heading
# followed by one `## <op summary>` per operation, each containing an
# `<OAOperation>` block (vitepress-openapi). Existing files are
# overwritten; tags removed from the spec leave stale files behind, which
# the user can clean up manually.

using JSON

function emit_api_pages(spec_path::AbstractString, dst_dir::AbstractString)
    isfile(spec_path) ||
        error("emit_api_pages: spec not found at $spec_path")
    spec = JSON.parsefile(spec_path)
    paths = get(spec, "paths", Dict())
    tag_descriptions = Dict(
        t["name"] => get(t, "description", "")
            for t in get(spec, "tags", Any[])
    )

    grouped = Dict{String, Vector{NamedTuple}}()
    for (path, methods) in paths, (method, op) in methods
        method in ("get", "post", "put", "delete", "patch", "head", "options") || continue
        tag = isempty(get(op, "tags", String[])) ? "default" : op["tags"][1]
        push!(
            get!(grouped, tag, NamedTuple[]),
            (
                method = uppercase(method),
                path = path,
                summary = get(op, "summary", "$(uppercase(method)) $path"),
                operationId = get(op, "operationId", ""),
            ),
        )
    end

    mkpath(dst_dir)
    written = String[]
    for tag in sort!(collect(keys(grouped)))
        ops = sort!(grouped[tag], by = o -> (o.path, o.method))
        body = IOBuffer()
        println(body, "# ", titlecase(tag))
        println(body)
        desc = get(tag_descriptions, tag, "")
        if !isempty(desc)
            println(body, desc)
            println(body)
        end
        for op in ops
            isempty(op.operationId) && continue
            println(body, "## ", op.summary)
            println(body)
            println(body, "`", op.method, " ", op.path, "`")
            println(body)
            # `prefix-headings="true"` makes vitepress-openapi prefix every
            # sub-section anchor ID with this operation's `operationId`
            # (e.g. `<operationId>-authorizations`), so the inner TOC links
            # resolve to the right section instead of all collapsing onto
            # the first occurrence on the page.
            println(body, "```@raw html")
            println(body, "<OAOperation operationId=\"", op.operationId, "\" prefix-headings=\"true\" />")
            println(body, "```")
            println(body)
        end
        page_path = joinpath(dst_dir, "$tag.md")
        write(page_path, take!(body))
        push!(written, "$tag.md")
    end
    return written
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) >= 2 || error(
        "Usage: julia --project gen/emit_api_pages.jl <spec.json> <dst_dir>"
    )
    pages = emit_api_pages(ARGS[1], ARGS[2])
    @info "Wrote $(length(pages)) tag page(s) to $(ARGS[2])." pages = pages
end
