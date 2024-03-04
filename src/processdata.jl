using ConfigEnv
using Logging
using Dates
using VAConvert
using DBInterface
using DataFrames
using PrettyTables
using Arrow
using CSV
#get environment variables
dotenv()

#region Setup Logging
l = open("logs/process_log.log", "w")
io = IOContext(l, :displaysize => (100, 100))
logger = SimpleLogger(io)
old_logger = global_logger(logger)
@info "===== Execution started $(Dates.format(now(), "yyyy-mm-dd HH:MM"))"
flush(io)
start_time = now()
#endregion

try
  #read va data
  inputdir = joinpath(ENV["DATA_PATH"], "arrowfiles")
  vadata = Arrow.Table(joinpath(inputdir, "VAVariableValues.arrow")) |> DataFrame
  vadeaths = Arrow.Table(joinpath(inputdir, "VAIndividualDeaths.arrow")) |> DataFrame
  vavariables = Arrow.Table(joinpath(inputdir, "VAVariables.arrow")) |> DataFrame
  vadomains = Arrow.Table(joinpath(inputdir, "VAVariableDomains.arrow")) |> DataFrame
  vadomains = sort(vadomains, [:VarDomain, :Sequence])
  @info "VA Variable Values $(nrow(vadata)) rows\n"
  @info "VA Deaths $(nrow(vadeaths)) rows\n"
  @info "VA Variables $(nrow(vavariables)) rows\n"
  pretty_table(io, vavariables; alignment=[:l, :l, :l, :l, :r], show_subheader=false)
  #summarise rows for each source
  sources = combine(groupby(vadata, :Source), nrow => :n)
  pretty_table(io, sources; alignment=[:c, :r], show_subheader=false)
  #summarise variables for each source
  va_variables = combine(groupby(vadata, [:Source, :Variable]), nrow => :n)
  pretty_table(io, va_variables; alignment=[:c, :l, :r], show_subheader=false)
  va_variables = leftjoin(va_variables, vavariables, on=:Variable, makeunique=true)
  # output csv files for each source variables
  outputdir = joinpath(ENV["DATA_PATH"], "csvfiles")
  if !isdir(outputdir)
      mkpath(outputdir)
  end
for source in unique(va_variables.Source)
    source_variables = filter(row -> row.Source == source, va_variables)
    CSV.write(joinpath(outputdir, "VAVariables_$source.csv"), source_variables)
  end
  #output variable domains
  CSV.write(joinpath(outputdir, "VAVariableDomains.csv"), vadomains)
finally
  elapsed = now() - start_time
  @info "===== Completed $(Dates.format(now(), "yyyy-mm-dd HH:MM")) duration $(canonicalize(Dates.CompoundPeriod(elapsed)))"
  flush(io)
  global_logger(old_logger)
  close(io)
end