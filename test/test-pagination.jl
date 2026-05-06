using EntsoE
using Test

@testset "paginate_cursor" begin
    pages = Dict(
        nothing => ([1, 2, 3], "c1"),
        "c1" => ([4, 5], "c2"),
        "c2" => ([6], nothing),
    )
    items = collect(EntsoE.paginate_cursor(c -> pages[c]))
    @test items == [1, 2, 3, 4, 5, 6]
end

@testset "paginate_offset stops on short page" begin
    data = collect(1:23)
    fetched = Tuple{Int,Int}[]
    items = collect(EntsoE.paginate_offset(; page_size = 10) do offset, limit
        push!(fetched, (offset, limit))
        data[(offset+1):min(offset + limit, length(data))]
    end)
    @test items == data
    @test fetched == [(0, 10), (10, 10), (20, 10)]
end

@testset "paginate_pagenum stops on empty page" begin
    pages = Dict(1 => ['a', 'b'], 2 => ['c'], 3 => Char[])
    items = collect(EntsoE.paginate_pagenum(p -> pages[p]))
    @test items == ['a', 'b', 'c']
end
