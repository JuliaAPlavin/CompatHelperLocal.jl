# Overview

Helps keep `[compat]` entries in your `Project.toml` up to date. Notifies when a `[compat]` is absent or incompatible with the latest available version of the corresponding dependency.

# Basic usage

Put the following lines to `<your package>/test/runtests.jl`:
```julia
import CompatHelperLocal as CHL
CHL.@check()
```

# Example

`Project.toml` content:
```@example
println(read("./test/test_package_dir/Project.toml", String)) # hide
```
`CompatHelperLocal` output:
```@example
import CompatHelperLocal as CHL
CHL.@check()
CHL.check("./test/test_package_dir/")  # hide
nothing  # hide
```

# Reference

```@autodocs
Modules = [CompatHelperLocal]
```
