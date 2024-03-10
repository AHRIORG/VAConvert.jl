using DataFrames

n = 10

df = DataFrame(IIntID = 11:n*2)

df2 = select(df, [] => Returns(1:n) => :row_id, [] => Returns("IIntID") => :variable, :IIntID => :value) 