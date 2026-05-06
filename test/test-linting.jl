using EntsoE
using Test

# Aqua and JET are NOT default deps of test/Project.toml — install on demand:
#   pkg> activate test
#   pkg> add Aqua@0.8 JET@0.11

let aqua_id = Base.identify_package("Aqua")
    if aqua_id === nothing
        @info "Aqua not installed; skipping. `pkg> add Aqua@0.8` in `test/` to enable."
    else
        Aqua = Base.require(aqua_id)
        @testset "Aqua" begin
            Aqua.test_all(EntsoE; ambiguities = false, stale_deps = false)
        end
    end
end

if v"1.12" <= VERSION < v"1.13"
    let jet_id = Base.identify_package("JET")
        if jet_id === nothing
            @info "JET not installed; skipping. `pkg> add JET@0.11` in `test/` to enable."
        else
            JET = Base.require(jet_id)
            @testset "JET" begin
                JET.test_package(EntsoE; target_modules = (EntsoE,))
            end
        end
    end
else
    @info "JET tests require Julia 1.12; skipping on $VERSION."
end
