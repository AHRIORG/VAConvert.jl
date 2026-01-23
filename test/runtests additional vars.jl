using VAConvert
using Test

@testset "VAConvert.jl" begin
    # Write your tests here.
end

using CSV
using DataFrames
using Arrow
using Logging
using Dates
using ConfigEnv
using PrettyTables
using VAConvert
#get environment variables
dotenv()

#region Setup Logging
l = open("logs/mapping_log_tests.log", "w")
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
    for source in [#"VAP",  "VAQ",
        "VAW"
        ]
        #read va data
        mapfile = joinpath(mappath, "$(source)_rename_test.csv")
        if isfile(mapfile)
            map = read_variablemap(mapfile)
            source_cols = unique(map.from_variable)
            @info "Number of unique source variables: $(length(source_cols)) in $source"
            flush(io)
            source_data = Arrow.Table(joinpath(outputdir, "arrowfiles", "VAData_$source.arrow")) |> DataFrame
            @info "Number of deaths: $(nrow(source_data)) in $source input"
            df = map_dataframe(source_data, map, :IIntID)
            flat_output = unstack(df, :row_id, :variable, :value)
            @info "Number of deaths: $(nrow(flat_output)) in $source output"
            Arrow.write(joinpath(outputdir, "arrowfiles", "VAData_converted_$(source)_test_new_vars.arrow"), flat_output)
            CSV.write(joinpath(outputdir, "csvfiles", "VAData_converted_$(source)_test_new_var.csv"), flat_output)
            flush(io)
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


