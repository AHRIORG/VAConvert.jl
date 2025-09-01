## Verifying mapping files 
## Ariane Sessego - August 2025


## Libraries
library(foreign)
library(stringr)
library(tidyverse)
library(data.table)
library(dplyr)
library(questionr)

## First test with VAW -----

test_mapping_files <- function(Source){
  Mapping_file <- read.csv(paste0(Source, "/", Source, "_to_InSilicoVA.csv"))
  Variable_file <- read.csv(paste0("../VA_Variables_and_domains/VAVariables_",Source, ".csv"), check.names = F, sep=",")
  Variable_domain <- read.csv("../VA_Variables_and_Domains/VAVariableDomains.csv", check.names = F, sep=",")
  VA_Duration_consolidation <- read.csv("Pre_processing_files/VA_Duration_consolidation.csv") %>% filter(Source == Source)
  
  
  
  # 1. Testing relationship - I add a trimws here (trim white space) because in the function reading the mapping, we also add a strip ------
  
    # Isolating variables that would not meet requirement
  Relationship_pb <- Mapping_file %>% filter(!(trimws(Relationship) %in% c(NA,"", "eq", "gt", "ge", "lt", "le", "contains", "between")))
      #Error message
  if (nrow(Relationship_pb)>0) {
    print(paste0("Errors in Relationships for ", Source, "following variables:"))
    print(Relationship_pb %>% select(New.Column.Name, Relationship))
  } else {print("Relationship verified")}

  
  
  
  # 2. Testing Prerequisite -----
  Prerequisite_pb <- Mapping_file %>% filter(!(Prerequisite %in% c(NA,"", Mapping_file$New.Column.Name)))
  #Error message
  if (nrow(Prerequisite_pb)>0) {
    print(paste0("Errors in Prerequisite for ", Source, " following variables:"))
    print(Prerequisite_pb %>% select(New.Column.Name, Prerequisite))
  } else {print("Prerequisite verified")}
  
  
  
  
  # 3. Testing Source Column ID ------
  
  # variables available for mapping
  HDSS_var <- c("hdss_sex", "hdss_ageindays", "hdss_dod_month", "PartnerStatus")
  consolidated_duration <- VA_Duration_consolidation$Consolidated_variable
  
  Source_Col_pb <- Mapping_file %>% filter(!(Source.Column.ID %in% c(HDSS_var, consolidated_duration, Variable_file$Variable, NA, "")))
  
  #Error message
  if (nrow(Source_Col_pb)>0) {
    print(paste0("Errors in Source Column ID for ", Source, " following variables:"))
    print(Source_Col_pb %>% select(Source.Column.ID, Source.Column.Documentation))
  } else {print("Source Column ID verified")}
  
  
  
  
  # 4. Testing condition is part of the variable domain
  
    # Testing variable domain
  # Exceptional variable domains: HDSS, Numeric, NA
  Var_Domain_pb <- Mapping_file %>% filter(!(VarDomain %in% c(Variable_domain$VarDomain, NA, "Numeric", "", "HDSS")))
  if (nrow(Var_Domain_pb)>0) {
    print(paste0("Errors in VarDomain for ", Source, " following variables:"))
    print(Var_Domain_pb %>% select(New.Column.Name, VarDomain, Source.Column.ID))
  } 
  
  # Testing if condition belongs to Vardomain
  Vardomain_to_be_tested <- Mapping_file %>% filter(!(VarDomain %in% c(NA, "Numeric", "", "HDSS")))
  pb_lines_VarDomain <- c(NULL)
  for (i in nrow(Vardomain_to_be_tested)){
    #Extracting line domain
    VarDomain_i <- Vardomain_to_be_tested$VarDomain[i]
    # Extracting possible values of the Vardomain
    VarDomain_values_i <- Variable_domain %>% filter(VarDomain == VarDomain_i)
    # Verifying the condition is in the possible values of this VarDomain
    Test <- Vardomain_to_be_tested$Condition[i] %in% VarDomain_values_i$Code
    
    # If not verified, store the line number into the list of problematic lines
    if(Test == F){pb_lines_VarDomain <- c(pb_lines_VarDomain,i)}
  }
  
  if (length(pb_lines_VarDomain)>0) {
    print(paste0("Errors in Condition for ", Source, " following variables:"))
    print(Mapping_file[pb_lines_VarDomain,] %>% select(New.Column.Name, Source.Column.ID, Condition))
  } else {print("Conditions verified")}
  
  
  ## 4. Verification for numeric variables
  ## Verifying numeric variables are in the preprocessing file for missing
  
  ## Verifying duration variables
  
}


# tests
test_mapping_files("VAW")
test_mapping_files("VAP")
test_mapping_files("VAQ")


