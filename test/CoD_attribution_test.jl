using CSV
using DataFrames
using Dates
using Statistics
using Logging
using Random
using RCall
using Chain
using ConfigEnv

#get environment variables
dotenv()

#region Setup Logging
l = open("logs/InterVA_log.log", "w")
io = IOContext(l, :displaysize => (100, 100))
logger = SimpleLogger(io)
old_logger = global_logger(logger)
@info "===== Execution started $(Dates.format(now(), "yyyy-mm-dd HH:MM"))"
flush(io)
start_time = now()
#endregion

outputdir = joinpath(ENV["DATA_PATH"], "csvfiles")
if !isdir(outputdir)
    mkpath(outputdir)
end

VA_all = CSV.read(joinpath(ENV["TEST_PATH"], "Checked_data.csv"), DataFrame,drop=[1])

@rlibrary openVA
@rlibrary InSilicoVA



@rput VA_all  # Send Julia DataFrame to R

## InterVA -----

R"""

VA_all_InterVA <- codeVA(
    VA_all,
    data.type = "WHO2016",
    model = "InterVA",
    HIV = "h",
    Malaria = "v",
    version = "5",
    write = TRUE,
    returnCheckedData = TRUE,
    filename = "InterVA5_results_all_deaths",
    directory = "Z:/RDM/ResearchData/Datasets/AdHoc/Verbal Autopsy/VA Harmonisation/csvfiles/VA_CoD"
)
"""

VA_all_InterVA = @rget VA_all_InterVA   # Bring result back to Julia

## InSilicoVA -----

# Call the R function from Julia
R"""
VA_all_InSilico <- codeVA(VA_all,
                          data.type = "WHO2016",
                          model = "InSilicoVA",
                          data.check = TRUE,
                          write = TRUE, 
                          indiv.CI = 0.95,
                          warning.write = TRUE,
                          directory = "Z:/RDM/ResearchData/Datasets/AdHoc/Verbal Autopsy/VA Harmonisation/csvfiles/VA_CoD",
                          seed = 19800508,
                          java_option = "-Xmx32g", # Memory space
                          exclude.impossible.cause = "subset2" # Insure no impossible causes
)
"""
# To access the result in Julia
VA_all_InSilico = @rget VA_all_InSilico

elapsed = now() - start_time
@info "===== Completed $(Dates.format(now(), "yyyy-mm-dd HH:MM")) duration $(canonicalize(Dates.CompoundPeriod(elapsed)))"
flush(io)
global_logger(old_logger)
close(io)
