# ENTSO-E specific helpers layered on top of the generated API client and the
# template-provided `Client` overlay. Lives outside `src/api/` so it survives
# `gen/regenerate.jl` runs unchanged.

include("period.jl")
include("eic.jl")
include("codes.jl")
include("parsing.jl")
include("client.jl")
include("config.jl")
include("queries.jl")
include("splitting.jl")

export entsoe_period, EIC, ENTSOEClient, entsoe_apis, ENTSOE_BASE_URL
export DOCUMENT_TYPE, PROCESS_TYPE, BUSINESS_TYPE, PSR_TYPE
export parse_timeseries, parse_timeseries_per_psr, parse_installed_capacity
export parse_acknowledgement, check_acknowledgement, ENTSOEAcknowledgement
export unzip_response
export EIC_REGISTRY, lookup_eic, is_known_eic, eics_of_type, validate_eic
export day_ahead_prices,
    actual_total_load,
    day_ahead_load_forecast, week_ahead_load_forecast,
    month_ahead_load_forecast, year_ahead_load_forecast,
    installed_capacity_per_production_type,
    generation_forecast_day_ahead,
    wind_solar_forecast,
    actual_generation_per_production_type,
    cross_border_physical_flows
# `omi_other_market_information` is already exported by the codegen layer
# (`ENTSOEAPI`); our paginated method is just a new dispatch on the same
# name (`(::Client, …)` instead of `(::OMIApi, …)`), so no extra export.
export split_period, query_split
export ENTSOEConfig, set_config, get_config
