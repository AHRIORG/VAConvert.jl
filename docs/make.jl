using VAConvert
using Documenter

DocMeta.setdocmeta!(VAConvert, :DocTestSetup, :(using VAConvert); recursive=true)

makedocs(;
    modules=[VAConvert],
    authors="Kobus Herbst, Ariane Sessego",
    sitename="VAConvert.jl",
    format=Documenter.HTML(;
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)
