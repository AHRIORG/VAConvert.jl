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


### First function to test if the numeric variables are in the spreadsheet to encode missing ---


test_numericvar_recoded <- function(Source){ #a function to test if all numeric variable are processed for recoding as missing
  # Isolates numeric variables from the mapping file
  Mapping_Numeric <- read.csv(paste0(Source, "/", Source, "_to_InSilicoVA.csv")) %>% filter(VarDomain == "Numeric") %>% 
    # we exclude constructed ones for VAW
    filter(!(str_ends(Source.Column.ID, "_consolidated"))) 
  
  if (F %in% c(Mapping_Numeric$Source.Column.ID %in% NumericVar_missing$VariableName)){
    # If not all numeric variables are recoded - save the non-recoded ones 
    print(
      paste("In", Source, "some numeric variables are missing from NumericVariables_with_missing. They have been saved in the Source repository."))
    
    Mapping_Numeric_missing <- Mapping_Numeric %>% filter(!(Mapping_Numeric$Source.Column.ID %in% NumericVar_missing$VariableName)) 
    
    write.csv(Mapping_Numeric_missing, paste0(Source, "/X_", Source, "_Numeric_not_encoded.csv"))
  } else { # Otherwise, all's good
    paste(Source, ": all numeric variable are in the NumericVariables_with_missing file ")
  }
}


### Overall function to test the mapping spreadsheet ---

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
  Var_Domain_pb <- Mapping_file %>% filter(!(VarDomain %in% c(Variable_domain$VarDomain, NA, "Numeric", "", "HDSS", "Text")))
  if (nrow(Var_Domain_pb)>0) {
    print(paste0("Errors in VarDomain for ", Source, " following variables:"))
    print(Var_Domain_pb %>% select(New.Column.Name, VarDomain, Source.Column.ID))
  } else {print("Variable domains verified")}
  
  # Testing if condition belongs to Vardomain
  Vardomain_to_be_tested <- Mapping_file %>% filter(!(trimws(VarDomain) %in% c(NA, "Numeric", "", "HDSS", "Text", "VA_Checklist", " ")))
  pb_lines_VarDomain <- c(NULL)
  for (i in 1:nrow(Vardomain_to_be_tested)){
    #Extracting line domain
    VarDomain_i <- Vardomain_to_be_tested$VarDomain[i]
    # Extracting possible values of the Vardomain
    VarDomain_values_i <- Variable_domain %>% filter(VarDomain == VarDomain_i)
    # Verifying the condition is in the possible values of this VarDomain
    Test <- trimws(Vardomain_to_be_tested$Condition[i]) %in% trimws(VarDomain_values_i$Code)
    
    # If not verified, store the line number into the list of problematic lines
    if(Test == F){pb_lines_VarDomain <- c(pb_lines_VarDomain,i)}
  }
  
  if (length(pb_lines_VarDomain)>0) {
    print(paste0("Errors in Condition for ", Source, " following variables:"))
    print(Vardomain_to_be_tested[pb_lines_VarDomain,] %>% select(New.Column.Name, Source.Column.ID, VarDomain, Condition))
  } else {print("Conditions verified")}
  
  
  ## 4. Verification for numeric variables
  ## Verifying numeric variables are in the preprocessing file for missing
  test_numericvar_recoded(Source)
  
}


# tests
test_mapping_files("VAW")
test_mapping_files("VAP")
test_mapping_files("VAQ")


