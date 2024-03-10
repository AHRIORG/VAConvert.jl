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

function convert_durations!(data::AbstractDataFrame)::AbstractDataFrame
    duration_lookup = Dict{String,Union{Number,Missing}}("NAD" => missing, "DFT" => missing, "MIS" => missing, "R" => missing,
        "DAY" => 1, "WEE" => 7, "MON" => 30, "YEA" => 365, "U" => missing,
        "H" => 1 / 24, "M" => 30, "D" => 1, "Y" => 365, "W" => 7, "HRS" => 1/24, "YRS" => 365)
    duration_data = CSV.read(joinpath(ENV["MAPPING_PATH"], "VA_Duration_Unit_equivalence.csv"), DataFrame)
    duration_map = Dict{String,String}(zip(duration_data[!, :Variable_numeric], duration_data[!, :Variable_unit]))
    for row in eachrow(data)
        for (k, v) in duration_map
            if hasproperty(row, k) && !ismissing(row[k]) && !ismissing(row[v])
                if haskey(duration_lookup, row[v])
                    #println("$k $v")
                    nvalue = parse(Int,row[k]) * duration_lookup[row[v]]
                    #println(nvalue)
                else
                    @warn "Unknown duration unit: '$(row[v])' $k $v"
                end
            end
        end
    end
    return data
end


inputdir = joinpath(ENV["DATA_PATH"], "arrowfiles")
vadata = Arrow.Table(joinpath(inputdir, "VAVariableValues.arrow")) |> DataFrame
for source in unique(vadata.Source)
    source_data = filter(row -> row.Source == source, vadata)
    flat_data = unstack(source_data, :IIntID, :Variable, :Value)
    convert_durations!(flat_data)
  end
 