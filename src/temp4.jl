using ConfigEnv
using Logging
using Dates
using DBInterface
using DataFrames
using PrettyTables
using Arrow
using CSV

function encodenumeric(df::AbstractDataFrame, numericvalues::AbstractDataFrame)::AbstractDataFrame
    numeric_dict = Dict(row[:VariableName] => row[:Condition] for row in eachrow(numericvalues))
    values = copy(df)
    for row in eachrow(values)
        if haskey(numeric_dict, row.Variable)
            value = tryparse(Int64, row.Value)
            if !isnothing(value) && value >= numeric_dict[row.Variable]
                row.Value = missing
            end
        end
    end
    return values
end

#get environment variables
dotenv()

# deaths = Arrow.Table(joinpath(ENV["DATA_PATH"], "arrowfiles/VAIndividualDeaths.arrow")) |> DataFrame
# sexvalues = combine(groupby(deaths,:Sex), nrow => :n)
# pretty_table(sexvalues; alignment=[:c, :r], show_subheader=false)
vadata = Arrow.Table(joinpath(ENV["DATA_PATH"], "arrowfiles/VAVariableValues.arrow")) |> DataFrame
numericvalues = CSV.read("mapping/NumericVariables_with_missing.csv", DataFrame)
# sort!(numericvalues, [:VariableName])
# numeric_dict = Dict(row[:VariableName] => row[:Condition] for row in eachrow(numericvalues))
recoded = encodenumeric(vadata, numericvalues)
subset!(recoded, :Variable => ByRow(x -> x == "ih_duration_1"))