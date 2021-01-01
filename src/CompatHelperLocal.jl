module CompatHelperLocal
import Pkg


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


function latest_registered_versions()
    agg = map(Pkg.Types.collect_registries()) do reg
        registry = Pkg.Types.read_registry(joinpath(reg.path, "Registry.toml"))
        map(registry["packages"] |> collect) do (uuid, pkg_dict)
            versions = Pkg.Operations.load_versions(Pkg.Types.Context(), joinpath(reg.path, pkg_dict["path"]))
            pkg_dict["name"] => maximum(versions)[1]
        end |> Dict
    end
    return mergewith(max, agg...)
end


function check(pkg_dir::String)
    latest_vers = latest_registered_versions()
    all_ok = true
    for dir in [pkg_dir, joinpath(pkg_dir, "test")]
        f = Pkg.Types.projectfile_path(dir, strict=true)
        isfile(f) || continue
        project = Pkg.Types.read_project(f)
        dep_compats = map(project.deps |> collect) do (name, uuid)
            Pkg.Types.is_stdlib(uuid) && return (; name, compat_state = :stdlib, ok=true)
            compat = get(project.compat, name, "")
            haskey(latest_vers, name) || return (; name, compat_spec = :not_found, ok=false)
            latest = latest_vers[name]
            if isempty(compat)
                return (; name, compat_state = :missing, ok=false, latest)
            else
                compat_spec = Pkg.Types.semver_spec(compat)
                latest ∈ compat_spec && return (; name, compat_state = :uptodate, ok=true, compat, compat_spec)
                return (; name, compat_state = :compat_outdated, ok=false, latest, compat, compat_spec)
            end
        end
        all(c.ok for c in dep_compats) && continue
        all_ok = false
        println("Project $f has issues with [compat]:")
        for c in sort(dep_compats, by=c -> (c.compat_state, c.name))
            if c.compat_state == :not_found
                println("unknown    $(c.name)")
            elseif c.compat_state == :missing
                println("missing    $(c.name)")
            elseif c.compat_state == :compat_outdated
                println("outdated   $(c.name)    compat=$(c.compat_spec)    latest=$(c.latest)")
            else
                @assert c.ok
            end
        end
        println("Suggested content:")
        println("[compat]")
        for c in sort(dep_compats, by=c -> c.name)
            if c.compat_state == :missing
                println("""$(c.name) = "$(generate_new_compat(c.latest))" """)
            elseif c.compat_state == :compat_outdated
                println("""$(c.name) = "$(merge_old_new_compat(c.compat, c.latest))" """)
            elseif c.compat_state == :compat_uptodate
                println("""$(c.name) = "$(c.compat)" """)
            else
                @assert c.compat_state ∈ (:not_found, :stdlib)
            end
        end
    end
    return all_ok
end

check(m::Module) = check(pkgdir(m))

macro check()
    file = String(__source__.file)
    dir = dirname(file)
    if basename(dir) == "test"
        dir = dirname(dir)
    end
    :(check($dir))
end

end