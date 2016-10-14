isdefined(Base, :__precompile__) && __precompile__()
#__precompile__()

module StatModel

using Compat, DataArrays, GLM, DataFrames, Distributions, Showoff, StatsBase, DataStructures, StatsFuns, JSON

import DataArrays,  GLM, DataFrames, Distributions, Showoff, StatsBase, DataStructures, StatsFuns, JSON
import StatsBase: coef, coeftable, df, deviance, fit!, fitted, loglikelihood, model_response, nobs, vcov
import Base: cond, std
import Distributions: Bernoulli, Binomial, Poisson, Gamma
import GLM: LogitLink, LogLink, InverseLink
import DataFrames: @~

export
       @~,
       vif,
       tst2

include("diagnostics.jl")
include("misc.jl")
include("modsel.jl")
#include("RConvert5.1.jl")

function test2() 
end

end # module
