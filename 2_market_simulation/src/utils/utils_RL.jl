# =======================================================
# Utils per la parte di Reinforcement Learning
# =======================================================

function create_action_space(operatori::Dict{String, Operatore}, markup_space)
    action_space = Dict{String, Any}()
    legenda = Dict{String, Any}()  
    for op_key in keys(operatori)
        operatore = operatori[op_key]
        clusters = unique([up.SubType for up in operatore.up_portfolio])
        legenda[op_key] = clusters
        num_clusters = length(clusters)
        markup_space_cluster = [markup_space for _ in 1:num_clusters]
        action_space[op_key] = collect(Iterators.product(markup_space_cluster...))
    end

    return action_space, legenda # Dizionario: chiave = operatore, valore = array di tuple (combinazioni markup per cluster)
end

function create_empty_Q_table(Q, counts, state_space, action_space)
    #= 
    Struttura di Q e counts, per ora Q è un dizionario dove ad ogni chiave (stato, azione) è associato il Q value.
    Ogni stato è un valore corrispondente alla domanda elettrica.
    Ogni azione è una tupla di markup per ogni cluster.
    =#

    # Q = Dict{Tuple{Float64, typeof(action_space[1])}, Float64}()
    # counts = Dict{Tuple{Float64, typeof(action_space[1])}, Int}()
    
    for s in state_space
        for a in action_space
            Q[(s, a)] = 0.0
            counts[(s, a)] = 0
        end
    end

    return Q, counts
end

function load_Q_table(data_dir::String, Q_table_name::String)
    data = JLD2.load(joinpath(data_dir, Q_table_name)) 

    @info "Q-table caricata: $Q_table_name"
    return data["Q"], data["counts"]
end

function init_Q_table(
    operatori::Union{Nothing, Dict{String, Operatore}}=nothing, 
    state_space::Any=nothing, 
    action_space::Any=nothing 
    )

    Q = Dict{String, Any}()             # Contiene tutte le Q table degli operatori
    counts = Dict{String, Any}()        # Contiene tutti i counts delle Q table degli operatori

    for op in keys(operatori)
        Q[op] = Dict{Tuple{Float64, typeof(action_space[op][1])}, Float64}()    # Q table dell'operatore op
        counts[op] = Dict{Tuple{Float64, typeof(action_space[op][1])}, Int}()   # counts della Q table dell'operatore op
        
        Q[op], counts[op] = create_empty_Q_table(Q[op], counts[op], state_space, action_space[op])
    end

    @info "Q-table inizializzata a zero."
    return Q, counts    
end

function choose_action_combo(Q, state, action_space, ε)
    if rand() < ε
        return rand(action_space)
    else
        q_vals = [Q[(state, a)] for a in action_space]
        return action_space[argmax(q_vals)]
    end
end

function update_Q_table!(Q, state, action, revenue, counts)
    counts[(state, action)] += 1 # counts deve essere valutato prima di aggiornare Q altrimenti \alpha sarebbe Nan/Inf

    α = 1 / counts[(state, action)]
    Q[(state, action)] += α * (revenue - Q[(state, action)])    
end

function calculate_decay_rate(ε_MAX, ε_MIN, num_episodi)
    return -log(ε_MIN / ε_MAX) / num_episodi
end

function update_ε(episode, ε_MAX, ε_MIN, decay_rate)
    ε = ε_MAX * exp(-decay_rate * (episode - 1))  # Decay esponenziale di ε
    if ε < ε_MIN # Per assicurare che non scenda sotto ε_MIN
        ε = ε_MIN
    end
    return ε
end

function RL_training_test_stato!(
    Q,
    counts,
    num_episodi::Int,
    ε_MAX::Float64,
    ε_MIN::Float64,
    operatori::Dict{String, Operatore},
    action_space,
    legenda_azioni::Dict{String, Any},
    decay_rate::Float64;
    state::Float64,
    market_type::Symbol,
    logging::Bool=false,
    pbar=nothing
    )

    a = Dict{String, Any}()
    markups = Dict{String, Dict{String, Float64}}()

    if logging
        # Crea un dataframe per salvare i profitti: colonne episode, operator, profit
        num_operatori = length(operatori)
        total_rows = num_episodi * num_operatori
        profit_df = DataFrame(
            episode=Vector{Int}(undef, total_rows), 
            operator=Vector{String}(undef, total_rows), 
            profit=Vector{Float64}(undef, total_rows)
            )
        row_idx = 1

        if market_type == :PaB || market_type == :PaC
            pun = Vector{Float64}(undef, num_episodi)
            costo_tot = Vector{Float64}(undef, num_episodi)
        elseif market_type == :SPaC
            pun = Matrix{Float64}(undef, num_episodi, 3) # Colonne: PUN, PUN_FCMT, PUN_FCMNT
            costo_tot = Vector{Float64}(undef, num_episodi)
        end
    end

    for episode in 1:num_episodi

        try
            # Aggiorna ε ad ogni episodio
            ε = update_ε(episode, ε_MAX, ε_MIN, decay_rate)

            # Scegli azione per ogni operatore
            for op in keys(operatori)
                a[op] = choose_action_combo(Q[op], state, action_space[op], ε)
                markups[op] = Dict(cluster => a[op][i] for (i, cluster) in enumerate(legenda_azioni[op]))  # mappa l'azione scelta ai cluster dell'operatore
            end

            # Simula il mercato con le azioni scelte
            offerte = presenta_offerte_mercato(operatori, markups)

            if market_type == :PaB
                result = simulate_market_PaB(offerte, state)
            elseif market_type == :PaC
                result = simulate_market_PaC(offerte, state)
            elseif market_type == :SPaC
                result = simulate_market_SPaC1(offerte, state)
            else
                error("Tipo di mercato non valido. Usa :PaB, :PaC o :SPaC.")
            end

            # Ottieni i ricavi e aggiorna la Q-table per ogni operatore
            for op in keys(operatori)

                update_Q_table!(
                    Q[op], 
                    state, 
                    a[op], 
                    result.profitti[op], 
                    counts[op]
                    )
                
                if logging
                    # Riempi il dataframe pre-allocato invece di push!
                    profit_df.episode[row_idx] = episode
                    profit_df.operator[row_idx] = op
                    profit_df.profit[row_idx] = result.profitti[op]
                    row_idx += 1
                end
            end

            if logging
                if market_type == :PaB || market_type == :PaC
                pun[episode] = result.results["PUN [€/MWh]"]
                costo_tot[episode] = result.results["Costo tot [€]"]
                elseif market_type == :SPaC
                    pun[episode, 1] = result.results["PUN [€/MWh]"]
                    pun[episode, 2] = result.results["FCMT Clearing price [€/MWh]"]
                    pun[episode, 3] = result.results["FCMNT Clearing price [€/MWh]"]
                    costo_tot[episode] = result.results["Costo tot [€]"]
                end
            end

            # Aggiorna la barra di progresso
            if pbar !== nothing
                next!(pbar)
            end

        catch e
            if isa(e, InterruptException)
                @warn "Interruzione manuale all'episodio $episode dello stato $state"
                rethrow(e)
            else
                @warn "Errore all'episodio $episode dello stato $state: $e"
                rethrow(e)
            end
        end
    end

    if logging
        return profit_df, pun, costo_tot
    else
        return nothing
    end
end

function estract_optimal_policy(Q, state_space, action_space, operatori)
    op_policy = Dict{String, Any}()
    for op in keys(operatori)
        op_policy[op] = Dict{Float64, NTuple{length(action_space[op][1]), Float64}}()
        for s in state_space
            q_vals = [Q[op][(s, a)] for a in action_space[op]]
            best_action_idx = argmax(q_vals)
            op_policy[op][s] = action_space[op][best_action_idx]
        end
    end
    return op_policy
end

function interpolate_policy(op_policy, s, state_space, legenda_azioni)
    # Trova lo stato discreto più vicino
    idx_low = findlast(x -> x <= s, state_space)
    idx_high = findfirst(x -> x >= s, state_space)
    
    # Se s coincide esattamente con uno stato o è fuori bounds
    if idx_low == idx_high || idx_low === nothing || idx_high === nothing
        if idx_low === nothing
            # s è minore del primo stato, usa il primo
            return op_policy[state_space[1]]
        elseif idx_high === nothing
            # s è maggiore dell'ultimo stato, usa l'ultimo
            return op_policy[state_space[end]]
        else
            # s coincide con uno stato
            return op_policy[state_space[idx_low]]
        end
    end
    
    # Calcola quale stato è più vicino
    s_low = state_space[idx_low]
    s_high = state_space[idx_high]
    
    if abs(s - s_low) <= abs(s - s_high)
        # Lo stato inferiore è più vicino
        return op_policy[s_low]
    else
        # Lo stato superiore è più vicino
        return op_policy[s_high]
    end
end

function RL_training_stato_completo!(
    Q,
    counts,
    num_episodi::Int,
    ε_MAX::Float64,
    ε_MIN::Float64,
    operatori::Dict{String, Operatore},
    action_space,
    legenda_azioni::Dict{String, Any},
    decay_rate::Float64;
    state::Float64,
    market_type::Symbol,
    pbar=nothing
    )

    a = Dict{String, Any}()
    markups = Dict{String, Dict{String, Float64}}()

    for episode in 1:num_episodi

        try
            # Aggiorna ε ad ogni episodio
            ε = update_ε(episode, ε_MAX, ε_MIN, decay_rate)

            # Scegli azione per ogni operatore
            for op in keys(operatori)
                a[op] = choose_action_combo(Q[op], state, action_space[op], ε)
                markups[op] = Dict(cluster => a[op][i] for (i, cluster) in enumerate(legenda_azioni[op]))  # mappa l'azione scelta ai cluster dell'operatore
            end

            # Simula il mercato con le azioni scelte
            offerte = presenta_offerte_mercato(operatori, markups)

            if market_type == :PaB
                result = simulate_market_PaB(offerte, state)
            elseif market_type == :PaC
                result = simulate_market_PaC(offerte, state)
            elseif market_type == :SPaC
                result = simulate_market_SPaC1(offerte, state)
            else
                error("Tipo di mercato non valido. Usa :PaB, :PaC o :SPaC.")
            end

            # Ottieni i ricavi e aggiorna la Q-table per ogni operatore
            for op in keys(operatori)

                update_Q_table!(
                    Q[op], 
                    state, 
                    a[op], 
                    result.profitti[op], 
                    counts[op]
                    )
                
            end

            # Aggiorna la barra di progresso
            if pbar !== nothing
                next!(pbar)
            end

        catch e
            if isa(e, InterruptException)
                @warn "Interruzione manuale all'episodio $episode dello stato $state"
                rethrow(e)
            else
                @warn "Errore all'episodio $episode dello stato $state: $e"
                rethrow(e)
            end
        end
    end

    # # Aggiorna la barra di progresso
    # if pbar !== nothing
    #     next!(pbar)
    # end

    return nothing
end
