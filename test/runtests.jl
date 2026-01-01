using Test
import Pkg
import CompatHelperLocal as CHL

@time CHL.@check()

# Test deprecated checktest parameter
@testset "checktest deprecation" begin
    # Should show deprecation warning but still work
    @test_logs (:warn, r"checktest parameter is deprecated") match_mode=:any CHL.@check(checktest=true, quiet=true)
    @test_logs (:warn, r"checktest parameter is deprecated") match_mode=:any CHL.@check(checktest=false, quiet=true)
    # Verify the function still works with old parameter
    @test CHL.check(pwd(), checktest=true, quiet=true) isa Bool
    @test CHL.check(pwd(), checktest=false, quiet=true) isa Bool
end

@testset begin
    @test CHL.CompatStates.generate_new_compat(v"1.2.3"; include_patch=true) == "1.2.3"
    @test CHL.CompatStates.generate_new_compat(v"0.0.3"; include_patch=true) == "0.0.3"
    @test CHL.CompatStates.generate_new_compat(v"0.1.3"; include_patch=true) == "0.1.3"
    @test CHL.CompatStates.generate_new_compat(v"1.2.3+5"; include_patch=true) == "1.2.3"
    @test CHL.CompatStates.generate_new_compat(v"1.2.3"; include_patch=false) == "1.2"
    @test CHL.CompatStates.generate_new_compat(v"0.1.3"; include_patch=false) == "0.1"
    @test CHL.CompatStates.generate_new_compat(v"1.2.3+5"; include_patch=false) == "1.2"

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
Dates = "[\d., ]+"
Downloads = "[\d., ]+"
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
        @test dates_compat isa CHL.CompatStates.Missing  # stdlib with no compat
        @test dates_compat.is_stdlib == true
        @test dates_compat.versions == [CHL.JULIA_VERSION_SUGGESTED]

        downloads_compat = compats[findfirst(c -> c.name == "Downloads", compats)]
        @test downloads_compat isa CHL.CompatStates.Missing  # stdlib with no compat
        @test downloads_compat.is_stdlib == true
        @test downloads_compat.versions == [CHL.JULIA_VERSION_SUGGESTED]
        
        csv_compat = compats[findfirst(c -> c.name == "CSV", compats)]
        @test csv_compat isa CHL.CompatStates.Missing  # no compat, so missing
        
        julia_compat = compats[findfirst(c -> c.name == "julia", compats)]
        @test julia_compat isa CHL.CompatStates.Missing  # julia compat missing
        @test julia_compat.versions == [CHL.JULIA_VERSION_SUGGESTED]

        # Test that versions are populated for all packages except PackageNotFound
        for c in compats
            if c isa CHL.CompatStates.PackageNotFound
                # PackageNotFound doesn't have versions field
                @test !hasfield(typeof(c), :versions)
            else
                @test hasfield(typeof(c), :versions)
                @test !isempty(c.versions)
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
        # Now includes Dates and Downloads since they're stdlib with missing compat
        expected_issue_names = ["CSV", "DataFrames", "Dates", "Downloads", "OrderedCollections", "julia", "xxxPackageXXX", "YYYPackageYYY"]
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

# Test with a package that has both main and test Project.toml
@testset "main + test filtering integration" begin
    test_logger = Test.TestLogger()

    # Run check with logger, suppressing stdout/stderr
    result = Test.with_logger(test_logger) do
        CHL.check("./test_package_dir/")
    end

    @test !result

    logs = test_logger.logs

    # Check that both projects are warned about
    @test any(l -> l.level == Base.CoreLogging.Warn && occursin("test_package_dir/Project.toml", string(get(l.kwargs, :project, ""))), logs)
    @test any(l -> l.level == Base.CoreLogging.Warn && occursin("test_package_dir/test/Project.toml", string(get(l.kwargs, :project, ""))), logs)

    # Find where test project warning starts
    test_warn_idx = findfirst(l -> l.level == Base.CoreLogging.Warn && occursin("test/Project.toml", string(get(l.kwargs, :project, ""))), logs)
    @test !isnothing(test_warn_idx)

    # Logs before test warning are from main project
    main_logs = logs[1:test_warn_idx-1]
    main_package_names = [get(l.kwargs, :name, nothing) for l in main_logs if l.level == Base.CoreLogging.Info]

    # Logs after test warning are from test project
    test_logs = logs[test_warn_idx+1:end]
    test_package_names = [get(l.kwargs, :name, nothing) for l in test_logs if l.level == Base.CoreLogging.Info]

    # Main project should mention CSV, DataFrames, etc
    @test "CSV" ∈ main_package_names
    @test "DataFrames" ∈ main_package_names
    @test "OrderedCollections" ∈ main_package_names

    # Test project should only mention test-exclusive packages
    @test "JSON3" ∈ test_package_names
    @test "Test" ∈ test_package_names

    # Test project should NOT mention packages from main
    @test "CSV" ∉ test_package_names
    @test "OrderedCollections" ∉ test_package_names
    @test "Scratch" ∉ test_package_names
    # Even packages in both should be filtered
    @test "DataFrames" ∉ test_package_names
    @test "Dates" ∉ test_package_names
end
