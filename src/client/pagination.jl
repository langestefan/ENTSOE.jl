"""
    paginate_cursor(fetch_fn; channel_size=0) -> Channel

Lazy iterator over a cursor-paginated API. `fetch_fn(cursor)` must return
`(items, next_cursor)` where `items` is iterable and `next_cursor === nothing`
signals the end of pagination.

```julia
for user in paginate_cursor(c -> list_users(client; cursor=c))
    @show user.id
end
```
"""
function paginate_cursor(fetch_fn; channel_size::Int = 0)
    Channel(channel_size) do ch
        cursor = nothing
        while true
            items, cursor = fetch_fn(cursor)
            for item in items
                put!(ch, item)
            end
            cursor === nothing && break
        end
    end
end

"""
    paginate_offset(fetch_fn; page_size=50, start=0, channel_size=0) -> Channel

Lazy iterator over an offset-paginated API. `fetch_fn(offset, limit)` must
return an iterable of items. Iteration stops on the first short page (fewer
items than `page_size`).
"""
function paginate_offset(fetch_fn; page_size::Int = 50, start::Int = 0, channel_size::Int = 0)
    Channel(channel_size) do ch
        offset = start
        while true
            items = collect(fetch_fn(offset, page_size))
            for item in items
                put!(ch, item)
            end
            length(items) < page_size && break
            offset += length(items)
        end
    end
end

"""
    paginate_pagenum(fetch_fn; start=1, channel_size=0) -> Channel

Lazy iterator over a page-number-paginated API. `fetch_fn(page)` must return
an iterable of items. Iteration stops on the first empty page.
"""
function paginate_pagenum(fetch_fn; start::Int = 1, channel_size::Int = 0)
    Channel(channel_size) do ch
        page = start
        while true
            items = collect(fetch_fn(page))
            isempty(items) && break
            for item in items
                put!(ch, item)
            end
            page += 1
        end
    end
end
