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
l = open("logs/mapping_log.log", "w")
io = IOContext(l, :displaysize => (100, 100))
logger = SimpleLogger(io)
old_logger = global_logger(logger)
@info "===== Execution started $(Dates.format(now(), "yyyy-mm-dd HH:MM"))"
flush(io)
start_time = now()
#endregion

try
    path = ENV["MAPPING_PATH"]
    @info "Mapping path: $path"
    global df = read_variablemap(path,"2012WHO_to_InSilicoVA.csv")
finally
    elapsed = now() - start_time
    @info "===== Completed $(Dates.format(now(), "yyyy-mm-dd HH:MM")) duration $(canonicalize(Dates.CompoundPeriod(elapsed)))"
    flush(io)
    global_logger(old_logger)
    close(io)
  end

