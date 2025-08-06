using ConfigEnv
using Logging
using Dates
using VAConvert
using DBInterface
using DataFrames
using PrettyTables
using Arrow

#get environment variables
dotenv()

#region Setup Logging
logfile = open("logs/extract_log.log", "w")
io = IOContext(logfile, :displaysize => (100, 100))
logger = SimpleLogger(io)
old_logger = global_logger(logger)
@info "===== Execution started $(Dates.format(now(), "yyyy-mm-dd HH:MM"))"
flush(io)
start_time = now()
#endregion

acq = connectdb(ENV["SERVER"], ENV["DATABASE"])
hdss = connectdb(ENV["HDSS_SERVER"], ENV["HDSS"])
flush(io)
try
    outputdir = joinpath(ENV["DATA_PATH"], "arrowfiles")
    if !isdir(outputdir)
        mkpath(outputdir)
    end
    df1 = sessions(acq, "VAQ") # read old questionnaire sessions
    df2 = sessions(acq, "VAP") # read new questionnaire sessions
    df3 = sessions(acq, "VCL") # read checklist sessions
    df4 = sessions(acq, "VAW") # read WHO2020 sessions
    df5 = sessions(acq, "VAN") # read narrative sessions
    df = vcat(df1, df2, df3, df4, df5)
    @info "Sources\n"
    flush(io)
    sources = combine(groupby(df, :Source), nrow => :n)
    pretty_table(io, sources; alignment=[:c, :r], show_subheader=false)
    deaths = unstack(df, :IIntID, :Source, :QSessionID)
    individuals = individual_deaths(hdss)
    @info "Deaths\n"
    dyr = combine(groupby(individuals, [:DoDYr]; sort=true), nrow => :n)
    pretty_table(io, dyr; alignment=[:c, :r], show_subheader=false)
    deaths = leftjoin(individuals, deaths, on=:IIntID, matchmissing=:error)
    transform!(deaths, :VAQ => ByRow(x -> ismissing(x) ? 0 : 1) => :hasVAQ,
        :VAP => ByRow(x -> ismissing(x) ? 0 : 1) => :hasVAP,
        :VCL => ByRow(x -> ismissing(x) ? 0 : 1) => :hasVCL,
        :VAW => ByRow(x -> ismissing(x) ? 0 : 1) => :hasVAW,
        :VAN => ByRow(x -> ismissing(x) ? 0 : 1) => :hasVAN)
    dyr = combine(groupby(deaths, :DoDYr; sort=true), 
        :hasVAQ => sum => :nVAQ,
        :hasVAP => sum => :nVAP,
        :hasVCL => sum => :nVCL,
        :hasVAW => sum => :nVAW,
        :hasVAN => sum => :nVAN,
        nrow => :nDeaths)
    pretty_table(io, dyr; alignment=[:c, :r, :r, :r, :r, :r, :r], show_subheader=false)
    flush(io)
    v = sessionvalues(acq, deaths, :VAQ)
    @info "$(nrow(v)) values written for source $(:VAQ)"
    l = sessionvalues(acq, deaths, :VCL)
    @info "$(nrow(l)) values written for source $(:VCL)"
    p = sessionvalues(acq, deaths, :VAP)
    @info "$(nrow(p)) values written for source $(:VAP)"
    w = sessionvalues(acq, deaths, :VAW)
    @info "$(nrow(w)) values written for source $(:VAW)"
    n = sessionvalues(acq, deaths, :VAN)
    Arrow.write(joinpath(outputdir, "VANValues.arrow"), n, compress=:zstd)
    @info "$(nrow(n)) values written for source $(:VAN)"
    values = vcat(v, l, p, w, n)
    flush(io)
    variables = getvariables(acq)
    domains = getdomains(acq)
    # write arrow files
    Arrow.write(joinpath(outputdir, "VAVariables.arrow"), variables, compress=:zstd)
    @info "Variables $(nrow(variables)) written"
    Arrow.write(joinpath(outputdir, "VAVariableValues.arrow"), values, compress=:zstd)
    @info "Values $(nrow(values)) written"
    Arrow.write(joinpath(outputdir, "VAIndividualDeaths.arrow"), deaths, compress=:zstd)
    @info "Deaths $(nrow(deaths)) written"
    Arrow.write(joinpath(outputdir, "VAVariableDomains.arrow"), domains, compress=:zstd)
    @info "Domains $(nrow(domains)) written"
finally
    DBInterface.close!(acq)
    DBInterface.close!(hdss)
    elapsed = now() - start_time
    @info "===== Completed $(Dates.format(now(), "yyyy-mm-dd HH:MM")) duration $(canonicalize(Dates.CompoundPeriod(elapsed)))"
    flush(io)
    global_logger(old_logger)
    close(io)
end