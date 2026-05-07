"""
    EIC

Curated `NamedTuple` of EIC (Energy Identification Code) strings for the most
frequently queried ENTSO-E bidding zones and control areas. Use these as
`in_Domain` / `out_Domain` / `area` values for the generated query functions:

```julia
market121_d_energy_prices(api, "A44", EIC.NL, EIC.NL, period_start, period_end)
```

The list is intentionally not exhaustive — pass any 16-character EIC string
directly when your zone isn't here. Authoritative codes are published by
ENTSO-E at <https://www.entsoe.eu/data/energy-identification-codes-eic/>.
"""
const EIC = (
    AT = "10YAT-APG------L",
    BE = "10YBE----------2",
    BG = "10YCA-BULGARIA-R",
    CH = "10YCH-SWISSGRIDZ",
    CZ = "10YCZ-CEPS-----N",
    DE_LU = "10Y1001A1001A82H",   # Bidding zone DE/LU since 2018-10-01
    DK1 = "10YDK-1--------W",
    DK2 = "10YDK-2--------M",
    EE = "10Y1001A1001A39I",
    ES = "10YES-REE------0",
    FI = "10YFI-1--------U",
    FR = "10YFR-RTE------C",
    GB = "10YGB----------A",
    GR = "10YGR-HTSO-----Y",
    HR = "10YHR-HEP------M",
    HU = "10YHU-MAVIR----U",
    IE_SEM = "10Y1001A1001A59C",
    IT_NORTH = "10Y1001A1001A73I",
    LT = "10YLT-1001A0008Q",
    LU = "10YLU-CEGEDEL-NQ",
    LV = "10YLV-1001A00074",
    NL = "10YNL----------L",
    NO1 = "10YNO-1--------2",
    NO2 = "10YNO-2--------T",
    NO3 = "10YNO-3--------J",
    NO4 = "10YNO-4--------9",
    NO5 = "10Y1001A1001A48H",
    PL = "10YPL-AREA-----S",
    PT = "10YPT-REN------W",
    RO = "10YRO-TEL------P",
    RS = "10YCS-SERBIATSOV",
    SE1 = "10Y1001A1001A44P",
    SE2 = "10Y1001A1001A45N",
    SE3 = "10Y1001A1001A46L",
    SE4 = "10Y1001A1001A47J",
    SI = "10YSI-ELES-----O",
    SK = "10YSK-SEPS-----K",
)

"""
    EIC_REGISTRY :: Dict{String, Vector{NamedTuple{(:name, :types), …}}}

Comprehensive catalog of every Energy Identification Code emitted by the
ENTSO-E Transparency Platform — about 120 entries covering bidding zones
(`:BZN`), control areas (`:CTA`), market balance areas (`:MBA`),
scheduling areas (`:SCA`), load-frequency areas/blocks (`:LFA`/`:LFB`),
imbalance pricing/balancing areas (`:IPA`/`:IBA`), aggregated zones
(`:BZA`), regions (`:REG`), countries (`:CTY`), synchronous areas
(`:SNA`), and a handful of cross-border interconnectors.

A single EIC sometimes represents multiple aliases (e.g. SEM in Ireland
maps to both `IE(SEM)` and `IE-NIE`); the value is therefore a
*vector* of `(name, types)` rather than a single tuple.

Use [`lookup_eic`](@ref) for safe lookups and [`is_known_eic`](@ref) to
validate user input. ENTSO-E's authoritative register lives at
<https://www.entsoe.eu/data/energy-identification-codes-eic/>.

```jldoctest
julia> lookup_eic("10YNL----------L")
1-element Vector{@NamedTuple{name::String, types::Vector{Symbol}}}:
 (name = "NL", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])

julia> is_known_eic("10YNOT-A-CODE---")
false
```
"""
const EIC_REGISTRY = Dict{String, Vector{@NamedTuple{name::String, types::Vector{Symbol}}}}(
    "10Y1001A1001A016" => [(name = "NIE", types = [:CTA, :SCA]), (name = "SEM(SONI)", types = [:MBA])],
    "10Y1001A1001A39I" => [(name = "EE", types = [:BZN, :CTA, :CTY, :MBA, :SCA])],
    "10Y1001A1001A44P" => [(name = "SE1", types = [:BZN, :IPA, :MBA, :SCA])],
    "10Y1001A1001A45N" => [(name = "SE2", types = [:BZN, :IPA, :MBA, :SCA])],
    "10Y1001A1001A46L" => [(name = "SE3", types = [:BZN, :IPA, :MBA, :SCA])],
    "10Y1001A1001A47J" => [(name = "SE4", types = [:BZN, :IPA, :MBA, :SCA])],
    "10Y1001A1001A48H" => [(name = "NO5", types = [:BZN, :IBA, :IPA, :MBA, :SCA])],
    "10Y1001A1001A49F" => [(name = "RU", types = [:BZN, :CTA, :MBA, :SCA])],
    "10Y1001A1001A50U" => [(name = "RU-KGD", types = [:BZN, :CTA, :MBA, :SCA])],
    "10Y1001A1001A51S" => [(name = "BY", types = [:BZN, :CTA, :MBA, :SCA])],
    "10Y1001A1001A59C" => [(name = "IE(SEM)", types = [:BZN, :MBA, :SCA]), (name = "IE-NIE", types = [:LFB]), (name = "Ireland", types = [:SNA])],
    "10Y1001A1001A63L" => [(name = "DE-AT-LU", types = [:BZN])],
    "10Y1001A1001A64J" => [(name = "NO1A", types = [:BZN])],
    "10Y1001A1001A65H" => [(name = "Denmark (DK)", types = [:CTY])],
    "10Y1001A1001A66F" => [(name = "IT-GR", types = [:BZN])],
    "10Y1001A1001A67D" => [(name = "IT-North-SI", types = [:BZN])],
    "10Y1001A1001A68B" => [(name = "IT-North-CH", types = [:BZN])],
    "10Y1001A1001A699" => [(name = "IT-Brindisi", types = [:BZN, :SCA]), (name = "IT-Z-Brindisi", types = [:MBA])],
    "10Y1001A1001A70O" => [(name = "IT-Centre-North", types = [:BZN, :SCA]), (name = "IT-Z-Centre-North", types = [:MBA])],
    "10Y1001A1001A71M" => [(name = "IT-Centre-South", types = [:BZN, :SCA]), (name = "IT-Z-Centre-South", types = [:MBA])],
    "10Y1001A1001A72K" => [(name = "IT-Foggia", types = [:BZN, :SCA]), (name = "IT-Z-Foggia", types = [:MBA])],
    "10Y1001A1001A73I" => [(name = "IT-North", types = [:BZN, :SCA]), (name = "IT-Z-North", types = [:MBA])],
    "10Y1001A1001A74G" => [(name = "IT-Sardinia", types = [:BZN, :SCA]), (name = "IT-Z-Sardinia", types = [:MBA])],
    "10Y1001A1001A75E" => [(name = "IT-Sicily", types = [:BZN, :SCA]), (name = "IT-Z-Sicily", types = [:MBA])],
    "10Y1001A1001A76C" => [(name = "IT-Priolo", types = [:BZN, :SCA]), (name = "IT-Z-Priolo", types = [:MBA])],
    "10Y1001A1001A77A" => [(name = "IT-Rossano", types = [:BZN, :SCA]), (name = "IT-Z-Rossano", types = [:MBA])],
    "10Y1001A1001A788" => [(name = "IT-South", types = [:BZN, :SCA]), (name = "IT-Z-South", types = [:MBA])],
    "10Y1001A1001A796" => [(name = "DK", types = [:CTA])],
    "10Y1001A1001A80L" => [(name = "IT-North-AT", types = [:BZN])],
    "10Y1001A1001A81J" => [(name = "IT-North-FR", types = [:BZN])],
    "10Y1001A1001A82H" => [(name = "DE-LU", types = [:BZN, :IPA, :MBA, :SCA])],
    "10Y1001A1001A83F" => [(name = "DE", types = [:CTY, :IPA])],
    "10Y1001A1001A84D" => [(name = "IT-MACRZONENORTH", types = [:MBA, :SCA])],
    "10Y1001A1001A85B" => [(name = "IT-MACRZONESOUTH", types = [:MBA, :SCA])],
    "10Y1001A1001A869" => [(name = "UA-DobTPP", types = [:BZN, :CTA, :SCA])],
    "10Y1001A1001A877" => [(name = "IT-Malta", types = [:BZN])],
    "10Y1001A1001A885" => [(name = "IT-SACOAC", types = [:BZN])],
    "10Y1001A1001A893" => [(name = "IT-SACODC", types = [:BZN, :SCA])],
    "10Y1001A1001A91G" => [(name = "Nordic", types = [:LFB, :REG, :SNA])],
    "10Y1001A1001A92E" => [(name = "United Kingdom (UK)", types = [:CTY])],
    "10Y1001A1001A93C" => [(name = "MT", types = [:BZN, :CTA, :CTY, :MBA, :SCA])],
    "10Y1001A1001A990" => [(name = "MD", types = [:BZN, :CTA, :CTY, :LFA, :MBA, :SCA])],
    "10Y1001A1001B004" => [(name = "AM", types = [:BZN, :CTA, :CTY])],
    "10Y1001A1001B012" => [(name = "GE", types = [:BZN, :CTA, :CTY, :MBA, :SCA])],
    "10Y1001A1001B05V" => [(name = "AZ", types = [:BZN, :CTA, :CTY])],
    "10Y1001C--00002H" => [(name = "DE(Amprion)-LU", types = [:LFA, :SCA])],
    "10Y1001C--00003F" => [(name = "UA", types = [:BZN, :CTY, :LFB, :MBA, :SCA])],
    "10Y1001C--000182" => [(name = "UA-IPS", types = [:BZN, :CTA, :LFA, :MBA, :SCA])],
    "10Y1001C--00031A" => [(name = "WE_REGION", types = [:REG])],
    "10Y1001C--00038X" => [(name = "CZ-DE-SK-LT-SE4", types = [:BZA])],
    "10Y1001C--00059P" => [(name = "CORE", types = [:REG])],
    "10Y1001C--00085O" => [(name = "MFRR", types = [:SCA]), (name = "MFRR_REGION", types = [:REG])],
    "10Y1001C--00090V" => [(name = "AFRR", types = [:REG, :SCA])],
    "10Y1001C--00095L" => [(name = "SWE", types = [:REG])],
    "10Y1001C--00096J" => [(name = "IT-Calabria", types = [:BZN, :SCA]), (name = "IT-Z-Calabria", types = [:MBA])],
    "10Y1001C--00098F" => [(name = "GB(IFA)", types = [:BZN])],
    "10Y1001C--00100H" => [(name = "XK", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA])],
    "10Y1001C--00119X" => [(name = "IN", types = [:SCA])],
    "10Y1001C--001219" => [(name = "NO2A", types = [:BZN])],
    "10Y1001C--00137V" => [(name = "ITALYNORTH", types = [:REG])],
    "10Y1001C--00138T" => [(name = "GRIT", types = [:REG])],
    "10YAL-KESH-----5" => [(name = "AL", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YAT-APG------L" => [(name = "AT", types = [:BZN, :CTA, :CTY, :IPA, :LFA, :LFB, :MBA, :SCA])],
    "10YBA-JPCC-----D" => [(name = "BA", types = [:BZN, :CTA, :CTY, :LFA, :MBA, :SCA])],
    "10YBE----------2" => [(name = "BE", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YCA-BULGARIA-R" => [(name = "BG", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YCB-GERMANY--8" => [(name = "DE_DK1_LU", types = [:LFB, :SCA])],
    "10YCB-JIEL-----9" => [(name = "RS_MK_ME", types = [:LFB])],
    "10YCB-POLAND---Z" => [(name = "PL", types = [:LFB])],
    "10YCB-SI-HR-BA-3" => [(name = "SI_HR_BA", types = [:LFB])],
    "10YCH-SWISSGRIDZ" => [(name = "CH", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YCS-CG-TSO---S" => [(name = "ME", types = [:BZN, :CTA, :CTY, :LFA, :MBA, :SCA])],
    "10YCS-SERBIATSOV" => [(name = "RS", types = [:BZN, :CTA, :CTY, :LFA, :MBA, :SCA])],
    "10YCY-1001A0003J" => [(name = "CY", types = [:BZN, :CTA, :CTY, :MBA, :SCA])],
    "10YCZ-CEPS-----N" => [(name = "CZ", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YDE-ENBW-----N" => [(name = "DE(TransnetBW)", types = [:CTA, :LFA, :SCA])],
    "10YDE-EON------1" => [(name = "DE(TenneT GER)", types = [:CTA, :LFA, :SCA])],
    "10YDE-RWENET---I" => [(name = "DE(Amprion)", types = [:CTA, :LFA, :SCA])],
    "10YDE-VE-------2" => [(name = "DE(50Hertz)", types = [:CTA, :LFA, :SCA]), (name = "DE(50HzT)", types = [:BZA])],
    "10YDK-1--------W" => [(name = "DK1", types = [:BZN, :IBA, :IPA, :LFA, :MBA, :SCA])],
    "10YDK-1-------AA" => [(name = "DK1A", types = [:BZN])],
    "10YDK-2--------M" => [(name = "DK2", types = [:BZN, :IBA, :IPA, :LFA, :MBA, :SCA])],
    "10YDOM-1001A082L" => [(name = "PL-CZ", types = [:BZA, :CTA])],
    "10YDOM-CZ-DE-SKK" => [(name = "CZ+DE+SK", types = [:BZN]), (name = "CZ-DE-SK", types = [:BZA])],
    "10YDOM-PL-SE-LT2" => [(name = "LT-SE4", types = [:BZA])],
    "10YDOM-REGION-1V" => [(name = "CWE", types = [:REG])],
    "10YES-REE------0" => [(name = "ES", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YEU-CONT-SYNC0" => [(name = "Continental Europe", types = [:SNA])],
    "10YFI-1--------U" => [(name = "FI", types = [:BZN, :CTA, :CTY, :IBA, :IPA, :MBA, :SCA])],
    "10YFR-RTE------C" => [(name = "FR", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YGB----------A" => [(name = "GB", types = [:BZN, :LFA, :LFB, :MBA, :SCA, :SNA]), (name = "National Grid", types = [:CTA])],
    "10YGR-HTSO-----Y" => [(name = "GR", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YHR-HEP------M" => [(name = "HR", types = [:BZN, :CTA, :CTY, :LFA, :MBA, :SCA])],
    "10YHU-MAVIR----U" => [(name = "HU", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YIE-1001A00010" => [(name = "IE", types = [:CTA, :CTY, :SCA]), (name = "SEM(EirGrid)", types = [:MBA])],
    "10YIT-GRTN-----B" => [(name = "IT", types = [:CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YLT-1001A0008Q" => [(name = "LT", types = [:BZN, :CTA, :CTY, :MBA, :SCA])],
    "10YLU-CEGEDEL-NQ" => [(name = "LU", types = [:CTA, :CTY])],
    "10YLV-1001A00074" => [(name = "LV", types = [:BZN, :CTA, :CTY, :MBA, :SCA])],
    "10YMK-MEPSO----8" => [(name = "MK", types = [:BZN, :CTA, :CTY, :LFA, :MBA, :SCA])],
    "10YNL----------L" => [(name = "NL", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YNO-0--------C" => [(name = "NO", types = [:CTA, :CTY, :MBA, :SCA])],
    "10YNO-1--------2" => [(name = "NO1", types = [:BZN, :IBA, :IPA, :MBA, :SCA])],
    "10YNO-2--------T" => [(name = "NO2", types = [:BZN, :IBA, :IPA, :MBA, :SCA])],
    "10YNO-3--------J" => [(name = "NO3", types = [:BZN, :IBA, :IPA, :MBA, :SCA])],
    "10YNO-4--------9" => [(name = "NO4", types = [:BZN, :IBA, :IPA, :MBA, :SCA])],
    "10YPL-AREA-----S" => [(name = "PL", types = [:BZA, :BZN, :CTA, :CTY, :LFA, :MBA, :SCA])],
    "10YPT-REN------W" => [(name = "PT", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YRO-TEL------P" => [(name = "RO", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YSE-1--------K" => [(name = "SE", types = [:CTA, :CTY, :MBA, :SCA])],
    "10YSI-ELES-----O" => [(name = "SI", types = [:BZN, :CTA, :CTY, :LFA, :MBA, :SCA])],
    "10YSK-SEPS-----K" => [(name = "SK", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YTR-TEIAS----W" => [(name = "TR", types = [:BZN, :CTA, :CTY, :LFA, :LFB, :MBA, :SCA])],
    "10YUA-WEPS-----0" => [(name = "UA-BEI", types = [:BZN, :CTA, :LFA, :LFB, :MBA, :SCA])],
    "11Y0-0000-0265-K" => [(name = "GB(ElecLink)", types = [:BZN])],
    "17Y0000009369493" => [(name = "GB(IFA2)", types = [:BZN])],
    "46Y000000000007M" => [(name = "DK1-NO1", types = [:BZN])],
    "50Y0JVU59B4JWQCU" => [(name = "NO2NSL", types = [:BZN])],
    "BY" => [(name = "Belarus (BY)", types = [:CTY])],
    "IS" => [(name = "Iceland (IS)", types = [:CTY])],
    "RU" => [(name = "Russia (RU)", types = [:CTY])],
)

# ---------------------------------------------------------------------------
# Lookup helpers

"""
    lookup_eic(code) -> Vector{NamedTuple{(:name, :types), …}}

Return every entry registered for the given EIC code. Empty vector
when the code is unknown — see [`is_known_eic`](@ref) for a boolean
form. Most EICs map to exactly one entry; SEM-Ireland and a handful of
cross-zone aggregates have two or three.
"""
lookup_eic(code::AbstractString) = get(EIC_REGISTRY, String(code), eltype(values(EIC_REGISTRY))())

"""
    is_known_eic(code) -> Bool

Return `true` if `code` appears in the registry. Used by
[`validate_eic`](@ref) for opt-in client-side input validation; off by
default because the registry trails ENTSO-E's authoritative list — a
new bidding zone takes a release before it shows up here.
"""
is_known_eic(code::AbstractString) = haskey(EIC_REGISTRY, String(code))

"""
    eics_of_type(type::Symbol) -> Vector{String}

Every EIC code that carries the given type tag (e.g. `:BZN`, `:CTA`).
Useful for "show me every bidding zone" type queries:

```julia
julia> bidding_zones = eics_of_type(:BZN);  # ~70 entries

julia> "10YNL----------L" in bidding_zones
true
```
"""
function eics_of_type(type::Symbol)
    out = String[]
    for (code, entries) in EIC_REGISTRY
        if any(type in e.types for e in entries)
            push!(out, code)
        end
    end
    sort!(out)
    return out
end

"""
    validate_eic(code; type=nothing) -> Nothing

Throw a descriptive `ArgumentError` if `code` is not in the
[`EIC_REGISTRY`](@ref). Optionally also require the entry to carry a
specific area-type tag — e.g. `validate_eic(area; type = :BZN)` rejects
control areas, market balance areas, etc. that aren't bidding zones.

Off by default in the named-argument query wrappers (the registry
trails ENTSO-E's authoritative list — newly created bidding zones
won't be in it for a release or two). Enable explicitly per call:

```julia
day_ahead_prices(client, area, start, stop; validate = true)
```

A typo or scrambled code is by far the most common cause of an
ENTSO-E "no matching data" acknowledgement, so flipping this on is a
cheap way to debug.
"""
function validate_eic(code::AbstractString; type::Union{Nothing, Symbol} = nothing)
    entries = lookup_eic(code)
    if isempty(entries)
        throw(
            ArgumentError(
                "unknown EIC `$(code)` — not in EIC_REGISTRY. " *
                    "ENTSO-E's authoritative list is at " *
                    "https://www.entsoe.eu/data/energy-identification-codes-eic/"
            )
        )
    end
    if type !== nothing && !any(type in e.types for e in entries)
        present = sort!(unique!(reduce(vcat, [e.types for e in entries])))
        throw(
            ArgumentError(
                "EIC `$(code)` exists but does not carry type `:$(type)`. " *
                    "Registered types for this code: " *
                    join(":" .* String.(present), ", ")
            )
        )
    end
    return nothing
end
