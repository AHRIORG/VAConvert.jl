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
l = open("logs/checks_mapping_file.log", "w")
io = IOContext(l, :displaysize => (100, 100))
logger = SimpleLogger(io)
old_logger = global_logger(logger)
@info "===== Execution started $(Dates.format(now(), "yyyy-mm-dd HH:MM"))"
flush(io)
start_time = now()
#endregion

try
    mappath = ENV["MAPPING_PATH"]
    @info "Mapping path: $mappath"
    outputdir = joinpath(ENV["DATA_PATH"])
    @info "Output path: $outputdir"
    #map each source in vadata
    #for source in ["VAQ", "VAP", "VAW"]
    for source in ["VAW"]
        #read va data
        mapfile = joinpath(mappath, "$(source)_to_InSilicoVA.csv")
        if isfile(mapfile)
            ## A. Reading files

            # Reading mapping file to be checked
            mapping = read_variablemap(mapfile)
            duration_consolidation_mapping = CSV.read(joinpath(mappath, "VA_Duration_consolidation.csv"), DataFrame)

            # Reading Source data
            outputdir = joinpath(ENV["DATA_PATH"], "csvfiles")
            source_data = CSV.read(joinpath(outputdir, "VAData_$source.csv"), DataFrame)

            # Reading Variable description 
            va_variable = CSV.read(joinpath(outputdir, "VAVariables_$source.csv"), DataFrame)

            # Reading consolidation mapping
            

            ## B. Performing quality checks 

            # 1. testing Source Column ID
            hdss_variables <-

            invalid_variable = unique(filter(x -> x !== missing &&
             !(x in [va_variable.Variable, duration_consolidation_mapping.Consolidated_variable]), 
             mapping.from_variable )) # check that if relationship is not missing it is an allowed value

                if !isempty(invalid_variable)
                error("Invalid values found in `Source Column ID`: $(invalid_variable).")
                end

            # 2. checking relationship
            
            allowed_operator_values = ["eq", "between", "ge", "le", "lt", "gt", "ne", "contains"]
            invalid_operator = unique(filter(x -> x !== missing && !(x in allowed_operator_values), mapping.operator)) # check that if relationship is not missing it is an allowed value
                if !isempty(invalid_operator)
                error("Invalid values found in `Relationship`: $(invalid_operant). Allowed values are: $(allowed_operant_values)")
                end

            # testing prerequisite

            # testing consolidated duration


            #= source_cols = unique(map.from_variable)
            @info "Number of unique source variables: $(length(source_cols)) in $source"
            flush(io)
            
            @info "Number of deaths: $(nrow(source_data)) in $source input"
            df = map_dataframe(source_data, map, :IIntID)
            flat_output = unstack(df, :row_id, :variable, :value)
            @info "Number of deaths: $(nrow(flat_output)) in $source output"
            Arrow.write(joinpath(outputdir, "arrowfiles", "VAData_converted_$(source).arrow"), flat_output)
            CSV.write(joinpath(outputdir, "csvfiles", "VAData_converted_$(source).csv"), flat_output)
            flush(io)=#
        end 
    end
catch e
    # log or handle error
    @error "Error caught" exception=e stacktrace=catch_backtrace()
    # optionally rethrow or handle
    rethrow()

finally
    elapsed = now() - start_time
    @info "===== Completed $(Dates.format(now(), "yyyy-mm-dd HH:MM")) duration $(canonicalize(Dates.CompoundPeriod(elapsed)))"
    flush(io)
    global_logger(old_logger)
    close(io)
end






