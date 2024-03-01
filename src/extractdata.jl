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
acdis = connectdb(ENV["SERVER"], ENV["ACDIS"])

try
    df1 = sessions(acq, "VAQ") # read old questionnaire sessions
    df2 = sessions(acq, "VAP") # read new questionnaire sessions
    df3 = sessions(acq, "VCL") # read checklist sessions
    df = vcat(df1, df2, df3)
    @info "Sources\n"
    sources = combine(groupby(df, :Source), nrow => :n)
    pretty_table(io, sources; alignment=[:c, :r], show_subheader=false)
    deaths = unstack(df, :IIntID, :Source, :QSessionID)
    individuals = individual_deaths(acdis)
    @info "Deaths\n"
    dyr = combine(groupby(individuals, [:DoDYr]; sort = true), nrow => :n)
    pretty_table(io, dyr; alignment=[:c, :r], show_subheader=false)
    deaths = leftjoin(individuals, deaths, on=:IIntID, matchmissing = :error)
    transform!(deaths, :VAQ => ByRow(x -> ismissing(x) ? 0 : 1) => :hasVAQ,
                       :VAP => ByRow(x -> ismissing(x) ? 0 : 1) => :hasVAP,
                       :VCL => ByRow(x -> ismissing(x) ? 0 : 1) => :hasVCL)
    dyr = combine(groupby(deaths,:DoDYr; sort = true), :hasVAQ => sum => :nVAQ,
                                                       :hasVAP => sum => :nVAP,
                                                       :hasVCL => sum => :nVCL,
                                                       nrow => :nDeaths)
    pretty_table(io, dyr; alignment=[:c, :r, :r, :r, :r], show_subheader=false)
    flush(io)
    v = sessionvalues(acq, deaths, :VAQ)
    @info "$(nrow(v)) values written for source $(:VAQ)"
    l = sessionvalues(acq, deaths, :VCL)
    @info "$(nrow(l)) values written for source $(:VCL)"
    p = sessionvalues(acq, deaths, :VAP)
    @info "$(nrow(p)) values written for source $(:VAP)"
    values = vcat(v,l,p)
    flush(io)
    acq_variables = getvariables(acq)
    va_variables = combine(groupby(values, [:Variable]), nrow => :n)
    variables = innerjoin(acq_variables, va_variables, on=:Variable, matchmissing = :notequal)
    vadomains = combine(groupby(variables, [:VarDomain], skipmissing = true), nrow => :n)
    var_domains = getdomains(acq)
    domains = innerjoin(vadomains, var_domains, on=:VarDomain)
    # write arrow files
    outputdir = joinpath(ENV["DATA_PATH"], "arrowfiles")
    if !isdir(outputdir)
        mkpath(outputdir)
    end
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
    DBInterface.close!(acdis)
    elapsed = now() - start_time
    @info "===== Completed $(Dates.format(now(), "yyyy-mm-dd HH:MM")) duration $(canonicalize(Dates.CompoundPeriod(elapsed)))"
    flush(io)
    global_logger(old_logger)
    close(io)
end