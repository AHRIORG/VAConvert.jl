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
 function combine_values(values)
    if all(ismissing, values)
        return missing
    end
    cleaned_vector = collect(skipmissing(values))
    if length(cleaned_vector) == 0
        return missing
    elseif length(cleaned_vector) >= 1
        return cleaned_vector[1]
    end
end
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
  pretty_table(io, vavariables; alignment=[:l, :l, :l, :l]) #pretty_table(io, vavariables; alignment=[:l, :l, :l, :l, :r], show_subheader=false)
  transform!(vadata, :Source => ByRow(x -> x) => :Questionnaire)
  # combine VCL into VAQ
  transform!(vadata, :Source => ByRow(x -> x == "VCL" ? "VAQ" : x) => :Source)
  # combine VAC into VAQ
  transform!(vadata, :Source => ByRow(x -> x == "VAC" ? "VAQ" : x) => :Source)
  # combine VAN into VAQ
  transform!(vadata, :Source => ByRow(x -> x == "VAN" ? "VAQ" : x) => :Source)
  # Get the questionnaire(s) and source for each individual
  individualsources = combine(
      groupby(vadata, :IIntID),
      :Source => first => :Source,
      :Questionnaire => (v -> begin
          qs = collect(skipmissing(v))
          qs = unique(qs)                # keep first occurrence order
          isempty(qs) ? missing : join(qs, ';')
      end) => :Questionnaire
  )
  #summarise rows for each source
  sources = combine(groupby(vadata, :Source), nrow => :n)
  pretty_table(io, sources; alignment=[:c, :r]) #pretty_table(io, sources; alignment=[:c, :r], show_subheader=false)
  #summarise variables for each source
  va_variables = combine(groupby(vadata, [:Source, :Variable]), nrow => :n)
  va_variables = outerjoin(va_variables, vavariables, on=:Variable, makeunique=true)
  transform!(va_variables, :Source => ByRow(x -> ismissing(x) ? "VAW" : x) => :Source)
  @info "VA Variables $(names(va_variables)) columns\n"
  pretty_table(io, va_variables; alignment=[:c, :l, :r, :l, :l, :l]) #pretty_table(io, va_variables; alignment=[:c, :l, :r, :l, :l, :l], show_subheader=false)
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

  #output before preprocessing
  for source in unique(vadata.Source)
    @info "Processing source $source"
    source_data = filter(row -> row.Source == source, vadata)
    source_data = stripcrlf(source_data) # remove carriage return and line feed in text fields
    flat_data = unstack(source_data, :IIntID, :Variable, :Value; combine = combine_values)
    # add the source and questionnaire for each individual
    flat_data = leftjoin(flat_data, individualsources, on=:IIntID, matchmissing=:error)
    CSV.write(joinpath(outputdir, "VAData_raw_$source.csv"), flat_data)
  end

  #output after processing
  domainvalues = CSV.read("mapping/VAVariableDomains_with_missing.csv", DataFrame)
  vadata = encodemissing(vadata, domainvalues)
  numericvalues = CSV.read("mapping/NumericVariables_with_missing.csv", DataFrame)
  vadata = encodenumeric(vadata, numericvalues)
  for source in unique(vadata.Source)
    @info "Processing source $source"
    source_data = filter(row -> row.Source == source, vadata)
    source_data = stripcrlf(source_data) # remove carriage return and line feed in text fields
    flat_data = unstack(source_data, :IIntID, :Variable, :Value; combine = combine_values)
    # add the source and questionnaire for each individual
    flat_data = leftjoin(flat_data, individualsources, on=:IIntID, matchmissing=:error)
    # CSV.write(joinpath(outputdir, "VAData_raw_$source.csv"), flat_data)
      if source == "VAW" #add other sources that need consolidation
        consolidate_duration_variables!(flat_data)
      end
    f = convert_durations!(flat_data)
    f = add_individual_dates(f, vadeaths)
    f = add_marriage(f)
    f = CallCentreInterviews(f, source)
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