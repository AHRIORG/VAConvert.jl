using Revise
using DataFrames
using VAConvert

# unit tests


""" ---------------------------
# Test consolidate_duration_variables!
 ---------------------------
""" 
# create a fictional duration dataframe emulating VAW 
df = DataFrame(
    wsi_cough_days = [missing, "10", missing],
    wsi_cough_month = ["5", missing, missing],
    wsi_cough_durati = ["DAY", "MON", "DAY"]  # unit variable
)

consolidate_duration_variables!(df)

println(df)

"""  ---------------
     Test contains
     ---------------
""" 

contains("hello", "lo")
contains("ble", "bleed")
contains("stra", "streak")

"""  ---------------
Testing map_category function
    ---------------
"""

function map_category(x, y::String)
    # Parse the mapping string into a Dict
    mapping = Dict{String,String}()
    for pair in split(y, ",")
        k, v = strip.(split(pair, "="))   # split each "A=a" into ["A","a"]
        mapping[k] = v
    end

    # Define lookup function (uppercase output)
    lookup(val) = begin
        res = get(mapping, string(val), missing)
        res === missing ? missing : uppercase(res)
    end
    
    # Apply to single value or array
    if isa(x, AbstractVector)
        return [lookup(xi) for xi in x]
    else
        return lookup(x)
    end
end


map_category("A", "A=a, B=b, C=a")   # "a"

map_category("hos", "hos=a, B=b, C=a")

map_category("Bilbao d", "Ariane and =a, Bilbao d=b, C=a") 
map_category("Bilbao d", "Ariane and =a, Bilbao d=b, C=a") 

map_category("m", "Ariane and =a, Bilbao d=b, C=a") 


"""  ---------------
Testing rename function - function that simply renames the variable for harmonization
    ---------------
"""

function rename_var(x, y)
    return x
end


rename_var("HOS", missing)

rename_var(missing, missing)

rename_var(3, missing)


""" ---------------------------
# Test encodenumeric
 ---------------------------
""" 

# Dummy example

df = DataFrame(
    Variable = ["var1", "var1", "var1", "var2", "var2", "var3", "var3"],
    Value    = Union{Missing, String}["0", "50", "150", "OK", "error", "safe", missing]
)

numericvalues = DataFrame(
    VariableName = ["var1", "var1", "var2", "var3"],
    Relationship = ["eq", "ge", "contains", "contains"],
    Condition    = [0, 98, "error", "warn"]
)


# Test

f = getfield(VAConvert, Symbol("ge"))
f("5","6")

result = encodenumeric(df, numericvalues)

println("\n--- Original Data ---")
println(df)
println("\n--- Encoded Data ---")
println(result)





