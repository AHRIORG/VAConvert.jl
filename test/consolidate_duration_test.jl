using Revise
using DataFrames
using VAConvert

# unit tests


# function
function consolidate_duration_variables!(df::AbstractDataFrame)::AbstractDataFrame
    # Read the metadata CSV that describes which variables to consolidate
    consolidation_info = CSV.read(joinpath(ENV["MAPPING_PATH"], "VA_Duration_consolidation.csv"), DataFrame)

    # Iterate over each consolidation instruction
    for row in eachrow(consolidation_info)
        # Name of the output consolidated variable (e.g. wsi_cough_dur_days)
        consolidated_var = Symbol(row[:Consolidated_variable])
    
        # Gather all numeric variable columns listed (e.g. wsi_cough_days, wsi_fevermon)
        Numeric_vars = [
            row[c] for c in propertynames(row)
            if startswith(string(c), "Numeric_var") && !ismissing(row[c])
        ]

        # Creates the consolidated variable if it doesn't yet exist
        if !(:consolidated_var in names(df))
            df[!, consolidated_var] = Vector{Union{Missing, String}}(missing, nrow(df))
        end

        # Iterate through each row in the main data
        for rowVA in eachrow(df)
            nonmissing_values = []

            # Look for non-missing numeric values among all candidate variables
            for nv in Numeric_vars
                if nv in names(df) && !ismissing(rowVA[nv])
                    push!(nonmissing_values, (nv, rowVA[nv]))
                    rowVA[consolidated_var] = rowVA[nv]  # set the column name that has the value
                end
            end

            if length(nonmissing_values) == 1
                # Exactly one value: assign it
                #rowVA[consolidated_var] = nonmissing_values[1][2]
            elseif length(nonmissing_values) > 1
                # More than one value: warn and leave as missing
                rowVA[consolidated_var] = missing
                @warn "Multiple numeric values found for $(consolidated_var) at row $i: $(nonmissing_values). Consolidated value not assigned."
            end
        end
    end

    return df
end


# create a fictional duration dataframe emulating VAW 
df = DataFrame(
    wsi_cough_days = [missing, "10", missing],
    wsi_cough_month = ["5", missing, missing],
    wsi_cough_durati = ["DAY", "MON", "DAY"]  # unit variable
)


consolidate_duration_variables!(df)


println(df)



