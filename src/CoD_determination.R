## Ariane Sessego
## October 2025
## Script for CoD attribution


# Set up ------

# Set memory requirements
options(java.parameters = c("-Xmx32g"))

## Load the package 

# install.packages("openVA")
# install.packages("nbc4va")
library(openVA)
library(InSilicoVA)
library(dplyr)
library(data.table)
library(questionr)
library(tibble)

# Function 
select_InSilico_prob <- function(Indiv_InSilico_CoD, cause1_lim, cause2_3_lim){
  Indiv_InSilico_CoD$cause1[Indiv_InSilico_CoD$prob1 <cause1_lim] <- "Indetermined"
  Indiv_InSilico_CoD$cause2[Indiv_InSilico_CoD$prob2 <cause2_3_lim] <- NA_character_
  Indiv_InSilico_CoD$prob2[Indiv_InSilico_CoD$prob2 <cause2_3_lim] <- NA_character_
  
  Indiv_InSilico_CoD$cause3[Indiv_InSilico_CoD$prob3 <cause2_3_lim] <- NA_character_
  Indiv_InSilico_CoD$prob3[Indiv_InSilico_CoD$prob3 <cause2_3_lim] <- NA_character_
  
  
  Indiv_InSilico_CoD$cause2[Indiv_InSilico_CoD$prob1 <cause1_lim] <- NA_character_
  Indiv_InSilico_CoD$prob2[Indiv_InSilico_CoD$prob1 <cause1_lim] <- NA_character_
  Indiv_InSilico_CoD$cause3[Indiv_InSilico_CoD$prob1 <cause1_lim] <- NA_character_
  Indiv_InSilico_CoD$prob3[Indiv_InSilico_CoD$prob1 <cause1_lim] <- NA_character_
  Indiv_InSilico_CoD$prob1[Indiv_InSilico_CoD$prob1 <cause1_lim] <- 1.0
  
  ## Next step, add CI?
  
  return(Indiv_InSilico_CoD)
}


# Data -----
## Download data 
VAQ <- fread("C:/Data/1_VA/0_VA_raw_data/csvfiles/VAData_converted_VAQ.csv", sep= ",", drop = 1
             )
VAP <- fread("C:/Data/1_VA/0_VA_raw_data/csvfiles/VAData_converted_VAP.csv", sep= ",", drop = 1)
VAW <- fread("C:/Data/1_VA/0_VA_raw_data/csvfiles/VAData_converted_VAW.csv", sep= ",", drop = 1) %>% 
  filter(IIntID %in% VAP$IIntID == F) #Supress 26 individuals both with a VAP and VAW questionnaire

# names(VAW)[names(VAW) %in% names(VAQ) == F] # problem missing variable
# freq(VAW$IIntID %in% VAP$IIntID)
# freq(VAP$IIntID %in% VAQ$IIntID)

## Check duplicated ----
# table(duplicated(VAQ$IIntID))
# table(duplicated(VAP$IIntID))
# table(duplicated(VAW$IIntID))

## Merge Sources 

VA_all <- bind_rows(VAP, VAQ) %>% 
  bind_rows(VAW)


freq(duplicated(VA_all))

## select appropriate indicator names for CoD attribution $$$ ----
## make sure they are in the right order

Mapping_framework <- fread("C:/Users/Ariane.Sessego/VAConvert.jl/mapping/Mapping_framework_probbase_2016.csv", sep= ",") 

Algorithm_indic <- c("IIntID", Mapping_framework$`New Column Name`)
# 
# table(names(VA_all) %in% Mapping_framework$`New Column Name`)
# table(Mapping_framework$`New Column Name` %in% names(VA_all)  )
# names(VA_all)[names(VA_all) %in% Mapping_framework$`New Column Name` == F]
# names(VA_all)
# VA_all[,c("IntID", Mapping_framework$`New Column Name`)]


# Run algorithms -------

## Run consistency checks -----

# DataCheck5(Input, id, probbaseV5, InSilico_check = FALSE, write) - has to be in the InterVA format 1, 0, NA

## InterVA ----

start_time <- Sys.time()
log_file <-paste0("C:/Data/1_VA/0_VA_raw_data/csvfiles/VA_CoD", "/InterVA5_run_log.txt")
cat("Running InterVA5 all deaths, starting at:", format(start_time, "%Y-%m-%d %H:%M:%S") , " SAST \n", 
    file = log_file, append = TRUE)

VA_all_InterVA <- codeVA(VA_all,
                          data.type = "WHO2016",
                          model = "InterVA", 
                          HIV = "h",
                          Malaria = "v",
                          version = "5", 
                          write = T, 
                          returnCheckedData = T, 
                          filename = "InterVA5_results_all_deaths",
                          directory = "C:/Data/1_VA/0_VA_raw_data/csvfiles/VA_CoD"
)
end_time <- Sys.time()
cat("Finished at:", format(end_time, "%Y-%m-%d %H:%M:%S") , " SAST\n", file = log_file, append = TRUE)
cat("Duration:", difftime(end_time, start_time, units = "hours"), "hours\n", 
    file = log_file, append = TRUE)

## rename ID as IIntID $$$$ ??



## InSilicoVA -----

start_time <- Sys.time()
log_file_InSilico <-paste0("C:/Data/1_VA/0_VA_raw_data/csvfiles/VA_CoD", "/InterVA5_run_log.txt")
cat("Running InSilicoVA all deaths, starting at:", format(start_time, "%Y-%m-%d %H:%M:%S") , " SAST \n", 
    file = log_file_InSilico, append = TRUE)

VA_all_InSilico <- codeVA(VA_all,
                          data.type = "WHO2016",
                          model = "InSilicoVA",
                          data.check = T,
                          write = T, 
                          indiv.CI = 0.95,
                          warning.write = T,
                          directory = "C:/Data/1_VA/0_VA_raw_data/csvfiles/VA_CoD",
                          seed = 19800508,
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

Individual_CoD_InSilicoVA_select <- select_InSilico_prob(Individual_CoD_InSilico,
                                                     cause1_lim = 0.40, 
                                                     cause2_3_lim = 0.20)

Individual_CoD_InSilico_full <- as.data.frame(VA_all_InSilico$indiv.prob) %>% 
  rownames_to_column(var = "IIntID")

## Save Checked dataset -----

VA_all_InSilico_Checked_data <- VA_all_InSilico$data.checked %>% 
  rename(IIntID = ID)


#### Add non-indicator variables to the dataset


####  Writing

write.csv(Individual_CoD_InterVA, "C:/Data/1_VA/0_VA_raw_data/csvfiles/VA_CoD/Individual_CoD_InterVA.csv")
write.csv(Individual_CoD_InSilicoVA_select, "C:/Data/1_VA/0_VA_raw_data/csvfiles/VA_CoD/Individual_CoD_InSilicoVA_select.csv")
write.csv(Individual_CoD_InSilico_full, "C:/Data/1_VA/0_VA_raw_data/csvfiles/VA_CoD/Individual_CoD_InSilicoVA_full.csv")
write.csv(VA_all_InSilico_Checked_data,"C:/Data/1_VA/0_VA_raw_data/csvfiles/VA_all_checked_data.csv" )



### Handling missing data ----

## List of deaths without a CoD ----

VA_missing <- VA_all %>% filter(IIntID %in% Individual_CoD_InSilico$IIntID == F)

VAQ <- fread("C:/Data/1_VA/0_VA_raw_data/csvfiles/VAData_VAQ.csv", sep= ",") %>% 
  mutate(Missing = ifelse(IIntID %in% VA_missing$IIntID, "missing", "not missing"))

VAQ_missing <- VAQ %>% filter(IIntID %in% VA_missing$IIntID)

freq(VAQ_missing$Questionnaire)

freq(VAQ_missing$VAN_PremCompl)

table(VAQ$VAN_PremCompl, VAQ$Missing)
table(VAQ$Questionnaire, VAQ$Missing)


Odd <- VAQ %>% filter(Missing == "not missing", VAN_PremCompl %in% c("ALV", "NCT", "RFS") ) %>% 
  select(VAN_PremCompl, VAN_MedPart)


VAP <- fread("C:/Data/1_VA/0_VA_raw_data/csvfiles/VAData_VAP.csv", sep= ",") %>% 
  mutate(Missing = ifelse(IIntID %in% VA_missing$IIntID, "missing", "not missing"))

freq(VAP$Missing)
table(VAP$ca_non_contact, VAP$Missing)
table(VAP$ca_particip_refu, VAP$Missing)

VAP_missing_odd <- VAP %>% filter(Missing == "not missing", ca_particip_refu == "YES")

VAP_refusal_odd <- VAP %>% filter(ca_particip_refu == "" & Missing == "not missing"
                                  )

         
VAW <- fread("C:/Data/1_VA/0_VA_raw_data/csvfiles/VAData_VAW.csv", sep= ",") %>% 
           mutate(Missing = ifelse(IIntID %in% VA_missing$IIntID, "missing", "not missing"))

freq(VAW$Missing)
table(VAW$wca_non_contact, VAW$Missing)
table(VAW$wca_particip_ref, VAW$Missing)

VAW_missing_odd <- VAW %>% filter(Missing == "not missing", wca_non_contact == "YES") 
# This one is okay, just the one that was done twice in VAP (completed) and then VAW (not completed)



