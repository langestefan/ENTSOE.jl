#!/usr/bin/env julia
# Re-run OpenAPI codegen against the upstream spec.
# Run from the package root: `julia --project gen/regenerate.jl`.
#
# Requires Java 11+ (and Node 18+ for the `npx` wrapper). End users of the
# generated wrapper package never need either — this script is for the
# maintainer only.
#
# Flags:
#   --no-fetch              Skip the network round-trip; use the spec already
#                           at `spec/openapi.json`.
#   --from-file <path>      Use <path> as the spec source (copied into
#                           `spec/openapi.json`); overrides the pinned URL.
#                           Mutually exclusive with --no-fetch.
#   -h, --help              Print this help and exit.

using Pkg

const SPEC_URL = "/home/langestefan/Nextcloud/Projects/2026/EntsoE.jl/entsoe-openapi.json"
const API_PKG = "EntsoEAPI"
const GENERATOR_VERSION = "7.10.0"
const NPM_WRAPPER_VERSION = "2.21.4"

const USAGE = """
Usage: julia --project gen/regenerate.jl [--no-fetch | --from-file <path>]

  --no-fetch              Reuse the existing spec/openapi.json (no download).
  --from-file <path>      Copy <path> into spec/openapi.json before codegen.
  -h, --help              Show this message.
"""

function parse_args(argv)
    spec_override = nothing
    no_fetch = false
    i = 1
    while i <= length(argv)
        arg = argv[i]
        if arg == "--no-fetch"
            no_fetch = true
            i += 1
        elseif arg == "--from-file"
            i + 1 <= length(argv) || error("--from-file requires a path argument")
            spec_override = argv[i + 1]
            i += 2
        elseif startswith(arg, "--from-file=")
            spec_override = split(arg, '='; limit = 2)[2]
            i += 1
        elseif arg == "-h" || arg == "--help"
            println(USAGE)
            exit(0)
        else
            error("Unknown argument: $arg\n\n" * USAGE)
        end
    end
    if no_fetch && spec_override !== nothing
        error("--no-fetch and --from-file are mutually exclusive")
    end
    return (; spec_override, no_fetch)
end

function main()
    Sys.which("java") === nothing && error(
        "java not found on PATH. Install Java 11+ from https://adoptium.net/.",
    )

    opts = parse_args(ARGS)

    pkg_root = dirname(@__DIR__)
    spec_local = joinpath(pkg_root, "spec", "openapi.json")
    api_target = joinpath(pkg_root, "src", "api")
    mkpath(dirname(spec_local))

    if opts.spec_override !== nothing
        isfile(opts.spec_override) ||
            error("Spec not found: $(opts.spec_override)")
        @info "Using local spec $(opts.spec_override)"
        cp(opts.spec_override, spec_local; force = true)
    elseif opts.no_fetch
        isfile(spec_local) || error(
            "--no-fetch given but $spec_local does not exist; run without " *
                "--no-fetch once to populate it.",
        )
        @info "Reusing existing spec $spec_local (--no-fetch)"
    elseif startswith(SPEC_URL, r"^https?://"i)
        @info "Refreshing spec from $SPEC_URL"
        Pkg.PlatformEngines.download(SPEC_URL, spec_local)
    else
        isfile(SPEC_URL) || error("Spec not found: $SPEC_URL")
        cp(SPEC_URL, spec_local; force = true)
    end

    mktempdir() do tmp
        out = joinpath(tmp, "out")
        cmd = Cmd(`npx --yes @openapitools/openapi-generator-cli@$(NPM_WRAPPER_VERSION) generate
                   -i $spec_local
                   -g julia-client
                   -o $out
                   --additional-properties=packageName=$(API_PKG),exportModels=true,exportOperations=true`;
                  dir = tmp)
        env = copy(ENV)
        env["OPENAPI_GENERATOR_VERSION"] = GENERATOR_VERSION
        run(setenv(cmd, env))

        # Replace src/api/ in place.
        isdir(api_target) && rm(api_target; recursive = true)
        mkpath(api_target)
        for entry in readdir(joinpath(out, "src"); join = false)
            cp(joinpath(out, "src", entry), joinpath(api_target, entry))
        end
    end

    # Format the generated tree if JuliaFormatter is available.
    try
        @eval using JuliaFormatter
        Base.invokelatest(JuliaFormatter.format, api_target)
    catch
        @info "JuliaFormatter not installed; skipping formatting of src/api/."
    end

    # Print a quick summary of what changed.
    if Sys.which("git") !== nothing && isdir(joinpath(pkg_root, ".git"))
        run(Cmd(`git diff --stat src/api spec`; dir = pkg_root))
    end

    @info "Regeneration complete." spec = spec_local api = api_target
end

main()
