# ENTSO-E specific helpers layered on top of the generated API client and the
# template-provided `Client` overlay. Lives outside `src/api/` so it survives
# `gen/regenerate.jl` runs unchanged.

include("period.jl")
include("eic.jl")
include("client.jl")

export entsoe_period, EIC, EntsoEClient, entsoe_apis, ENTSOE_BASE_URL
