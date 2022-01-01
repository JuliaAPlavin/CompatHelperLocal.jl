module CompatHelperLocal
import Pkg
using UUIDs: uuid4

using DocStringExtensions
@template DEFAULT = """
$(TYPEDSIGNATURES)
$(DOCSTRING)
"""

@static if Base.VERSION >= v"1.7.0-"
    function get_versions_in_repository(pkg_name::String)
        if pkg_name == "julia"
            return [VERSION]
        end
        return mapreduce(vcat, Pkg.Registry.reachable_registries()) do reg
            pkgs = filter(((uuid, pkg),) -> pkg.name == pkg_name, reg.pkgs)
            if isempty(pkgs)
                return []
            else
                uuid, pkg = only(pkgs)
                info = Pkg.Registry.registry_info(pkg)
                return collect(keys(info.version_info))
            end
        end
    end
else
    function get_versions_in_repository(pkg_name::String)
        if pkg_name == "julia"
            return [VERSION]
        end
        return mapreduce(vcat, Pkg.Types.collect_registries()) do reg
            registry = Pkg.Types.read_registry(joinpath(reg.path, "Registry.toml"))
            pkgs = filter(((uuid, dict),) -> dict["name"] == pkg_name, registry["packages"])
            if isempty(pkgs)
                return []
            else
                uuid, dict = only(pkgs)
                versions = Pkg.Operations.load_versions(Pkg.Types.Context(), joinpath(reg.path, dict["path"]))
                return collect(keys(versions))
            end
        end
    end
end

@static if Base.thisminor(VERSION) <= v"1.6"
    get_compat_full(proj, name) = haskey(proj.compat, name) ? (val=Pkg.Types.semver_spec(proj.compat[name]), str=proj.compat[name]) : (val=Pkg.Types.VersionSpec(), str=nothing)
else
    get_compat_full(proj, name) = (val=Pkg.Operations.get_compat(proj, name), str=Pkg.Operations.get_compat_str(proj, name))
end

module CompatStates
abstract type State end

Base.@kwdef struct PackageNotFound <: State
    name::String
    compat
end

Base.@kwdef struct IsStdlib <: State
    name::String
end

Base.@kwdef struct Missing <: State
    name::String
    compat
    versions::Vector{VersionNumber}
end

Base.@kwdef struct Uptodate <: State
    name::String
    compat
    versions::Vector{VersionNumber}
end

Base.@kwdef struct Outdated <: State
    name::String
    compat
    versions::Vector{VersionNumber}
end

is_ok(::Union{IsStdlib, Uptodate}) = true
is_ok(::Union{Missing, Outdated, PackageNotFound}) = false

generate_new_compat(v::VersionNumber)::String = (v.major, v.minor) == (0, 0) ? "0.0.$(v.patch)" : "$(v.major).$(v.minor)"

generate_compat_str(c::Missing) = generate_new_compat(maximum(c.versions))
generate_compat_str(c::Outdated) = "$(c.compat.str), $(generate_new_compat(maximum(c.versions)))"
generate_compat_str(c::Uptodate) = c.compat.str
generate_compat_str(c::PackageNotFound) = c.compat.str
generate_compat_str(c::IsStdlib) = nothing

info_message_args(c::CompatStates.PackageNotFound) = ("package in [deps] but not found in registries", (;c.name))
info_message_args(c::CompatStates.Missing) = ("[compat] missing", (;c.name))
info_message_args(c::CompatStates.Outdated) = ("[compat] outdated", (;c.name, c.compat, latest=maximum(c.versions)))
end
import .CompatStates: is_ok, generate_compat_str, info_message_args


function gather_compats(project_file)
    project = Pkg.Types.read_project(project_file)
    return map([collect(project.deps); [("julia", nothing)]]) do (name, uuid)
        uuid !== nothing && Pkg.Types.is_stdlib(uuid) && return CompatStates.IsStdlib(; name)
        compat = get_compat_full(project, name)
        versions = get_versions_in_repository(name)
        isempty(versions) && return CompatStates.PackageNotFound(; name, compat)
        return if compat.str === nothing
            CompatStates.Missing(; name, compat, versions)
        elseif maximum(versions) ∈ compat.val
            CompatStates.Uptodate(; name, compat, versions)
        else
            CompatStates.Outdated(; name, compat, versions)
        end
    end
end

"""Check [compat] entries for package in `pkg_dir`.
Reports issues and returns whether checks pass."""
function check(pkg_dir::String)
    all_ok = true
    for dir in [pkg_dir, joinpath(pkg_dir, "test")]
        f = Pkg.Types.projectfile_path(dir, strict=true)
        !isnothing(f) || continue
        dep_compats = gather_compats(f)
        all(is_ok(c) for c in dep_compats) && continue
        all_ok = false
        @warn "Project has issues with [compat]" project=f

        for c in sort(filter(!is_ok, dep_compats), by=c -> (string(typeof(c)), c.name))
            msg, args = info_message_args(c)
            @info msg args...
        end
        println()
        println("Suggested content:")
        println("[compat]")
        for c in sort(dep_compats, by=c -> c.name == "julia" ? "я" : c.name)  # put julia latest in the list
            compat_str = generate_compat_str(c)
            compat_str === nothing || println("$(c.name) = \"$(compat_str)\"")
        end
        println()
    end
    return all_ok
end

"""Check [compat] entries for package that contains module `m`.
Reports issues and returns whether checks pass."""
check(m::Module) = check(pkgdir(m))

"""Check [compat] entries for current package.
Reports issues and returns whether checks pass.
Can be called from the package itself, or from its tests."""
macro check()
    file = String(__source__.file)
    dir = dirname(file)
    if basename(dir) == "test"
        dir = dirname(dir)
    end
    :(check($dir))
end



function get_compats_combinations(project_file)
    original_compats_dict = Pkg.Types.read_project(project_file).compat
    compats = gather_compats(project_file)
    filter!(c -> haskey(c, :versions_compatible) && c.name != "julia", compats)
    return map(Iterators.product(compats, 1:2)) do (c, i)
        new_dict = copy(original_compats_dict)
        ver = extrema(c.versions_compatible)[i]
        ver = Base.thispatch(ver)
        new_dict[c.name] = "=$(ver)"
        return new_dict
    end |> unique
end

function write_project_with_compat(orig_proj_file, new_proj_file, compat::Dict)
    @assert isfile(orig_proj_file)
    proj = Pkg.Types.read_project(orig_proj_file)
    proj.compat = compat
    Pkg.Types.write_project(proj, new_proj_file)
end

function copy_project_change_compat(orig_proj_dir, new_proj_dir, compat::Dict)
    @assert isdir(orig_proj_dir)
    @info "Copying project files $orig_proj_dir => $new_proj_dir"
    cp(orig_proj_dir, new_proj_dir, force=true)
    chmod(new_proj_dir, 0o777, recursive=true)
    rm(joinpath(new_proj_dir, "Manifest.toml"), force=true)  # not really needed?..
    @info "Modifying compat in $new_proj_dir"
    write_project_with_compat(
        joinpath(new_proj_dir, "Project.toml"),
        joinpath(new_proj_dir, "Project.toml"),
        compat,
    )
end

function test_compats_combinations(proj_dir; tmpdir=tempdir())
    prev_env = basename(Base.active_project())
    try
        compats = get_compats_combinations(joinpath(proj_dir, "Project.toml"))
        @info "Going to test with modified [compat]s" length(compats)
        for compat in compats
            @info "Testing with modified [compat]" compat
            new_dir = mktempdir(tmpdir)
            copy_project_change_compat(proj_dir, new_dir, compat)
            Pkg.activate(new_dir)
            Pkg.test()
        end
    finally
        @info "Restoring previous environment" prev_env
        Pkg.activate(prev_env)
    end
end

end
