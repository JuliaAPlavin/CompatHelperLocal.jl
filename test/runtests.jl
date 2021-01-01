using Test
import CompatHelperLocal

@time CompatHelperLocal.@check()

@time CompatHelperLocal.check("./test_package_dir/")

# run(`$(Base.julia_cmd()) ../docs/make.jl`)
