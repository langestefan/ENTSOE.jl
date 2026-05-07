# Request splitting for queries that exceed ENTSO-E's per-call period
# limits.
#
# The Transparency Platform caps most time-series endpoints at "one year
# per request". A naive call covering five years silently returns only
# the first year. This file splits a long period into a sequence of
# bounded windows, calls a query function for each, and concatenates the
# results.

using Dates: Dates, DateTime, Date, Year, Day, Period

# Internal: invert `_to_period`. Accept anything `_to_period` accepts
# and produce a `DateTime`. Used by `query_split` to chunk the period
# arithmetically before feeding chunks back into the wrapper.
function _to_datetime(t)
    t isa DateTime && return t
    t isa Date && return DateTime(t)
    t isa Dates.AbstractDateTime && return DateTime(t)
    if t isa Integer
        s = lpad(string(t), 12, '0')
        return DateTime(parse(Int, s[1:4]),     # yyyy
                        parse(Int, s[5:6]),     # MM
                        parse(Int, s[7:8]),     # dd
                        parse(Int, s[9:10]),    # HH
                        parse(Int, s[11:12]))   # mm
    end
    throw(ArgumentError("don't know how to convert $(typeof(t)) to DateTime"))
end

"""
    split_period(start, stop; window=Year(1)) -> Vector{Tuple{DateTime, DateTime}}

Slice the half-open interval `[start, stop)` into consecutive
`(window_start, window_end)` chunks of at most `window` length. The
last chunk is short if the total period isn't an exact multiple of
`window`. Accepts `DateTime`, `Date`, or `yyyymmddHHMM` integer
endpoints.

Use [`query_split`](@ref) to actually call a query function once per
chunk and concatenate the results — `split_period` is the pure
arithmetic.

```jldoctest
julia> using Dates

julia> split_period(DateTime("2022-01-01"), DateTime("2025-01-01"); window = Year(1))
3-element Vector{Tuple{Dates.DateTime, Dates.DateTime}}:
 (DateTime("2022-01-01T00:00:00"), DateTime("2023-01-01T00:00:00"))
 (DateTime("2023-01-01T00:00:00"), DateTime("2024-01-01T00:00:00"))
 (DateTime("2024-01-01T00:00:00"), DateTime("2025-01-01T00:00:00"))
```
"""
function split_period(start, stop; window::Period = Year(1))
    s = _to_datetime(start)
    e = _to_datetime(stop)
    s <= e || throw(ArgumentError("start ($s) must be ≤ stop ($e)"))
    chunks = Tuple{DateTime, DateTime}[]
    cursor = s
    while cursor < e
        nxt = min(cursor + window, e)
        push!(chunks, (cursor, nxt))
        cursor = nxt
    end
    return chunks
end

"""
    query_split(query_fn, fixed_args..., start, stop; window=Year(1), kwargs...)

Call `query_fn(fixed_args..., chunk_start, chunk_end; kwargs...)` for
each window in [`split_period(start, stop; window)`](@ref) and
concatenate the results with `vcat`.

`query_fn` must be one of the named-argument wrappers (or anything
with the `(client, args..., start, stop; kwargs...)` shape) that
returns a `Vector` per call. The two period arguments must be the
*last two positional* arguments — same convention as the wrappers in
this package.

# Example
```julia
using Dates

# Five years of NL prices, split into yearly chunks under the hood.
prices = query_split(
    day_ahead_prices,
    client, EIC.NL,
    DateTime("2020-01-01"), DateTime("2025-01-01");
    window = Year(1),
)
```

`Dates.Year(1)` is the right window for most ENTSO-E series; some
endpoints (e.g. balancing energy bids) cap at one day, so pass
`window = Day(1)` there.

A chunk that returns an empty result (`EntsoEAcknowledgement` —
"no matching data") is skipped rather than aborting the whole run,
unless the chunk *throws* during a non-acknowledgement error in which
case the exception propagates as usual.
"""
function query_split(
        query_fn::Function, args...;
        window::Period = Year(1),
        kwargs...,
    )
    length(args) >= 2 ||
        throw(ArgumentError(
            "query_split needs at least 2 positional args (start, stop)"
        ))
    head  = args[1:(end - 2)]
    start = args[end - 1]
    stop  = args[end]

    chunks = split_period(start, stop; window = window)
    results = Any[]
    for (s, e) in chunks
        chunk_result = try
            query_fn(head..., s, e; kwargs...)
        catch err
            err isa EntsoEAcknowledgement || rethrow()
            continue   # acknowledgement on this window → skip it
        end
        push!(results, chunk_result)
    end
    isempty(results) && return []
    return reduce(vcat, results)
end
