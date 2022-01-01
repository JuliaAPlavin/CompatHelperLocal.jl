using Test
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

    dep_compats = CHL.gather_compats("./test_package_dir/Project.toml")
    compat_block = CHL.generate_compat_block(dep_compats)
    @test occursin(r"""\[compat\]
CSV = "\d\.\d\.\d+"
DataFrames = "1\.\d\.\d"
OrderedCollections = "1\.4\.\d"
Scratch = "0\.1, 0\.2, 1"
xxxPackageXXX = "1\.0"
julia = "1\.\d"
""", compat_block)
end

@time CHL.check("./test_package_dir/")

# run(`$(Base.julia_cmd()) ../docs/make.jl`)
