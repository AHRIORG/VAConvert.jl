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

deaths = Arrow.Table(joinpath(ENV["DATA_PATH"], "arrowfiles/VAIndividualDeaths.arrow")) |> DataFrame