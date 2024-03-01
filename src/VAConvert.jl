# SPDX-License-Identifier: MIT

module VAConvert

using DBInterface
using ODBC
using DataFrames
using CSV
using Logging
# Write your package code here.
export readtable, connectdb, sessions, individual_deaths, sessionvalues, getvariables, getdomains

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
    return nothing
end

end
