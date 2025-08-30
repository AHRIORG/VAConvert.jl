using Revise
using DataFrames
using VAConvert
using CSV


# ===============================
# Function: compare DataFrames
# ===============================
"""
    compare_dfs(df_output::DataFrame, df_expected::DataFrame; idcol::Symbol=:IIntID)

Compare two DataFrames, aligning rows by `idcol` and ignoring:
- Row order
- Column order
- Data type differences (everything cast to String)

Reports detailed differences by row & column.
"""
function compare_dfs(df_output::DataFrame, df_expected::DataFrame; idcol::Symbol=:IIntID)
    # Convert all values to String for comparison
    df_out_str = DataFrame([c => string.(df_output[!, c]) for c in names(df_output)])
    df_exp_str = DataFrame([c => string.(df_expected[!, c]) for c in names(df_expected)])

    # Ensure ID column exists
    # if !(idcol in names(df_out_str)) || !(idcol in names(df_exp_str))
    #     error("ID column $(idcol) not found in both DataFrames.")
    # end

    # Align rows by idcol
    df_out_sorted = sort(df_out_str, idcol)
    df_exp_sorted = sort(df_exp_str, idcol)

    # Align column names (union of both sets)
    all_cols = union(names(df_out_sorted), names(df_exp_sorted))
    select!(df_out_sorted, all_cols, renamecols=false)
    select!(df_exp_sorted, all_cols, renamecols=false)

    diffs = []

    for row in 1:nrow(df_out_sorted)
        for col in setdiff(all_cols, [idcol])  # skip ID column itself
            val_out = df_out_sorted[row, col]
            val_exp = df_exp_sorted[row, col]

            if val_out != val_exp
                push!(diffs, (
                    id    = df_out_sorted[row, idcol],
                    row   = row,
                    col   = col,
                    got   = val_out,
                    expected = val_exp
                ))
            end
        end
    end

    if isempty(diffs)
        println("✅ DataFrames match perfectly (ignoring order and type).")
    else
        println("❌ Differences found:")
        for d in diffs
            println("ID $(d.id), Row $(d.row), Column '$(d.col)': got $(d.got), expected $(d.expected)")
        end
    end
end

# ===============================
# Main test runner
# ===============================

 


for source in ["VAW", "VAP" #, "VAP",
    ]
    println("Evaluating $(source) mapping")
    # --- Read input + expected datasets ---
    df_output    = CSV.read(joinpath(ENV["DATA_PATH"], "csvfiles/VAData_converted_$(source).csv"), DataFrame)
    df_expected = CSV.read("mapping/test_datasets/$(source)_test_output_expected.csv", DataFrame)
    select!(df_expected, Not(:Column1))

    

    # --- Extract IDs and variables from expected ---
    ids_to_keep  = unique(df_expected.IIntID)             # all test IDs
    vars_to_keep = names(df_expected)                     # all columns in expected
    vars_to_keep = filter(!=("IIntID"), vars_to_keep) 
    vars_to_keep = filter(!=("Column1"), vars_to_keep)    # drop ID col if present

    # --- Subset input dataset ---
    df_test_output = filter(row -> row.IIntID in ids_to_keep, df_output)
    df_test_output = select(df_test_output, Cols("IIntID", vars_to_keep...))

    compare_dfs(df_test_output, df_expected; idcol=:IIntID)
# Run when script is executed directly
end



## To develop in the future? If the package is better factorised

# function main()
#     for source in ["VAP", "VAW", "VAQ"
#         ]
#         # === File paths  ===
#         input_file    = "mapping/test_datasets/$(source)_test_input.csv"
#         expected_file = "mapping/test_datasets/$(source)_test_output_expected.csv"

#         println("Reading input test dataset...")
#         df_input    = CSV.read(input_file, DataFrame)

#         println("Reading expected reference dataset...")
#         df_expected = CSV.read(expected_file, DataFrame)

#         println("Running preprocessing...")
#         #Preporcessing
#         domainvalues = CSV.read("mapping/VAVariableDomains_with_missing.csv", DataFrame)
#         numericvalues = CSV.read("mapping/NumericVariables_with_missing.csv", DataFrame)
        
#         df_input_long = stack(df_input, Not(:IIntID); variable_name=:Variable, value_name=:Value)
#         df_encode_missing = encodemissing(df_input_long, domainvalues)
#         df_encode_missing_num = encodenumeric(df_input_long, numericvalues)

#         println(" Running harmonization...")
#         #Mapping
#         mapfile = joinpath(ENV["MAPPING_PATH"], "$(source)_to_InSilicoVA.csv")
#         map = read_variablemap(mapfile)
#         df_output_long = map_dataframe(df_input_long, map, :IIntID)

#         # put in wide format
#         df_flat_output = unstack(df_output_long, :row_id, :variable, :value)
        
#         println("Comparing output vs expected...")
#         compare_dfs(df_flat_output, df_expected; idcol=:IIntID)
#     end
# end

