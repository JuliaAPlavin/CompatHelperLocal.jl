using Test
import Pkg
import CompatHelperLocal as CHL

@time CHL.@check()

@testset begin
    @test CHL.CompatStates.generate_new_compat(v"1.2.3"; is_julia=false) == "1.2.3"
    @test CHL.CompatStates.generate_new_compat(v"0.0.3"; is_julia=false) == "0.0.3"
    @test CHL.CompatStates.generate_new_compat(v"0.1.3"; is_julia=false) == "0.1.3"
    @test CHL.CompatStates.generate_new_compat(v"1.2.3+5"; is_julia=false) == "1.2.3"
    @test CHL.CompatStates.generate_new_compat(v"1.2.3"; is_julia=true) == "1.2"
    @test CHL.CompatStates.generate_new_compat(v"0.1.3"; is_julia=true) == "0.1"
    @test CHL.CompatStates.generate_new_compat(v"1.2.3+5"; is_julia=true) == "1.2"

    projfile = "./test_package_dir/Project.toml"
    dep_compats = CHL.gather_compats(projfile)
    
    compat_dict = CHL.generate_compat_dict(dep_compats)
    # check that our values can replace existing compat - e.g., types match
    let
        proj = Pkg.Types.read_project(projfile)
        for (k, v) in pairs(compat_dict)
            Pkg.Operations.set_compat(proj, k, v)
        end
    end

    compat_block = CHL.generate_compat_block(dep_compats)
    @test occursin(r"""\[compat\]
CSV = "[\d., ]+"
DataFrames = "[\d., ]+"
OrderedCollections = "[\d., ]+"
Scratch = "[\d., ]+"
xxxPackageXXX = "[\d., ]+"
julia = "[\d., ]+"
""", compat_block)
end

@time CHL.check("./test_package_dir/")

# run(`$(Base.julia_cmd()) ../docs/make.jl`)
