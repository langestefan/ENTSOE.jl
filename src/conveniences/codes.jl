# ENTSO-E "code list" reference tables.
#
# Every Transparency Platform query takes one or more codes —
# `documentType=A44`, `processType=A16`, `businessType=B33`, `psrType=B19`,
# etc. — drawn from a fixed enumeration published in the IEC 62325
# standard. The generated wrapper takes them as raw `String`s, so users
# need a way to look up "what is A44 again" without leaving the REPL.
#
# Each constant below is a `NamedTuple` keyed by the canonical code symbol
# (`A44`, `B19`) holding the human-readable description. A reverse
# Dict `<NAME>_BY_LABEL` is provided for case-insensitive lookup the other
# way. The tables are *not* exhaustive but cover every code emitted by the
# 77 operations our spec exposes; uncommon codes can still be passed
# straight as strings.

"""
    DOCUMENT_TYPE

Canonical ENTSO-E `documentType` codes (parameter on most operations).

```jldoctest
julia> DOCUMENT_TYPE.A44
"Price document"
```
"""
const DOCUMENT_TYPE = (
    A09 = "Finalised schedule",
    A11 = "Aggregated energy data report",
    A15 = "Acquiring system operator reserve schedule",
    A24 = "Bid document",
    A25 = "Allocation result document",
    A26 = "Capacity document",
    A31 = "Agreed capacity",
    A36 = "Capacity allocation considering reliability margin",
    A37 = "Reliability margin",
    A38 = "Reserve allocation result document",
    A44 = "Price document",
    A60 = "MOL capacity allocation",
    A61 = "MOL document",
    A62 = "Bid availability document",
    A63 = "Reserve plan",
    A64 = "Acquiring system operator reserve schedule",
    A65 = "System total load",
    A68 = "Installed generation per type",
    A69 = "Wind and solar forecast",
    A70 = "Load forecast margin",
    A71 = "Generation forecast",
    A72 = "Reservoir filling information",
    A73 = "Actual generation",
    A74 = "Wind and solar generation",
    A75 = "Actual generation per type",
    A76 = "Load unavailability",
    A77 = "Production unavailability",
    A78 = "Transmission unavailability",
    A79 = "Offshore grid infrastructure unavailability",
    A80 = "Generation unavailability",
    A81 = "Contracted reserves",
    A82 = "Accepted offers",
    A83 = "Activated balancing quantities",
    A84 = "Activated balancing prices",
    A85 = "Imbalance prices",
    A86 = "Imbalance volume",
    A87 = "Financial situation",
    A88 = "Cross border balancing",
    A89 = "Contracted reserve prices",
    A90 = "Interconnection network expansion",
    A91 = "Counter trade notice",
    A92 = "Congestion costs",
    A93 = "DC link capacity",
    A94 = "Non EU allocations",
    A95 = "Configuration document",
    A96 = "Settlement document",
    A97 = "Capacity available for non market activities",
    B11 = "Production unit",
)

"""
    PROCESS_TYPE

Canonical ENTSO-E `processType` codes (parameter on Load, Generation, and
some Balancing operations).

```jldoctest
julia> PROCESS_TYPE.A16
"Realised"
```
"""
const PROCESS_TYPE = (
    A01 = "Day ahead",
    A02 = "Intra day incremental",
    A16 = "Realised",
    A18 = "Intraday total",
    A31 = "Week ahead",
    A32 = "Month ahead",
    A33 = "Year ahead",
    A39 = "Synchronisation process",
    A40 = "Intraday process",
    A46 = "Replacement reserve",
    A47 = "Manual frequency restoration reserve",
    A51 = "Automatic frequency restoration reserve",
    A52 = "Frequency containment reserve",
    A56 = "Frequency restoration reserve",
)

"""
    BUSINESS_TYPE

Canonical ENTSO-E `businessType` codes — the most heavily overloaded code
list in the standard. These describe the *purpose* of a document or
TimeSeries (energy, capacity, reserve, balancing, redispatch …).

```jldoctest
julia> BUSINESS_TYPE.A33
"Outage"
```
"""
const BUSINESS_TYPE = (
    A01 = "Production",
    A02 = "Internal trade",
    A03 = "External trade explicit allocation",
    A04 = "Consumption",
    A05 = "External trade total",
    A06 = "Resulting imbalance",
    A07 = "Inadvertent energy",
    A25 = "General Capacity Information",
    A29 = "Already allocated capacity (AAC)",
    A33 = "Outage",
    A37 = "Installed generation",
    A38 = "Available margin",
    A39 = "Generation forecast",
    A43 = "Requested capacity (without price)",
    A44 = "Compensation for absolute decrease",
    A45 = "Compensation for relative decrease",
    A46 = "System operator redispatching",
    A48 = "Cross-border redispatching",
    A52 = "Common reserve allocation",
    A53 = "Planned maintenance",
    A54 = "Unplanned outage",
    A55 = "Other operative information",
    A56 = "Frequency containment reserve",
    A60 = "Min margin",
    A61 = "Max margin",
    A62 = "Spot price",
    A63 = "Minimum possible",
    A64 = "Maximum possible",
    A66 = "Power system resource type",
    A85 = "Internal redispatch",
    A95 = "FCR contracted",
    A96 = "Automatic frequency restoration reserve",
    A97 = "Manual frequency restoration reserve",
    A98 = "Replacement reserve",
    B01 = "Activation",
    B02 = "Capacity",
    B03 = "Auction revenue",
    B04 = "Cost",
    B05 = "Counter trade",
    B07 = "Volume contracted",
    B08 = "Reliability margin",
    B09 = "Specific information not necessarily defined elsewhere",
    B10 = "Congestion income",
    B11 = "Production unit",
    B33 = "Area Control Error",
    B95 = "Procured capacity",
)

"""
    PSR_TYPE

Canonical ENTSO-E `psrType` codes — the production / consumption /
infrastructure type taxonomy used by the generation, capacity, and
balancing endpoints.

```jldoctest
julia> PSR_TYPE.B16
"Solar"
```
"""
const PSR_TYPE = (
    A03 = "Mixed",
    A04 = "Generation",
    A05 = "Load",
    B01 = "Biomass",
    B02 = "Fossil Brown coal/Lignite",
    B03 = "Fossil Coal-derived gas",
    B04 = "Fossil Gas",
    B05 = "Fossil Hard coal",
    B06 = "Fossil Oil",
    B07 = "Fossil Oil shale",
    B08 = "Fossil Peat",
    B09 = "Geothermal",
    B10 = "Hydro Pumped Storage",
    B11 = "Hydro Run-of-river and poundage",
    B12 = "Hydro Water Reservoir",
    B13 = "Marine",
    B14 = "Nuclear",
    B15 = "Other renewable",
    B16 = "Solar",
    B17 = "Waste",
    B18 = "Wind Offshore",
    B19 = "Wind Onshore",
    B20 = "Other",
    B21 = "AC Link",
    B22 = "DC Link",
    B23 = "Substation",
    B24 = "Transformer",
    B25 = "Battery storage",
)

# ---------------------------------------------------------------------------
# Lookup helpers

"""
    describe(table, code) -> String

Resolve a code (string or symbol) against one of the code-list NamedTuples
[`DOCUMENT_TYPE`](@ref), [`PROCESS_TYPE`](@ref), [`BUSINESS_TYPE`](@ref),
[`PSR_TYPE`](@ref). Throws `KeyError` if the code isn't in the table.

```jldoctest
julia> ENTSOE.describe(DOCUMENT_TYPE, "A44")
"Price document"

julia> ENTSOE.describe(PSR_TYPE, :B19)
"Wind Onshore"
```
"""
describe(table::NamedTuple, code::AbstractString) = describe(table, Symbol(code))
function describe(table::NamedTuple, code::Symbol)
    haskey(table, code) ||
        throw(KeyError("$(code) not found in this code list"))
    return table[code]
end

"""
    code_for(table, label) -> String

Reverse-lookup: case-insensitive substring match on the human-readable
description; returns the *string* code (e.g. `"A44"`). Useful for quickly
finding a code from a fragment of the official label.

```jldoctest
julia> ENTSOE.code_for(PSR_TYPE, "wind onshore")
"B19"

julia> ENTSOE.code_for(DOCUMENT_TYPE, "price document")
"A44"
```

Throws if zero or multiple entries match.
"""
function code_for(table::NamedTuple, label::AbstractString)
    needle = lowercase(label)
    matches = Pair{Symbol, String}[]
    for (k, v) in pairs(table)
        occursin(needle, lowercase(v)) && push!(matches, k => v)
    end
    isempty(matches) &&
        throw(KeyError("no code in this list matches `$label`"))
    length(matches) == 1 ||
        error(
        "ambiguous: $(label) matches " *
            join(("$(k) ($(v))" for (k, v) in matches), ", ")
    )
    return String(first(matches[1]))
end
