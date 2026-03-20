## Ariane Sessego
## October 2025
## Script for CoD attribution


# Set up ------

# Set memory requirements
options(java.parameters = c("-Xmx32g"))

## Load the package 

library(openVA)
library(InSilicoVA)
library(dplyr)
library(data.table)
library(questionr)
library(tibble)
library(lubridate)

#data_repository <- "C:/Data/1_VA/0_VA_raw_data"
data_repository <- Sys.getenv("DATA_PATH")

# Function to select TopCOD for InSilicoVA  -----

# Extract cause CI for top cause
extract_ci <- function(cause_vec, full_proba_list) {
  upper_df <- full_proba_list$indiv.prob.upper
  lower_df <- full_proba_list$indiv.prob.lower
  
  upper_mat <- as.matrix(upper_df)
  lower_mat <- as.matrix(lower_df)
  
  row_idx <- seq_along(cause_vec)
  col_idx <- match(cause_vec, colnames(upper_mat))
  
  prob_upper <- rep(NA_real_, length(cause_vec))
  prob_lower <- rep(NA_real_, length(cause_vec))
  
  valid <- !is.na(col_idx)
  
  prob_upper[valid] <- upper_mat[cbind(row_idx[valid], col_idx[valid])]
  prob_lower[valid] <- lower_mat[cbind(row_idx[valid], col_idx[valid])]
  
  data.table(prob_upper = prob_upper, prob_lower = prob_lower)
}

# Select top causes according to rules
select_InSilico_prob <- function(df, 
                                 cause1_lim = 0.4,
                                 other_lim  = 0.2,
                                 n_cause    = 3,
                                 undetermined_label = "Undetermined", 
                                 extract_CI = F, 
                                 full_proba_list = NULL
) {
  
  # column names
  cause_cols <- paste0("cause", seq_len(n_cause))
  prob_cols  <- paste0("prob",  seq_len(n_cause))
  
  ##  ---------- Rule 1: first cause Undetermined
  
  indiv_lowprob1 <- df$prob1 <= cause1_lim
  
  df$cause1[indiv_lowprob1] <- undetermined_label
  df$prob1[indiv_lowprob1]  <- 1
  
  if (n_cause > 1) {
    df[indiv_lowprob1, cause_cols[-1]] <- NA_character_ #cause_cols[-1] are all cols except first col
    df[indiv_lowprob1, prob_cols[-1]]  <- NA_real_
  }
  
  ## --------   Rule 2: threshold for secondary causes
  
  if (n_cause > 1) {
    for (i in 2:n_cause) {
      low_prob <- df[[prob_cols[i]]] <= other_lim | is.na(df[[prob_cols[i]]])
      df[[cause_cols[i]]][low_prob] <- NA_character_
      df[[prob_cols[i]]][low_prob]  <- NA_real_
      
    }
  }
  
  
  
  if(extract_CI == T){
    
    df <- as.data.table(df)
    
    cause_cols <- paste0("cause", 1:n_cause) 
    prob_name <- paste0("prob", 1:n_cause) 
    
    # Extract CIs for each cause column
    ci_list <- lapply(cause_cols, function(col) {
      extract_ci(df[[col]], full_proba_list)
    })
    
    df[, c(rbind(paste0(prob_name,"_upper"), paste0(prob_name,"_lower"))) := do.call(cbind, ci_list)]
    
    
  }
  return(df)
}




# Data -----
## Download data 
VAQ <- fread(paste0(data_repository, "/csvfiles/VAData_converted_VAQ.csv"), sep= ",", drop = 1)
VAP <- fread(paste0(data_repository, "/csvfiles/VAData_converted_VAP.csv"), sep= ",", drop = 1)
VAW <- fread(paste0(data_repository, "/csvfiles/VAData_converted_VAW.csv"), sep= ",", drop = 1) %>% 
  filter(IIntID %in% VAP$IIntID == F) #Supress 26 individuals both with a VAP and VAW questionnaire


# Tests ----

freq(duplicated(VA_all))

## select appropriate indicator names for CoD attribution $$$ ----
## make sure they are in the right order

Mapping_framework <- fread("mapping/Mapping_framework_probbase_2016.csv", sep= ",") 

Algorithm_indic <- c("IIntID", Mapping_framework$`New Column Name`)

## Merge Sources -----

VA_all <- bind_rows(VAP, VAQ) %>% 
  bind_rows(VAW) %>% filter(MissingVA != "y", #filter deaths with missing VAs
                            year(DoD) <= 2024) #filter deaths after 2024
  

# Selecting only the indicators necessary for the algorithm
VA_all_indic <- VA_all[,..Algorithm_indic]


# Run algorithms -------

## Run consistency checks -----



## InterVA ----

start_time <- Sys.time()
log_file <- paste0(data_repository, "/csvfiles/VA_CoD", "/CoD_determination_run_log.txt")
cat("-------------------------\n Running InterVA5 all deaths, starting at:", format(start_time, "%Y-%m-%d %H:%M:%S") , " SAST \n", 
    file = log_file, append = TRUE)

VA_all_InterVA <- codeVA(VA_all_indic,
                          data.type = "WHO2016",
                          model = "InterVA", 
                          HIV = "h",
                          Malaria = "v",
                          version = "5", 
                          # write = T, 
                          returnCheckedData = T, 
                          directory = paste0(data_repository,"/csvfiles/VA_CoD")
)
end_time <- Sys.time()
cat("Finished at:", format(end_time, "%Y-%m-%d %H:%M:%S") , " SAST\n", file = log_file, append = TRUE)
cat("Duration:", difftime(end_time, start_time, units = "hours"), "hours\n", 
    file = log_file, append = TRUE)

## rename ID as IIntID $$$$ ??



## InSilicoVA -----

start_time <- Sys.time()
log_file_InSilico <-paste0(data_repository, "/csvfiles/VA_CoD", "/CoD_determination_run_log.txt")
cat("Running InSilicoVA all deaths, starting at:", format(start_time, "%Y-%m-%d %H:%M:%S") , " SAST \n", 
    file = log_file_InSilico, append = TRUE)

VA_all_InSilico <- codeVA(VA_all_indic,
                          data.type = "WHO2016",
                          model = "InSilicoVA",
                          data.check = T,
                          write = T, 
                          indiv.CI = 0.95,
                          warning.write = T,
                          directory = directory = paste0(data_repository,"/csvfiles/VA_CoD")
                          seed = 19800508, # Day of the declaration of smallpox eradication!!
                          java_option = "-Xmx32g", #Memory space
                          exclude.impossible.cause = "subset2" #Insure no impossible causes, here we put the default
)
end_time <- Sys.time()
cat("Finished at:", format(end_time, "%Y-%m-%d %H:%M:%S") , " SAST\n", file = log_file_InSilico, append = TRUE)
cat("Duration:", difftime(end_time, start_time, units = "hours"), "hours\n", 
    file = log_file_InSilico, append = TRUE)




### Save individual probabilities ----

# InterVA
Individual_CoD_InterVA <- getTopCOD(VA_all_InterVA, interVA.rule = T, include.prob = T, n = 3)%>% 
  rename(IIntID = ID)

# InSilicoVA
Individual_CoD_InSilico <- getTopCOD(VA_all_InSilico, n = 3, 
                                   include.prob = T) %>% 
  rename(IIntID = ID)

Individual_CoD_InSilicoVA_full <- getIndivProb(VA_all_InSilico, CI = 0.95)

Individual_CoD_InSilicoVA_select <- Individual_CoD_InSilico %>% 
  select_InSilico_prob(cause1_lim = 0.4, other_lim  = 0.2,
                       n_cause    = 3, undetermined_label = "Undetermined",
                       extract_CI = T,
                       full_proba_list = Individual_CoD_InSilicoVA_full)


# get the full sample of individual probabilities for each death and cause of death
# Full_sample_prob <- get.indiv(VA_all_InSilico, CI = 0.95, is.sample = T) 
# saveRDS(Full_sample_prob, paste0(data_repository,"/csvfiles/VA_CoD/VA_InSilicoVA_Indiv_CoD_full_probability_distribution.rds"))


## Save Checked dataset -----

VA_all_InSilico_Checked_data <- VA_all_InSilico$data.checked %>% 
  rename(IIntID = ID)



####  Writing

saveRDS(VA_all_InSilico, paste0(data_repository,"/csvfiles/VA_CoD/VA_InSilicoVA.rds"))
saveRDS(VA_all_InterVA, paste0(data_repository,"/csvfiles/VA_CoD/VA_InterVA.rds"))

write.csv(Individual_CoD_InterVA, paste0(data_repository,"/csvfiles/VA_CoD/Individual_CoD_InterVA.csv"))
write.csv(Individual_CoD_InSilicoVA_select, paste0(data_repository,"/csvfiles/VA_CoD/Individual_CoD_InSilicoVA_select.csv"))
saveRDS(Individual_CoD_InSilicoVA_full, paste0(data_repository,"/csvfiles/VA_CoD/Individual_CoD_InSilicoVA_full.csv"))
write.csv(VA_all_InSilico_Checked_data,paste0(data_repository,"/csvfiles/VA_all_checked_data.csv" ))


VA_all_InSilico <- readRDS(paste0(data_repository,"/csvfiles/VA_CoD/VA_InSilicoVA.rds"))

# Individual_CoD_InSilico_full <- read.csv(paste0(data_repository,"/csvfiles/VA_CoD/Individual_CoD_InSilicoVA_full.csv"))





