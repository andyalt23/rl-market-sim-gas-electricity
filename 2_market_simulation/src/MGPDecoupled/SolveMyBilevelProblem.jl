#-----------------------------------------------------------
#-----------------------------------------------------------
#-->FILE SolveMyBilevelProblem.jl: Solve Decoupled MGP Bilevel Problem with rigid demand
#Function SolveMyBilevelProblem
#LANGUAGE:Julia http://julialang.org
#AUTHOR: Fabrizio Lacalandra
#First Date: 24-04-2022
#Last update:
#ver: 0.150
#----------------------------------------------------------
#----------------------------------------------------------
function SolveMyBilevelProblem(; 
    k=nothing, 
    UseSolver,
    OutputFlagGurobi=0, 
    MyTimeLimit, 
    MyGAP, 
    D, 
    PrintStdSomeProb=false, 
    PrintStdProb, 
    S, 
    πOfferedDec, 
    Q, 
    Dr_Sim=nothing, 
    QAcceptedDec_Sim=nothing, 
    πg_Sim=nothing, 
    πr_Sim=nothing,
    OfferteFCMT=OfferteFCMT,
    OfferteFCMNT=OfferteFCMNT,
    Offerte = Offerte
    )

    #choose solver: Gurobi or Ipopt
    if UseSolver == "Gurobi" || UseSolver == "gurobi"
        #MyBMod = BilevelModel(Gurobi.Optimizer, mode=BilevelJuMP.SOS1Mode())
        #MyBMod = BilevelModel(Gurobi.Optimizer, mode=BilevelJuMP.FortunyAmatMcCarlMode())
        #MyBMod = BilevelModel(Gurobi.Optimizer, mode=BilevelJuMP.IndicatorMode())
        #MyBMod = BilevelModel(Gurobi.Optimizer, mode = BilevelJuMP.ProductMode())
        MyBMod = BilevelModel(() -> Gurobi.Optimizer(GUROBI_ENV), mode=BilevelJuMP.StrongDualityMode())
        #BilevelJuMP.set_mode(MyBMod,BilevelJuMP.MixedMode(default = BilevelJuMP.StrongDualityMode()))
        #set_optimizer_attribute(MyBMod, MOI.Silent(), true)
        set_optimizer_attribute(MyBMod, "OutputFlag", OutputFlagGurobi)
        set_optimizer_attribute(MyBMod, "TimeLimit", MyTimeLimit)
        #set_optimizer_attribute(MyBMod, "MIPGap", MyGAP)
        #set_optimizer_attribute(MyBMod, "RLTCuts", 0)
        #set_optimizer_attribute(MyBMod, "Heuristics", 0.8)
        #set_optimizer_attribute(MyBMod, "Presolve", 2)
        #set_optimizer_attribute(MyBMod, "Disconnected", 2)
        #set_optimizer_attribute(MyBMod, "RINS", 100)
        set_optimizer_attribute(MyBMod, "Threads", 1)
        #set_optimizer_attribute(MyBMod, "FeasibilityTol", 1e-2)
        #set_optimizer_attribute(MyBMod, "IntFeasTol", 1e-2)
        #set_optimizer_attribute(MyBMod, "PreSOS1Encoding", 1)
        set_optimizer_attribute(MyBMod, "NonConvex", 2)
    elseif UseSolver == "Cplex"
        # MyBMod = BilevelModel(
        # ()->QuadraticToBinary.Optimizer{Float64}(
        # MOI.instantiate(CPLEX.Optimizer, with_bridge_type = Float64))
        # ,mode = BilevelJuMP.ProductMode(1e-5)
        # )
        #SOLVER = CPLEX.Optimizer()
        #Q_SOLVER = ()->QuadraticToBinary.Optimizer{Float64}(
        #MOI.instantiate(CPLEX.Optimizer, with_bridge_type = Float64))
        #MyBMod = BilevelModel(CPLEX.Optimizer, mode=BilevelJuMP.SOS1Mode())
        #MyBMod = BilevelModel(CPLEX.Optimizer, mode = BilevelJuMP.IndicatorMode())
        #MyBMod = BilevelModel(Q_SOLVER, mode = BilevelJuMP.ProductMode(1e-5))
        MyBMod = BilevelModel(CPLEX.Optimizer, mode=BilevelJuMP.StrongDualityMode(10^-2))
        set_optimizer_attribute(MyBMod, "CPX_PARAM_EPGAP", MyGAP)
        set_optimizer_attribute(MyBMod, "CPX_PARAM_MIPDISPLAY", 3)
        set_optimizer_attribute(MyBMod, "CPX_PARAM_TILIM", MyTimeLimit)
        #set_optimizer_attribute(MyBMod, "CPXPARAM_Benders_Strategy", 3)
        set_optimizer_attribute(MyBMod, "CPXPARAM_OptimalityTarget", 3)
    elseif UseSolver == "Ipopt"
        MyBMod = BilevelModel(Ipopt.Optimizer, mode=BilevelJuMP.ProductMode())
        set_optimizer_attribute(MyBMod, "max_cpu_time", 60.0)
        set_optimizer_attribute(MyBMod, "print_level", 4)
    elseif UseSolver == "HiGHS"
        MyBMod = Model(HiGHS.Optimizer)
        set_optimizer_attribute(MyBMod, "presolve", "on")
        set_optimizer_attribute(MyBMod, "time_limit", 60.0)
        set_optimizer_attribute(MyBMod, "log_to_console", true)
        #https://www.scipopt.org/doc-6.0.1/html/PARAMETERS.php
    elseif UseSolver == "SCIP" || UseSolver == "Scip"
        #using SCIP
        MyBMod = BilevelModel(SCIP.Optimizer, mode = BilevelJuMP.StrongDualityMode())
        set_optimizer_attribute(MyBMod, "display/verblevel", 5)
        #set_optimizer_attribute(MyBMod, MOI.Silent(), true)
        #set_optimizer_attribute(MyBMod, "limits/gap", MyGAP)
        set_optimizer_attribute(MyBMod, "limits/time", MyTimeLimit)
        #set_optimizer_attribute(MyBMod, "nlhdlr/convex/extendedform", false)
        #nlhdlr/quadratic/useintersectioncuts = FALSE
        #set_optimizer_attribute(MyBMod, "nlhdlr/quadratic/useintersectioncuts", true)
        #constraints/indicator/generatebilinear = FALSE
        #set_optimizer_attribute(MyBMod, "constraints/indicator/generatebilinear", true)
        #propagating/obbt/createlincons = FALSE
        #set_optimizer_attribute(MyBMod, "propagating/obbt/createlincons", true)
        println("Using SCIP version: the last in the path\n")
    end

    #min and max Dr
    DrMin = max(0, D - sum(Q[j] for j in OfferteFCMNT))
    DrMax = min(D, sum(Q[j] for j in OfferteFCMT))
    DMin = max(0, D - sum(Q[j] for j in OfferteFCMT))

    #Naive segmentation wrt the energy offered in both market, non optimal
    DRStart = D * sum(Q[j] for j in OfferteFCMT) / sum(Q[j] for j in Offerte)


    #-->Some hints or explicit cns, useful for big data file
    #-->In general also for the small data, the root relaxation is unbounded otherwise
    πMin = minimum(πOfferedDec[j] for j in OfferteFCMNT)
    πMax = maximum(πOfferedDec[j] for j in OfferteFCMNT)
    #these are bounds to be applied to 
    #π+πr >= πrMin =>πr >= πrLB-π
    #π+πr <= πrMax =>πr <= πrUB-π
    πrMin = minimum(πOfferedDec[j] for j in OfferteFCMT) #- πMax
    πrMax = maximum(πOfferedDec[j] for j in OfferteFCMT) #- πMin
    #    

    #for j in Offerte
    #    @printf("Type=%s\tQ=%.2f\tπOfferedDec=%.2f\n",S[j].Type,S[j].Q,πOfferedDec[j])
    #end
    OffTupleFCMT = Vector{Tuple{Int64,Float64,Float64}}(undef, length(OfferteFCMT))
    OffTupleFCMNT = Vector{Tuple{Int64,Float64,Float64}}(undef, length(OfferteFCMNT))
    OffTuple = Vector{Tuple{Int64,Float64,Float64}}(undef, length(Offerte))
    #
    OffTupleFCMT = [(j, πOfferedDec[j], Q[j]) for j in OfferteFCMT]
    OffTupleFCMNT = [(j, πOfferedDec[j], Q[j]) for j in OfferteFCMNT]
    OffTuple = [(j, πOfferedDec[j], Q[j]) for j in Offerte]

    sort!(OffTupleFCMT, by=v -> v[2])
    sort!(OffTupleFCMNT, by=v -> v[2])
    sort!(OffTuple, by=v -> v[2])

    DrLB_iter = 0
    πrLB = 0
    for Off in OffTupleFCMT
        DrLB_iter += Off[3]
        #@printf("UP %d DrLB_iter %.3f\n",Off[1],DrLB_iter)
        if DrLB_iter >= DrMin
            πrLB = Off[2]
            PrintStdProb ? @printf("UP %d πroff %.3f πrLB %.3f\n", Off[1], Off[2], πrLB) : nothing
            break
        end
    end
    #
    DLB_iter = 0
    πLB = 0
    for Off in OffTupleFCMNT
        DLB_iter += Off[3]
        #@printf("UP %d DrLB_iter %.3f\n",Off[1],DrLB_iter)
        if DLB_iter >= DMin
            πLB = Off[2]
            PrintStdProb ? @printf("UP %d πoff %.3f πLB %.3f\n", Off[1], Off[2], πLB) : nothing
            break
        end
    end
    #
    DUB_iter = 0
    πMargTot = 0
    for Off in OffTuple
        DUB_iter += Off[3]
        #@printf("UP %d DrLB_iter %.3f\n",Off[1],DrLB_iter)
        if DUB_iter >= D
            πMargTot = Off[2] #- πMax
            #@printf("UP %d πoff %.3f πMargTot %.3f\n", Off[1], Off[2], πMargTot)
            break
        end
    end
    #
    DUB_iter = 0
    πMargDMin = 0
    for Off in OffTupleFCMNT
        DUB_iter += Off[3]
        #@printf("UP %d DrLB_iter %.3f\n",Off[1],DrLB_iter)
        if DUB_iter >= D - DrMax
            πMargDMin = Off[2] #- πMax
            #@printf("UP %d πoff %.3f πMargDMin %.3f\n", Off[1], Off[2], πMargDMin)
            break
        end
    end

    #Set upper bound on FO
    tUP = πMargDMin * D + (πMargDMin - πrLB) * DrMin
    #--->Print various things
    if PrintStdSomeProb == true
        @printf("\n\nDRStart Naive=%.3f DrLast=%5.3f\n", DRStart, Dr_Sim)
        @printf("D = %.5f\tDrMin = %.5f\tDrMax = %.5f\tDMin = %.5f\tSum(QFCMT) = %.5f\tSum(QFCMNT) = %.5f \n",
            D, DrMin, DrMax, DMin, sum(Q[j] for j in OfferteFCMT), sum(Q[j] for j in OfferteFCMNT))
        @printf("DrLB=%.3f DrUB=%.3f πMax=%.3f πrMax=%.3f\n", DrMin, DrMax, πMax, πrMax)
        @printf("Hints to the solver (πLB,πrLB possibly tighter): πMin=%.2f πLB=%.2f πrMin=%.2f πrLB=%.2f\n", πMin, πLB, πrMin, πrLB)
        @printf("Hints to the solver: πMargDMin = %.3f   πrLB = %.3f   (FO max): = %.2f\n\n", πMargDMin, πrLB, tUP)
    end

    #Upper var declaration before lower
    @variable(Upper(MyBMod), Dr)

    #Lower var
    @variable(Lower(MyBMod), s[i in Offerte])
    #@variable(Lower(MyBMod), u[i in Offerte], Bin)
    #-->Lower Problem in its primal form
    @objective(Lower(MyBMod), Min, sum(πOfferedDec[j] * s[j] for j in Offerte))
    @constraints(Lower(MyBMod),
        begin
            OffLB[j in Offerte], s[j] >= 0
            OffUB[j in Offerte], s[j] <= Q[j]
            DemandFCMT, sum(s[j] for j in OfferteFCMT) <= Dr
            DemandTOT, sum(s[j] for j in Offerte) == D
        end
    )

    #Upper vars after their definition in the lower for π,πr
    @variable(Upper(MyBMod), π, DualOf(DemandTOT))
    @variable(Upper(MyBMod), πr, DualOf(DemandFCMT))
    @variable(Upper(MyBMod), t)
    #@variable(Upper(MyBMod), z1)
    #@variable(Upper(MyBMod), z2)

    #-->Upper Problem
    #\min \left( \pi*d + s_i^r*d^r \right)
    #Dr=sum(s[j] for j in OfferteFCMT) otherwise πr=0
    @objective(Upper(MyBMod), Min, t)
    #@objective(Upper(MyBMod), Min, π*D + πr*Dr)
    #@objective(Upper(MyBMod), Min, π*D+z1^2-z2^2)
    @constraints(Upper(MyBMod),
        begin
            #z1==0.5*(πr+Dr)
            #z2==0.5*(πr-Dr)
            #epigraph, t >= π * D + z1^2-z2^2
            epigraph, t >= π * D + πr * Dr
            #z1 <= DrMin*πr
            #z1 >= DrMax*πr
            #t <= tUP
            Dr >= DrMin
            Dr <= DrMax
            π  >= πLB
            π  <= max(πMax, πrMax)
            # πr >= min(0,(πrLB - πMin))
            πr >= min(0, πrLB - πLB) # cosi si assicura che π+πr >= πrLB
            πr <= min(0,πrMax - πMin)
        end
    )
    #
    #= for j in Offerte
        BilevelJuMP.set_primal_lower_bound_hint(s[j], 0)
        BilevelJuMP.set_primal_upper_bound_hint(s[j], Q[j])
    end  
    BilevelJuMP.set_primal_lower_bound_hint(Dr, DrLB)
    BilevelJuMP.set_primal_upper_bound_hint(Dr, DrUB)
    BilevelJuMP.set_primal_lower_bound_hint(π, πLB)
    BilevelJuMP.set_primal_upper_bound_hint(π, πUB)
    BilevelJuMP.set_primal_lower_bound_hint(πr, πrLB)
    BilevelJuMP.set_primal_upper_bound_hint(πr, πrUB)
    =#

    #BilevelJuMP.set_mode(DemandFCMT, BilevelJuMP.ProductMode(1e-5))
    #We don't have a print like in pure JuMP
    #JuMP.show_constraints_summary(stdout,MyBMod::BilevelModel)
    optimize!(MyBMod)

    #@printf("z1 = %.5f\n",value(z1)) 

    if termination_status(MyBMod) != "INFEASIBLE_OR_UNBOUNDED"
        if PrintStdProb
            @printf("\nP status: %s P Status Upper %s Termination status: %s \n",
                primal_status(MyBMod), primal_status(Upper(MyBMod)), termination_status(MyBMod))
            #DualOf(Lower1)
            #display(dual.(Lower3))
            @printf("π = %.5f πr = %.5f (π+πr) = %.5f  Dr = %.5f \n", value(π), value(πr), value(π) + value(πr), value(Dr))
            #for j in Offerte
            #@printf("s[%d] = %.5f  \n", j,value(s[j]) )
            #@printf("s[%d] = %.5f  %.5f\n", j,value(s[j]),dual.(Lower3) )
            #end
            @printf("Objective value Bilevel Problem (by getobj) %.1f  *while* PaC = %.1f  Ratio = %.5f%%", objective_value(MyBMod), πMargTot * D, 100 * objective_value(MyBMod) / (πMargTot * D))
            @printf("\n")
        end

        #JuMP.objective_value(stdout,MyBMod)
        #@printf("dual di lower 2 = > πr %.5f  \n", DualOf(Lower2))
        #TO DO:Add some statistics to S.P
        CostFCMT = sum((JuMP.value(π) + JuMP.value(πr)) * value(s[j]) for j in OfferteFCMT)
        QOFFFCMT = sum(Q[j] for j in OfferteFCMT)
        QAFCMT = sum(value(s[j]) for j in OfferteFCMT)
        #
        CostFCMNT = sum(JuMP.value(π) * value(s[j]) for j in OfferteFCMNT)
        QOFFFCMNT = sum(Q[j] for j in OfferteFCMNT)
        QAFCMNT = sum(value(s[j]) for j in OfferteFCMNT)
        QAS = QAFCMT+QAFCMNT
        CostTot = CostFCMT + CostFCMNT

        if PrintStdProb == true
            h = size(Offerte, 1)
            MyOfferOut = Array{Any}(undef, h, 9)
            for j in 1:h
                if abs(value(s[j])) <= 10^-5
                    MyOfferOut[j, :] = [S[j].Op, S[j].Zona, S[j].UP, S[j].Type, S[j].SubType, "N. ACCEPTED", πOfferedDec[j], Q[j], value(s[j])]
                elseif abs(value(s[j]) - Q[j]) <= 10^-5
                    MyOfferOut[j, :] = [S[j].Op, S[j].Zona, S[j].UP, S[j].Type, S[j].SubType, "T. ACCEPTED", πOfferedDec[j], Q[j], value(s[j])]
                elseif value(s[j]) < S[j].Q
                    MyOfferOut[j, :] = [S[j].Op, S[j].Zona, S[j].UP, S[j].Type, S[j].SubType, "P. ACCEPTED", πOfferedDec[j], Q[j], value(s[j])]
                else
                    @printf("ERROR Bil offer Elastic\n")
                end
            end
            @printf("\nBids (Sell orders)\n")
            MyHeaderOffer = ["Operatore", "Zona", "UP", "Type", "SubType", "Status", "P Off", "Q Off", "Q. Acc"]
            pretty_table(MyOfferOut, header=MyHeaderOffer, tf=tf_compact; alignment=:c)
            #
            @printf("\nFCMT:\n")
            @printf("QTot = %.3f \nQAcc = %.3f \nCost: %.3f \nCost per MWh = %.3f\n",
                QOFFFCMT, QAFCMT, CostFCMT, CostFCMT / QAFCMT
            )
            @printf("\nFCMNT:\n")
            @printf("QTot = %.3f \nQAcc = %.3f \nCost: %.3f \nCost per MWh = %.3f\n",
                QOFFFCMNT, QAFCMNT, CostFCMNT, CostFCMNT / QAFCMNT
            )
            @printf("\nSystem DeC:\n")
            @printf("QSell:%.3f \nCost: %.3f \nCost per MWh (PUN-Like) = %.3f\n",
            QAS, CostTot, CostTot / D
            )
            #printstyled(color=:yellow,"\nObjective value Bilevel Problem: (as reported by getobj): ", objective_value(MyPMod))
            @printf("\n")
        end

        #return Offerte, OfferteFCMT, OfferteFCMNT, JuMP.value(π), JuMP.value(πr), JuMP.value(Dr), JuMP.value.(s), CostFCMT, CostFCMNT
        return JuMP.value(π), JuMP.value(πr), JuMP.value(Dr), JuMP.value.(s), CostFCMT, CostFCMNT
    else
        @printf("Model infeasible??? %s\n", termination_status(MyBMod))
    end



end
