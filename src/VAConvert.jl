# SPDX-License-Identifier: MIT

module VAConvert

using DBInterface
using ODBC
using DataFrames
using CSV
using Logging
# Write your package code here.
export readtable, connectdb, sessions, individual_deaths, sessionvalues, getvariables, getdomains, 
        convert_durations, read_variablemap

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
            CAST(VarValue AS varchar) Value
        FROM dbo.QVarValuesCode
        WHERE QSessionID = ?
        UNION
        SELECT
            QSessionID,
            Variable,
            CAST(VarValue AS varchar) Value
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
            CAST(VarValue AS varchar) Value
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
            CAST(VarValue AS varchar) Value
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
            insertcols!(rf, :QSessionID, :IIntID => df[i, :IIntID], :Source => String(col))
            i += 1
            for j in i:nrow(df)
                if !ismissing(df[j, col])
                    params = fill(df[j, col], 7)
                    f = DBInterface.execute(stmt, params) |> DataFrame
                    insertcols!(f, :QSessionID, :IIntID => df[j, :IIntID], :Source => String(col))
                    append!(rf, f)
                end
            end
        end
        return rf
    end
    return DataFrame()
end
function convert_durations(variables::AbstractDataFrame, data::AbstractDataFrame)::AbstractDataFrame
    duration_map = Dict{String, Union{Number, Missing}("NAD" => missing, "DFT" => missing, "MIS" => missing, "R"=> "missing",
    "DAY" => 1, "WEE" => 7, "MON" => 30, "YEA" => 365, "U" => missing,
    "H" => 1/24, "M" => 30, "D" => 1, "Y" => 365, "W" => 7)}
    duration_domains = ["VA_Units","VAPUnits","VAWUnit1","VAWUnit2","VAWUnit3"]
    duration_variables = subset(variables, in.(variables[!, :VarDomain], duration_domains))[:, :Variable]
    for row in eachrow(subset(data, in.(data[!, :Variable], duration_variables)))
        if row[:Value] != missing
            if row[:Variable] in duration_variables
                data[row, :Value] = row[:Value] * duration_map[row[:Variable]]
            end
        end
    end

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
function read_variablemap(path, file)::AbstractDataFrame
    filepath = joinpath(path, file)
    if !isfile(filepath)
        @error "File not found: $filepath"
        return DataFrame()
    end
    df = CSV.read(joinpath(path, file), DataFrame)
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
eq(x, y) = ifelse(ismissing(x) || ismissing(y), "-", ifelse(isequal(x, y), "y", "n"))
gt(x, y) = ifelse(ismissing(x) || ismissing(y), "-", ifelse(x > y, "y", "n"))
ge(x, y) = ifelse(ismissing(x) || ismissing(y), "-", ifelse(x >= y, "y", "n"))
lt(x, y) = ifelse(ismissing(x) || ismissing(y), "-", ifelse(isless(x,y), "y", "n"))
le(x, y) = ifelse(ismissing(x) || ismissing(y), "-", ifelse(x <= y, "y", "n"))
contains(x, y) = ifelse(ismissing(x) || ismissing(y), "-", ifelse(Base.contains(x, y), "y", "n"))

"""
    between(x, y)

Whether x falls within the range y.  y must be a string of the form "a to b" where a and b are integers.
x will be converted to an integer if it is a string.
"""
function between(x, y)
    if ismissing(x) || ismissing(y)
        return "-"
    else
        r = split(y, "to")
        if length(r) != 2
            error("Invalid range: $y")
        else
            if isa(x, AbstractString)
                x = parse(Int64, x)
            end
            a = parse(Int64, r[1])
            b = parse(Int64, r[2])
            return x >= a && x <= b ? "y" : "n"
        end
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

end
