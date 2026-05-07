# Generated Reference

```@meta
CurrentModule = EntsoE
```

This page lists every Julia name produced by [OpenAPI Generator](https://openapi-generator.tech/)
from `spec/openapi.json` — operation functions, response model types, and
shared API helpers. The set is regenerated wholesale by `gen/regenerate.jl`
whenever the spec changes; do not edit `src/api/` directly.

The interactive REST browser under [REST API Reference](api/index.md)
covers the same surface from the *spec* side (parameter shapes, response
schemas, example payloads). This page is the *Julia* side: function
signatures and the docstrings codegen attached to them.

```@autodocs
Modules = [EntsoEAPI]
Private = false
Order = [:type, :function, :constant]
```

## Per-API base paths

The `basepath` function returns the canonical server URL declared in
`spec/openapi.json` for each tagged API. It is the default used by the
domain client constructor when no explicit `base_url` is supplied.

```@docs
EntsoEAPI.basepath(::Type{EntsoEAPI.BalancingApi})
EntsoEAPI.basepath(::Type{EntsoEAPI.GenerationApi})
EntsoEAPI.basepath(::Type{EntsoEAPI.LoadApi})
EntsoEAPI.basepath(::Type{EntsoEAPI.MarketApi})
EntsoEAPI.basepath(::Type{EntsoEAPI.MasterDataApi})
EntsoEAPI.basepath(::Type{EntsoEAPI.OMIApi})
EntsoEAPI.basepath(::Type{EntsoEAPI.OutagesApi})
EntsoEAPI.basepath(::Type{EntsoEAPI.TransmissionApi})
```
