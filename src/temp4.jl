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
numericvalues = CSV.read("mapping/NumericVariables_with_missing.csv", DataFrame)