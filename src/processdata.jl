using ConfigEnv
using Logging
using Dates
using Revise
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
  #output va data as flat csv files
  domainvalues = CSV.read("mapping/VAVariableDomains_with_missing.csv", DataFrame)
  vadata = encodemissing(vadata, domainvalues)
  numericvalues = CSV.read("mapping/NumericVariables_with_missing.csv", DataFrame)
  vadata = encodenumeric(vadata, numericvalues)
  for source in unique(vadata.Source)
    @info "Processing source $source"
    source_data = filter(row -> row.Source == source, vadata)
    source_data = stripcrlf(source_data) # remove carriage return and line feed in text fields
    flat_data = unstack(source_data, :IIntID, :Variable, :Value)
    CSV.write(joinpath(outputdir, "VAData_raw_$source.csv"), flat_data)
      if source == "VAW" #add other sources that need consolidation
        consolidate_duration_variables!(flat_data)
      end
    f = convert_durations!(flat_data)
    f = add_individual_dates(f, vadeaths)
    f = add_marriage(f)
    Arrow.write(joinpath(ENV["DATA_PATH"], "arrowfiles", "VAData_$source.arrow"), f)
    CSV.write(joinpath(outputdir, "VAData_$source.csv"), f)
  end

catch e
    # log or handle error
    @error "Error caught" exception=e stacktrace=catch_backtrace()
    rethrow()  # so the error also appears in terminal as usual

finally
  elapsed = now() - start_time
  @info "===== Completed $(Dates.format(now(), "yyyy-mm-dd HH:MM")) duration $(canonicalize(Dates.CompoundPeriod(elapsed)))"
  flush(io)
  global_logger(old_logger)
  close(io)
end