# SPDX-License-Identifier: MIT

module VAConvert

using DBInterface
using ODBC
using DataFrames
using CSV
using Logging
using Dates
using TidierFiles
using StatFiles
# Write your package code here.
export readtable, connectdb, sessions, individual_deaths, sessionvalues, getvariables, getdomains,
    read_variablemap, consolidate_duration_variables!, convert_durations!, map_dataframe, stripcrlf, add_individual_dates, add_marriage,
    encodemissing, encodenumeric, eq, ge, gt, lt, le, between, contains

function readtable(server, database, table)
    conStr = "Driver=ODBC Driver 18 for SQL Server;SERVER=$server;DATABASE=$database;Trusted_Connection=yes;TrustServerCertificate=yes"
    con = ODBC.Connection(conStr)
    return DBInterface.execute(con, "SELECT * FROM $table") |> DataFrame
end

function connectdb(server, database)
    @info "Connecting to database $database on server $server"
    if Sys.isapple()
        ODBC.setunixODBC(; ODBCSYSINI="/opt/homebrew/etc", ODBCINSTINI="odbcinst.ini", ODBCINI="odbc.ini")
    end
    if Sys.iswindows()
        connStr = "Driver=ODBC Driver 18 for SQL Server; SERVER=$server; DATABASE=$database;Trusted_Connection=yes;TrustServerCertificate=yes;AutoTranslate=no"
    end
    if Sys.islinux()
        connStr = "Driver={/opt/microsoft/msodbcsql18/lib64/libmsodbcsql-18.4.so.1.1};Server=$server;Database=$database;UID=$(ENV["ServerUser"]);PWD=$(ENV["ServerPW"]);TrustServerCertificate=yes;AutoTranslate=no;"
    end
    if Sys.isapple()
        connStr = """
                    Driver={ODBC Driver 18 for SQL Server};
                    Server=$server;
                    DATABASE=$database;
                    Uid=$(ENV["ServerUser"]);
                    Pwd=$(ENV["ServerPW"]);
                    TrustServerCertificate=yes;
                    Encrypt=yes;
                    AutoTranslate=no;
                """
    end
    con = ODBC.Connection(connStr)
    return con
end

function getvariables(con)
    sql = """
        SELECT
            Variable, Prompt, VarDomain, VarGroup
        FROM dbo.Variables
        WHERE VarGroup IN ('VA Checklist','VA Narrative','Verbal Autopsy','WHO 2016','WHO 2022');
    """
    df = DBInterface.execute(con, sql) |> DataFrame
    return df
end

function getdomains(con)
    sql = """
    WITH varvalues AS (
    SELECT v.VarDomain, q.VarValue Code, COUNT(*) n FROM dbo.QVarValuesCode q
        JOIN dbo.Variables v ON q.Variable = v.Variable
    WHERE v.VarGroup IN ('VA Checklist','VA Narrative','Verbal Autopsy','WHO 2016','WHO 2022')
    GROUP BY v.VarDomain, q.VarValue
    ),
    domains AS (
        SELECT DISTINCT
            vc.VarDomain,vc.Code,vc.Caption,vc.Sequence
        FROM dbo.VarDomainCodes vc
        JOIN dbo.Variables v ON v.VarDomain = vc.VarDomain
        WHERE v.VarGroup IN ('VA Checklist','VA Narrative','Verbal Autopsy','WHO 2016','WHO 2022')
    )
    SELECT
    COALESCE(v.VarDomain,d.VarDomain) VarDomain,
    COALESCE(v.Code,d.Code) Code,
    d.Caption,
    d.Sequence,
    v.n
    FROM varvalues v
    FULL JOIN domains d ON v.VarDomain = d.VarDomain AND v.Code = d.Code
    WHERE NOT COALESCE(v.Code,d.Code) IS NULL
    ORDER BY VarDomain, Sequence, Code;
    """
    df = DBInterface.execute(con, sql) |> DataFrame
    return df
end

function sessions(con, source)
    sql = """
    WITH FinalQ AS (
        SELECT
          SubjectID IIntID,
          MAX(QSessionID) QSessionID
        FROM dbo.QSessions
        WHERE Questionnaire = '$(source)'
          AND Status=('Final')
        GROUP BY SubjectID
      ),
      DefinitiveQ AS (
        SELECT
          *
        FROM FinalQ
        UNION
        SELECT
          SubjectID IIntID,
          MAX(QSessionID) QSessionID
        FROM dbo.QSessions
        WHERE Questionnaire = '$(source)'
          AND Status IN ('Verified','Validated')
          AND NOT SubjectID IN (SELECT IIntID FROM FinalQ)
        GROUP BY SubjectID
      )
    SELECT
      *,
      '$(source)' as Source
    FROM DefinitiveQ;
    """
    df = DBInterface.execute(con, sql) |> DataFrame
    return df
end

function individual_deaths(con)
    sql = """
    SELECT
        CAST(i.IndividualUid AS VARCHAR(36)) IndividualUid,
        im.IndividualId IIntID,
        i.Sex,
        b.EventDate DoB,
        e.EventDate DoD,
        YEAR(e.EventDate) DoDYr
    FROM AHRI_STG.dbo.Individuals i
        JOIN AHRI_STG.dbo.Events e ON i.EndEventUid = e.EventUid
        JOIN AHRI_STG.dbo.Events b ON i.BirthEventUid = b.EventUid
        JOIN AHRI_STG.ops.IndividualMaps im ON i.IndividualUid = im.IndividualUid
    WHERE e.EventTypeId = 7;
    """
    df = DBInterface.execute(con, sql) |> DataFrame
    return df
end

function sessionvalues(con, df::AbstractDataFrame, col::Symbol)::DataFrame
    sql = """
        SELECT
            QSessionID,
            vc.Variable,
            v.VarDomain,
            CAST(TRIM(VarValue) AS varchar(MAX)) Value
        FROM dbo.QVarValuesCode vc
          LEFT JOIN dbo.Variables v ON (vc.Variable = v.Variable)
        WHERE QSessionID = ?
        UNION
        SELECT
            QSessionID,
            Variable,
            NULL AS VarDomain,
            CAST(CONVERT(VARCHAR, VarValue, 23) AS varchar(MAX)) Value --CONVERT(VARCHAR, VarValue, 23) Value
        FROM dbo.QVarValuesDate
        WHERE QSessionID = ?
        UNION
        SELECT
            QSessionID,
            Variable,
            NULL AS VarDomain,
            CAST(VarValue AS varchar(MAX)) Value
        FROM dbo.QVarValuesFloat
        WHERE QSessionID = ?
        UNION
        SELECT
            QSessionID,
            Variable,
            NULL AS VarDomain,
            CAST(VarValue AS varchar(MAX)) Value
        FROM dbo.QVarValuesInt
        WHERE QSessionID = ?
        UNION
        SELECT
        QSessionID,
            Variable,
            NULL AS VarDomain,
            CAST(TRIM(VarValue) AS varchar(MAX)) Value
        FROM dbo.QVarValuesStr
        WHERE QSessionID = ?
        UNION
        SELECT
            QSessionID,
            Variable,
            NULL AS VarDomain,
            CAST(VarValue AS varchar(MAX)) Value
        FROM dbo.QVarValuesText
        WHERE QSessionID = ?
        UNION
        SELECT
            QSessionID,
            Variable,
            NULL AS VarDomain,
            CAST(CONVERT(VARCHAR, AssignedDate, 23) AS varchar(MAX)) Value --CONVERT(VARCHAR, AssignedDate, 23) Value
        FROM dbo.QVarValuesVPDate
        WHERE QSessionID = ?;
    """
    stmt = DBInterface.prepare(con, sql)
    if nrow(df) >= 1
        i = 1
        while ismissing(df[i, col]) && i <= nrow(df)
            i += 1
        end
        if i <= nrow(df)
            params = fill(df[i, col], 7)
            rf = DBInterface.execute(stmt, params) |> DataFrame
            insertcols!(rf, :QSessionID, :IIntID => df[i, :IIntID], :Source => string(col))
            i += 1
            for j in i:nrow(df)
                if !ismissing(df[j, col])
                    params = fill(df[j, col], 7)
                    f = DBInterface.execute(stmt, params) |> DataFrame
                    insertcols!(f, :QSessionID, :IIntID => df[j, :IIntID], :Source => string(col))
                    append!(rf, f)
                end
            end
        end
        return rf
    end
    return DataFrame()
end
#
"""
    consolidate_duration_variables(data::AbstractDataFrame)::AbstractDataFrame

Creating a new numerical duration variable when there is more than one numeric variable for a duration 
    (different variable for days, month, years...)
"""

function consolidate_duration_variables!(df::AbstractDataFrame)::AbstractDataFrame
    # Read the metadata CSV that describes which variables to consolidate
    consolidation_info = CSV.read(joinpath(ENV["MAPPING_PATH"], "VA_Duration_consolidation.csv"), DataFrame)

    # Iterate over each consolidation instruction
    for row in eachrow(consolidation_info)
        # Name of the output consolidated variable 
        consolidated_var = Symbol(row[:Consolidated_variable])

        # Gather all numeric variable columns listed 
        Numeric_vars = [
            row[c] for c in propertynames(row)
            if startswith(string(c), "Numeric_var") && !ismissing(row[c])
        ]

        # Creates the consolidated variable if it doesn't yet exist
        if !(:consolidated_var in names(df))
            df[!, consolidated_var] = Vector{Union{Missing,String}}(missing, nrow(df))
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
                i = rowVA[:IIntID]
                @warn "Multiple numeric values found for $(consolidated_var) at individual IIntId $i : $(nonmissing_values). Consolidated value assigned as missing."
            end
        end
    end

    return df
end




"""
    convert_durations!(data::AbstractDataFrame)::AbstractDataFrame

Take a verbal autopsy file in flat format and normalise the duration variables to days.
"""
function convert_durations!(data::AbstractDataFrame)::AbstractDataFrame
    duration_lookup = Dict{String,Union{Number,Missing}}("NAD" => missing, "DFT" => missing, "MIS" => missing, "R" => missing,
        "DAY" => 1, "WEE" => 7, "MON" => 30, "YEA" => 365, "U" => missing, "QRY" => missing, "MIN" => 1 / 1440, "HOR" => 1 / 24,
        "H" => 1 / 24, "M" => 30, "D" => 1, "Y" => 365, "W" => 7, "HRS" => 1 / 24, "YRS" => 365, "DKN" => missing, "HOU" => 1 / 24)
    default_duration = Dict{String,Real}("NAD" => 0, "DFT" => 0, "MIS" => 0, "R" => 0, "DAY" => 5, "WEE" => 3.5, "MON" => 5, "YEA" => 3,
        "U" => 0, "QRY" => 0, "MIN" => 7, "HOR" => 7, "H" => 7, "M" => 7, "D" => 5, "Y" => 3, "W" => 3.5, "HRS" => 7, "YRS" => 3,
        "DKN" => 0, "HOU" => 7)
    duration_data = CSV.read(joinpath(ENV["MAPPING_PATH"], "VA_Duration_Unit_equivalence.csv"), DataFrame)
    duration_map = Dict{String,String}(zip(duration_data[!, :Variable_numeric], duration_data[!, :Variable_unit]))
    for row in eachrow(data)
        for (k, v) in duration_map
            if hasproperty(row, k) && !ismissing(row[v]) # && !ismissing(row[k]) # check if the variable exists and duration unitis not missing
                if haskey(duration_lookup, row[v])
                    #println("$k $v")
                    if ismissing(row[k]) # if the numeric value is missing but the duration unit is present, we impute the numeric value using default
                        nvalue = default_duration[row[v]] * duration_lookup[row[v]]
                        row[v] = row[v] * "_non_specific__imputed"
                    else
                        nvalue = parse(Int, row[k]) * duration_lookup[row[v]]
                        #row[v] = "DAY"
                    end
                    row[k] = string(nvalue)
                    #println(nvalue)
                else
                    @warn "Unknown duration unit: '$(row[v])' $k $v"
                end
            end
        end
    end
    return data
end

"""
    read_variablemap(path,file)::AbstractDataFrame

Read a PyCrossVA configuration file and return a DataFrame with the contents.
Renames the columns to match the variablemappings table:
    * New Column Name = destination_variable - the variable_id of the new column
    * New Column Documentation = destination_description - Stored in the variable table
    * Source Column ID = from_variable - the variable_id of the source variable
    * Source Column Documentation = from_description - will be in the variables table
    * Relationship = operator - the operator to be used to create the new variable
    * Condition = operants - the operants to be used with the operator
    * Prerequisite = prerequisite_variable - the variable name of the prerequisite
"""
function read_variablemap(file)::AbstractDataFrame
    if !isfile(file)
        @error "File not found: $filepath"
        return DataFrame()
    end
    df = CSV.read(file, DataFrame; missingstring=["NA", ""])

    # Strip leading and trailing whitespace from all String values in the DataFrame
    for col in names(df)
        if eltype(df[!, col]) <: AbstractString || eltype(df[!, col]) <: Union{Missing, AbstractString}
        df[!, col] = [ismissing(x) ? missing : strip(String(x)) for x in df[!, col]]
        end
    end

    rename!(df, Dict("New Column Name" => "destination_variable",
        "New Column Documentation" => "destination_description",
        "Source Column ID" => "from_variable",
        "Source Column Documentation" => "from_description",
        "Relationship" => "operator",
        "Condition" => "operants",
        "Prerequisite" => "prerequisite_variable"))
    return df
end
"""
  * eq: is equal to
  * gt: is greater than
  * ge: is greater than or equal to
  * lt: is less than
  * le: is less than or equal to
  * ne: is not equal to # not yet implemented
  * contains: contains the substring
  * between: is between 2 numbers, inclusive
"""

"""
    eq(x, y)

    First try to convert x & y to Int or Float64 if they are strings.
    Then compare x and y and return "y" if they are equal, "n" if they are not, and "-" if either is missing.
"""
function eq(x, y)
    if ismissing(x) || ismissing(y)
        return "-"
    end
    if isequal(x, "missing") || isequal(y, "missing")
        return "-"
    end
    if tryparse(Int, x) !== nothing && tryparse(Int, y) !== nothing
        x = parse(Int, x)
        y = parse(Int, y)
    elseif tryparse(Float64, x) !== nothing && tryparse(Float64, y) !== nothing
        x = parse(Float64, x)
        y = parse(Float64, y)
    end
    return ifelse(isequal(x, y), "y", "n")
end

"""
    gt(x, y)

First try to convert x & y to Int or Float64 if they are strings.
Then compare x and y and return "y" if x is greater than y, "n" if it is not, and "-" if either is missing.
"""
function gt(x, y)
    if ismissing(x) || ismissing(y)
        return "-"
    end
    if isequal(x, "missing") || isequal(y, "missing")
        return "-"
    end
    if tryparse(Int, x) !== nothing && tryparse(Int, y) !== nothing
        x = parse(Int, x)
        y = parse(Int, y)
    elseif tryparse(Float64, x) !== nothing && tryparse(Float64, y) !== nothing
        x = parse(Float64, x)
        y = parse(Float64, y)
    end
    return ifelse(x > y, "y", "n")
end

"""
    ge(x,y)

First try to convert x & y to Int or Float64 if they are strings.
Then compare x and y and return "y" if x is greater than or equal to y, "n" if it is not, and "-" if either is missing.
"""
function ge(x, y)
    if ismissing(x) || ismissing(y)
        return "-"
    end
    if isequal(x, "missing") || isequal(y, "missing")
        return "-"
    end
    if tryparse(Int, x) !== nothing && tryparse(Int, y) !== nothing
        x = parse(Int, x)
        y = parse(Int, y)
    elseif tryparse(Float64, x) !== nothing && tryparse(Float64, y) !== nothing
        x = parse(Float64, x)
        y = parse(Float64, y)
    end
    return ifelse(x >= y, "y", "n")
end

"""
    lt(x, y)

First try to convert x & y to Int or Float64 if they are strings.
Then compare x and y and return "y" if x is less than y, "n" if it is not, and "-" if either is missing.
"""
function lt(x, y)
    if ismissing(x) || ismissing(y)
        return "-"
    end
    if isequal(x, "missing") || isequal(y, "missing")
        return "-"
    end
    if tryparse(Int, x) !== nothing && tryparse(Int, y) !== nothing
        x = parse(Int, x)
        y = parse(Int, y)
    elseif tryparse(Float64, x) !== nothing && tryparse(Float64, y) !== nothing
        x = parse(Float64, x)
        y = parse(Float64, y)
    end
    return ifelse(x < y, "y", "n")
end
"""
    le(x, y)

    First try to convert x & y to Int or Float64 if they are strings.
    Then compare x and y and return "y" if x is less or equal than y, "n" if it is not, and "-" if either is missing.
"""
function le(x, y)
    if ismissing(x) || ismissing(y)
        return "-"
    end
    if isequal(x, "missing") || isequal(y, "missing")
        return "-"
    end
    if tryparse(Int, x) !== nothing && tryparse(Int, y) !== nothing
        x = parse(Int, x)
        y = parse(Int, y)
    elseif tryparse(Float64, x) !== nothing && tryparse(Float64, y) !== nothing
        x = parse(Float64, x)
        y = parse(Float64, y)
    end
    return ifelse(x <= y, "y", "n")
end

function contains(x, y) 
    if ismissing(x) || ismissing(y)
        return "-"
    elseif occursin(y, x)
        return "y"
    else
        return "n"
    end
end
""" contains tests
contains("hello", "lo")
"""


"""
    between(x, y)

Whether x falls within the range y.  y must be a string of the form "a to b" where a and b are integers.
x will be converted to an integer if it is a string.
"""
function between(x, y)
    if ismissing(x) || ismissing(y)
        return "-"
    end
    if isequal(x, "missing") || isequal(y, "missing")
        return "-"
    end
    r = split(y, "to")
    if length(r) != 2
        error("Invalid range: $y")
    else
        if isa(x, AbstractString)
            x = parse(Float64, x)
        end
        a = parse(Float64, r[1])
        b = parse(Float64, r[2])
        return ifelse(x >= a && x <= b, "y", "n")
    end
end

"""
    OR(old,new)

    Evaluate OR condition
"""
function OR(old, new)
    if old == "y" || new == "y"
        return "y"
    elseif old == "-" && new == "-"
        return "-"
    else
        return "n"
    end
end

"""
    AND(x, y)

Evaluate AND condition
"""
function AND(x, y)
    if x == "y" && y == "y"
        return "y"
    elseif x == "-" && y == "-"
        return "-"
    else
        return "n"
    end
end

"""
   map_category(x,y) - y is a dictionnary

A function to map a variable into categories (relationship of the respondent to the deceased, death location....)
    y has to be formated as a dictionnary in the following manner:  "Hello world =a, B=b, C=a"

"""

function map_category(x, y::String)
    # Parse the mapping string into a Dict
    mapping = Dict{String,String}()
    for pair in split(y, ",")
        k, v = strip.(split(pair, "="))   # split each "A=a" into ["A","a"]
        mapping[k] = v
    end

    # Define lookup function
    lookup(val) = get(mapping, string(val), missing)

    # Apply to single value or array
    if isa(x, AbstractVector)
        return [lookup(xi) for xi in x]
    else
        return lookup(x)
    end
end




function prepare(x) # prepare strings to put them in lowercase
    if !ismissing(x)
        if isa(x, String)
            return strip(lowercase(x))
        else
            return string(x) # if it is an integer, we transform it into a string as it will be transformed again
        end
    else
        return x
    end
end
"""
    map_dataframe(fromdf::AbstractDataFrame, map::AbstractDataFrame, source_columns::AbstractDataFrame, row_identifier)::AbstractDataFrame

Convert fromdf (must be in wide format) to an output dataframe using the variablemap.
The output dataframe is in long format suitable for insertion into the data table.

Change the approach to converting line by line for mapping table, add support for prerequisite.
TODO: currently assume multiple conditions are OR. But can add column in mapping file to allow AND relationships. 
"""
function map_dataframe(fromdf::AbstractDataFrame, map_table::AbstractDataFrame, row_identifier::Symbol)::AbstractDataFrame

    # sort!(map_table, [:from_variable, :destination_variable]) #order matters for prerequisites #this has been commented out because ordered in a way that did not make sense
    N = size(fromdf, 1)

    #Create a new dataframe to store the output
    outdf = select(fromdf, [] => Returns(1:N) => :row_id, [] => Returns(string(row_identifier)) => :variable, row_identifier => ByRow(x -> string(x)) => :value)
    #
    for maprow in eachrow(map_table)
        @info "Processing: ", maprow

        if ismissing(maprow.from_variable) # if the from_variable is empty (there is no corresponding variable in the questionnaire) then we set the variable to missing "-"
            @info "Processing: ", "Missing from_variable"
            value = "-"

        else  # else we apply the transformation

            if in(maprow.from_variable, names(fromdf))
                sourcevalue = fromdf[!, Symbol(maprow.from_variable)]
            else
                sourcevalue = fill(missing, N)
                @info "$from_var (variable id $(maprow.from_id)) in mapping file not found in input dataframe, assign missing as default value."
            end
            sourcevalue = [prepare(x) for x in sourcevalue]
            operant = strip(lowercase(maprow.operants))
                
            # Construct the conversion expression and get converted values
            # println("Processing: Construct the conversion expression and get converted values ")
            value = [eval(Expr(:call, Symbol(strip(maprow.operator)), x, operant)) for x in sourcevalue] #strip(maprow.operator) - to make sure operator clean

            # If destination id already exists in output, meaning mapping is based on multiple conditions 
            if in(maprow.destination_variable, outdf.variable)
                # Update existing values
                prevvalue = filter(row -> row.variable .== maprow.destination_variable, outdf)
                sort!(prevvalue, :row_id)
                value = OR.(prevvalue.value, value)
                # Remove existing values
                filter!(row -> row.variable .!= maprow.destination_variable, outdf)
            end

            # Check whether prerequisites are met and adjust values

            if !ismissing(maprow.prerequisite_variable)
                #println("Processing: Check whether prerequisites are met and adjust values")
                #println("row.variable:", unique(outdf.variable), "// maprow.prerequisite_variable:", maprow.prerequisite_variable)
                prereq = filter(row -> row.variable .== maprow.prerequisite_variable, outdf)

                value = ifelse.(prereq.value .== "y", value, "-")
            end

        end

        #println("Processing: Append")
        append!(outdf, DataFrame(row_id=1:N,  #temporary row id for each row in fromdf
            variable=maprow.destination_variable,
            value=value))
    end
    #
    return outdf
end

function stripcrlf(df::AbstractDataFrame)::AbstractDataFrame
    return transform(df, :Value => ByRow(x -> !ismissing(x) ? replace(x, r"\r\n|\r|\n" => ";") : x) => :Value)
end

function add_individual_dates(df::AbstractDataFrame, deaths::AbstractDataFrame)::AbstractDataFrame
    s = select(deaths,
        :IIntID, :DoB => ByRow(x -> Dates.Date(x)) => :hdss_dob,
        :DoD => ByRow(x -> Dates.Date(x)) => :hdss_dod,
        :DoD => ByRow(x -> month(Dates.Date(x))) => :hdss_dod_month, #add month of death to determine season
        [:DoB, :DoD] => ByRow((x, y) -> !ismissing(x) && !ismissing(y) ? Dates.value(Dates.Date(y) - Dates.Date(x)) : missing) => :hdss_ageindays,
        :Sex => :hdss_sex) #fix age calculation to get days
    return innerjoin(s, df, on=:IIntID)
end

"""
    add_marriage(df::AbstractDataFrame)::AbstractDataFrame

Add partner status to the dataframe from the SurveillanceEpisodesYrAge_Partners table.
This function connects to the DuckDB database specified in the environment variable `EpisodesDb`
    Values in dta
    1 = No partnership
    2 = Married
    3 = Regular partnership
    4 = Casual partnership

    Labels shown in the csv
    Married = Married
    Regular = Regular partnership
    Casual = Casual relationship
    Widowed/Seperated = Widowed or seperated
    No partner = No partner

"""
function add_marriage(df::AbstractDataFrame)::AbstractDataFrame
    #partnerepisodes = read_dta(ENV["PARTNER_DTA"])
    partnerepisodes = DataFrame(load(ENV["PARTNER_DTA"]))
    p = combine(groupby(partnerepisodes, [:IndividualId]), :Episode => maximum => :Episodes)
    p = innerjoin(partnerepisodes, p, on=[:IndividualId])
    # Get just the most recent episode
    subset!(p, [:Episode, :Episodes] => ByRow((x, y) -> x == y))
    #map = read_dta(ENV["INDIVIDUAL_MAP"])
    map = DataFrame(load(ENV["INDIVIDUAL_MAP"]))
    p = innerjoin(p, map, on=:IndividualId)
    select!(p, :IIntId => :IIntID, :PartnerStatus)
    @info "Partner status $(nrow(p)) rows, columns: $(names(p))"
    #"
    # file = joinpath(ENV["DATA_PATH"], "csvfiles", "IndividualMap.csv")
    # map = CSV.read(file, DataFrame)
    # mapped = innerjoin(p, map, on=:IndividualUid)
    # select!(mapped, :IIntId => :IIntID, :PartnerStatus)
    return leftjoin(df, p, on=:IIntID)
end

function encodemissing(df::AbstractDataFrame, domainvalues::AbstractDataFrame)::AbstractDataFrame
    transform!(domainvalues, :Code => ByRow(x -> strip(x)) => :Code)
    values = copy(df)
    #Change all empty strings to missing
    values = transform(values, :Value => ByRow(x -> !ismissing(x) && x == "" ? missing : x) => :Value)
    domain_dict = Dict(
        d[1, :VarDomain] => Dict(row[:Code] => row[:SetMissing] for row in eachrow(d))
        for d in groupby(domainvalues, :VarDomain)
    )
    for row in eachrow(values)
        if !ismissing(row.VarDomain) && !ismissing(row.Value)
            domain = get(domain_dict, row.VarDomain, Dict())
            if haskey(domain, row.Value)
                if domain[row.Value] == 1 || (ismissing(row.Value) || strip(row.Value) == "")
                    row.Value = missing
                end
            else
                @info "Variable $(row.Variable) Value $(row.Value) not found in domain $(row.VarDomain)"
            end
        end
    end
    return values
end

# function encodenumeric(df::AbstractDataFrame, numericvalues::AbstractDataFrame)::AbstractDataFrame
#     numeric_dict = Dict(row[:VariableName] => row[:Condition] for row in eachrow(numericvalues))
#     values = copy(df)
#     for row in eachrow(values)
#         if haskey(numeric_dict, row.Variable)
#             value = tryparse(Int64, row.Value)
#             if !isnothing(value) && value >= numeric_dict[row.Variable]
#                 row.Value = missing
#             end
#         end
#     end
#     return values
# end


function encodenumeric(df::AbstractDataFrame, numericvalues::AbstractDataFrame)::AbstractDataFrame
    # Build a dictionary: VariableName => vector of (Relationship, Condition) tuples
    #empty dictionnary
    rule_dict = Dict{String, Vector{Tuple{String, Any}}}()

    # now we fill the dictionnary with the numericvalues missing mapping sheet
    for row in eachrow(numericvalues)
        var = row[:VariableName]
        rel = row[:Relationship] # same function as for mapping
        cond = row[:Condition]
        if !haskey(rule_dict, var)
            rule_dict[var] = [(rel, cond)]
        # one var can have several rules for missing, this allows to treat these rules successively
        else
            push!(rule_dict[var], (rel, cond))
        end
    end

    # Copy df to avoid mutating original
    values = copy(df)

    # we evaluate every variable
    for row in eachrow(values)
        var = row.Variable
        #is the variable in the dictionnary?
        if haskey(rule_dict, var)
            # We make sure the value is a string as our relationship function take strings as input
            x = isnothing(row.Value) || ismissing(row.Value) ? "" : string(row.Value)
            # x = if isa(row.Value, AbstractString)
            #     tryparse(Int64, row.Value)
            # else
            #     row.Value
            # end

            # x = tryparse(Int64, row.Value) #transform it in numerical value
            # x = isnothing(x) ? row.Value : x

            #for each variable, goes through all the rules that applies 
            for (rel, cond) in rule_dict[var]
                if isdefined(Main, Symbol(rel))
                    f = getfield(VAConvert, Symbol(rel)) # find function in VAConvert module
                    cond_str = isnothing(cond) || ismissing(cond) ? "" : string(cond) #transform condition in string as functions all take Relationship as strings
                    result = f(x, cond_str)
                    # result = eval(Expr(:call, Symbol(rel), x, cond))
                    if result == "y" # if the condition is met, set the value to missing
                        row.Value = missing 
                        break # if one rule is verified then no need to look through the others
                    end
                else
                    @warn "Function $(rel) not found for variable $(var)"
                end
            end
        end
    end

    return values
end



end # module VAConvert