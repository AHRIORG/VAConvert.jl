# VAConvert

## Overview

This repository contains the code used by the Africa Health Research Institue (AHRI) to produce a harmonized cause-of-death datasets from VAs, across four different VA questionnaire versions from 2000 to 2024, using InterVA5 and InSilicoVA to estimate causes of death.

It is based on a structured data processing framework set up to ensure transparency and traceability. Its key principle is that all data transformation is performed through correspondence tables that systematically document which variables from the historical data are used to produced the harmonized input format required by InterVA5 and InSilicoVA. It builds on the structure of the open-source tools CrossVA and PyCrossVA built (listed below), implements their principles in Julia and extends them data pre-processing stages and quality control. 

**For more details, see the report describing the harmonization process** (soon to be released, link will be added here)

pyCrossVA: https://github.com/verbal-autopsy-software/pyCrossVA 

CrossVA: https://github.com/SwissTPH/CrossVA


## Folder description

***/src***:includes
- extractdata.jl: script to extract relevant information from the main database
- processdata.jl: script to prepare the data into a format ready for mapping, in particular setting missing values and transforming all duration variables in days.
- variable_mapping.jl: script to harmonize data to the standard input expected by VA algorithms InSilicoVA and InterVA5
- CoD_determination.R: script used to estimate the causes of death with InSilicoVA and InterVA5 and extract the top causes of death
- Creating_datasets.R: script to create the final released datasets.

**/test**: includes the following validation tests
- mapping_file_checks.R: script running tests on the mapping files (validity of source variable, relationship...à
- test_mapping.jl: script to test the harmonization with validated test datasets

**/mapping**: contains datasets used for harmonization

Files to preprocess the data:

a. Files to transform all durations variable in a common unit (days)

- VA_Duration_equivalence.csv
- VA_Duration_consolidation.csv
  
b. Files to define missing variables

- NumericVarialbes_with_missing.csv
- VAVariableDomains_with_missing.csv

Mapping files, correspondance tables used to map historical VA data to a harmonized format 

- VAQ_to_InSilicoVA.csv: mapping file for VAs using questionnaires from 2000 to 2016, including AHRI questionnaire (VAQ - 2000-2016), supplemented by AHRI's checklist 1 (VAC - 2000-2010) and AHRI's checklist 2 (2011-2016).
- VAP_to_InSilicoVA.csv: mapping file for VAs using WHO 2016 standard questionnaire (VAP - 2017-2021)
- VAW_to_InSilicoVA.csv: mapping file for VA using WHO 2016 standard questionnaire (VAP - 2017-2021)
- Mapping_framework_probbase2016.csv: the general framework 



