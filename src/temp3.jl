using ConfigEnv
using Logging
using Dates
using DBInterface
using DataFrames
using PrettyTables
using Arrow
using CSV
using VAConvert

#get environment variables
dotenv()

inputdir = joinpath(ENV["DATA_PATH"], "arrowfiles")
# vadeaths = Arrow.Table(joinpath(inputdir, "VAIndividualDeaths.arrow")) |> DataFrame
# df = VAConvert.add_marriage(vadeaths)
narratives = Arrow.Table(joinpath(inputdir, "VANValues.arrow")) |> DataFrame