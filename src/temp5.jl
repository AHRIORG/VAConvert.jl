using ConfigEnv
using Logging
using Dates
using DBInterface
using DataFrames
using PrettyTables
using Arrow
using CSV


dotenv()


  
vaq_arr = Arrow.Table("Z:\\RDM\\ResearchData\\Datasets\\AdHoc\\Verbal Autopsy\\VA Harmonisation\\arrowfiles\\VAData_VAQ.arrow") |> DataFrame
#freq_table = combine(groupby(vaq_arr, [:hdss_sex,:PartnerStatus]), nrow => :count)
freq_table = combine(groupby(vaq_arr, [:PartnerStatus]), nrow => :count)
println(freq_table)


vap_arr = Arrow.Table("Z:\\RDM\\ResearchData\\Datasets\\AdHoc\\Verbal Autopsy\\VA Harmonisation\\arrowfiles\\VAData_VAP.arrow") |> DataFrame
freq_table = combine(groupby(vap_arr, [:hdss_sex,:PartnerStatus]), nrow => :count)
println(freq_table)


vaw_arr = Arrow.Table("Z:\\RDM\\ResearchData\\Datasets\\AdHoc\\Verbal Autopsy\\VA Harmonisation\\arrowfiles\\VAData_VAW.arrow") |> DataFrame
freq_table = combine(groupby(vaw_arr, [:hdss_sex,:PartnerStatus]), nrow => :count)
println(freq_table)



cross_table = freqtable(df.Gender, df.Education)





vaq_csv = CSV.read(joinpath(outputdir, "VAData_VAQ.csv", DataFrame))
freq_table = combine(groupby(vaq_arr, :PartnerStatus), nrow => :count)
println(freq_table)




     Arrow.write(joinpath(ENV["DATA_PATH"], "arrowfiles", "VAData_$source.arrow"), f)
    CSV.write(joinpath(outputdir, "VAData_$source.csv"), f)

# deaths = Arrow.Table(joinpath(ENV["DATA_PATH"], "arrowfiles/VAIndividualDeaths.arrow")) |> DataFrame
# sexvalues = combine(groupby(deaths,:Sex), nrow => :n)
# pretty_table(sexvalues; alignment=[:c, :r], show_subheader=false)
vadata = Arrow.Table(joinpath(ENV["DATA_PATH"], "arrowfiles/VAVariableValues.arrow")) |> DataFrame
numericvalues = CSV.read("mapping/NumericVariables_with_missing.csv", DataFrame)
# sort!(numericvalues, [:VariableName])
# numeric_dict = Dict(row[:VariableName] => row[:Condition] for row in eachrow(numericvalues))
recoded = encodenumeric(vadata, numericvalues)
subset!(recoded, :Variable => ByRow(x -> x == "ih_duration_1"))


