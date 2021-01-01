using Test
import CompatHelperLocal as CHL

@time @test CHL.@check()

@time CHL.check("./test_package_dir/")

# run(`$(Base.julia_cmd()) ../docs/make.jl`)
