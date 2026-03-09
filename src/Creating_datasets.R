## Ariane Sessego
## February 2026 
## R Script for creating publishable databases from harmonization




# setup ----
# libraries
library(dplyr)
library(data.table)
library(lubridate)
library(zoo)
library(questionr)


data_repo <- Sys.getenv("DATA_PATH")

# 1. Downloading VA data ----

VAQ <- fread(paste0(data_repo, "/csvfiles/VAData_converted_VAQ.csv"), sep= ",", drop = 1)
VAP <- fread(paste0(data_repo, "/csvfiles/VAData_converted_VAP.csv"), sep= ",", drop = 1)
VAW <- fread(paste0(data_repo, "/csvfiles/VAData_converted_VAW.csv"), sep= ",", drop = 1) %>% 
  filter(IIntID %in% VAP$IIntID == F) #Supress 26 individuals both with a VAP and VAW questionnaire

# Merge and select data 

All_deaths <- bind_rows(VAP, VAQ) %>% 
  bind_rows(VAW) %>% select(IIntID, DoB, DoD, Sex, 
                            MissingVA, NonContact, VARefused, Questionnaire, VAVisitDate, VAInterviewType, 
                            RespRelationship, LivedWithDeceased, DeathSetting,
                            covid_diag, covid_test,covid_test_r,taste_loss, extreme_fatigue
  )%>% filter(year(DoD) <= 2024)


# CoD data -----

InterVA_CoD <- read.csv(paste0(data_repo,"csvfiles/VA_CoD/Individual_CoD_InterVA.csv"), sep= ",", row.names =1) %>% 
  rename(cause1_InterVA = cause1, 
         lik1_InterVA = lik1, 
         cause2_InterVA = cause2, 
         lik2_InterVA = lik2, 
         cause3_InterVA = cause3, 
         lik3_InterVA = lik3
         )

InSilico_CoD <- read.csv(paste0(data_repo,"csvfiles/VA_CoD/Individual_CoD_InSilicoVA_select.csv"), sep= ",", row.names =1) %>% 
  rename(cause1_InSilicoVA = cause1, 
         prob1_InSilicoVA = prob1, 
         cause2_InSilicoVA = cause2, 
         prob2_InSilicoVA = prob2, 
         cause3_InSilicoVA = cause3, 
         prob3_InSilicoVA = prob3)


# 2. Detailed data checked ----

VA_all_detailed_checked <- read.csv(paste0(data_repo,"csvfiles/VA_all_checked_data.csv"), sep= ",", row.names =1) %>% 
  filter(IIntID %in% All_deaths$IIntID)  ### $$$ We will be able to suppress that line once CoD determination corrected
  

if(F %in% (VA_all_detailed_checked$IIntID %in% All_deaths$IIntID)){
  
  Error_id <- VA_all_detailed_checked$IIntID[VA_all_detailed_checked$IIntID %in% All_deaths$IIntID == F]
  stop(paste0("Error: the following individuals have detailed VA symptoms but are not part of the death dataset: IIntId ",
              paste(Error_id, collapse =",")
              )
       )
  
}

additional_detailed_vars <- c("IIntID","covid_diag", "covid_test","covid_test_r","taste_loss", "extreme_fatigue")

VA_all_detailed_checked_with_added_vars<- left_join(VA_all_detailed_checked, All_deaths[,..additional_detailed_vars], by = "IIntID")


write.csv(VA_all_detailed_checked_with_added_vars, paste0(data_repo,"csvfiles/Publishable_datasets/AHRI.HDSS.VA-detailed-2000-2024.v1.csv"))





## join datasets -----

Deaths <- left_join(All_deaths, InterVA_CoD, by = "IIntID") %>% 
  left_join(InSilico_CoD, by = "IIntID") %>% 
  # Correct missingVA, set as missing those identified as missing by the algorithm and correct those identified as "-" according to the status given by the algorithm
  mutate(MissingVA = ifelse(IIntID %in% VA_all_detailed_checked$IIntID, "n", "y"), 
         # Set questionnaire as missing when Missing = yes
         Questionnaire = ifelse(MissingVA == "y", NA_character_, Questionnaire), 

         # calculate Age in completed years
         Age_in_years = floor(time_length(interval(DoB, DoD), "years")),  
         # Age in completed days for death < 1 year old
        Age_in_days = ifelse(Age_in_years == 0, 
                             floor(time_length(interval(DoB, DoD), "days")), 
                             NA_real_),
        # DoB in year, month
        DoB_ym = format(as.yearmon(DoB),"%Y-%m"),
        # DoD in year, month
        DoD_ym = format(as.yearmon(DoD),"%Y-%m"),
        
        # Errors in VisitDates - before 2000 or in the future - setting them to missing
        VAVisitDate = replace(VAVisitDate, VAVisitDate < as.Date("2000-01-01") | VAVisitDate > Sys.Date(), NA)
          ) 



write.csv(Deaths, paste0(data_repo,"csvfiles/Deaths_CoD_2000_2024_all_variables.csv"))


# freq(Deaths$Age_in_years)
# freq(is.na(Deaths$Age_in_days))
# freq(is.na(Deaths$VAVisitDate))
# max(Deaths$Age_in_days, na.rm = T)
# 
# ym(Deaths$DoB)
# year(as.period(interval(Deaths$DoB, Deaths$DoD), unit = "years"))


#table(Deaths$MissingVA, Deaths$MissingVA_corrected)


# Exporting database -----

Deaths_vars <- c("IIntID", "DoB_ym", "DoD_ym", "Sex", "Age_in_years", "Age_in_days",
                "MissingVA", "NonContact", "VARefused", "Questionnaire", "VAVisitDate", "VAInterviewType",
                "RespRelationship", "LivedWithDeceased", "DeathSetting",
                "cause1_InterVA", "lik1_InterVA", "cause2_InterVA", "lik2_InterVA", "cause3_InterVA", "lik3_InterVA",
                "cause1_InSilicoVA", "prob1_InSilicoVA", "prob1_upper", "prob1_lower", "cause2_InSilicoVA", 
                "prob2_InSilicoVA", "prob2_upper","prob2_lower",
                "cause3_InSilicoVA", "prob3_InSilicoVA", "prob3_upper","prob3_lower"
                )

if(F %in% (Deaths_vars %in% names(Deaths))){
  
  Missing_var <- Deaths_vars[Deaths_vars %in% names(Deaths) == F]
  stop(paste0("Error: the following variables are not in the deaths dataset ",
              paste(Missing_var, collapse =",")
  )
  )
  
}

Deaths_selected_vars <- Deaths[,..Deaths_vars]


# Detailed VA data, only deaths with a VA

write.csv(Deaths_selected_vars, paste0(data_repo,"csvfiles/Publishable_datasets/AHRI.HDSS.DEATHS-COD-2000-2024.v1.csv"))


## Sanity checks


# freq(Deaths$cause1_InterVA)
# freq(Deaths$cause1_InSilicoVA)
# 
# freq(Deaths$Questionnaire)


