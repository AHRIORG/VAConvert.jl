using ConfigEnv
using Logging
using Dates
using DBInterface
using DataFrames
using PrettyTables
using Arrow
using CSV

#get environment variables
dotenv()

# deaths = Arrow.Table(joinpath(ENV["DATA_PATH"], "arrowfiles/VAIndividualDeaths.arrow")) |> DataFrame
# sexvalues = combine(groupby(deaths,:Sex), nrow => :n)
# pretty_table(sexvalues; alignment=[:c, :r], show_subheader=false)
vadata = Arrow.Table(joinpath(ENV["DATA_PATH"], "arrowfiles/VAVariableValues.arrow")) |> DataFrame
domainvalues = CSV.read("mapping/VAVariableDomains_with_missing.csv", DataFrame)
transform!(domainvalues, :Code => ByRow(x -> strip(x)) => :Code)
v = subset(vadata, :VarDomain => ByRow(x -> x == "VAWBreathSound"); skipmissing=true)
# CSV.write("mapping/temp.csv", v)
# Assume your DataFrame is called df and has columns: :VarDomain, :Code, :SetMissing

domain_dict = Dict(
    d[1, :VarDomain] => Dict(row[:Code] => row[:SetMissing] for row in eachrow(d))
    for d in groupby(domainvalues, :VarDomain)
)