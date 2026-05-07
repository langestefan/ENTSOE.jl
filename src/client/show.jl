"""
    Base.show(io::IO, ::MIME"text/plain", x::OpenAPI.APIModel)

Pretty multi-line display for any generated model type. Lists each non-`nothing`
property on its own line, indented under the type name. Falls back to `string`
for nested models so the output stays readable in the REPL.
"""
function Base.show(io::IO, ::MIME"text/plain", x::T) where {T <: OpenAPI.APIModel}
    indent = get(io, :indent, 0)
    pad = repeat(' ', indent)
    print(io, pad, nameof(T), ":")
    for name in fieldnames(T)
        val = getfield(x, name)
        val === nothing && continue
        print(io, "\n", pad, "  ", name, ": ")
        _show_field(io, val, indent + 4)
    end
    return nothing
end

_show_field(io::IO, val::OpenAPI.APIModel, indent::Int) =
    show(IOContext(io, :indent => indent), MIME"text/plain"(), val)

function _show_field(io::IO, val::AbstractVector, indent::Int)
    return if isempty(val)
        print(io, "[]")
    else
        print(io, "[", length(val), " item", length(val) == 1 ? "" : "s", "]")
    end
end

_show_field(io::IO, val, _indent::Int) = show(io, val)
