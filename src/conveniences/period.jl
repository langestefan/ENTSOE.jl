using Dates: Dates, DateTime, Date

"""
    entsoe_period(t) -> Int64

Format `t` as the integer ENTSO-E expects for `periodStart` / `periodEnd`,
namely `yyyyMMddHHmm` in UTC.

Accepts:

- `Dates.DateTime` — interpreted as UTC.
- `Dates.Date` — interpreted as `00:00` UTC on that day.
- `TimeZones.ZonedDateTime` — converted to UTC first.

# Examples
```jldoctest
julia> using Dates: DateTime

julia> entsoe_period(DateTime("2023-08-23T22:00"))
202308232200
```
"""
entsoe_period(dt::DateTime) = parse(Int, Dates.format(dt, "yyyymmddHHMM"))

entsoe_period(d::Date) = entsoe_period(DateTime(d))

# ZonedDateTime support — TimeZones.jl is a runtime dep of the generated
# package so the import is already paid for.
using TimeZones: ZonedDateTime, astimezone, TimeZone
const _ENTSOE_UTC = TimeZone("UTC")
entsoe_period(zdt::ZonedDateTime) =
    entsoe_period(DateTime(astimezone(zdt, _ENTSOE_UTC)))
