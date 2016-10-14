addprocs(5)
using DataStructures, DataArrays , DataFrames, StatsFuns, GLM , JuMP,NLopt, HDF5, JLD, Distributions, MixedModels, RCall, StatsBase, xCommon
@everywhere using DataStructures, DataArrays , DataFrames, StatsFuns, GLM , JuMP,NLopt, HDF5, JLD, Distributions, MixedModels, RCall, StatsBase, xCommon

function loadDF()
    #cd("/media/u01/analytics/scoring/Healthy/modeling5/")
    #df_data = readtable("csv_final_healthychoice1_I3.csv",header=true); #lowercase(df_data)
    #df_h = readtable("Headers_healthy_choice3.csv",header=false); #lowercase(df_data)
    #names!(df_data, convert(Array{Symbol}, df_h[:x1]) ) 
    
    #cd("/media/u01/analytics/scoring/CDW5_792/")
    cd("/mnt/resource/analytics/CDW5_792/")
    df_data = readtable("csv_final_cdw5_792.csv",header=false);
    df_h = readtable("Headers_cdw5.csv",header=false);
    
    #df_data = readtable("/media/u01/analytics/scoring/Natural_choice_5_851_modeling/csv_final_nc_851",header=false);
    #df_h = readtable("/media/u01/analytics/scoring/Natural_choice_5_851_modeling/Headers_NC5.csv",header=false);
  
    names!(df_data, convert(Array{Symbol}, df_h[:x1]) )
end
df_in=loadDF()


function Pre_out(df_in::DataFrame)
     df_cat_pre = df_in[df_in[:Buyer_Pre_P0] .==1 , [:Prd_0_Net_Pr_PRE,:experian_id]]
     df_cat_pos = df_in[(df_in[:Buyer_Pre_P0] .==0) & (df_in[:Buyer_Pos_P0] .==1) , [:experian_id]]
     median_df = median(df_cat_pre[:Prd_0_Net_Pr_PRE])
     df_cat_pre[:Prd_0_Net_Pr_PRE_med1] = abs(df_cat_pre[:Prd_0_Net_Pr_PRE]-median_df)
     MAD=median(df_cat_pre[:Prd_0_Net_Pr_PRE_med1])
     df_cat_pre[:Prd_0_Net_Pr_PRE_med2] = (0.6745*(df_cat_pre[:Prd_0_Net_Pr_PRE]-median_df))/MAD
     df_cat_pre_zsc = df_cat_pre[abs(df_cat_pre[:Prd_0_Net_Pr_PRE_med2]) .< 3.5,:]
     df_cat_pre_zsc_1 = df_cat_pre_zsc[:,[:experian_id]]
     df_cat_pre_zsc_f = vcat(df_cat_pos,df_cat_pre_zsc_1)
     df_in_pout =  join(df_in, df_cat_pre_zsc_f, on =  :experian_id , kind = :inner);
end
df_in_pout = Pre_out(df_in);



function isValid(df_data::DataFrame,cfg::OrderedDict)
    function checkValid(iarr::Array{Symbol})  length(setdiff(iarr, names(df_data))) > 0 ? false : true end
    !checkValid(cfg[:all_mandatory_vars]) ? error("ERROR: Not all mandatory_vars in dataset ") : println("VALID : mandatory_vars") 
    !checkValid(cfg[:scoring_vars]) ? error("ERROR: Not all scoring_vars in dataset ") : println("VALID : scoring_vars") 
end


const cfgDefaults=OrderedDict( :P2_Competitor => true
                        ,:pvalue_lvl => 0.20  #pvalue_lvl = 0.20 
                        ,:excludedBreaks => String[]    #["estimated_hh_income","hh_age","number_of_children_in_living_un","person_1_gender"]
                        ,:excludedLevels => ["none"]
                        ,:excludedKeys => String[]
                        ,:exposed_flag_var => :exposed_flag
                        ,:sigLevel => "0.2"
                        ,:random_demos => [:estimated_hh_income,:hh_age,:number_of_children_in_living_Un,:person_1_gender]
                        ,:random_campaigns => []
                        ,:dropvars => [:exposed_flag]
                        ,:scoring_vars => [:Prd_1_Net_Pr_PRE,:Prd_1_Net_Pr_POS,:Buyer_Pos_P0,:Buyer_Pre_P0]
                        ,:occ_y_var => :Trps_POS_P1
                        ,:occ_logvar => :Trps_PRE_P1
                        ,:dolocc_y_var => :Dol_per_Trip_POS_P1
                        ,:dolocc_logvar => :Dol_per_Trip_PRE_P1
                        ,:pen_y_var => :Buyer_Pos_P1
                        ,:pen_logvar => :Buyer_Pre_P1
                        ,:TotalModelsOnly=>false
                       )

#NatC : cfgDefaults[:random_demos] = [:estimated_hh_income,:hh_age,:person_1_gender]
#cfgDefaults[random_campaigns] = [:Targeting_fct,:Media_Source_fct,:Media_Type_fct,:Publisher_fct,:Creative_fct]        
cfgDefaults[:random_demos] = [:estimated_hh_income,:hh_age,:number_of_children_in_living_Un,:person_1_gender]
cfgDefaults[:random_campaigns] = [:Publisher_Fct1,:Targeting_Fct1]


function getCFG(df_in::DataFrame)
    cfg=xCommon.loadCFG(cfgDefaults, pwd()*"/app.cfg")
    cfg[:exposed_flag_var] = :exposed_flag_new                  # Go In app.cfg
    #cfg[:random_campaigns] = [:Publisher_Fct1,:Targeting_Fct1]  # Go In app.cfg

    cfg[:allrandoms] = vcat(cfg[:random_demos],cfg[:random_campaigns])
    #cfg[:ProScore] = grep1("MODEL",names(df_in))   
    ps = filter(x->contains(string(x), "MODEL"), names(df_in)) # Set the ProScore variable in the dataset   #push!(cfg[:all_mandatory_vars], cfg[:ProScore])
    cfg[:ProScore] = length(ps) > 0 ? ps[1] : :MISSING_MODEL_VARIABLE_IN_DATA
    cfg[:num_products] = length( grep("Buyer_Pre_P",names(df_in)))-1  # get number of products in the data
    #rework vars after loading cfg
    cfg[:random_campaigns] = intersect(cfg[:random_campaigns],names(df_in))
 
    cfg[:occ_logvar_colname] = Symbol("LOG_"*string(cfg[:occ_logvar]))
    cfg[:dolocc_logvar_colname] = Symbol("LOG_"*string(cfg[:dolocc_logvar]))
    cfg[:pen_logvar_colname] = Symbol("LOG_"*string(cfg[:pen_logvar]))
    
    cfg[:all_mandatory_vars] = vcat( [:experian_id,
                                      cfg[:pen_y_var],cfg[:pen_logvar],
                                      cfg[:occ_y_var], cfg[:occ_logvar],
                                      cfg[:dolocc_y_var], cfg[:dolocc_logvar]
                                     ]
                                     , cfg[:random_demos]
                                   )
    return cfg
end
cfg=getCFG(df_in)

isValid(df_in,cfg)



function reworkCFG!(df_in::DataFrame,cfg::OrderedDict)
    xflags=[cfg[:exposed_flag_var],:exposed_flag,:Nonbuyer_Pre_P1]  # :Nonbuyer_Pre_P1 no longer used
    features = setdiff(names(df_in),xflags)
    if :state in names(df_in)
        cfg[:xVarsDemos]=vcat([:experian_id, :banner, :Prd_0_Qty_PRE],features[findfirst(features, :state):findfirst(features, :Mosaic)])   # exclude demos between....
    else
        cfg[:xVarsDemos]=Symbol[]
    end
    cfg[:xVarsDemos]=setdiff(cfg[:xVarsDemos],[:person_1_gender,:number_of_children_in_living_Un]) # exclude person, # from non-used demos
    cfg[:xVarsPost] = grep(["POS","Pos","Buyer_Pre_","Nonbuyer_Pre_"],features)   #exclude POST variables
    cfg[:iVarsPREPOS] = grep(["PRE_POS","Pre_Pos"],features) 
    features=setdiff(features, setdiff(  vcat(cfg[:xVarsDemos],cfg[:xVarsPost]) ,cfg[:iVarsPREPOS])  )
    cfg[:xVarsP0] =  setdiff(grep("0", features ),[cfg[:ProScore]] ) #exclude category variables(exclude P0's)  
    features=setdiff(features,cfg[:xVarsP0])
    cfg[:xVarsReports] = grep(["Perc_","Pr_per_"],features)  #exclude Reporting vars
    features=setdiff(features,cfg[:xVarsReports])
    cfg[:xvars] = vcat(xflags,cfg[:xVarsDemos], cfg[:xVarsPost],cfg[:xVarsP0], cfg[:xVarsReports],cfg[:dropvars])
    features=setdiff(features,cfg[:dropvars])
    cfg[:ivars] = vcat(cfg[:iVarsPREPOS],cfg[:all_mandatory_vars],cfg[:scoring_vars])
    cfg[:ALL_vars_to_exclude] = setdiff(cfg[:xvars], cfg[:ivars])
    df_in[:group] = df_in[cfg[:exposed_flag_var]]
    df_in[:panid] = df_in[:experian_id] 
    features = setdiff(unique(vcat(features,cfg[:iVarsPREPOS],cfg[:all_mandatory_vars],cfg[:scoring_vars],[:group,:panid])  ) ,[:experian_id] )
    cfg[:negativevars] = grep(vec(hcat([["P"*string(i),string(i)*"_"] for i=3:cfg[:num_products]]...)),features)   # get variables that need to have negative sign
    cfg[:positivevars] = grep(["P1", "1_","MODEL"], features)    # get variables that need to have positive sign
    if cfg[:P2_Competitor] == true  
        cfg[:negativevars] = unique(vcat(cfg[:negativevars],grep(["P2","2_"],features))) 
    else
        cfg[:positivevars] = unique(vcat(cfg[:positivevars],grep(["P2","2_"],features))) 
    end
    return df_in[features]
end

dfd = reworkCFG!(df_in,cfg)



#######################################
#--------- Data Manipulation ---------#
#######################################

function data_Prep(dfd::DataFrame, cfg::OrderedDict)
    dfd[:isO]=false
    dfd[:whyO]="" 
    dfd[dfd[:number_of_children_in_living_Un].>=4,:number_of_children_in_living_Un] = 4  # aggregate #of children for 4+ L_114
    if typeof(dfd[:group]) in [DataArray{String,1}] 
        dfd[ findin(dfd[:group],["//N","\\N"]), :group] = "0" 
        dfd[DataArrays.isna(dfd[:group]), :group]="0"
        dfd[:group] = [parse(Int64,s) for s = dfd[:group]]
    else
        dfd[ DataArrays.isnan(dfd[:group]), :group] = 0
    end
    vars = DataFrame(names=names(dfd),eltypes=eltypes(dfd))
    for c in setdiff(vars[findin(vars[:eltypes],[String]),:names],cfg[:allrandoms]) # set variables as.numeric and replace NA's with zero
        print("Convert String: String->Numeric: ",c)
        try dfd[c] = map( x -> DataArrays.isna.(x) ?  NaN : convert(Float64, x)  , dfd[c]) catch e println("  (failed)") end  #NA to NaN
        try dfd[c] = convert(Array{Float64}, dfd[c]) catch e end   # To Float64
    end
    vars = DataFrame(names=names(dfd),eltypes=eltypes(dfd))
    for c in setdiff(vars[findin(vars[:eltypes],[Float64]),:names],cfg[:allrandoms])  # replace NaN's with zero for numeric variables 
        println("Replace Float64 NaN (0.0): ",c)
        dfd[ DataArrays.isnan(dfd[c]), c] = 0.0
    end
    for c in  setdiff(vars[findin(vars[:eltypes],[Int64]),:names],cfg[:allrandoms])    
        println("Replace Int64 NaN (0) : ",c)
        dfd[ DataArrays.isnan(dfd[c]), c] = 0
    end
    # NOTE : Do QCs here
    dfd[dfd[:person_1_gender].=="U",:isO] = true   # remove HHs with no gender info
    dfd[dfd[:person_1_gender].=="U",:whyO] = "person_1_gender=U; remove HHs with no gender info"
    dfd[findin(dfd[:estimated_hh_income],["U","L"]),:estimated_hh_income]="L" # aggregate U and L levels of hh income

    for r in cfg[:random_campaigns]    # check and drop exposed HHs with no publisher info or non-exposed HHs with publisher info
        dfd[findin(dfd[r],["\\N","NULL","0","NONE"])  ,r] ="none"
        dfd[ (dfd[:isO].==false) & (dfd[r].!="none") & (dfd[:group].==0) ,:whyO] = "non exposed HHs with publisher info"
        dfd[ (dfd[:isO].==false) & (dfd[r].!="none") & (dfd[:group].==0) ,:isO] = true
        println(r," non exposed HHs with publisher info : ",nrow(dfd[dfd[:whyO].=="non exposed HHs with publisher info",:] )   )
        dfd[ (dfd[:isO].==false) & (dfd[r].=="none") & (dfd[:group].!=0) ,:whyO] = "exposed HHs with no publisher info"   
        dfd[ (dfd[:isO].==false) & (dfd[r].=="none") & (dfd[:group].!=0) ,:isO] = true
        println(r," exposed HHs with no publisher info : ",nrow(dfd[dfd[:whyO].=="exposed HHs with no publisher info",:] )   )
    end
    # segments for outliers detection
    dfd[:data_NB_NE_B] = false
    dfd[ (dfd[:Buyer_Pre_P1].==0 ) & (dfd[:group].==0 ) & (dfd[:Buyer_Pos_P1].==1 ) ,:data_NB_NE_B] = true
    dfd[:data_B_E_NB] = false
    dfd[ (dfd[:Buyer_Pre_P1].==1 ) & (dfd[:group].==0 ) & (dfd[:Buyer_Pos_P1].==0 ) ,:data_B_E_NB] = true
    dfd[:pen_reduction] = false
    dfd[ (dfd[:Buyer_Pre_P1].==1) & (dfd[:group].==0) & (dfd[:Buyer_Pos_P1].==0 )  ,:pen_reduction] = true
    dfd[:occ_reduction] = false
    dfd[ (dfd[:group].==0) & (dfd[:Buyer_Pos_P1].==1) & (dfd[:Trps_POS_P1].< dfd[:Trps_PRE_P1] ) ,:occ_reduction] = true
    dfd[:dolocc_reduction] = false
    dfd[  (dfd[:group].==0) & (dfd[:Buyer_Pos_P1].==1) & (dfd[:Dol_per_Trip_POS_P1].< dfd[:Dol_per_Trip_PRE_P1] )  , :dolocc_reduction] = true
    return dfd[dfd[:isO].==false, : ]   #[setdiff(names(dfd),[:isO,:whyO])] 
end

dfd = data_Prep(dfd, cfg);




function MatchMe(dfd::DataFrame,cfg::OrderedDict)
    df=dfd[dfd[:isO].==false,:]
    df_exp     = df[df[:group].==1,:]
    df_unexp   = df[df[:group].==0,:]
    df_exp_dim   = nrow(df_exp)
    df_unexp_dim = nrow(df_unexp)
    new_unexp_dim = df_unexp_dim*(df_unexp_dim>2000000 ? 0.3 : df_unexp_dim>1000000 ? 0.4 : df_unexp_dim>750000 ? 0.6 : 0.7)
    if length(string(cfg[:ProScore])) == 0
        df_unexp_1 =  df[(df[:group].==0)&(df[:Buyer_Pre_P1].==1),:]
        df_unexp_0 =  df[(df[:group].==0)&(df[:Buyer_Pre_P1].==0),:]
        
        df_exp_1_dim = nrow(df[(df[:group].==1)&(df[:Buyer_Pre_P1].==1),:])
        df_exp_0_dim = nrow(df[(df[:group].==1)&(df[:Buyer_Pre_P1].==0),:])
        df_unexp_1_dim = nrow(df_unexp_1)
        df_unexp_0_dim =  nrow(df_unexp_0)     
        dim_sample0 = round(Int64, (new_unexp_dim-df_exp_dim  ) / (1+(df_exp_1_dim / df_exp_0_dim)) )
        dim_sample1 = round(Int64, new_unexp_dim - df_exp_dim - dim_sample0)    
        
        new_df_unexp_1 = df_unexp_1[sample(1:size(df_unexp_1,1), dim_sample1 ),:]
        new_df_unexp_0 = df_unexp_0[sample(1:size(df_unexp_0,1), dim_sample0 ),:]
        dfd_sample  = vcat(df_exp,new_df_unexp_1,new_df_unexp_0)
    elseif length(string(cfg[:ProScore])) > 0    
        sample_control_data=similar(df_unexp, 0)
        for (key, value) in countmap(df_exp[cfg[:ProScore]])
            sample_dim=round(Int64,new_unexp_dim*(value/df_exp_dim))
            temp_data = df_unexp[df_unexp[cfg[:ProScore]].==key,:]
            samp_data = temp_data[sample(1:size(temp_data,1), sample_dim, replace=false),:]
            sample_control_data = vcat(sample_control_data,    samp_data   )
        end
        
        sample_data = vcat(sample_control_data,df_exp)
        sample_df_unexp = sample_data[sample_data[:group].==0,:]
        sample_df_exp   = sample_data[sample_data[:group].==1,:]
        sample_df_unexp_1 = sample_data[(sample_data[:group].==0)&(sample_data[:Buyer_Pre_P1].==1),:]  
        sample_df_unexp_0 = sample_data[(sample_data[:group].==0)&(sample_data[:Buyer_Pre_P1].==0),:]    
        sample_df_exp_1 =  sample_data[(sample_data[:group].==1)&(sample_data[:Buyer_Pre_P1].==1) ,:]
        sample_df_exp_0 =  sample_data[(sample_data[:group].==1)&(sample_data[:Buyer_Pre_P1].==0) ,:]
        sample_df_unexp_1_dim = nrow(sample_df_unexp_1)
        sample_df_unexp_0_dim = nrow(sample_df_unexp_0)
        sample_df_exp_1_dim = nrow(sample_df_exp_1)
        sample_df_exp_0_dim = nrow(sample_df_exp_0)
        dim_sampleA = round(Int64,(sample_df_exp_1_dim/sample_df_exp_0_dim)*sample_df_unexp_0_dim)
        dim_sampleB = round(Int64,(sample_df_exp_0_dim/sample_df_exp_1_dim)*sample_df_unexp_1_dim)
        
        if sample_df_unexp_1_dim/sample_df_unexp_0_dim > sample_df_exp_1_dim/sample_df_exp_0_dim
            new_df_unexp_1 = sample_df_unexp_1[sample(1:sample_df_unexp_1_dim,dim_sampleA , replace=false),:]
            dfd_sample = vcat(sample_df_exp,new_df_unexp_1,sample_df_unexp_0)
        else
            new_df_unexp_0 = sample_df_unexp_0[sample(1:sample_df_unexp_0_dim, dim_sampleB, replace=false ),:]
            dfd_sample = vcat(sample_df_exp,sample_df_unexp_1,new_df_unexp_0)
        end
    end 
    rows2remove = setdiff(dfd[dfd[:isO].==false, :panid],dfd_sample[:panid])
    dfd[findin(dfd[:panid],rows2remove),:whyO]="NoMatch"
    dfd[findin(dfd[:panid],rows2remove),:isO]=true 
    return dfd[dfd[:isO].==false, : ]  #[setdiff(names(dfd),[:isO,:whyO])] 
end

dfd = MatchMe(dfd,cfg)

lowercase!(dfd)
cfg=lowercase(cfg)



######################################
#------------MODEL OBJECTS-----------#  [:fea_or_dis_trps_shr_dpp_p1,:fea_or_dis_trps_shr_dpp_p2,:fea_or_dis_trps_shr_dpp_p3,:fea_or_dis_trps_shr_dpp_p4]
######################################
@everywhere abstract MModel 

function xResiduals(g::DataFrames.DataFrameRegressionModel)
    resp = g.model.rr
    sign(resp.y - resp.mu) .* sqrt(resp.devresid)
end

type xGLM
    vfactors::Vector{Symbol}
    fmula::DataFrames.Formula
    xvars::Vector{Symbol}   
    model::Any #DataFrameRegressionModel
    sdf::DataFrame
    wasSuccessful::Bool
    resids::DataFrame
 
    function xGLM(dfd::DataFrame, dist::Distribution, y_var::Symbol, logvar::Symbol , lnk::Link , vfactors::Array{Symbol} )  
        this=new()
        this.wasSuccessful=false
        this.xvars=Symbol[]
        this.vfactors=setdiff(vfactors, [y_var,logvar])
        for l in 1:30
            this.fmula = genFmula(y_var, this.vfactors, logvar  )
            try
                f=this.fmula
                this.model = glm(f,  dfd[convert(Array{Symbol},vcat(f.lhs,f.rhs.args[3:end]))]  , dist, lnk )
                
                this.resids = DataFrame(panid=dfd[:panid], resids=xResiduals(this.model))
                
                this.sdf = DataFrame(vars=vcat([:intercept],this.model.mf.terms.terms)  #g.model.mm.assign
                                     , coef=coef(this.model)
                                     , se=stderr(this.model)
                                     , zval=coef(this.model)./stderr(this.model) 
                                     ,pval= ccdf(FDist(1, dof_residual(this.model)), abs2(coef(this.model)./stderr(this.model))))   
                """
                g.model.mm.assign
                g=m.glm1_pvals
                DataFrame(vars=vcat([:intercept],g.model.mf.terms.terms)
                          , coef=coef(g.model)
                          , se=stderr(g.model)
                          , zval=coef(g.model)./stderr(g.model) 
                          ,pval= ccdf(FDist(1, dof_residual(g.model)), abs2(coef(g.model)./stderr(g.model))))  
                """
                this.wasSuccessful=true
                break
            catch e
                if isa(e, Base.LinAlg.PosDefException)
                    v=this.vfactors[e.info-1]
                    push!(this.xvars,v)
                    println("!!! Multicollinearity, removing :",v,"~~~",e.info-1, "\n~~~",e)
                else
                    println("....",e)
                    break
                end
            end
        end
        return this 
    end
end
 

type MDolOcc <: MModel
    vars::Vector{Symbol}
    finalvars::Vector{Symbol}
    y_var::Symbol
    dist::Distribution
    lnk::Link
    exclude_vars::Vector{Symbol}
    removed_SingleLevelVars::Vector{Symbol}
    singularity_x::Vector{Symbol}
    glm1_pvals::xGLM
    glm1_pvals_x::Vector{Symbol}
    glm2_ZnVIF::xGLM
    glm2_ZnVIF_x::Vector{Symbol}
    glm3_PnSigns::xGLM
    glm3_PnSigns_x::Vector{Symbol}
    glm4_PnSignsClean::xGLM
    glm4_PnSignsClean_x::Vector{Symbol}
    glm5::xGLM
    glm5_Z_x::Vector{Symbol}
    corrvars_x::Vector{Symbol}
    glm6_final::xGLM
    Buyer_Pos_P1_is1::Bool
    modelName::String
    logvar::Symbol
    logvar_colname::Symbol
    fdf::DataFrame
    rdf::DataFrame
    df_resid::DataFrame
    groupDeviance::Float64
    function MDolOcc(dfd::DataFrame,cfg::OrderedDict=Dict()) 
        this=new(); this.modelName="dolocc"; this.logvar=cfg[:dolocc_logvar]; this.y_var=cfg[:dolocc_y_var]; this.dist=Gamma()
        this.logvar_colname = cfg[:dolocc_logvar_colname]
        this.lnk=LogLink()
        this.removed_SingleLevelVars=Symbol[]
        this.glm1_pvals_x=Symbol[]
        this.glm2_ZnVIF_x=Symbol[]
        this.glm3_PnSigns_x=Symbol[]
        this.glm4_PnSignsClean_x=Symbol[]
        this.corrvars_x=Symbol[]
        this.exclude_vars= Symbol[ cfg[:occ_y_var],cfg[:occ_logvar],cfg[:occ_logvar_colname],cfg[:pen_y_var],cfg[:pen_logvar],cfg[:pen_logvar_colname], :buyer_pos_p1 ]
        this.Buyer_Pos_P1_is1=true
        dfd[this.logvar_colname] = log(Array(dfd[this.logvar]+1))
        this.vars=setdiff(names(dfd),vcat(this.exclude_vars,[:iso,:whyo,:data_nb_ne_b, :data_b_e_nb ,:pen_reduction,:occ_reduction,:dolocc_reduction]))
        this.vars=setdiff(this.vars,[this.logvar, this.logvar_colname])
        return this 
    end
end
mdolocc = MDolOcc(dfd,cfg)





type MOcc <: MModel
    vars::Vector{Symbol}
    finalvars::Vector{Symbol}
    y_var::Symbol
    dist::Distribution
    lnk::Link
    exclude_vars::Vector{Symbol}
    singularity_x::Vector{Symbol}
    removed_SingleLevelVars::Vector{Symbol}
    glm1_pvals::xGLM
    glm1_pvals_x::Vector{Symbol}
    glm2_ZnVIF::xGLM
    glm2_ZnVIF_x::Vector{Symbol}
    glm3_PnSigns::xGLM
    glm3_PnSigns_x::Vector{Symbol}
    glm4_PnSignsClean::xGLM
    glm4_PnSignsClean_x::Vector{Symbol}
    glm5::xGLM
    glm5_Z_x::Vector{Symbol}
    corrvars_x::Vector{Symbol}
    glm6_final::xGLM
    Buyer_Pos_P1_is1::Bool
    modelName::String
    logvar::Symbol
    logvar_colname::Symbol
    fdf::DataFrame
    rdf::DataFrame
    df_resid::DataFrame
    groupDeviance::Float64
    function MOcc(dfd::DataFrame,cfg::OrderedDict=Dict()) 
        this=new(); this.modelName="occ"; this.logvar=cfg[:occ_logvar]; this.y_var=cfg[:occ_y_var]; this.dist=Poisson()
        this.logvar_colname = cfg[:occ_logvar_colname]
        this.lnk=LogLink()
        this.removed_SingleLevelVars=Symbol[]
        this.glm1_pvals_x=Symbol[]
        this.glm2_ZnVIF_x=Symbol[]
        this.glm3_PnSigns_x=Symbol[]
        this.glm4_PnSignsClean_x=Symbol[]
        this.corrvars_x=Symbol[]
        this.exclude_vars=Symbol[cfg[:dolocc_y_var],cfg[:dolocc_logvar],cfg[:dolocc_logvar_colname],cfg[:pen_y_var],cfg[:pen_logvar],cfg[:pen_logvar_colname], :buyer_pos_p1 ]
        this.Buyer_Pos_P1_is1=true
        #dfd[this.logvar_colname] = log(Array(dfd[this.logvar]+1))
        this.vars=setdiff(names(dfd),vcat(this.exclude_vars,[:iso,:whyo,:data_nb_ne_b, :data_b_e_nb ,:pen_reduction,:occ_reduction,:dolocc_reduction]))
        this.vars=setdiff(this.vars,[this.logvar, this.logvar_colname])
        return this 
    end
end
mocc = MOcc(dfd,cfg)



type MPen <: MModel
    vars::Vector{Symbol}
    finalvars::Vector{Symbol}
    y_var::Symbol
    dist::Distribution
    lnk::Link
    exclude_vars::Vector{Symbol}
    singularity_x::Vector{Symbol}
    removed_SingleLevelVars::Vector{Symbol}
    glm1_pvals::xGLM
    glm1_pvals_x::Vector{Symbol}
    glm2_ZnVIF::xGLM
    glm2_ZnVIF_x::Vector{Symbol}
    glm3_PnSigns::xGLM
    glm3_PnSigns_x::Vector{Symbol}
    glm4_PnSignsClean::xGLM
    glm4_PnSignsClean_x::Vector{Symbol}
    glm5::xGLM
    glm5_Z_x::Vector{Symbol}
    corrvars_x::Vector{Symbol}
    glm6_final::xGLM
    Buyer_Pos_P1_is1::Bool
    modelName::String
    logvar::Symbol
    logvar_colname::Symbol
    fdf::DataFrame
    rdf::DataFrame
    df_resid::DataFrame
    groupDeviance::Float64
    function MPen(dfd::DataFrame,cfg::OrderedDict=Dict()) 
        this=new(); this.modelName="pen"; this.logvar=cfg[:pen_logvar]; this.y_var=cfg[:pen_y_var]; this.dist=Bernoulli() #Binomial()
        this.logvar_colname = cfg[:pen_logvar_colname]
        this.lnk=LogitLink()
        this.removed_SingleLevelVars=Symbol[]
        this.glm1_pvals_x=Symbol[]
        this.glm2_ZnVIF_x=Symbol[]
        this.glm3_PnSigns_x=Symbol[]
        this.glm4_PnSignsClean_x=Symbol[]
        this.corrvars_x=Symbol[]     
        this.exclude_vars=Symbol[cfg[:occ_y_var],cfg[:occ_logvar],cfg[:occ_logvar_colname],cfg[:dolocc_y_var],cfg[:dolocc_logvar],cfg[:dolocc_logvar_colname] ]
        this.Buyer_Pos_P1_is1=false
        #dfd[this.logvar_colname] = log(Array(dfd[this.logvar]+1))
        this.vars=setdiff(names(dfd),vcat(this.exclude_vars,[:iso,:whyo,:data_nb_ne_b, :data_b_e_nb ,:pen_reduction,:occ_reduction,:dolocc_reduction]))    
        this.vars=setdiff(this.vars,[this.logvar, this.logvar_colname])
        return this 
    end
end
mpen = MPen(dfd,cfg)



    include("/home/iriadmin/.julia/v0.5/RegTools/src/diagnostics.jl")
    include("/home/iriadmin/.julia/v0.5/RegTools/src/misc.jl")
    include("/home/iriadmin/.julia/v0.5/RegTools/src/modsel.jl")

#include("/media/u01/analytics/RegTools/diagnostics.jl")
#include("/media/u01/analytics/RegTools/misc.jl")
#include("/media/u01/analytics/RegTools/modsel.jl")


function vif!(g::xGLM)
    vdf=vif(g.model)
    vdf[:vars] = convert(Array{Symbol}, vdf[:variable])
    g.sdf = join(g.sdf,vdf[[:vars,:vif]], on = :vars, kind=:outer)
end




function checksingularity(form::Formula, data::DataFrame, tolerance = 1.e-8)
    mf = ModelFrame(form, data)
    mm = ModelMatrix(mf)
    qrf = qrfact!(mm.m, Val{true})
    vals = abs.(diag(qrf[:R]))
    firstbad = findfirst(x -> x < min(tolerance, 0.5) * vals[1], vals)
    if firstbad == 0
        return Symbol[]
    end
    mf.terms.terms[view(mm.assign[qrf[:p]], firstbad:length(vals))]
end



# =======================================================================================
# =======================================================================================

#using IRImodels

dfd[mocc.logvar_colname]=log(Array(dfd[mocc.logvar]+1))
dfd[mdolocc.logvar_colname]=log(Array(dfd[mdolocc.logvar]+1))
dfd[mpen.logvar_colname]=log(Array(dfd[mpen.logvar]+1))

function featureSelection(dfd::DataFrame, m::MModel)
    function rmVars(v::Array{Symbol})
        v=setdiff(v,[:group])
        return setdiff(vars,v)
    end        
    
    custom_vars=[:dolocc_reduction,:occ_reduction,:pen_reduction,:data_b_e_nb,:data_nb_ne_b,:whyo,:iso]
    required_vars=vcat([m.y_var,:panid,m.logvar],cfg[:random_demos],cfg[:random_campaigns],cfg[:scoring_vars])
    vars=setdiff(vcat(m.vars,[m.logvar_colname]),vcat(required_vars,custom_vars))
    
    println(uppercase(mocc.modelName)*" : SingleValue") #SingleValue
    m.removed_SingleLevelVars=FS_singleLevel(dfd,vars)
    vars = rmVars(m.removed_SingleLevelVars)
    
    println(uppercase(mocc.modelName)*" : Singularity : "*string(genFmula(m.y_var,vars,m.logvar))) # Singularity
    m.singularity_x = checksingularity(genFmula(m.y_var,vars,m.logvar), dfd)
    vars = rmVars(m.singularity_x)
    
    println(uppercase(mocc.modelName)*" : PVals") #PVals
    m.glm1_pvals = xGLM(dfd, m.dist, m.y_var, m.logvar, m.lnk , vars  )  
    g1=m.glm1_pvals
    m.glm1_pvals_x=g1.sdf[g1.sdf[:pval].>0.7,:vars]
    vars = rmVars(vcat(m.glm1_pvals_x, g1.xvars ) )
    
    println(uppercase(mocc.modelName)*" : Z & Vif") #Z & Vif
    m.glm2_ZnVIF = xGLM(dfd, m.dist, m.y_var, m.logvar, m.lnk ,vars  ) 
    g2=m.glm2_ZnVIF
    vif!(g2)
    z = g2.sdf[abs(g2.sdf[:zval]).<1.96,:vars]
    v = g2.sdf[ !DataArrays.isna(g2.sdf[:vif])&(g2.sdf[:vif].>15),:vars]
    m.glm2_ZnVIF_x =intersect(z,v)
    vars = rmVars(vcat(m.glm2_ZnVIF_x, g2.xvars) )


    function chkSigns(m::MModel, vars::Array{Symbol}, dfd::DataFrame, cfg::OrderedDict)  # Pvalue & Signs
        vars=unique(vcat(vars,[:group]))
        g = xGLM(dfd, m.dist, m.y_var, m.logvar, m.lnk , vars  )  
        neutralvars = setdiff(vars,vcat(cfg[:negativevars],cfg[:positivevars])) 
        neg=intersect(cfg[:negativevars],g.sdf[g.sdf[:coef].<0,:vars])
        pos=intersect(cfg[:positivevars],g.sdf[g.sdf[:coef].>0,:vars])
        varstokeep = intersect(vcat(neutralvars, pos,neg) ,  g.sdf[ g.sdf[:pval].<cfg[:pvalue_lvl] ,:vars] )
        return g, varstokeep
    end

    println(uppercase(mocc.modelName)*" : SIGN Check 1") 
    (m.glm3_PnSigns, initialvars) = chkSigns(m, vars, dfd, cfg)
    println(uppercase(mocc.modelName)*" : SIGN Check 2") 
    (m.glm4_PnSignsClean, vars_2) = chkSigns(m, convert(Array{Symbol},initialvars) , dfd, cfg)


    function getCorrVars(dfd::DataFrame, vars_2::Array{Symbol})
        rm_lst=Symbol[]
        if (length(vars_2) > 1) & (   length(getColswithType("num", dfd, convert(Array{Symbol},vars_2) ) ) > 1  )
            stackdf = corrDFD(dfd,vars_2)
            stackdf[:variable_pval] = [ m.glm4_PnSignsClean.sdf[m.glm4_PnSignsClean.sdf[:vars].==c,:pval][1]   for c in stackdf[:variable]]
            stackdf[:vars_pval] = [ m.glm4_PnSignsClean.sdf[m.glm4_PnSignsClean.sdf[:vars].==c,:pval][1]   for c in stackdf[:vars]] 
            stackdf[:most_Sig] = map((x,y) -> x < y ? "variable" : "vars" ,stackdf[:variable_pval],stackdf[:vars_pval])
     
            for row in eachrow(stackdf[(stackdf[:value].> 0.8) | (stackdf[:value].<-0.8),:])
                if row[:vars] == "group"
                    push!(rm_lst,row[:variable])
                elseif row[:variable] == "group"
                    push!(rm_lst,row[:vars])
                else
                    row[:most_Sig] == "variable" ? push!(rm_lst,row[:vars]) : push!(rm_lst,row[:variable])
                end
            end    
        end
        return rm_lst
    end
    
    println(uppercase(mocc.modelName)*" : Correlation") 
    m.corrvars_x = getCorrVars(dfd,convert(Array{Symbol},setdiff(vars_2,factor_cols)))
    vars_2 = setdiff(vars_2,m.corrvars_x)
    
    (m.glm5, m.finalvars) =  chkSigns(m, convert(Array{Symbol},vars_2), dfd, cfg)
    
    println(uppercase(mocc.modelName)*" : Final Review") # Final Review:
    m.glm6_final = xGLM(dfd, m.dist, m.y_var, m.logvar, m.lnk , convert(Array{Symbol},vcat(m.finalvars,[:group]))  )
    #rename!(m.glm6_final.resids,:resids,Symbol(m.modelName*"_residual"))
    m.df_resid = m.glm6_final.resids
    return m.glm6_final
end


factor_cols=vcat( [ cfg[:proscore], :group, :panid], cfg[:allrandoms] )

# -- convert factor ints to strings --
for c in setdiff(factor_cols,[:panid, cfg[:proscore]]) #cfg[:random_campaigns]
    if !( typeof(dfd[c]) in [  DataArray{String,1}  ]) 
        println("converting to Strings : ", c," of type : ",typeof(dfd[c]))
        dfd[c] = map(x->string(x),dfd[c])
        dfd[c] = convert(Array{String},dfd[c]) 
    end
end
poolit!(dfd,factor_cols)



featureSelection(dfd[(dfd[:iso].==false)&(dfd[:buyer_pos_p1].==1),:], mocc)
featureSelection(dfd[(dfd[:iso].==false)&(dfd[:buyer_pos_p1].==1),:], mdolocc)
featureSelection(dfd[(dfd[:iso].==false) ,:], mpen)


































# --- clustering ---

@everywhere function runRemotemodels(fname::String, raneff::Array{Symbol} ,m::MModel)
    #fdfd = Feather.read(fname)
    dfd = readtable(fname,header=true);
    repool!(dfd,raneff)
    runmodels(dfd, raneff ,m)
end

function genQues()
    ques=OrderedDict()
    ques[:occ]=RemoteChannel(1)
    ques[:dolocc]=RemoteChannel(1)
    ques[:pen]=RemoteChannel(1)
    return ques
end
ques = genQues()



# ------------------------------------


@everywhere function runGlmm(dfd::DataFrame, raneff::Array{Symbol}, m::MModel)
    function genFmula(y::Symbol, iv::Array{Symbol},ranef::Array{Symbol})  
        vars=setdiff(iv,vcat([y],ranef))
        eval(parse( string(y)*" ~ 1"* reduce(*, [ " + "*  string(c) for c in vars ] ) * reduce(*, [ " + "*  "(1 | "*string(c)*")" for c in ranef ] )  ) )
    end
    v_out = OrderedDict()
    for r in cfg[:random_campaigns]
        #f = xgenFmula(m.y_var,m.finalvars,cfg[:random_campaigns]) 
        f = genFmula(m.y_var,m.finalvars,[r])
        println(f)
        if m.Buyer_Pos_P1_is1
    #        #gmm1 = fit!(glmm(f, dfd[ (dfd[:iso].==false)&(dfd[:buyer_pos_p1].==1) ,convert(Array{Symbol},vcat(m.finalvars, [m.y_var, m.logvar],cfg[:random_campaigns]))] , m.dist  ,m.lnk)  ) 
            #gmm1 = fit!(glmm(f, dfd[ (dfd[:buyer_pos_p1].==1) ,convert(Array{Symbol},vcat(m.finalvars, [m.y_var, m.logvar],raneff  ))] , m.dist  ,m.lnk)  ) 
            dfd = dfd[ (dfd[:buyer_pos_p1].==1) ,convert(Array{Symbol},vcat(m.finalvars, [m.y_var, m.logvar],raneff  ))]
        else
    #        #gmm1 = fit!(glmm(f, dfd[ (dfd[:iso].==false) ,convert(Array{Symbol},vcat(m.finalvars, [m.y_var, m.logvar],cfg[:random_campaigns]))] , m.dist  ,m.lnk)  )
            #gmm1 = fit!(glmm(f, dfd[convert(Array{Symbol},vcat(m.finalvars, [m.y_var, m.logvar],raneff ))] , m.dist  ,m.lnk)  )
            dfd = dfd[convert(Array{Symbol},vcat(m.finalvars, [m.y_var, m.logvar],raneff  ))]
        end  
        println("O.K. running glmm!! : ",names(dfd))
        gmm1 = fit!(glmm(f, dfd , m.dist  ,m.lnk)  )
    #    v_out[r] = gmm1
    end
    return v_out
end

#runGlmm(dfd, mocc)

@everywhere function runmodels(fname::String, raneff::Array{Symbol} ,m::MModel,ques::OrderedDict)
    fdfd = Feather.read("dfd.feather")
    #poolit!(fdfd,raneff)
    println("start glmm on : ",myid())
    gout = runGlmm(fdfd, raneff, m)        
    put!(ques[Symbol(m.modelName)],gout)
    println("ending runGLMM!!!")
end

# --- Create Feather Files ----
#using Feather, CategoricalArrays
#@everywhere using Feather, CategoricalArrays
for c in cfg[:random_campaigns]
    dfd[c] = Array(dfd[c])
    #dfd[c] = categorical(dfd[c])
    factor_cols
end
cols = vcat(mocc.finalvars,mdolocc.finalvars, [:buyer_pos_p1, mdolocc.y_var, mdolocc.logvar, mocc.y_var, mocc.logvar],cfg[:random_campaigns])
cols = vcat(cols,mpen.finalvars,[mpen.y_var, mpen.logvar])
Feather.write("dfd.feather", dfd[ (dfd[:iso].==false) ,cols])
# --- END Feather Files ----

#test
take!(ques[:dolocc]); runmodels( "/mnt/resource/analytics/CDW5_792/dfd.feather", cfg[:random_campaigns] ,mdolocc,ques)


@async @spawnat 2 runmodels( "/mnt/resource/analytics/CDW5_792/dfd.feather", cfg[:random_campaigns] ,mdolocc,ques)


@async @spawnat 2 testid(ques)

#fetch(ques[:occ])
#take!(ques[:dolocc])




dfd2=dfd[ (dfd[:iso].==false)&(dfd[:buyer_pos_p1].==1), convert(Array{Symbol},vcat(m.finalvars, [m.y_var, m.logvar],cfg[:random_campaigns]))]
trps_pos_p1 ~ 1 + prd_1_qty_pre + cpn_un_pre_p4 + (1 | publisher_fct1)
Poisson()
LogLink()

gmm1 = fit!(glmm(trps_pos_p1 ~ 1 + prd_1_qty_pre + cpn_un_pre_p4 + (1 | publisher_fct1), dfd[ (dfd[:iso].==false)&(dfd[:buyer_pos_p1].==1),:] ,   Poisson()  ))


# ------------------------------------------------------------------------------------------------------------
# ---------- END END END -------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------------------------------

