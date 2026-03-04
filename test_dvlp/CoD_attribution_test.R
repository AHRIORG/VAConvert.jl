## Ariane Sessego
## January 2026
## Test script for CoD attribution to integrate into VAConvert




# Set up ------

# Set memory requirements
options(java.parameters = c("-Xmx32g"))

## Load the package 

library(openVA)
library(InSilicoVA)
library(dplyr)
library(data.table)
library(tibble)

## Download test data 

data(RandomVA5)

directory_results <- "test_results"

### ---- Running algorithms -----

#  InterVA
RandomVA5_InterVA <- codeVA(RandomVA5,
                         data.type = "WHO2016",
                         model = "InterVA", 
                         HIV = "h",
                         Malaria = "v",
                         version = "5", 
                         returnCheckedData = T, 
                         directory = directory_results, 
                         write =F
)

#  InSilico
RandomVA5_InSilico <- codeVA(RandomVA5,
                          data.type = "WHO2016",
                          model = "InSilicoVA",
                          data.check = T,
                          write = T, 
                          indiv.CI = 0.95,
                          warning.write = T,
                          directory = directory_results,
                          seed = 19800508,
                          java_option = "-Xmx32g", #Memory space
                          exclude.impossible.cause = "subset2" #Insure no impossible causes, here we put the default
)

## ---- Compute individual probabilities ------

Individual_CoD_InterVA <- getTopCOD(RandomVA5_InterVA, interVA.rule = T, include.prob = T, n = 3)%>% rename(IIntID = ID)

Individual_CoD_InSilico <- getTopCOD(RandomVA5_InSilico, n = 3, 
                                     include.prob = T) %>% rename(IIntID = ID)

VA_Checked_data <- RandomVA5_InSilico$data.checked %>% rename(IIntID = ID)



## ----- save as csv -----

write.csv(Individual_CoD_InterVA, paste0(directory_results, "/Individual_CoD_InterVA.csv"))
write.csv(Individual_CoD_InSilico, paste0(directory_results, "/Individual_CoD_InSilicoVA.csv"))
write.csv(VA_Checked_data, paste0(directory_results, "/Checked_data.csv"))






