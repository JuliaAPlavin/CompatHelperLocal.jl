
<a id='Overview'></a>

<a id='Overview-1'></a>

# Overview


Helps keep `[compat]` entries in your `Project.toml` up to date. Notifies when a `[compat]` is absent or incompatible with the latest available version of the corresponding dependency.


<a id='Basic-usage'></a>

<a id='Basic-usage-1'></a>

# Basic usage


Put the following lines to `<your package>/test/runtests.jl`:


```julia
import CompatHelperLocal as CHL
@test CHL.@check()
```


<a id='Example'></a>

<a id='Example-1'></a>

# Example


`Project.toml` content:


```
name = "TestPackage"
uuid = "fde2a2d7-f0f0-4afe-ab6c-a8c3d7349667"
authors = ["Alexander Plavin <alexander@plav.in>"]
version = "0.1.0"

[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
Downloads = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
OrderedCollections = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
Scratch = "6c6a2e73-6563-6170-7368-637461726353"
XXXPackageXXX = "6c6a2e73-6563-6170-7368-637461726355"
YYYPackageYYY = "6c6a2e73-6563-6170-7368-637461726354"

[compat]
Scratch = "0.1, 0.2"
XXXPackageXXX = "1.0"
```


`CompatHelperLocal` output:


```julia
import CompatHelperLocal as CHL
CHL.@check()
```


```
┌ Warning: Project has issues with [compat]
│   project = "./test/test_package_dir/Project.toml"
└ @ CompatHelperLocal ~/.julia/dev/CompatHelperLocal/src/CompatHelperLocal.jl:60
┌ Info: [compat] missing
└   name = "CSV"
┌ Info: [compat] missing
└   name = "DataFrames"
┌ Info: [compat] missing
└   name = "OrderedCollections"
┌ Info: package not in registries
└   name = "XXXPackageXXX"
┌ Info: package not in registries
└   name = "YYYPackageYYY"
┌ Info: [compat] outdated
│   name = "Scratch"
│   compat = "0.1, 0.2"
│   compat_spec = VersionSpec("0.1-0.2")
└   latest = v"1.0.3"

Suggested content:
[compat]
CSV = "0.8"
DataFrames = "0.22"
OrderedCollections = "1.3"
Scratch = "0.1, 0.2, 1.0"
XXXPackageXXX = "1.0"  # package not found in registries
```


<a id='Reference'></a>

<a id='Reference-1'></a>

# Reference

<a id='CompatHelperLocal.check-Tuple{Module}' href='#CompatHelperLocal.check-Tuple{Module}'>#</a>
**`CompatHelperLocal.check`** &mdash; *Method*.



```julia
check(m::Module) -> Bool

```

Check [compat] entries for package that contains module `m`.


<a target='_blank' href='https://github.com/aplavin/CompatHelperLocal.jl/blob/98b8fc0444e4a36b2baf821cdd20e5f4017fed8d/src/CompatHelperLocal.jl#L93' class='documenter-source'>source</a><br>

<a id='CompatHelperLocal.check-Tuple{String}' href='#CompatHelperLocal.check-Tuple{String}'>#</a>
**`CompatHelperLocal.check`** &mdash; *Method*.



```julia
check(pkg_dir::String) -> Bool

```

Check [compat] entries for package in `pkg_dir`. Reports issues and returns whether checks pass.


<a target='_blank' href='https://github.com/aplavin/CompatHelperLocal.jl/blob/98b8fc0444e4a36b2baf821cdd20e5f4017fed8d/src/CompatHelperLocal.jl#L37' class='documenter-source'>source</a><br>

<a id='CompatHelperLocal.@check-Tuple{}' href='#CompatHelperLocal.@check-Tuple{}'>#</a>
**`CompatHelperLocal.@check`** &mdash; *Macro*.



Check [compat] entries for current package. Can be called from the package itself, or from its tests.


<a target='_blank' href='https://github.com/aplavin/CompatHelperLocal.jl/blob/98b8fc0444e4a36b2baf821cdd20e5f4017fed8d/src/CompatHelperLocal.jl#L96' class='documenter-source'>source</a><br>
