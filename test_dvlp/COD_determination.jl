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

# Function to select causes based on probability thresholds
function select_InSilico_prob(Indiv_InSilico_CoD, cause1_lim, cause2_3_lim)
    df = copy(Indiv_InSilico_CoD)
    
    df.cause1[df.prob1 .< cause1_lim] .= "Indetermined"
    df.cause2[df.prob2 .< cause2_3_lim] .= missing
    df.prob2[df.prob2 .< cause2_3_lim] .= missing
    
    df.cause3[df.prob3 .< cause2_3_lim] .= missing
    df.prob3[df.prob3 .< cause2_3_lim] .= missing
    
    df.cause2[df.prob1 .< cause1_lim] .= missing
    df.prob2[df.prob1 .< cause1_lim] .= missing
    df.cause3[df.prob1 .< cause1_lim] .= missing
    df.prob3[df.prob1 .< cause1_lim] .= missing
    df.prob1[df.prob1 .< cause1_lim] .= 1.0
       
    return df
end
  
VAQ = CSV.read(joinpath(outputdir, "VAData_converted_VAQ.csv"), DataFrame,drop=[1])
VAP = CSV.read(joinpath(outputdir, "VAData_converted_VAP.csv"), DataFrame, drop=[1])
VAW = CSV.read(joinpath(outputdir, "VAData_converted_VAW.csv"), DataFrame, drop=[1])

# Filter VAW individuals not in VAP
filter!(row -> !(row.IIntID in VAP.IIntID), VAW)

# Check dimensions
println("VAQ dimensions: ", size(VAQ))
println("VAP dimensions: ", size(VAP))
println("VAW dimensions: ", size(VAW))

## Check for duplicates ----
println("Duplicate IDs in VAQ: ", sum(nonunique(VAQ, :IIntID)))
println("Duplicate IDs in VAP: ", sum(nonunique(VAP, :IIntID)))
println("Duplicate IDs in VAW: ", sum(nonunique(VAW, :IIntID)))

## Merge Sources 
VA_all = vcat(VAP, VAQ, VAW, cols=:union)

println("Total rows in merged dataset: ", nrow(VA_all))
println("Duplicate IDs in merged: ", sum(nonunique(VA_all, :IIntID)))

## select appropriate indicator names for CoD attribution ----
## make sure they are in the right order

Mapping_framework = CSV.read("mapping/Mapping_framework_probbase_2016.csv", DataFrame)

Algorithm_indic = ["IIntID"; Mapping_framework[!, "New Column Name"]]

# Check which columns are available
available_cols = intersect(propertynames(VA_all), Symbol.(Algorithm_indic))
println("Available columns from mapping: ", length(available_cols), "/", length(Algorithm_indic))


@rput VA_all   # Send Julia DataFrame to R

## InterVA ----


R"""
library(openVA)

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
library(InSilicoVA)
library(openVA)

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

  CSV.write("Z:/RDM/ResearchData/Datasets/AdHoc/Verbal Autopsy/VA Harmonisation/csvfiles/VA_CoD/VA_all_InterVA.csv", df)
  CSV.write("Z:/RDM/ResearchData/Datasets/AdHoc/Verbal Autopsy/VA Harmonisation/csvfiles/VA_CoD/VA_all_InSilico.csv", VA_all_InSilico)

