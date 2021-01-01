cd(@__DIR__)
import Pkg
Pkg.activate(".")
Pkg.develop(path="../")
Pkg.instantiate()
push!(LOAD_PATH, "../src/")
using Documenter, DocumenterMarkdown, CompatHelperLocal

makedocs(format=Markdown(), modules=[CompatHelperLocal], workdir="..")
mv("./build/README.md", "../README.md", force=true)
