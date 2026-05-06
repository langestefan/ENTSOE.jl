```@meta
CurrentModule = EntsoE
```

# EntsoE.jl

Documentation for [EntsoE.jl](https://github.com/langestefan/EntsoE.jl).

A Julia REST/JSON API wrapper scaffolded with
[OpenAPITemplate.jl](https://github.com/langestefan/OpenAPITemplate.jl).

## Quick start

```julia
using EntsoE

client = Client("https://api.example.com"; auth = BearerToken(ENV["ENTSOE_TOKEN"]))
```

See the [Getting Started](getting_started.md) guide for a worked example, or
the [Julia API Reference](julia_reference.md) for the full surface.
