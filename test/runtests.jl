using Test
import CompatHelperLocal as CHL

@test CHL.@check()

CHL.check("./test_package_dir/")
