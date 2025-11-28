#-----------------------------------------------------------
#-----------------------------------------------------------
#-->FILE SolveMyPaC.jl: Solve Primal Problem with classic PaC with rigid demand
#Function SolveMyPaC
#LANGUAGE:Julia http://julialang.org
#AUTHOR: Fabrizio Lacalandra
#First Date: 21-04-2022
#Last update:
#ver: 0.150
#----------------------------------------------------------
#----------------------------------------------------------

function SolveMyPaC(S,D,Offerte,PrintStdProb,π,Q)

    if UseSolver == "Gurobi" || UseSolver == "gurobi"
        MyPacMod = Model(() -> Gurobi.Optimizer(GUROBI_ENV))
        set_optimizer_attribute(MyPacMod, MOI.Silent(), true)
        set_optimizer_attribute(MyPacMod, "OutputFlag", 0)
        set_optimizer_attribute(MyPacMod, "TimeLimit", MyTimeLimit)
        set_optimizer_attribute(MyPacMod, "MIPGap", MyGAP)
        set_optimizer_attribute(MyPacMod, "Threads", 1)
    elseif UseSolver == "Cplex"
        MyPacMod = Model(CPLEX.Optimizer)
        set_optimizer_attribute(MyMod, "CPX_PARAM_EPGAP",MyGAP)
        set_optimizer_attribute(MyMod, "CPX_PARAM_MIPDISPLAY", 3)
        set_optimizer_attribute(MyMod, "CPX_PARAM_TILIM", MyTimeLimit)
        #set_optimizer_attribute(MyMod, "CPXPARAM_OptimalityTarget", 3)
    elseif UseSolver == "Ipopt"
        MyPacMod = Model(Ipopt.Optimizer)
        set_optimizer_attribute(MyPacMod, "max_cpu_time", 60.0)
        set_optimizer_attribute(MyPacMod, "print_level", 4)
    elseif UseSolver == "SCIP" || UseSolver == "Scip"
        #using SCIP
        #MyPacMod = Model(Gurobi.Optimizer)
        #set_optimizer_attribute(MyPacMod, MOI.Silent(), true)
        #set_optimizer_attribute(MyPacMod, "OutputFlag", 0)
        #set_optimizer_attribute(MyPacMod, "TimeLimit", MyTimeLimit)
        #set_optimizer_attribute(MyPacMod, "MIPGap", MyGAP)
        MyPacMod = Model(HiGHS.Optimizer)
        set_optimizer_attribute(MyPacMod, "presolve", "on")
        set_optimizer_attribute(MyPacMod, "time_limit", 60.0)
        set_optimizer_attribute(MyPacMod, "log_to_console", true)
        #https://www.scipopt.org/doc-6.0.1/html/PARAMETERS.php
    end

    @variable(MyPacMod, s[j in Offerte])
    @objective(MyPacMod, Min, sum(π[j]*s[j] for j in Offerte))
    @constraints(MyPacMod,
    begin
        QuantLBound[j in Offerte], s[j] >= 0
        QuantUBound[j in Offerte], s[j] <= Q[j]
        DemandTOT,sum(s[j] for j in Offerte) == D
    end)
    #print(MyPacMod)
    optimize!(MyPacMod)

    if termination_status(MyPacMod)!="INFEASIBLE_OR_UNBOUNDED"
        πPaC= dual(DemandTOT)
        CostoTotPac=D*πPaC
        #
        if PrintStdProb == true
        printstyled(color=:yellow,"\n*PaC* Primal Problem With rigid demand: \n")
        h = size(Offerte, 1)
        MyOfferOut = Array{Any}(undef, h, 9)
        for j in 1:h
            if abs(value(s[j])) <= 10^-5
                MyOfferOut[j, :] = [S[j].Op, S[j].Zona, S[j].UP, S[j].Type, S[j].SubType, "N. ACCEPTED", π[j], Q[j], value(s[j])]
            elseif abs(value(s[j]) - Q[j]) <= 10^-5
                MyOfferOut[j, :] = [S[j].Op, S[j].Zona, S[j].UP, S[j].Type, S[j].SubType, "T. ACCEPTED", π[j], Q[j], value(s[j])]
            elseif value(s[j]) < S[j].Q
                MyOfferOut[j, :] = [S[j].Op, S[j].Zona, S[j].UP, S[j].Type, S[j].SubType, "P. ACCEPTED", π[j], Q[j], value(s[j])]
            else
                @printf("ERROR PaC offer Rigid\n")
            end
        end
        @printf("\nBids (Sell orders PaC Rigid)\n")
        MyHeaderOffer = ["Operatore", "Zona", "UP", "Type", "SubType", "Status", "P Off", "Q Off", "Q. Acc"]
        pretty_table(MyOfferOut, header=MyHeaderOffer, tf=tf_compact; alignment=:c)
        #
        #TO DO:Add some statistics to S.P
        @printf("\nSystem PaC:\n")
        @printf("Cost: %.3f \nCost per MWh = %.3f\n",CostoTotPac,CostoTotPac/D)
        printstyled(color=:green,"\nObjective value PaC Primal Problem: (as reported by getobj): ", objective_value(MyPacMod))
        @printf("\n\n")
        end

        sPaC= JuMP.value.(s)
    end


    return sPaC,CostoTotPac,πPaC

end #Function
