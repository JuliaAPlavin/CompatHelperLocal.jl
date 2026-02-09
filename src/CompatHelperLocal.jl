module CompatHelperLocal
import Pkg

# update to latest Julia LTS whenever one comes out:
const JULIA_VERSION_SUGGESTED = v"1.10"

function get_versions_in_repository(pkg_name::String, is_stdlib::Bool)
    # for Julia and stdlibs, always recommend the fixed Julia version
    if pkg_name == "julia" || is_stdlib
        return [JULIA_VERSION_SUGGESTED]
    end
    return mapreduce(vcat, Pkg.Registry.reachable_registries()) do reg
        pkgs = filter(((uuid, pkg),) -> pkg.name == pkg_name, reg.pkgs)
        if isempty(pkgs)
            return []
        else
            uuid, pkg = only(pkgs)
            info = if applicable(Pkg.Registry.registry_info, reg, pkg)
                Pkg.Registry.registry_info(reg, pkg)
            else
                Pkg.Registry.registry_info(pkg)
            end
            return collect(keys(info.version_info))
        end
    end
end

get_compat_full(proj, name) = (val=Pkg.Operations.get_compat(proj, name), str=Pkg.Operations.get_compat_str(proj, name))

module CompatStates
abstract type State end

Base.@kwdef struct PackageNotFound <: State
    name::String
    compat
    is_stdlib::Bool = false
end

Base.@kwdef struct Missing <: State
    name::String
    compat
    versions::Vector{VersionNumber}
    is_stdlib::Bool = false
end

Base.@kwdef struct Uptodate <: State
    name::String
    compat
    versions::Vector{VersionNumber}
    is_stdlib::Bool = false
end

Base.@kwdef struct Outdated <: State
    name::String
    compat
    versions::Vector{VersionNumber}
    is_stdlib::Bool = false
end

is_ok(::Uptodate) = true
is_ok(::Union{Missing, Outdated, PackageNotFound}) = false

all_versions(c::Union{Missing, Uptodate, Outdated}) = c.versions
compatible_versions(c::Union{Missing, Uptodate, Outdated}) = filter(∈(c.compat.val), c.versions)

generate_new_compat(v::VersionNumber; include_patch::Bool)::String = include_patch ? string(Base.thispatch(v)) : "$(v.major).$(v.minor)" 

generate_compat_str(c::Missing) = generate_new_compat(maximum(c.versions); include_patch=c.name != "julia" && !c.is_stdlib)
generate_compat_str(c::Outdated) = "$(c.compat.str), $(generate_new_compat(maximum(c.versions); include_patch=c.name != "julia" && !c.is_stdlib))"
generate_compat_str(c::Uptodate) = c.compat.str
generate_compat_str(c::PackageNotFound) = c.compat.str

info_message_args(c::CompatStates.PackageNotFound) = ("package in [deps] but not found in registries", (;c.name))
info_message_args(c::CompatStates.Missing) = ("[compat] missing", (;c.name))
info_message_args(c::CompatStates.Outdated) = ("[compat] outdated", (;c.name, c.compat, latest=maximum(c.versions)))
end
import .CompatStates: is_ok, generate_compat_str, info_message_args


function gather_compats(project_file)
    project = Pkg.Types.read_project(project_file)
    return map([collect(project.deps); collect(project.weakdeps); [("julia", nothing)]]) do (name, uuid)
        is_stdlib = uuid !== nothing && Pkg.Types.is_stdlib(uuid)
        compat = get_compat_full(project, name)
        versions = get_versions_in_repository(name, is_stdlib)
        isempty(versions) && return CompatStates.PackageNotFound(; name, compat, is_stdlib)
        return if compat.str === nothing
            CompatStates.Missing(; name, compat, versions, is_stdlib)
        elseif maximum(versions) ∈ compat.val
            CompatStates.Uptodate(; name, compat, versions, is_stdlib)
        else
            CompatStates.Outdated(; name, compat, versions, is_stdlib)
        end
    end
end

function generate_compat_issues(dep_compats::Vector{<:CompatStates.State})
    dcs = sort(filter(!is_ok, dep_compats), by=c -> (string(typeof(c)), c.name))
    map(info_message_args, dcs)
end

function generate_compat_block(dep_compats::Vector{<:CompatStates.State})
    lines = ["[compat]"]
    for c in sort(dep_compats, by=c -> c.name == "julia" ? "я" : c.name)  # put julia latest in the list
        compat_str = generate_compat_str(c)
        compat_str === nothing || push!(lines, "$(c.name) = \"$(compat_str)\"")
    end
    return join(lines, "\n") * "\n"
end

function report_compat_issues(dep_compats::Vector{<:CompatStates.State})
    for (msg, args) in generate_compat_issues(dep_compats)
        @info msg args...
    end
    println()
    println("Suggested content:")
    println(generate_compat_block(dep_compats))
    println()
end

function generate_compat_dict(dep_compats::Vector{<:CompatStates.State})
    dct = Dict()
    for c in sort(dep_compats, by=c -> c.name == "julia" ? "я" : c.name)  # put julia latest in the list
        compat_str = generate_compat_str(c)
        compat_str === nothing && continue
        dct[c.name] = compat_str
    end
    return dct
end
generate_compat_dict(projectfile::String) = generate_compat_dict(gather_compats(projectfile))

"""
    check(pkg_dir::String; quiet=false, checktest=nothing)

Check [compat] entries for package in `pkg_dir`.
Checks both main Project.toml and test/Project.toml (if present).
For test dependencies, only recommends compats for packages not in main Project.toml.
Reports issues and returns whether checks pass.

Note: The `checktest` parameter is deprecated and ignored.
"""
function check(pkg_dir::String; quiet=false, checktest=nothing)
    if checktest !== nothing
        @warn "checktest parameter is deprecated and ignored. @check now always checks both main and test Project.toml files." maxlog=1
    end

    all_ok = true

    # First, process main project
    main_project_file = Pkg.Types.projectfile_path(pkg_dir, strict=true)
    if isnothing(main_project_file)
        @warn "No Project.toml found in $pkg_dir"
        return false
    end

    dep_compats = gather_compats(main_project_file)

    if !all(is_ok, dep_compats)
        all_ok = false
        if !quiet
            @warn "Issues with project's [compat]" project=main_project_file
            report_compat_issues(dep_compats)
        end
    end

    # Then, process test project (if it exists)
    test_dir = joinpath(pkg_dir, "test")
    test_project_file = Pkg.Types.projectfile_path(test_dir, strict=true)

    if !isnothing(test_project_file)
        all_test_compats = gather_compats(test_project_file)
        # Filter to only test-exclusive dependencies
        main_package_names = Set(c.name for c in dep_compats)
        dep_compats = filter(c -> !(c.name in main_package_names), all_test_compats)

        if !all(is_ok, dep_compats)
            all_ok = false
            if !quiet
                @warn "Issues with test project's [compat]" project=test_project_file
                report_compat_issues(dep_compats)
            end
        end
    end

    return all_ok
end

"""
    check(m::Module; kwargs...)

Check [compat] entries for package that contains module `m`.
Checks both main Project.toml and test/Project.toml (if present).
For test dependencies, only recommends compats for packages not in main Project.toml.
Reports issues and returns whether checks pass.
"""
check(m::Module; kwargs...) = check(pkgdir(m); kwargs...)

"""
    @check(args...)

Check [compat] entries for current package.
Checks both main Project.toml and test/Project.toml (if present).
For test dependencies, only recommends compats for packages not in main Project.toml.
Reports issues and returns whether checks pass.
Can be called from the package itself, or from its tests.
"""
macro check(args...)
    file = String(__source__.file)
    dir = dirname(file)
    if basename(dir) == "test"
        dir = dirname(dir)
    end
    :(check($dir; $(esc.(args)...)))
end



function get_compats_combinations(project_file; only_resolveable=false)
    compats = gather_compats(project_file)
    compats = filter(c -> c.name != "julia" && !c.is_stdlib, compats)
    @assert all(c -> !isempty(c.versions), compats)
    map(Iterators.product(compats, [identity, reverse])) do (c, f)
        cvers = CompatStates.compatible_versions(c)
        for ver in cvers |> sort |> f
            comp = Dict(c.name => "=$(Base.thispatch(ver))")
            if !only_resolveable || can_resolve(dirname(project_file), comp)
                return comp
            end
        end
    end
end

function get_all_compats_combinations(project_file, depnames::Union{Vector{String},Nothing}=nothing)
    compats = gather_compats(project_file)
    compats = filter(c -> c.name != "julia" && !c.is_stdlib, compats)
    @assert all(c -> !isempty(c.versions), compats)
    if !isnothing(depnames)
        compats = filter(c -> c.name ∈ depnames, compats)
    end
    mapreduce(vcat, compats) do c
        cvers = CompatStates.compatible_versions(c) |> sort
        map(cvers) do ver
            ver = ver |> Base.thispatch
            Dict(c.name => "=$(ver)")
        end
    end
end

function compats_combinations_to_gha_string(compats)
    "::set-output name=matrix::{\"compats\": [ $(join(["\"$(replace(repr(c), "\"" => "\\\""))\"" for c in compats], ", ")) ]}"
end

function copy_project_change_compat(orig_proj_dir, new_proj_dir, compat::Dict)
    @info "Copying project files $orig_proj_dir => $new_proj_dir"
    cp(orig_proj_dir, new_proj_dir, force=true)
    chmod(new_proj_dir, 0o777, recursive=true)  # github actions fail with permission error otherwise
    for p in ["Manifest.toml", "test/Manifest.toml"]
        rm(joinpath(new_proj_dir, p), force=true)
    end
    project_file = joinpath(new_proj_dir, "Project.toml")
    @info "Modifying compat in $project_file"
    proj = Pkg.Types.read_project(project_file)
    for (name, spec) in compat
        Pkg.Operations.set_compat(proj, name, spec)
    end
    Pkg.Types.write_project(proj, project_file)
end

function can_resolve(proj_dir, compat; new_dir=mktempdir())
    prev_env = basename(Base.active_project())
    copy_project_change_compat(proj_dir, new_dir, compat)
    Pkg.activate(new_dir)
    try
        Pkg.resolve()
        return true
    catch exc
        return false
    finally
        Pkg.activate(prev_env)
    end
end

test_compats_combinations(m::Module, args...; kwargs...) = test_compats_combinations(pathof(m) |> dirname |> dirname, args...; kwargs...)
function test_compats_combinations(
        proj_dir::AbstractString,
        new_compats=get_compats_combinations(joinpath(proj_dir, "Project.toml"); only_resolveable=true);
        throw=true
    )
    prev_env = basename(Base.active_project())
    try
        @info "Going to test with modified [compat]s" length(new_compats)
        map(new_compats) do compat
            new_dir = mktempdir()
            @info "Testing with modified [compat]" compat dir=new_dir
            copy_project_change_compat(proj_dir, new_dir, compat)
            Pkg.activate(new_dir)
            try
                Pkg.resolve()
            catch exc
                throw && rethrow()
                return (;compat, msg="couldn't resolve", exc)
            end
            try
                Pkg.test()
            catch exc
                throw && rethrow()
                return (;compat, msg="tests failed", exc)
            end
            return (compat, msg="ok", exc=nothing)
        end
    finally
        @info "Restoring previous environment" prev_env
        Pkg.activate(prev_env)
    end
end

end
