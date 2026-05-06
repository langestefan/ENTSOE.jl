#!/usr/bin/env julia
# postman_to_openapi.jl
# =====================
#
# Convert the ENTSO-E Transparency Platform Postman collection into a clean
# OpenAPI 3.1 specification with one operation per Postman request.
#
# Why this exists
# ---------------
# Generic Postman -> OpenAPI converters (e.g. `postman2openapi`) collapse
# every ENTSO-E request onto a single path `/`, because the real API differs
# only in query parameters. The resulting spec is unusable for code
# generation since every operation is identical. This script reads the
# Postman collection directly and emits one operation per request under a
# synthetic path of the form `/{group}/{request-name}`. The eight ENTSO-E
# groups become OpenAPI tags, the `securityToken` parameter is lifted into a
# global apiKey security scheme, and `[M]`/`[O]` markers in Postman parameter
# descriptions are translated into OpenAPI `required` flags.
#
# Usage
# -----
#     julia scripts/postman_to_openapi.jl
#     julia scripts/postman_to_openapi.jl <input.json> <output-base-without-ext>
#
# Defaults: reads `spec/Transparency Platform Restful API.postman_collection.json`
# and writes `spec/openapi.json` + `spec/openapi.yaml`. The JSON form is what
# `gen/regenerate.jl` consumes for `openapi-generator-cli`.
#
# Dependencies are installed into a per-user shared environment
# (`~/.julia/environments/entsoe-scripts`) on first run so this stays a
# single file with no Project.toml beside it.

using Pkg
let env = joinpath(first(DEPOT_PATH), "environments", "entsoe-scripts")
    Pkg.activate(env; io = devnull)
    for pkg in ("JSON3", "YAML", "OrderedCollections")
        Base.find_package(pkg) === nothing && Pkg.add(pkg; io = devnull)
    end
end

using JSON3, YAML, OrderedCollections

# ---- helpers -------------------------------------------------------------

function slugify(s::AbstractString)
    out = lowercase(String(s))
    out = replace(out, r"[^a-z0-9]+" => "-")
    out = strip(out, '-')
    return isempty(out) ? "endpoint" : String(out)
end

strip_marker(d::AbstractString) = replace(String(d), r"^\s*\[[MO]\]\s*" => "")
is_required(d::AbstractString)  = occursin(r"^\s*\[M\]", String(d))

function infer_schema(value)
    v = value === nothing ? "" : string(value)
    occursin(r"^-?\d+$", v) && return OrderedDict{String,Any}("type" => "integer")
    return OrderedDict{String,Any}("type" => "string")
end

# Recursively walk Postman's nested item tree, collecting (top-level-tag, leaf)
# pairs. The first non-root folder name encountered on the way down becomes
# the tag, so deeper sub-folders still group under their top-level section.
function collect_leaves!(items, tag, out)
    for item in items
        if haskey(item, :item)
            inner_tag = tag === nothing ? String(get(item, :name, "Untagged")) : tag
            collect_leaves!(item.item, inner_tag, out)
        elseif haskey(item, :request)
            push!(out, (tag === nothing ? "Untagged" : tag, item))
        end
    end
    return out
end

# ---- per-operation construction ------------------------------------------

function build_operation(item, tag::AbstractString, used_paths::Set{String})
    name = String(get(item, :name, "endpoint"))
    req  = item.request
    method = lowercase(String(get(req, :method, "GET")))

    params = OrderedDict{String,Any}[]
    url = get(req, :url, nothing)
    if url isa JSON3.Object && haskey(url, :query)
        for q in url.query
            key = String(get(q, :key, ""))
            isempty(key) && continue
            key == "securityToken" && continue   # lifted to global security scheme
            desc  = String(get(q, :description, ""))
            value = get(q, :value, nothing)
            p = OrderedDict{String,Any}(
                "name"     => key,
                "in"       => "query",
                "required" => is_required(desc),
                "schema"   => infer_schema(value),
            )
            stripped = strip_marker(desc)
            isempty(stripped) || (p["description"] = stripped)
            if value !== nothing
                v = string(value)
                isempty(v) || (p["example"] = v)
            end
            push!(params, p)
        end
    end

    base = "/" * slugify(tag) * "/" * slugify(name)
    path = base
    n = 1
    while path in used_paths
        n += 1
        path = base * "-" * string(n)
    end
    push!(used_paths, path)

    op_id = replace(slugify(tag) * "_" * slugify(name) *
                    (n > 1 ? "_$n" : ""), '-' => '_')

    op = OrderedDict{String,Any}(
        "tags"        => [tag],
        "summary"     => name,
        "operationId" => op_id,
    )
    req_desc = String(get(req, :description, ""))
    isempty(req_desc) || (op["description"] = req_desc)
    op["parameters"] = params
    op["responses"]  = OrderedDict{String,Any}(
        "200" => OrderedDict{String,Any}(
            "description" => "Successful response",
            "content"     => OrderedDict{String,Any}(
                "application/xml" => OrderedDict{String,Any}(
                    "schema" => OrderedDict{String,Any}("type" => "string"),
                ),
            ),
        ),
    )

    return path, method, op
end

# ---- main ----------------------------------------------------------------

const INFO_DESCRIPTION = """
Auto-generated from the official ENTSO-E Postman collection by
`scripts/postman_to_openapi.jl`.

The real ENTSO-E Transparency Platform API exposes a single endpoint that is
dispatched purely by query parameters. To make this spec useful for code
generation, each Postman request has been mapped to a SYNTHETIC path of the
form `/{group}/{request-name}`. A client implemented from this spec must
route every operation back to the real base URL with the query parameters
attached.
"""

function run_conversion(input_path::AbstractString, output_base::AbstractString)
    println("Reading: ", input_path)
    coll = JSON3.read(read(input_path, String))

    leaves = Tuple{String,Any}[]
    collect_leaves!(coll.item, nothing, leaves)
    println("Collected ", length(leaves), " leaf requests")

    paths    = OrderedDict{String,Any}()
    used     = Set{String}()
    tag_list = String[]

    for (tag, item) in leaves
        tag in tag_list || push!(tag_list, tag)
        result = build_operation(item, tag, used)
        result === nothing && continue
        path, method, op = result
        path_obj = get!(paths, path, OrderedDict{String,Any}())
        path_obj[method] = op
    end

    spec = OrderedDict{String,Any}(
        "openapi" => "3.1.0",
        "info" => OrderedDict{String,Any}(
            "title"       => String(coll.info.name),
            "version"     => "1.0.0",
            "description" => INFO_DESCRIPTION,
        ),
        "servers" => [OrderedDict{String,Any}(
            "url"         => "https://web-api.tp.entsoe.eu/api",
            "description" => "ENTSO-E Transparency Platform (synthetic paths -- see info.description)",
        )],
        "security" => [OrderedDict{String,Any}("SecurityToken" => String[])],
        "tags"     => [OrderedDict{String,Any}("name" => t) for t in tag_list],
        "paths"    => paths,
        "components" => OrderedDict{String,Any}(
            "securitySchemes" => OrderedDict{String,Any}(
                "SecurityToken" => OrderedDict{String,Any}(
                    "type" => "apiKey",
                    "in"   => "query",
                    "name" => "securityToken",
                ),
            ),
        ),
    )

    yaml_out = output_base * ".yaml"
    json_out = output_base * ".json"
    YAML.write_file(yaml_out, spec)
    open(json_out, "w") do io
        JSON3.pretty(io, JSON3.write(spec))
    end

    println("Wrote: ", yaml_out)
    println("Wrote: ", json_out)
    println("Operations: ", sum(length(v) for v in values(paths)))
    println("Tags: ", join(tag_list, ", "))
end

const REPO_ROOT      = normpath(joinpath(@__DIR__, ".."))
const SPEC_DIR       = joinpath(REPO_ROOT, "spec")
const DEFAULT_INPUT  = joinpath(SPEC_DIR,
    "Transparency Platform Restful API.postman_collection.json")
const DEFAULT_OUTPUT = joinpath(SPEC_DIR, "openapi")

if abspath(PROGRAM_FILE) == @__FILE__
    input  = length(ARGS) >= 1 ? ARGS[1] : DEFAULT_INPUT
    output = length(ARGS) >= 2 ? ARGS[2] : DEFAULT_OUTPUT
    run_conversion(input, output)
end
