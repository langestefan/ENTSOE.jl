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
    AT     = "10YAT-APG------L",
    BE     = "10YBE----------2",
    BG     = "10YCA-BULGARIA-R",
    CH     = "10YCH-SWISSGRIDZ",
    CZ     = "10YCZ-CEPS-----N",
    DE_LU  = "10Y1001A1001A82H",   # Bidding zone DE/LU since 2018-10-01
    DK1    = "10YDK-1--------W",
    DK2    = "10YDK-2--------M",
    EE     = "10Y1001A1001A39I",
    ES     = "10YES-REE------0",
    FI     = "10YFI-1--------U",
    FR     = "10YFR-RTE------C",
    GB     = "10YGB----------A",
    GR     = "10YGR-HTSO-----Y",
    HR     = "10YHR-HEP------M",
    HU     = "10YHU-MAVIR----U",
    IE_SEM = "10Y1001A1001A59C",
    IT_NORTH = "10Y1001A1001A73I",
    LT     = "10YLT-1001A0008Q",
    LU     = "10YLU-CEGEDEL-NQ",
    LV     = "10YLV-1001A00074",
    NL     = "10YNL----------L",
    NO1    = "10YNO-1--------2",
    NO2    = "10YNO-2--------T",
    NO3    = "10YNO-3--------J",
    NO4    = "10YNO-4--------9",
    NO5    = "10Y1001A1001A48H",
    PL     = "10YPL-AREA-----S",
    PT     = "10YPT-REN------W",
    RO     = "10YRO-TEL------P",
    RS     = "10YCS-SERBIATSOV",
    SE1    = "10Y1001A1001A44P",
    SE2    = "10Y1001A1001A45N",
    SE3    = "10Y1001A1001A46L",
    SE4    = "10Y1001A1001A47J",
    SI     = "10YSI-ELES-----O",
    SK     = "10YSK-SEPS-----K",
)
