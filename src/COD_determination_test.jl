using CSV
#using DataFrames
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
l = open("logs/CoD_determination_test_log.log", "w")
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

#= # Function to select causes based on probability thresholds
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
end =#

# Import converted VA data --------

VAQ = CSV.read(joinpath(outputdir, "VAData_converted_VAQ.csv"), DataFrame,drop=[1])
VAP = CSV.read(joinpath(outputdir, "VAData_converted_VAP.csv"), DataFrame, drop=[1])
VAW = CSV.read(joinpath(outputdir, "VAData_converted_VAW.csv"), DataFrame, drop=[1])

# Filter  individuals that have both a VA in VAW and VAP (keeping VAP as it is more complete)
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
CSV.write(joinpath(outputdir, "VAData_converted_ALL.csv"), VA_all)

println("Total rows in merged dataset: ", nrow(VA_all))
println("Duplicate IDs in merged: ", sum(nonunique(VA_all, :IIntID)))

## Select the indicators necessary for CoD attribution ----
# The algorithms do not run if there are other variables

# Mapping framework providing necessary indicator
Mapping_framework = CSV.read("mapping/Mapping_framework_probbase_2016.csv", DataFrame)

Algorithm_indic = ["IIntID"; Mapping_framework[!, "New Column Name"]] # Adding ID

# Checking for missing columns
missing_cols = setdiff(Algorithm_indic, names(VA_all))
if !isempty(missing_cols)
    println("Missing required columns in VA_all: $(missing_cols)")
    error("Missing required columns in VA_all: $(missing_cols)")
end

# Select the indicators and year of death
VA_all_indic =
    VA_all |>
    df -> subset(df, :DoD => ByRow(d -> year(d) <= 2024)) |>
    df -> select(df, Algorithm_indic) 

    
@rput VA_all_indic   # Send Julia DataFrame to R
@rput outputdir

## InterVA ----
R"""
library(openVA)

data(RandomVA5)
VA_all_indic <- RandomVA5

VA_all_InterVA <- codeVA(
    VA_all_indic,
    data.type = "WHO2016",
    model = "InterVA",
    HIV = "h",
    Malaria = "v",
    version = "5",
    write = F,
    returnCheckedData = TRUE,
    # filename = "InterVA5_results_all_deaths",
    directory = file.path(outputdir, "VA_CoD")
)

# Extracting Top causes of death
Individual_CoD_InterVA <- getTopCOD(VA_all_InterVA, interVA.rule = T, include.prob = T, n = 3)%>% 
  rename(IIntID = ID)

# Saving R object and Top cause of death
write.csv(Individual_CoD_InterVA, file = file.path(outputdir, "VA_CoD", "Individual_CoD_InterVA.csv"), row.names = F)
saveRDS(VA_all_InterVA, file.path(outputdir, "VA_CoD", "VA_InterVA.rds"))
"""

VA_all_InterVA = @rget VA_all_InterVA   # Bring result back to Julia


## InSilicoVA -----

@rput VA_all_indic
@rput outputdir
# Call the R function from Julia
R"""
# Set memory requirements
options(java.parameters = c("-Xmx32g"))
# libraries
library(InSilicoVA)
library(openVA)

data(RandomVA5)
VA_all_indic <- RandomVA5

VA_all_InSilico <- codeVA(VA_all_indic,
                          data.type = "WHO2016",
                          model = "InSilicoVA",
                          data.check = TRUE,
                          #write = TRUE, 
                          indiv.CI = 0.95,
                          warning.write = TRUE,
                          directory = file.path(outputdir, "VA_CoD")
                          seed = 19800508,
                          java_option = "-Xmx32g", # Memory space
                          exclude.impossible.cause = "subset2" # Insure no impossible causes
)

# Extracting Top causes of death
Individual_CoD_InSilico <- getTopCOD(VA_all_InSilico, n = 3, 
                                   include.prob = T) %>% 
  rename(IIntID = ID)

# Function 
select_InSilico_prob <- function(df, 
                                 cause1_lim = 0.4,
                                 other_lim  = 0.2,
                                 n_cause    = 3,
                                 undetermined_label = "Undetermined"
) {
  
  # column names
  cause_cols <- paste0("cause", seq_len(n_cause))
  prob_cols  <- paste0("prob",  seq_len(n_cause))
  
  ##  ---------- Rule 1: first cause Undetermined
  
  indiv_lowprob1 <- df$prob1 < cause1_lim
  
  df$cause1[indiv_lowprob1] <- undetermined_label
  df$prob1[indiv_lowprob1]  <- 1
  
  if (n_cause > 1) {
    df[indiv_lowprob1, cause_cols[-1]] <- NA_character_ #cause_cols[-1] are all cols except first col
    df[indiv_lowprob1, prob_cols[-1]]  <- NA_real_
  }
  
  ## --------   Rule 2: threshold for secondary causes
  
  if (n_cause > 1) {
    for (i in 2:n_cause) {
      low_prob <- df[[prob_cols[i]]] < other_lim | is.na(df[[prob_cols[i]]])
      df[[cause_cols[i]]][low_prob] <- NA_character_
      df[[prob_cols[i]]][low_prob]  <- NA_real_
      
    }
  }
  
  return(df)
}


# Selecting Top causes of death
Individual_CoD_InSilicoVA_select <- select_InSilico_prob(Individual_CoD_InSilico,
                                                     cause1_lim = 0.40, 
                                                     other_lim = 0.20)

Individual_CoD_InSilico_full <- as.data.frame(VA_all_InSilico$indiv.prob) %>% 
  rownames_to_column(var = "IIntID")

## Extracting Checked dataset
VA_all_InSilico_Checked_data <- VA_all_InSilico$data.checked %>% 
  rename(IIntID = ID)

## Save 
saveRDS(VA_all_InSilico, file.path(outputdir, "VA_CoD", "VA_InSilicoVA.rds"))

write.csv(Individual_CoD_InSilicoVA_select,file.path(outputdir, "VA_CoD", "Individual_CoD_InSilicoVA_select.csv"), row.names = F)
write.csv(Individual_CoD_InSilico_full, file.path(outputdir, "VA_CoD", "Individual_CoD_InSilicoVA_full.csv"), row.names = F)
write.csv(VA_all_InSilico_Checked_data,file.path(outputdir, "VA_CoD", "VA_all_checked_data.csv"), row.names = F)

"""

elapsed = now() - start_time
@info "===== Completed $(Dates.format(now(), "yyyy-mm-dd HH:MM")) duration $(canonicalize(Dates.CompoundPeriod(elapsed)))"
flush(io)
global_logger(old_logger)
close(io)

