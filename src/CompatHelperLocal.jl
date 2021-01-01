module CompatHelperLocal
import Pkg
using UUIDs: uuid4

using DocStringExtensions
@template DEFAULT = """
$(TYPEDSIGNATURES)
$(DOCSTRING)
"""

function generate_new_compat(v::VersionNumber)::String
    if v.major == 0 && v.minor == 0
        return "0.0.$(v.patch)"
    else
        return "$(v.major).$(v.minor)"
    end
end

function merge_old_new_compat(old::String, latest::VersionNumber)::String
    "$(old), $(generate_new_compat(latest))"
end

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

function gather_compats(project_file)
    project = Pkg.Types.read_project(project_file)
    return map([collect(project.deps); [("julia", uuid4())]]) do (name, uuid)
        Pkg.Types.is_stdlib(uuid) && return (; name, compat_state = :stdlib, ok=true)
        compat = get(project.compat, name, "")
        versions = get_versions_in_repository(name)
        isempty(versions) && return (; name, compat_state = :not_found, ok=false, compat)
        latest = maximum(versions)
        if isempty(compat)
            return (; name, compat_state = :missing, ok=false, latest, versions, versions_compatible=versions)
        else
            compat_spec = Pkg.Types.semver_spec(compat)
            versions_compatible = filter(∈(compat_spec), versions)
            latest ∈ compat_spec && return (; name, compat_state = :uptodate, ok=true, latest, versions, versions_compatible, compat, compat_spec)
            return (; name, compat_state = :outdated, ok=false, latest, versions, versions_compatible, compat, compat_spec)
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
        all(c.ok for c in dep_compats) && continue
        all_ok = false
        @warn "Project has issues with [compat]" project=f
        for c in sort(dep_compats, by=c -> (c.compat_state, c.name))
            if c.compat_state == :not_found
                @info "package in [deps] but not found in registries" name=c.name
            elseif c.compat_state == :missing
                @info "[compat] missing" name=c.name
            elseif c.compat_state == :outdated
                @info "[compat] outdated" name=c.name compat=c.compat compat_spec=c.compat_spec latest=c.latest
            else
                @assert c.ok
            end
        end
        println()
        println("Suggested content:")
        println("[compat]")
        for c in sort(dep_compats, by=c -> c.name == "julia" ? "я" : c.name)  # put julia latest in the list
            if c.compat_state == :missing
                println("$(c.name) = \"$(generate_new_compat(c.latest))\"")
            elseif c.compat_state == :outdated
                println("$(c.name) = \"$(merge_old_new_compat(c.compat, c.latest))\"")
            elseif c.compat_state == :uptodate
                println("$(c.name) = \"$(c.compat)\"")
            elseif c.compat_state == :not_found
                isempty(c.compat) || println("$(c.name) = \"$(c.compat)\"")
            else
                @assert c.compat_state == :stdlib
            end
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


struct ExtremaAll end

function get_compats_combinations(project_file, mode::ExtremaAll)
    original_compats_dict = Pkg.Types.read_project(project_file).compat
    compats = gather_compats(project_file)
    filter!(c -> haskey(c, :versions_compatible), compats)
    return map(1:2) do i
        new_dict = map(compats) do c
            c.name => string(extrema(c.versions_compatible)[i])
        end |> Dict
        @assert isempty( setdiff(keys(original_compats_dict), keys(new_dict)) )
        new_dict["julia"] = original_compats_dict["julia"]  # DEV versions cannot be parsed as spec
        return new_dict
    end
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
    @info "Modifying compat in $new_proj_dir"
    write_project_with_compat(
        joinpath(new_proj_dir, "Project.toml"),
        joinpath(new_proj_dir, "Project.toml"),
        compat,
    )
end

function test_compats_combinations(proj_dir, mode)
    prev_env = basename(Base.active_project())
    try
        compats = get_compats_combinations(joinpath(proj_dir, "Project.toml"), mode::ExtremaAll)
        for compat in compats
            @info "Going to test with modified [compat]" compat
            new_dir = mktempdir()
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
