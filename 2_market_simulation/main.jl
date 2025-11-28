# =======================================================
# Autore: Andrea Altamura
# Script principale per simulazioni di mercato elettrico
# Tesi Magistrale LM - Politecnico di Bari
# Anno accademico 2024/2025
# =======================================================

print("\n", "="^15)
print("\n\033[1;31mINIZIO SCRIPT\033[0m")
println("\n", "="^15)

# =======================================================
# Pacchetti e moduli necessari
# =======================================================
    # Carica i pacchetti necessari
        using CSV, DataFrames, Plots, Printf, PrettyTables
        using ProgressMeter
        using Base.Threads
        using JuMP, BilevelJuMP, Gurobi
        using Random, Statistics, Dates
        using JLD2 # Per salvare i dati di ogni simulazione stile workspace di MATLAB
        using Dierckx
        @info "Pacchetti caricati"

    # Carica i moduli necessari
        include("src/structures.jl")
        include("src/utils/utils.jl")
        include("src/utils/utils_RL.jl")
        include("src/utils/utils_print.jl")
        include("src/utils/utils_saving.jl")
        include("src/utils/utils_plotting.jl")
        include("src/utils/utils_conversion.jl")
        include("src/MGPDecoupled/SolveMyPaC.jl")
        include("src/MGPDecoupled/SolveMyBilevelProblem.jl")
        @info "Moduli personali caricati"

# =======================================================
# Parametri dello script
# =======================================================
    # Parametri generali
        Random.seed!(1234)  # Per riproducibilità
        timestamp       = Dates.format(now(), "yyyy-mm-dd_HHMMSS")
        figure_counter  = 0  # Contatore per il salvataggio delle figure

    # Cartelle di lavoro
        dir_workspace   = @__DIR__

        # Cartella di input
        dir_data        = joinpath(dir_workspace, "data")
        if !isdir(dir_data)
            error("La cartella 'data' non esiste in $dir_workspace.")
        end

    # Dataset da utilizzare
        # Caricare un dataset esistente
        # up_dataset = get_up_dataset(
        #     dir_data    =   dir_data,
        #     mode        =   2,
        #     # file_name   =   "up_dataset_for_market_simulations.csv",
        #     file_name   =   "up_dataset_PNIEC_2op.jdl2",
        #     mute        =   true
        #     )

        # Dataset di Fabrizio
            up_dataset = CSV.read(dir_data*"/Offers30.dat", DataFrame)
            for c in names(up_dataset)
                t = eltype(up_dataset[!, c])
                if t != String && (t <: AbstractString || occursin("String", string(t)) || occursin("CategoricalValue{String", string(t)))
                    try
                        up_dataset[!, c] = [ismissing(x) ? missing : String(x) for x in up_dataset[!, c]]
                    catch e
                        @warn "Conversione colonna $c fallita: $e"
                    end
                end
            end
            rename!(up_dataset, "Operatore" => "OP")
            rename!(up_dataset, :Q => "Capacity_MW")
            rename!(up_dataset, "Type " => "Type")
            rename!(up_dataset, "UP  " => "UP")
            rename!(up_dataset, "Mcost" => "MCost")
            up_dataset[!, "Cluster"] = Vector{Union{String, Missing}}(missing, nrow(up_dataset))
            for elem in eachrow(up_dataset)
                if elem.Type == "FCMT" && elem.SubType == "NP"
                    elem.Cluster = "PV/WIND"
                elseif elem.Type == "FCMT" && elem.SubType == "P"
                    elem.Cluster = "HYDRO"
                elseif elem.Type == "FCMNT"
                    elem.Cluster = "GAS"
                end
            end

        # Stampa le statistiche del dataset caricato
        print_up_dataset_stats(up_dataset)

        # Crea la lista di struct Operatore per le simulazioni
        operatori = create_operator_list(up_dataset, mute=false)

    # Impostazioni del solver (Gurobi)
        UseSolver = "Gurobi"
        GUROBI_ENV = Gurobi.Env() # Crea un ambiente Gurobi cosi da non avere il print della licenza ogni volta
        Gurobi._set_param(GUROBI_ENV, "OutputFlag", 0) # Disattiva l'output globale del solver
        HalfHour = 1800
        MyTimeLimit = Float64(1 * HalfHour)
        MyGAP = 10^-7
        @info "Impostazioni del solver (Gurobi) caricate"

# =======================================================
# Impostazioni simulazioni
# =======================================================
    # Domanda mercato elettrico [MW]
    D = 5_000.0 #15_000.0 #1_000.0 

    # Parametri peer simulazione con markup fissi
        # Markup fissi da applicare
        markups = generate_random_markups(
        operatori, 
        max_global_markup = 0.0, 
        max_specific_markup = 20.0
        )

        # è possibile impostarli manualmente
        # markups = Dict{String, Dict{String, Float64}}()
        # markups["OpB"] = Dict("global" => 5.0, "GAS" => 10.0, "COAL" => 15.0)
        # markups["OpA"] = Dict("global" => 2.0, "PV" => 5.0)

    # Parametri per reinforcement learning
        # NOTA: per beneficiare del multi threading bisogna impostare julia.NumThreads in VSCode al numero di core FISICI desiderati

        # Parametri Q-table
        skip_test_training      = false  # Saltare il training di test singolo stato
        skip_training           = false   # Saltare il training completo e caricare le Q table sotto indicate
            Q_table_name_PaB        = "Q_table_PaB_it2000.jld2"  
            Q_table_name_PaC        = "Q_table_PaC_it2000.jld2"
            Q_table_name_SPaC       = "Q_table_SPaC_it2000.jld2"

        # State space (domanda di mercato)
        Market_capacity = sum(up_dataset.Capacity_MW)
        D_MAX           = 0.80 * Market_capacity
        D_MIN           = 0.25 * Market_capacity
        state_space     = range(D_MIN, D_MAX; length=100)

        # Action space (markup)
        markup_space     = collect([0.0, 5.0, 10.0, 20.0]) 
        markup_space_PaB = collect([0.0, 50.0, 100.0, 200.0])  # Markup più ampi per PaB
        action_space, legenda_azioni = create_action_space(operatori, markup_space)
        action_space_PaB, legenda_azioni_PaB = create_action_space(operatori, markup_space_PaB) # Markup più ampi per PaB

        # Hypertraining parameters
        ε_MAX           = 1.0
        ε_MIN           = 0.05
        num_episodi     = 4_000 #2_000
        decay_rate      = calculate_decay_rate(ε_MAX, ε_MIN, num_episodi)

    # Debugging e visualizzazione
    PrintStdProb        = false  # Stampa i dettagli del problema di ottimizzazione
    plot_results        = true  # Mostra i plot dei risultati
    mute_market_output  = false  # Sopprime la stampa dei risultati di mercato

    # Salvataggio dati
    save_data_flag      = true   # Salva i dati della simulazione
    if save_data_flag
        dir_output      = joinpath(dir_workspace, "output", "$(timestamp)_D$(Int(D))_ep$(num_episodi)") # Cartella di output
        mkpath(dir_output)
        @info "Cartella di output creata in $dir_output"
    end
        
# =======================================================
# Esecuzione simulazioni
# =======================================================
    # Esecuzione simulazione a costi marginali
        print("\n", "="^60)
        print("\n\033[1;34mSimulazione a costi marginali\033[0m")
        println("\n", "="^60)

        # Presenta le offerte di mercato degli operatori
        offerte = presenta_offerte_mercato(operatori)
        @info "Offerte degli operatori presentate"

        # Simula i tre mercati
        sim_PaC,  p1    = simulate_market_PaC(offerte, D, PrintStdProb, plot_results, mute=mute_market_output)   
        sim_PaB,  p2    = simulate_market_PaB(offerte, D, PrintStdProb, plot_results, mute=mute_market_output)    
        sim_SPaC, p3    = simulate_market_SPaC1(offerte, D, PrintStdProb, plot_results, mute=mute_market_output)
        @info "Simulazioni di mercato completate"

        # Salva i risultati
        if save_data_flag
            sim_results = Dict(
            :sim_name   => "sim_a_costi_marginali",
            :D          => D,
            :PaC        => sim_PaC,
            :PaB        => sim_PaB,
            :SPaC       => sim_SPaC
            )
            
            save_simulation_data(sim_results, dir_output)

            if plot_results
                save_figure(figure_counter, p1, dir_output, "Risultati_PaC_costi_marginali.pdf")
                save_figure(figure_counter, p2, dir_output, "Risultati_PaB_costi_marginali.pdf")
                save_figure(figure_counter, p3, dir_output, "Risultati_SPaC_costi_marginali.pdf")
            end
        end

    # Esecuzione simulazione con markup fisso
        print("\n", "="^60)
        print("\n\033[1;34mSimulazione con markup fisso\033[0m")
        println("\n", "="^60)

        # Mostra i markup applicati 
        print_applied_markups(markups)

        # Presenta le offerte di mercato degli operatori
        offerte = presenta_offerte_mercato(operatori, markups)
        @info "Offerte degli operatori presentate"

        # Simula i tre mercati
        sim_PaC,  p1    = simulate_market_PaC(offerte, D, PrintStdProb, plot_results, mute=mute_market_output)   
        sim_PaB,  p2    = simulate_market_PaB(offerte, D, PrintStdProb, plot_results, mute=mute_market_output)    
        sim_SPaC, p3    = simulate_market_SPaC1(offerte, D, PrintStdProb, plot_results, mute=mute_market_output)
        @info "Simulazioni di mercato completate"
        
        # Salva i risultati
        if save_data_flag
            sim_results = Dict(
                :sim_name   => "sim_markup_fisso",
                :D          => D,
                :PaC        => sim_PaC,
                :PaB        => sim_PaB,
                :SPaC       => sim_SPaC
                )

            save_simulation_data(sim_results, dir_output)
            
            if plot_results
                save_figure(figure_counter, p1, dir_output, "Risultati_PaC_markup_casuali.pdf")
                save_figure(figure_counter, p2, dir_output, "Risultati_PaB_markup_casuali.pdf")
                save_figure(figure_counter, p3, dir_output, "Risultati_SPaC_markup_casuali.pdf")
            end
        end

    # Simulazione RL singolo stato per monitoraggio training
        if skip_test_training
            @info "Training singolo stato saltato"
        else
            print("\n", "="^60)
            print("\n\033[1;34mSimulazione RL singolo stato\033[0m")
            println("\n", "="^60)

            @info "Numero di thread disponibili: $(Threads.nthreads())"

            state_space_test = D:D

            # Inizializzazione Q-table
            Q_PaB,  counts_PaB  = init_Q_table(operatori, state_space_test, action_space_PaB)
            Q_PaC,  counts_PaC  = init_Q_table(operatori, state_space_test, action_space)
            Q_SPaC, counts_SPaC = init_Q_table(operatori, state_space_test, action_space)

            println("Numero di episodi di training per stato: $num_episodi")

            # Mostra delle statistiche per la Q table, in questo caso sono uguali tra i mercati di dimensione
            print_Q_table_stats(Q_PaB, state_space_test, action_space_PaB)

            @info "Inizio training singolo stato nei vari mercati: $(Dates.format(now(), "HH:MM:SS"))"

            # Creazione della progress bar
            pbar = Progress(num_episodi*3, showspeed=true, desc="Training RL D=$D")

            task_PaB = Threads.@spawn RL_training_test_stato!(
                Q_PaB, 
                counts_PaB, 
                num_episodi, 
                ε_MAX, 
                ε_MIN, 
                operatori, 
                action_space_PaB, 
                legenda_azioni_PaB, 
                decay_rate, 
                state=D, 
                market_type=:PaB, 
                logging=true, 
                pbar=pbar
                )

            task_PaC = Threads.@spawn RL_training_test_stato!(
                Q_PaC, 
                counts_PaC, 
                num_episodi, 
                ε_MAX, 
                ε_MIN, 
                operatori, 
                action_space, 
                legenda_azioni, 
                decay_rate, 
                state=D, 
                market_type=:PaC, 
                logging=true, 
                pbar=pbar
                )

            task_SPaC = Threads.@spawn RL_training_test_stato!(
                Q_SPaC, 
                counts_SPaC, 
                num_episodi, 
                ε_MAX, 
                ε_MIN, 
                operatori, 
                action_space, 
                legenda_azioni, 
                decay_rate, 
                state=D, 
                market_type=:SPaC, 
                logging=true, 
                pbar=pbar
                )

            profitti_PaB, pun_PaB, costo_tot_PaB   = fetch(task_PaB)
            profitti_PaC, pun_PaC, costo_tot_PaC   = fetch(task_PaC)
            profitti_SPaC, pun_SPaC, costo_tot_SPaC = fetch(task_SPaC)

            finish!(pbar)
            @info "Training finito: $(Dates.format(now(), "HH:MM:SS"))"

            # Estrai l'ultimo valore di costo totale di mercato
            costo_tot_finale_PaB = costo_tot_PaB[end]
            costo_tot_finale_PaC = costo_tot_PaC[end]
            costo_tot_finale_SPaC = costo_tot_SPaC[end]

            # Estrai l'ultimo valore di PUN per ogni mercato
            pun_finale_PaB = pun_PaB[end]
            pun_finale_PaC = pun_PaC[end]
            pun_finale_SPaC = pun_SPaC[end, 1]

            # Crea DataFrame riepilogativo
            tabella_RL = DataFrame(
                mercato = ["PaB", "PaC", "SPaC"],
                costo_tot = [costo_tot_finale_PaB, costo_tot_finale_PaC, costo_tot_finale_SPaC],
                PUN = [pun_finale_PaB, pun_finale_PaC, pun_finale_SPaC]
            )
            println("\nTabella riepilogativa RL (singolo stato):")
            pretty_table(tabella_RL; formatters=ft_printf("%.2f", 2:3))

            # Estrazione e stampa della policy ottimale per ogni operatore (un solo stato)
            op_policy_PaB = estract_optimal_policy(Q_PaB, state_space_test, action_space_PaB, operatori)
            print_optimal_policy(op_policy_PaB, "PaB", D, legenda_azioni_PaB)

            op_policy_PaC = estract_optimal_policy(Q_PaC, state_space_test, action_space, operatori)
            print_optimal_policy(op_policy_PaC, "PaC", D, legenda_azioni)

            op_policy_SPaC = estract_optimal_policy(Q_SPaC, state_space_test, action_space, operatori)
            print_optimal_policy(op_policy_SPaC, "SPaC", D, legenda_azioni)

            # Plot dei risultati
            if plot_results
                p1 = plot_profitti_RL_training(profitti_PaB)
                p2 = plot_PUN_RL_training_PaB_PaC(pun_PaB)
                
                p3 = plot_profitti_RL_training(profitti_PaC)
                p4 = plot_PUN_RL_training_PaB_PaC(pun_PaC)
                
                p5 = plot_profitti_RL_training(profitti_SPaC)
                p6 = plot_PUN_RL_training_SPaC(pun_SPaC)

                if save_data_flag
                    save_figure(figure_counter, p1, dir_output, "Profitti_RL_training_PaB.pdf")
                    save_figure(figure_counter, p2, dir_output, "PUN_RL_training_PaB.pdf")

                    save_figure(figure_counter, p3, dir_output, "Profitti_RL_training_PaC.pdf")
                    save_figure(figure_counter, p4, dir_output, "PUN_RL_training_PaC.pdf")

                    save_figure(figure_counter, p5, dir_output, "Profitti_RL_training_SPaC.pdf")
                    save_figure(figure_counter, p6, dir_output, "PUN_RL_training_SPaC.pdf")

                    @info "💾 Figure training di test salvate"
                end
            end
        end

    # Training completo multi stato per i tre mercati
        print("\n", "="^60)
        print("\n\033[1;34mTraining completo multi stato\033[0m")
        println("\n", "="^60)

        if skip_training
            println("\nTraining saltato, uso Q-table caricata")
            Q_PaB,  counts_PaB  = load_Q_table(dir_data, Q_table_name_PaB)
            Q_PaC,  counts_PaC  = load_Q_table(dir_data, Q_table_name_PaC)
            Q_SPaC, counts_SPaC = load_Q_table(dir_data, Q_table_name_SPaC)
        else
            @info "Numero di thread disponibili: $(Threads.nthreads())"

            # Inizializzo le Q-table
            Q_PaB,  counts_PaB  = init_Q_table(operatori, state_space, action_space_PaB)
            Q_PaC,  counts_PaC  = init_Q_table(operatori, state_space, action_space)
            Q_SPaC, counts_SPaC = init_Q_table(operatori, state_space, action_space)

            println("Spazio degli stati: $state_space")
            print_Q_table_stats(Q_PaB, state_space, action_space_PaB)

            # Training multi stato per PaB
                pbar = Progress(num_episodi*length(state_space), desc="Training RL mercato PaB", showspeed=true)

                @info "Inizio training completo PaB: $(Dates.format(now(), "HH:MM:SS"))"

                Threads.@threads for s in state_space
                    RL_training_stato_completo!(
                        Q_PaB, 
                        counts_PaB, 
                        num_episodi, 
                        ε_MAX, 
                        ε_MIN, 
                        operatori, 
                        action_space_PaB, 
                        legenda_azioni_PaB, 
                        decay_rate, 
                        state=s, 
                        market_type=:PaB, 
                        pbar=pbar
                        )
                end

                finish!(pbar)
                @info "Training finito: $(Dates.format(now(), "HH:MM:SS"))"

                if save_data_flag
                    save_Q_table(Q_PaB, counts_PaB, dir_output, "Q_table_PaB_it$(num_episodi).jld2")
                end

            # Training multi stato per PaC
                pbar = Progress(num_episodi*length(state_space), desc="Training RL mercato PaC", showspeed=true)

                @info "Inizio training completo PaC: $(Dates.format(now(), "HH:MM:SS"))"

                Threads.@threads for s in state_space
                    RL_training_stato_completo!(
                        Q_PaC, 
                        counts_PaC, 
                        num_episodi, 
                        ε_MAX, 
                        ε_MIN, 
                        operatori, 
                        action_space, 
                        legenda_azioni, 
                        decay_rate, 
                        state=s, 
                        market_type=:PaC, 
                        pbar=pbar
                        )
                end

                finish!(pbar)
                @info "Training finito: $(Dates.format(now(), "HH:MM:SS"))"

                if save_data_flag
                    save_Q_table(Q_PaC, counts_PaC, dir_output, "Q_table_PaC_it$(num_episodi).jld2")
                end

            # Training multi stato per SPaC
                pbar = Progress(num_episodi*length(state_space), desc="Training RL mercato SPaC", showspeed=true)

                @info "Inizio training completo SPaC: $(Dates.format(now(), "HH:MM:SS"))"

                tasks = [
                    Threads.@spawn RL_training_stato_completo!(
                        Q_SPaC, 
                        counts_SPaC, 
                        num_episodi, 
                        ε_MAX, 
                        ε_MIN, 
                        operatori, 
                        action_space, 
                        legenda_azioni, 
                        decay_rate, 
                        state=s, 
                        market_type=:SPaC, 
                        pbar=pbar
                    )
                    for s in state_space]

                # Attendi che tutti i task siano completati
                for t in tasks
                    fetch(t)
                end

                finish!(pbar)
                @info "Training finito: $(Dates.format(now(), "HH:MM:SS"))"

                if save_data_flag
                    save_Q_table(Q_SPaC, counts_SPaC, dir_output, "Q_table_SPaC_it$(num_episodi).jld2")
                end
        end

        # Estrazione policy ottimale degli operatori
        op_policy_PaB   = estract_optimal_policy(Q_PaB, state_space, action_space_PaB, operatori)
        op_policy_PaC   = estract_optimal_policy(Q_PaC, state_space, action_space, operatori)
        op_policy_SPaC  = estract_optimal_policy(Q_SPaC, state_space, action_space, operatori)

        p1 = plot_op_policy(op_policy_PaB, legenda_azioni_PaB, "PaB")
        p2 = plot_op_policy(op_policy_PaC, legenda_azioni, "PaC")
        p3 = plot_op_policy(op_policy_SPaC, legenda_azioni, "SPaC")

        if save_data_flag
            save_figure(figure_counter, p1, dir_output, "policy_PaB.pdf")
            save_figure(figure_counter, p2, dir_output, "policy_PaC.pdf")
            save_figure(figure_counter, p3, dir_output, "policy_SPaC.pdf")
            @info "💾 Grafici delle policy salvati"
        end

# =======================================================
# Test dei risultati del training completo
# =======================================================
    print("\n", "="^60)
    print("\n\033[1;34mSimulazione giorno intero (MGP)\033[0m")
    println("\n", "="^60)

    # Carica la curva della domanda di Terna
        d_x = JLD2.load(joinpath(dir_data, "spline_curva_domanda_Terna.jld2"), "spl")  

        # Riscala la curva tra D_MIN e D_MAX
        x = 1:96 # intervalli di 15 minuti in un giorno
        y = [d_x(s) for s in x]
        yₛ = rescale_demand(y, D_MIN, D_MAX)

        pd = plot_curva_domanda(x, yₛ)

        if save_data_flag
            save_figure(figure_counter, pd, dir_output, "curva_domanda_giornaliera.pdf")
            @info "💾 Grafico salvato: curva_domanda_giornaliera.pdf"
        end


    # 1. Simulazione giorno di mercato a costi marginali
        println("\n\033[1;32m📊 Simulazione giorno di mercato a costi marginali...\033[0m")

        # Crea le strutture dove salvare i dati
        costi_mercati_MC = DataFrame(
        mercato = String[],
        domanda = Float64[],
        PUN = Float64[],
        costo_tot = Float64[],
        )

        profitti_operatori_MC = DataFrame(
        mercato = String[],
        domanda = Float64[],
        operatore = String[],
        profitto_tot = Float64[],
        )

        for demand in yₛ
            # Presenta le offerte di mercato degli operatori
            local offerte = presenta_offerte_mercato(operatori)
            
            # Simula i tre mercati
            result_PaB     = simulate_market_PaB(offerte, demand, PrintStdProb, mute=true)  
            result_PaC     = simulate_market_PaC(offerte, demand, PrintStdProb, mute=true)   
            result_SPaC    = simulate_market_SPaC1(offerte, demand, PrintStdProb, mute=true)
            
            # Salva i risultati nei DataFrame
            for (mkt_name, result) in [("PaB", result_PaB), ("PaC", result_PaC), ("SPaC", result_SPaC)]
                push!(costi_mercati_MC, (
                mercato = mkt_name,
                domanda = demand,
                PUN = result.results["PUN [€/MWh]"],
                costo_tot = result.results["Costo tot [€]"]
                ))
                
                for (op_name, profitto) in result.profitti
                    push!(profitti_operatori_MC, (
                    mercato = mkt_name,
                    domanda = demand,
                    operatore = op_name,
                    profitto_tot = profitto,
                    ))
                end
            end
        end

        # Calcolo e stampa tabella riepilogativa per ogni mercato
        # Inizializza DataFrame riepilogativo
        riepilogo_MC = DataFrame(
        mercato = String[],
        costo_totale = Float64[],
        profitto_totale = Float64[],
        PUN_medio = Float64[]
        )

        for mkt in ["PaB", "PaC", "SPaC"]
            # Costo totale per mercato
            costo_totale = sum(costi_mercati_MC.costo_tot[costi_mercati_MC.mercato .== mkt])
            # Profitto totale degli operatori per mercato
            profitto_totale = sum(profitti_operatori_MC.profitto_tot[profitti_operatori_MC.mercato .== mkt])
            # PUN medio per mercato
            pun_medio = mean(costi_mercati_MC.PUN[costi_mercati_MC.mercato .== mkt])
            
            push!(riepilogo_MC, (mkt, costo_totale, profitto_totale, pun_medio))
        end

        # Stampa la tabella riepilogativa
        println("\nTabella riepilogativa CASO COSTI MARGINALI:")
        pretty_table(riepilogo_MC; formatters=ft_printf("%.2f", 2:4))

        if save_data_flag
            CSV.write(joinpath(dir_output, "costi_mercati_costi_marginali.csv"), costi_mercati_MC)
            CSV.write(joinpath(dir_output, "profitti_operatori_costi_marginali.csv"), profitti_operatori_MC)
            CSV.write(joinpath(dir_output, "riepilogo_strategia_costi_marginali.csv"), riepilogo_MC)
            @info "💾 Dati salvati: costi_mercati_costi_marginali.csv, profitti_operatori_costi_marginali.csv, riepilogo_strategia_costi_marginali.csv"
        end

        riepilogo_profitti_MC = DataFrame(
            operatore = String[],
            profitto_PaB = Float64[],
            profitto_PaC = Float64[],
            profitto_SPaC = Float64[]
            )

        for op_name in keys(operatori)
            profitto_PaB = sum(profitti_operatori_MC.profitto_tot[(profitti_operatori_MC.mercato .== "PaB") .& (profitti_operatori_MC.operatore .== op_name)])
            profitto_PaC = sum(profitti_operatori_MC.profitto_tot[(profitti_operatori_MC.mercato .== "PaC") .& (profitti_operatori_MC.operatore .== op_name)])
            profitto_SPaC = sum(profitti_operatori_MC.profitto_tot[(profitti_operatori_MC.mercato .== "SPaC") .& (profitti_operatori_MC.operatore .== op_name)])
            
            push!(riepilogo_profitti_MC, (op_name, profitto_PaB, profitto_PaC, profitto_SPaC))
        end

        println("\nTabella riepilogativa profitti operatori CASO COSTI MARGINALI:")
        pretty_table(riepilogo_profitti_MC; formatters=ft_printf("%.2f", 2:4))

        if save_data_flag
            CSV.write(joinpath(dir_output, "riepilogo_profitti_operatori_costi_marginali.csv"), riepilogo_profitti_MC)
            @info "💾 Dati salvati: riepilogo_profitti_operatori_costi_marginali.csv"
        end

    # 2. Simulazione giorno di mercato con markup ottimale RL
        println("\n\033[1;32m📊 Simulazione giorno di mercato con markup ottimale RL...\033[0m")

        # Crea le strutture dove salvare i dati
        costi_mercati_RL = DataFrame(
        mercato = String[],
        domanda = Float64[],
        PUN = Float64[],
        costo_tot = Float64[],
        )

        profitti_operatori_RL = DataFrame(
        mercato = String[],
        domanda = Float64[],
        operatore = String[],
        profitto_tot = Float64[],
        )

        for demand in  yₛ
            # Calcola i markup ottimali per ogni operatore in base alla domanda
            
            # PaB
            markups_rl = Dict{String, Dict{String, Float64}}()
            for op_name in keys(operatori)
                markups_rl[op_name] = Dict{String, Float64}()
                for (i, cluster) in enumerate(legenda_azioni_PaB[op_name])
                    markup_interpolato = interpolate_policy(op_policy_PaB[op_name], demand, state_space, legenda_azioni_PaB[op_name])
                    markups_rl[op_name][cluster] = markup_interpolato[i]
                end
            end

            # Presenta le offerte di mercato degli operatori PaB
            local offerte = presenta_offerte_mercato(operatori, markups_rl)
            result_PaB = simulate_market_PaB(offerte, demand, PrintStdProb, mute=true) 

            
            # PaC
            markups_rl = Dict{String, Dict{String, Float64}}()
            for op_name in keys(operatori)
                markups_rl[op_name] = Dict{String, Float64}()
                for (i, cluster) in enumerate(legenda_azioni[op_name])
                    markup_interpolato = interpolate_policy(op_policy_PaC[op_name], demand, state_space, legenda_azioni[op_name])
                    markups_rl[op_name][cluster] = markup_interpolato[i]
                end
            end

            # Presenta le offerte di mercato degli operatori PaC
            local offerte = presenta_offerte_mercato(operatori, markups_rl)
            result_PaC = simulate_market_PaC(offerte, demand, PrintStdProb, mute=true)    


            # SPaC
            markups_rl = Dict{String, Dict{String, Float64}}()
            for op_name in keys(operatori)
                markups_rl[op_name] = Dict{String, Float64}()
                for (i, cluster) in enumerate(legenda_azioni[op_name])
                    markup_interpolato = interpolate_policy(op_policy_SPaC[op_name], demand, state_space, legenda_azioni[op_name])
                    markups_rl[op_name][cluster] = markup_interpolato[i]
                end
            end

            # Presenta le offerte di mercato degli operatori SPaC
            local offerte = presenta_offerte_mercato(operatori, markups_rl)
            result_SPaC = simulate_market_SPaC1(offerte, demand, PrintStdProb, mute=true)    

            
            # Salva i risultati nei DataFrame
            for (mkt_name, result) in [("PaB", result_PaB), ("PaC", result_PaC), ("SPaC", result_SPaC)]
                push!(costi_mercati_RL, (
                mercato = mkt_name,
                domanda = demand,
                PUN = result.results["PUN [€/MWh]"],
                costo_tot = result.results["Costo tot [€]"]
                ))
                
                for (op_name, profitto) in result.profitti
                    push!(profitti_operatori_RL, (
                    mercato = mkt_name,
                    domanda = demand,
                    operatore = op_name,
                    profitto_tot = profitto,
                    ))
                end
            end
        end

        # Calcolo e stampa tabella riepilogativa per ogni mercato
        # Inizializza DataFrame riepilogativo
        riepilogo_RL = DataFrame(
        mercato = String[],
        costo_totale = Float64[],
        profitto_totale = Float64[],
        PUN_medio = Float64[]
        )

        for mkt in ["PaB", "PaC", "SPaC"]
            # Costo totale per mercato
            costo_totale = sum(costi_mercati_RL.costo_tot[costi_mercati_RL.mercato .== mkt])
            # Profitto totale degli operatori per mercato
            profitto_totale = sum(profitti_operatori_RL.profitto_tot[profitti_operatori_RL.mercato .== mkt])
            # PUN medio per mercato
            pun_medio = mean(costi_mercati_RL.PUN[costi_mercati_RL.mercato .== mkt])
            
            push!(riepilogo_RL, (mkt, costo_totale, profitto_totale, pun_medio))
        end

        # Stampa la tabella riepilogativa
        println("\nTabella riepilogativa CASO STRATEGIA RL:")
        pretty_table(riepilogo_RL; formatters=ft_printf("%.2f", 2:4))

        if save_data_flag
            CSV.write(joinpath(dir_output, "costi_mercati_strategia_RL.csv"), costi_mercati_RL)
            CSV.write(joinpath(dir_output, "profitti_operatori_strategia_RL.csv"), profitti_operatori_RL)
            CSV.write(joinpath(dir_output, "riepilogo_strategia_RL.csv"), riepilogo_RL)
            @info "💾 Dati salvati: costi_mercati_strategia_RL.csv, profitti_operatori_strategia_RL.csv, riepilogo_strategia_RL.csv"
        end

        riepilogo_profitti_RL = DataFrame(
        operatore = String[],
        profitto_PaB = Float64[],
        profitto_PaC = Float64[],
        profitto_SPaC = Float64[]
        )

        for op_name in keys(operatori)
            profitto_PaB = sum(profitti_operatori_RL.profitto_tot[(profitti_operatori_RL.mercato .== "PaB") .& (profitti_operatori_RL.operatore .== op_name)])
            profitto_PaC = sum(profitti_operatori_RL.profitto_tot[(profitti_operatori_RL.mercato .== "PaC") .& (profitti_operatori_RL.operatore .== op_name)])
            profitto_SPaC = sum(profitti_operatori_RL.profitto_tot[(profitti_operatori_RL.mercato .== "SPaC") .& (profitti_operatori_RL.operatore .== op_name)])
            
            push!(riepilogo_profitti_RL, (op_name, profitto_PaB, profitto_PaC, profitto_SPaC))
        end

        println("\nTabella riepilogativa profitti operatori CASO STRATEGIA RL:")
        pretty_table(riepilogo_profitti_RL; formatters=ft_printf("%.2f", 2:4))

        if save_data_flag
            CSV.write(joinpath(dir_output, "riepilogo_profitti_operatori_strategia_RL.csv"), riepilogo_profitti_RL)
            @info "💾 Dati salvati: riepilogo_profitti_operatori_strategia_RL.csv"
        end

        if plot_results
            p1 = plot_PUN_giornaliero(costi_mercati_MC, yₛ)
            p2 = plot_PUN_giornaliero(costi_mercati_RL, yₛ)

            # Trova il range comune per l'asse y (PUN)
            y_min = min(
            minimum(costi_mercati_MC.PUN),
            minimum(costi_mercati_RL.PUN)
            ) * 0.9
            y_max = max(
            maximum(costi_mercati_MC.PUN),
            maximum(costi_mercati_RL.PUN)
            ) * 1.10

            # Applica lo stesso range y ai due plot
            ylims!(p1, y_min, y_max)
            ylims!(p2, y_min, y_max)

            # Aggiungi margini per xlabel/ylabel
            plot!(p1, left_margin=10Plots.mm, bottom_margin=10Plots.mm)
            plot!(p2, left_margin=10Plots.mm, bottom_margin=10Plots.mm)

            p = plot(p1, p2, layout=(1,2), size=(1200,600), legend=:topright)
            display(p)

            if save_data_flag
            save_figure(figure_counter, p, dir_output, "PUN_giornaliero.pdf")
            @info "💾 Grafico salvato: PUN_giornaliero.pdf"
            end
        end    

    # Tabella finale comparativa per alcuni livelli di domanda (range 50% circa fino a 100%)
        x = 22:2:44
        y₁ = yₛ[collect(x)]

        labels = [
            "Market Capacity", "D", "D/Market Capacity [%]",
            "Costo tot PaB [€] (Marg)", "Costo tot PaC [€] (Marg)", "Costo tot SPaC [€] (Marg)",
            "Profitto operatori PaB [€] (Marg)", "Profitto operatori PaC [€] (Marg)", "Profitto operatori SPaC [€] (Marg)",
            "PUN PaB [€/MWh] (Marg)", "PUN PaC [€/MWh] (Marg)", "PUN SPaC [€/MWh] (Marg)",
            "Costo tot PaB [€] (RL)", "Costo tot PaC [€] (RL)", "Costo tot SPaC [€] (RL)",
            "Profitto operatori PaB [€] (RL)", "Profitto operatori PaC [€] (RL)", "Profitto operatori SPaC [€] (RL)",
            "PUN PaB [€/MWh] (RL)", "PUN PaC [€/MWh] (RL)", "PUN SPaC [€/MWh] (RL)"
        ]

        tabella = DataFrame()
        tabella.label = labels

        for (i, D) in enumerate(y₁)
            valori = zeros(length(labels))

            valori[1] = Market_capacity
            valori[2] = D
            valori[3] = D / Market_capacity * 100
            valori[4] = sum(costi_mercati_MC.costo_tot[(costi_mercati_MC.mercato .== "PaB") .& (costi_mercati_MC.domanda .== D)])
            valori[5] = sum(costi_mercati_MC.costo_tot[(costi_mercati_MC.mercato .== "PaC") .& (costi_mercati_MC.domanda .== D)])
            valori[6] = sum(costi_mercati_MC.costo_tot[(costi_mercati_MC.mercato .== "SPaC") .& (costi_mercati_MC.domanda .== D)])
            valori[7] = sum(profitti_operatori_MC.profitto_tot[(profitti_operatori_MC.mercato .== "PaB") .& (profitti_operatori_MC.domanda .== D)])
            valori[8] = sum(profitti_operatori_MC.profitto_tot[(profitti_operatori_MC.mercato .== "PaC") .& (profitti_operatori_MC.domanda .== D)])
            valori[9] = sum(profitti_operatori_MC.profitto_tot[(profitti_operatori_MC.mercato .== "SPaC") .& (profitti_operatori_MC.domanda .== D)])
            valori[10] = only(costi_mercati_MC.PUN[(costi_mercati_MC.mercato .== "PaB") .& (costi_mercati_MC.domanda .== D)])
            valori[11] = only(costi_mercati_MC.PUN[(costi_mercati_MC.mercato .== "PaC") .& (costi_mercati_MC.domanda .== D)])
            valori[12] = only(costi_mercati_MC.PUN[(costi_mercati_MC.mercato .== "SPaC") .& (costi_mercati_MC.domanda .== D)])
            valori[13] = sum(costi_mercati_RL.costo_tot[(costi_mercati_RL.mercato .== "PaB") .& (costi_mercati_RL.domanda .== D)])
            valori[14] = sum(costi_mercati_RL.costo_tot[(costi_mercati_RL.mercato .== "PaC") .& (costi_mercati_RL.domanda .== D)])
            valori[15] = sum(costi_mercati_RL.costo_tot[(costi_mercati_RL.mercato .== "SPaC") .& (costi_mercati_RL.domanda .== D)])
            valori[16] = sum(profitti_operatori_RL.profitto_tot[(profitti_operatori_RL.mercato .== "PaB") .& (profitti_operatori_RL.domanda .== D)])
            valori[17] = sum(profitti_operatori_RL.profitto_tot[(profitti_operatori_RL.mercato .== "PaC") .& (profitti_operatori_RL.domanda .== D)])
            valori[18] = sum(profitti_operatori_RL.profitto_tot[(profitti_operatori_RL.mercato .== "SPaC") .& (profitti_operatori_RL.domanda .== D)])
            valori[19] = only(costi_mercati_RL.PUN[(costi_mercati_RL.mercato .== "PaB") .& (costi_mercati_RL.domanda .== D)])
            valori[20] = only(costi_mercati_RL.PUN[(costi_mercati_RL.mercato .== "PaC") .& (costi_mercati_RL.domanda .== D)])
            valori[21] = only(costi_mercati_RL.PUN[(costi_mercati_RL.mercato .== "SPaC") .& (costi_mercati_RL.domanda .== D)])

            tabella[!, string(i)] = valori 
        end

        pretty_table(tabella)

        if save_data_flag
            CSV.write(joinpath(dir_output, "tabella_comparativa_finale.csv"), tabella)
            @info "💾 Dati salvati: tabella_comparativa_finale.csv"
        end

# =======================================================
# FINE SCRIPT
# =======================================================
    # Salvare il contenuto dello script corrente in un file .txt:
    if save_data_flag
        current_file = @__FILE__
        content = read(current_file, String)
        write(joinpath(dir_output, "main_jl.txt"), content)
        @info "Script corrente salvato main_jl.txt"
    end
