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
  vadata = Arrow.Table(joinpath(inputdir, "VAVariableValues.arrow")) |> DataFrame
  df = combine(groupby(vadata, :Source), nrow => :n)