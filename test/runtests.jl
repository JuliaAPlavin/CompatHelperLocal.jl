using Test
import Pkg
import CompatHelperLocal as CHL

@time CHL.@check()
@time CHL.@check(checktest=true)
@time CHL.@check(checktest=false)

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

    # Test gather_compats function
    @testset "gather_compats" begin
        compats = CHL.gather_compats(projfile)
        
        # Test that all expected packages are found
        compat_names = map(c -> c.name, compats)
        expected_names = ["CSV", "DataFrames", "Dates", "Downloads", "OrderedCollections", "Scratch", "xxxPackageXXX", "YYYPackageYYY", "julia"]
        @test issetequal(compat_names, expected_names)
        
        # Test specific compat states
        scratch_compat = compats[findfirst(c -> c.name == "Scratch", compats)]
        @test scratch_compat isa CHL.CompatStates.Uptodate
        @test scratch_compat.compat.str == "0.1, 0.2, 1"
        
        xxx_compat = compats[findfirst(c -> c.name == "xxxPackageXXX", compats)]
        @test xxx_compat isa CHL.CompatStates.PackageNotFound  # fake package not in registries
        
        yyy_compat = compats[findfirst(c -> c.name == "YYYPackageYYY", compats)]
        @test yyy_compat isa CHL.CompatStates.PackageNotFound  # fake package not in registries
        
        dates_compat = compats[findfirst(c -> c.name == "Dates", compats)]
        @test dates_compat isa CHL.CompatStates.IsStdlib
        
        csv_compat = compats[findfirst(c -> c.name == "CSV", compats)]
        @test csv_compat isa CHL.CompatStates.Missing  # no compat, so missing
        
        julia_compat = compats[findfirst(c -> c.name == "julia", compats)]
        @test julia_compat isa CHL.CompatStates.Missing  # julia compat missing
        
        # Test that versions are populated for non-stdlib packages
        for c in compats
            if !(c isa CHL.CompatStates.IsStdlib) && c.name != "julia"
                if c isa CHL.CompatStates.PackageNotFound
                    # PackageNotFound doesn't have versions field
                    @test !hasfield(typeof(c), :versions)
                else
                    @test hasfield(typeof(c), :versions)
                end
            end
        end
    end
    
    # Test generate_compat_issues function
    @testset "generate_compat_issues" begin
        compats = CHL.gather_compats(projfile)
        issues = CHL.generate_compat_issues(compats)
        
        # Find specific issues for packages we know about
        issue_names = map(((msg, args),) -> args.name, issues)
        # These packages should have issues (missing compat or not found)
        expected_issue_names = ["CSV", "DataFrames", "OrderedCollections", "julia", "xxxPackageXXX", "YYYPackageYYY"]
        @test issetequal(issue_names, expected_issue_names)
        
        # Check message types
        messages = map(first, issues)
        @test any(msg -> msg == "package in [deps] but not found in registries", messages)  # xxxPackageXXX
        @test any(msg -> msg == "[compat] missing", messages)  # YYYPackageYYY and others
        
        # Test specific message and args content
        xxx_issue = filter(((msg, args),) -> args.name == "xxxPackageXXX", issues)
        @test length(xxx_issue) == 1
        @test xxx_issue[1][1] == "package in [deps] but not found in registries"
        @test xxx_issue[1][2] == (name="xxxPackageXXX",)
        
        csv_issue = filter(((msg, args),) -> args.name == "CSV", issues)  
        @test length(csv_issue) == 1
        @test csv_issue[1][1] == "[compat] missing"
        @test csv_issue[1][2] == (name="CSV",)
    end
end

@time CHL.check("./test_package_dir/")

# run(`$(Base.julia_cmd()) ../docs/make.jl`)
