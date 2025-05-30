# SPDX-License-Identifier: MIT

module VAConvert

using DBInterface
using ODBC
using DataFrames
using CSV
using Logging
using Dates
# Write your package code here.
export readtable, connectdb, sessions, individual_deaths, sessionvalues, getvariables, getdomains,
    read_variablemap, convert_durations!, map_dataframe, stripcrlf, add_individual_dates

function readtable(server, database, table)
    conStr = "Driver=ODBC Driver 18 for SQL Server;SERVER=$server;DATABASE=$database;Trusted_Connection=yes;TrustServerCertificate=yes"
    con = ODBC.Connection(conStr)
    return DBInterface.execute(con, "SELECT * FROM $table") |> DataFrame
end

function connectdb(server, database)
    conStr = "Driver=ODBC Driver 18 for SQL Server;SERVER=$server;DATABASE=$database;Trusted_Connection=yes;TrustServerCertificate=yes"
    con = ODBC.Connection(conStr)
    return con
end

function getvariables(con)
    sql = """
    SELECT
      Variable, Prompt, VarDomain, VarGroup
    FROM dbo.Variables;
    """
    df = DBInterface.execute(con, sql) |> DataFrame
    return df
end

function getdomains(con)
    sql = """
    SELECT
      VarDomain,Code,Caption,Sequence
    FROM dbo.VarDomainCodes;
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
        I.IntID IIntID,
        I.Sex,
        SE.AssignedDate DoB,
        EE.AssignedDate DoD,
        YEAR(EE.AssignedDate) DoDYr
    FROM dbo.RegisteredIndividuals I
        JOIN dbo.Events SE ON (I.Delivery=SE.IntID)
        JOIN dbo.Events EE ON (I.EndEvent=EE.IntID)
    WHERE EE.Type = 'DTH'
    """
    df = DBInterface.execute(con, sql) |> DataFrame
    return df
end

function sessionvalues(con, df::AbstractDataFrame, col::Symbol)::DataFrame
    sql = """
        SELECT
            QSessionID,
            Variable,
            TRIM(VarValue) Value
        FROM dbo.QVarValuesCode
        WHERE QSessionID = ?
        UNION
        SELECT
            QSessionID,
            Variable,
            CONVERT(VARCHAR, VarValue, 23) Value
        FROM dbo.QVarValuesDate
        WHERE QSessionID = ?
        UNION
        SELECT
            QSessionID,
            Variable,
            CAST(VarValue AS varchar) Value
        FROM dbo.QVarValuesFloat
        WHERE QSessionID = ?
        UNION
        SELECT
            QSessionID,
            Variable,
            CAST(VarValue AS varchar) Value
        FROM dbo.QVarValuesInt
        WHERE QSessionID = ?
        UNION
        SELECT
        QSessionID,
            Variable,
            TRIM(VarValue) Value
            FROM dbo.QVarValuesStr
        WHERE QSessionID = ?
        UNION
        SELECT
            QSessionID,
            Variable,
            CAST(VarValue AS varchar) Value
        FROM dbo.QVarValuesText
        WHERE QSessionID = ?
        UNION
        SELECT
            QSessionID,
            Variable,
            CONVERT(VARCHAR, AssignedDate, 23) Value
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
    convert_durations!(data::AbstractDataFrame)::AbstractDataFrame

Take a verbal autopsy file in flat format and normalise the duration variables to days.
"""
function convert_durations!(data::AbstractDataFrame)::AbstractDataFrame
    duration_lookup = Dict{String,Union{Number,Missing}}("NAD" => missing, "DFT" => missing, "MIS" => missing, "R" => missing,
        "DAY" => 1, "WEE" => 7, "MON" => 30, "YEA" => 365, "U" => missing, "QRY" => missing, "MIN" => 1 / 1440, "HOR" => 1 / 24,
        "H" => 1 / 24, "M" => 30, "D" => 1, "Y" => 365, "W" => 7, "HRS" => 1 / 24, "YRS" => 365, "DKN" => missing, "HOU" => 1 / 24)
    duration_data = CSV.read(joinpath(ENV["MAPPING_PATH"], "VA_Duration_Unit_equivalence.csv"), DataFrame)
    duration_map = Dict{String,String}(zip(duration_data[!, :Variable_numeric], duration_data[!, :Variable_unit]))
    for row in eachrow(data)
        for (k, v) in duration_map
            if hasproperty(row, k) && !ismissing(row[k]) && !ismissing(row[v])
                if haskey(duration_lookup, row[v])
                    #println("$k $v")
                    nvalue = parse(Int, row[k]) * duration_lookup[row[v]]
                    row[k] = string(nvalue)
                    row[v] = "DAY"
                    #println(nvalue)
                else
                    @warn "Unknown duration unit: '$(row[v])' $k $v"
                end
            end
        end
    end
    return data
end

#
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
    df = CSV.read(file, DataFrame)
    rename!(df, Dict("New Column Name" => "destination_variable",
        "New Column Documentation" => "destination_description",
        "Source Column ID" => "from_variable",
        "Source Column Documentation" => "from_description",
        "Relationship" => "operator",
        "Condition" => "operants",
        "Prerequisite" => "prerequisite_variable"))
    return df
end
#=
  * eq: is equal to
  * gt: is greater than
  * ge: is greater than or equal to
  * lt: is less than
  * le: is less than or equal to
  * ne: is not equal to
  * contains: contains the substring
  * between: is between 2 numbers, inclusive
=#
# 

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
contains(x, y) = ifelse(ismissing(x) || ismissing(y), "-", ifelse(Base.contains(x, y), "y", "n"))

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
        a = parse(Int64, r[1])
        b = parse(Int64, r[2])
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
function prepare(x) # prepare strings to put them in lowercase
    if !ismissing(x)
        if isa(x, String)
            return strip(lowercase(x))
        else
            return x # if it is an integer
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
         println("Processing: ", maprow)
        
        if ismissing(maprow.from_variable) # if the from_variable is empty (there is no corresponding variable in the questionnaire) then we set the variable to missing "-"
           println("Processing: ", "Missing from_variable")
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
            value = [eval(Expr(:call, Symbol(maprow.operator), x, operant)) for x in sourcevalue]

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
    s = select(deaths, :IIntID, :DoB => ByRow(x -> Dates.Date(x)) =>:acdis_dob, :DoD => ByRow(x -> Dates.Date(x)) => :acdis_dod, 
    [:DoB, :DoD] => ByRow((x,y) -> !ismissing(x) && !ismissing(y) ? Dates.value(Dates.Date(y) - Dates.Date(x)) : missing) => :acdis_ageindays) #fix age calculation to get days
    return innerjoin(s, df, on=:IIntID)
end

end



