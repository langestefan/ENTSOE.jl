#!/usr/bin/env julia
# regenerate_smoke_cassettes.jl
# =============================
#
# Re-record `test/cassettes/*.{yml,bson}` against the live ENTSO-E
# API for every operation in the spec, plus the matching manifest at
# `test/_smoke_descriptors.jl`.
#
# Source of arguments: each endpoint's "canonical example" parameters
# from the official Postman collection at
# `spec/Transparency Platform Restful API.postman_collection.json`.
#
# Usage
# -----
#     julia --project scripts/regenerate_smoke_cassettes.jl
#
# Token resolution: `ENV["ENTSOE_API_TOKEN"]` first, then `token.txt`
# at the repo root (gitignored).
#
# A few endpoints (~8 of 76) return `application/zip`; YAML can't
# round-trip those bytes cleanly, so they are recorded as BSON instead.
# The smoke test (`test/test-smoke.jl`) auto-detects the cassette
# extension at replay time, so the manifest doesn't need to flag them.

using Pkg

const ROOT = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(ROOT; io = devnull)

# Test-env packages we need for recording (kept off the main `[deps]`).
Pkg.activate(joinpath(ROOT, "test"); io = devnull)
using BrokenRecord
Pkg.activate(ROOT; io = devnull)

# A temp env so we don't polute the package's own deps with JSON3.
let env = mktempdir()
    Pkg.activate(env; io = devnull)
    Pkg.add("JSON3"; io = devnull)
end

using JSON3
using ENTSOE

const POSTMAN_PATH = joinpath(
    ROOT, "spec", "Transparency Platform Restful API.postman_collection.json",
)
const SMOKE_DIR = joinpath(ROOT, "test", "cassettes")
const MANIFEST = joinpath(ROOT, "test", "_smoke_descriptors.jl")

# Pad BrokenRecord's per-thread STATE for Julia 1.12.
let target = Base.Threads.maxthreadid()
    while length(BrokenRecord.STATE) < target
        push!(
            BrokenRecord.STATE, (
                responses      = empty(BrokenRecord.STATE[1].responses),
                ignore_headers = String[],
                ignore_query   = String[],
            )
        )
    end
end

const TAG_TO_FIELD = Dict(
    "Balancing"   => :balancing,
    "Generation"  => :generation,
    "Load"        => :load,
    "Market"      => :market,
    "Master Data" => :master_data,
    "OMI"         => :omi,
    "Outages"     => :outages,
    "Transmission" => :transmission,
)

# ─── Postman walking ──────────────────────────────────────────────────────────

function _walk_leaves(items, tag, out)
    for item in items
        if haskey(item, :item)
            inner = tag === nothing ? String(item.name) : tag
            _walk_leaves(item.item, inner, out)
        elseif haskey(item, :request) && haskey(item.request, :url) &&
                haskey(item.request.url, :query)
            params = Pair{String, String}[]
            for q in item.request.url.query
                k = String(get(q, :key, ""))
                k == "securityToken" && continue
                push!(params, k => String(get(q, :value, "")))
            end
            push!(
                out, (
                    tag = String(tag),
                    name = String(item.name),
                    params = params,
                )
            )
        end
    end
    return out
end

# ─── Function-name matcher (Postman → generated) ────────────────────────────

_strip_norm(s) = replace(lowercase(s), r"[^a-z0-9]" => "")

function _build_fn_lookup()
    out = Dict{String, String}()
    for f in readdir(joinpath(ROOT, "src", "api", "apis"); join = true)
        for line in eachline(f)
            m = match(r"^function (\w+)\(_api::\w+", line)
            m === nothing && continue
            startswith(m.captures[1], "_oacinternal_") && continue
            out[_strip_norm(m.captures[1])] = m.captures[1]
        end
    end
    return out
end

# ─── Signature parser (positional + kwarg names) ─────────────────────────────

function _parse_sig(fn_name)
    pat_full   = Regex("^function $(fn_name)\\(_api::\\w+, (.*?)\\)\$")
    pat_kwonly = Regex("^function $(fn_name)\\(_api::\\w+; (.*?)\\)\$")
    for f in readdir(joinpath(ROOT, "src", "api", "apis"); join = true)
        for line in eachline(f)
            occursin("response_stream::Channel", line) && continue
            for (pat, has_pos) in ((pat_full, true), (pat_kwonly, false))
                m = match(pat, line)
                m === nothing && continue
                inner = m.captures[1]
                pos_names, kw_names = String[], String[]
                if has_pos
                    parts = split(inner, "; "; limit = 2)
                    for p in split(strip(parts[1]), ", "; keepempty = false)
                        push!(pos_names, String(first(split(p, "::"))))
                    end
                    if length(parts) >= 2
                        for p in split(strip(parts[2]), ", "; keepempty = false)
                            push!(kw_names, String(first(split(p, "="))))
                        end
                    end
                else
                    for p in split(strip(inner), ", "; keepempty = false)
                        push!(kw_names, String(first(split(p, "="))))
                    end
                end
                return (positional = pos_names, keyword = kw_names)
            end
        end
    end
    return nothing
end

# Postman param name (camelCase, possibly with `.`) → openapi-generator
# Julia identifier (snake_case). Mirrors the codegen's normalizer.
function _param_to_julia(s)
    s = String(s)
    s = replace(s, r"([A-Z])" => s"_\1")
    s = replace(s, "." => "_")
    s = lowercase(s)
    s = replace(s, r"_+" => "_")
    return strip(s, '_')
end

# ─── Build descriptor for one Postman leaf ──────────────────────────────────

function _build_descriptor(leaf, fn_name, sig)
    pmap = Dict(_param_to_julia(k) => v for (k, v) in leaf.params)
    pos_args = Any[]
    for arg in sig.positional
        haskey(pmap, arg) || error(
            "missing positional `$(arg)` for $(fn_name) — Postman leaf \"$(leaf.name)\"."
        )
        v = pmap[arg]
        push!(pos_args, occursin(r"^\d+$", v) ? parse(Int64, v) : v)
    end
    kw_pairs = Pair{Symbol, Any}[]
    for kw in sig.keyword
        kw == "_mediaType" && continue
        haskey(pmap, kw) || continue
        v = pmap[kw]
        push!(kw_pairs, Symbol(kw) => occursin(r"^\d+$", v) ? parse(Int64, v) : v)
    end
    return (
        fn_name    = fn_name,
        positional = pos_args,
        kwargs     = NamedTuple(kw_pairs),
        leaf_tag   = leaf.tag,
        leaf_name  = leaf.name,
    )
end

# ─── Recording loop ─────────────────────────────────────────────────────────

function _record_all(descriptors, client, apis)
    # Only delete cassettes the smoke set owns — never the curated ones
    # used by `test-cassettes.jl` / `test-queries.jl`. Smoke cassettes
    # are named exactly after a generated function symbol; descriptive
    # cassettes follow a different convention (`<area>_<id>_<name>.yml`).
    mkpath(SMOKE_DIR)
    for d in descriptors, ext in ("yml", "bson")
        path = joinpath(SMOKE_DIR, d.fn_name * "." * ext)
        isfile(path) && rm(path)
    end

    BrokenRecord.configure!(;
        path = SMOKE_DIR, extension = "yml",
        ignore_headers = [
            "Authorization", "X-API-Key", "User-Agent", "Accept-Encoding",
        ],
        ignore_query   = ["securityToken"],
    )

    binary = String[]
    for d in descriptors
        api = getfield(apis, Symbol(TAG_TO_FIELD[d.leaf_tag]))
        fn  = getfield(ENTSOE.ENTSOEAPI, Symbol(d.fn_name))
        # First pass with YAML.
        BrokenRecord.configure!(extension = "yml")
        result = try
            BrokenRecord.playback(d.fn_name * ".yml") do
                fn(api, d.positional...; d.kwargs...)
            end
            :ok
        catch e
            e isa ENTSOEAcknowledgement ? :ack : (e, sprint(showerror, e))
        end
        # If the response contained a ZIP body, the YAML cassette will be
        # corrupt at replay time. Detect via Content-Type and re-record
        # as BSON.
        yaml_path = joinpath(SMOKE_DIR, d.fn_name * ".yml")
        if isfile(yaml_path) && occursin("application/zip", read(yaml_path, String))
            rm(yaml_path)
            BrokenRecord.configure!(extension = "bson")
            try
                BrokenRecord.playback(d.fn_name * ".bson") do
                    fn(api, d.positional...; d.kwargs...)
                end
                push!(binary, d.fn_name)
                @info "recorded BSON (binary response)" fn = d.fn_name
            catch e
                @warn "BSON re-record failed" fn = d.fn_name err = sprint(showerror, e)
            end
        elseif result === :ok || result === :ack
            @info "recorded YAML" fn = d.fn_name
        else
            @warn "recording threw" fn = d.fn_name err = result[2]
        end
    end
    return binary
end

# ─── Manifest writer ─────────────────────────────────────────────────────────

function _jl_repr(v)
    v isa Integer       && return string(v)
    v isa AbstractString && return repr(String(v))
    return error("unsupported manifest value $(typeof(v))")
end

function _write_manifest(descriptors)
    io = IOBuffer()
    println(io, "# Auto-generated by `scripts/regenerate_smoke_cassettes.jl` —")
    println(io, "# do not edit by hand. Each entry pairs a generated function")
    println(io, "# in `EntsoEAPI` with the positional + keyword arguments")
    println(io, "# Postman publishes as the canonical example for that endpoint.")
    println(io)
    println(io, "const SMOKE_DESCRIPTORS = [")
    for d in descriptors
        pos = "[" * join(_jl_repr.(d.positional), ", ") * "]"
        kws = ["$(k) = $(_jl_repr(v))" for (k, v) in pairs(d.kwargs)]
        kw  = isempty(kws) ? "(;)" : "(; " * join(kws, ", ") * ")"
        api_field = TAG_TO_FIELD[d.leaf_tag]
        println(io, "    (fn = :$(d.fn_name),")
        println(io, "     api_field = :$(api_field),")
        println(io, "     positional = $pos,")
        println(io, "     kwargs = $kw),")
    end
    println(io, "]")
    return write(MANIFEST, String(take!(io)))
end

# ─── main ───────────────────────────────────────────────────────────────────

function main()
    token_env = get(ENV, "ENTSOE_API_TOKEN", "")
    token = isempty(token_env) ? strip(read(joinpath(ROOT, "token.txt"), String)) : token_env
    isempty(token) && error("no ENTSO-E token in ENV or token.txt")

    postman = JSON3.read(read(POSTMAN_PATH, String))
    leaves  = NamedTuple[]
    _walk_leaves(postman.item, nothing, leaves)
    @info "Postman leaves" count = length(leaves)

    fn_lookup = _build_fn_lookup()
    descriptors = NamedTuple[]
    for leaf in leaves
        key = _strip_norm(leaf.tag * "_" * leaf.name)
        haskey(fn_lookup, key) || (
            @warn "no matching generated function" tag = leaf.tag name = leaf.name; continue
        )
        fn_name = fn_lookup[key]
        sig = _parse_sig(fn_name)
        sig === nothing && (@warn "couldn't parse signature" fn = fn_name; continue)
        push!(descriptors, _build_descriptor(leaf, fn_name, sig))
    end
    @info "Resolved descriptors" count = length(descriptors)

    client = ENTSOEClient(String(token))
    apis   = entsoe_apis(client)
    binary = _record_all(descriptors, client, apis)
    @info "Recorded" total = length(descriptors) binary = length(binary)

    _write_manifest(descriptors)
    @info "Wrote manifest" path = MANIFEST
    return nothing
end

abspath(PROGRAM_FILE) == @__FILE__ && main()
