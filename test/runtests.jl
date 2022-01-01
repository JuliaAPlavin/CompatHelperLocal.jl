using Test
import CompatHelperLocal

@time CompatHelperLocal.@check()

@testset begin
    dep_compats = CompatHelperLocal.gather_compats("./test_package_dir/Project.toml")
    compat_block = CompatHelperLocal.generate_compat_block(dep_compats)
    @test compat_block == """[compat]
CSV = "0.8"
DataFrames = "0.22"
OrderedCollections = "1.4"
Scratch = "0.1, 0.2, 1.0"
xxxPackageXXX = "1.0"
julia = "1.6"
"""
end

@time CompatHelperLocal.check("./test_package_dir/")

# run(`$(Base.julia_cmd()) ../docs/make.jl`)
