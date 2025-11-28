# =======================================================
# Utils principali per simulazioni di mercato elettrico
# Contiene funzioni per strutture dati, offerte, e simulazioni
# =======================================================

# -------------------------------------------------------
# Funzioni per importare il dataset
# -------------------------------------------------------

# --------------------------------------------
# Funzioni per il dataset di partenza
# --------------------------------------------

# Funzione per importare il dataset
function get_up_dataset(;
    dir_data::String = "",
    mode::Int = 0,  
    file_name::String = "",
    mute::Bool = false
)
    # Scegli una delle modalità:
    # 1 = Importa da CSV clustering
    # 2 = Importa da file JLD2 esistente

    if mode == 1
        # Importa da CSV
        if isempty(file_name)
            error("Devi specificare il nome del file CSV da caricare.")
        end
        path = joinpath(dir_data, file_name)
        if !isfile(path)
            error("File CSV non trovato: $path")
        end
        up_dataset = CSV.read(path, DataFrame)
        if !mute
            println("\nDataset delle UP importato da CSV (prime righe):")
            println(first(up_dataset, 5), "\n")
        end

    elseif mode == 2
        # Importa da JLD2 esistente
        if isempty(file_name)
            error("Devi specificare il nome del file JLD2 da caricare.")
        end
        path = joinpath(dir_data, file_name)
        if !isfile(path)
            error("File JLD2 non trovato: $path")
        end
        up_dataset = JLD2.load(path, "df")
        if !mute
            println("\nDataset delle UP importato da JLD2 (prime righe):")
            println(first(up_dataset, 5), "\n")
        end
    else
        error("Modalità non valida. Usa 1 (CSV) o 2 (JLD2 esistente).")
    end

    @info "Dataset caricato"
    return up_dataset
end

# Crea un dataset di test
function create_test_up_dataset(;num_operatori::Int=1, dir_output::String="")

    df = DataFrame(
        OP = String[],
        UP = String[],
        Type = String[],
        Cluster = String[],
        MCost = Float64[],
        Capacity_MW = Float64[]
    )

    operatori = Vector{String}()

    for i in 1:num_operatori
        push!(operatori, "Op$(Char(64 + i))") 
    end

    Types = ["FCMT", "FCMNT"]
    Clusters = Dict(
        "FCMT" => ["PV", "WIND", "HYDRO"],
        "FCMNT"  => ["GAS", "COAL"]
    )

    Mcost = Dict(
        "PV"    =>  0.0:0.1:5.0,        # Fotovoltaico: 0-5 €/MWh
        "WIND"  =>  0.0:0.1:10.0,       # Eolico: 0-10 €/MWh
        "HYDRO" =>  10.0:0.5:40.0,      # Idroelettrico: 10-40 €/MWh
        "GAS"   =>  40.0:1.0:90.0,      # Gas: 40-90 €/MWh
        "COAL"  =>  60.0:1.0:120.0      # Carbone: 60-120 €/MWh
    )

    capacita = Dict(
        "PV"    =>  1.0:1.0:5.0,        # Fotovoltaico: 1-5 MW
        "WIND"  =>  1.0:1.0:10.0,       # Eolico: 1-10 MW
        "HYDRO" =>  5.0:5.0:50.0,       # Idroelettrico: 5-50 MW
        "GAS"   =>  10.0:10.0:100.0,    # Gas: 10-100 MW
        "COAL"  =>  20.0:20.0:200.0     # Carbone: 20-200 MW
    )

    for operatore in operatori
        num_up = rand(20:60)  # Range di up per operatore
        for i in 1:num_up
            up_id = "$operatore-UP$(i)"
            up_type = rand(Types)
            up_cluster = rand(Clusters[up_type])
            up_mcost = rand(Mcost[up_cluster])
            up_capacity = rand(capacita[up_cluster])

            push!(df, (
                operatore,
                up_id,
                up_type,
                up_cluster,
                round(up_mcost, digits=2),
                round(up_capacity, digits=2)
            ))
        end
    end

    if !isempty(dir_output)
        @save "$dir_output\\up_dataset_$(num_operatori)op.jdl2" df
        @info "Dataset salvato in: $dir_output"
    end

    return df
end

# Crea un dataset scenario PNIEC 2030 (40% RES e 60% fossili)
function create_PNIEC_up_dataset(dir_output::String="")

    df = DataFrame(
        OP = String[],
        UP = String[],
        Type = String[],
        Cluster = String[],
        MCost = Float64[],
        Capacity_MW = Float64[]
    )

    operatori = ["OpA", "OpB"]
    num_operatori = 2

    # Parametri portafoglio
    capacita_tot = 1000.0  # MW totali per operatore
    quota_RES = 0.4
    quota_TRAD = 0.6
    # Suddivisione RES (puoi variare le percentuali interne)
    quota_hydro = 0.4
    quota_wind  = 0.3
    quota_pv    = 0.3
    # Suddivisione tradizionali
    quota_gas   = 0.7
    quota_coal  = 0.3

    # Numero di UP per tecnologia (uguale per entrambi)
    n_up_RES = 3
    n_up_TRAD = 2
    n_up = Dict(
        "HYDRO" => Int(round(n_up_RES * quota_hydro)),
        "WIND"  => Int(round(n_up_RES * quota_wind)),
        "PV"    => n_up_RES - Int(round(n_up_RES * quota_hydro)) - Int(round(n_up_RES * quota_wind)),
        "GAS"   => Int(round(n_up_TRAD * quota_gas)),
        "COAL"  => n_up_TRAD - Int(round(n_up_TRAD * quota_gas))
    )

    # Capacità per UP (uguale per entrambi)
    cap = Dict(
        "HYDRO" => capacita_tot * quota_RES * quota_hydro / n_up["HYDRO"],
        "WIND"  => capacita_tot * quota_RES * quota_wind  / n_up["WIND"],
        "PV"    => capacita_tot * quota_RES * quota_pv    / n_up["PV"],
        "GAS"   => capacita_tot * quota_TRAD * quota_gas  / n_up["GAS"],
        "COAL"  => capacita_tot * quota_TRAD * quota_coal / n_up["COAL"]
    )

    # Costi marginali
    Mcost = Dict(
        "PV"    =>  0.0:0.1:5.0,        
        "WIND"  =>  0.0:1.0:10.0,       
        "HYDRO" =>  10.0:0.5:20.0,     
        "GAS"   =>  70.0:5.0:120.0,      
        "COAL"  =>  110.0:5.0:150.0      
    )

    Types = Dict(
        "HYDRO" => "FCMT",
        "WIND"  => "FCMT",
        "PV"    => "FCMT",
        "GAS"   => "FCMNT",
        "COAL"  => "FCMNT"
    )

    for (i, operatore) in enumerate(operatori)
        for tech in ["HYDRO", "WIND", "PV", "GAS", "COAL"]
            for up_idx in 1:n_up[tech]
                up_id = "$(operatore)-$(tech)-UP$(up_idx)"
                up_type = Types[tech]
                up_cluster = tech
                mcost_range = collect(Mcost[tech])
                up_mcost = rand(mcost_range) + rand([-1.0, 1.0]) # Piccola variazione
                up_capacity = cap[tech]
                push!(df, (
                    operatore,
                    up_id,
                    up_type,
                    up_cluster,
                    round(up_mcost, digits=2),
                    round(up_capacity, digits=2)
                ))
            end
        end
    end

    if !isempty(dir_output)
        @save "$dir_output\\up_dataset_PNIEC_$(num_operatori)op.jdl2" df
        @info "Dataset salvato in: $dir_output"
    end

    return df
end

# Creazione dizionario operatori da dataset
function create_operator_list(up_dataset::DataFrame; mute::Bool=true)
    operator_names = unique(up_dataset.OP)
    operator_names = [String(op) for op in operator_names]  # convertire a String

    operatori = Dict{String, Operatore}()
    for op in operator_names
        operatore = Operatore(op)
        for up in eachrow(up_dataset[up_dataset.OP .== op, :])
            up_istance = create_up(up)
            add_up_to_operator(operatore, up_istance)
        end
        operatori[op] = operatore
        if !mute
            @info "Creato l'operatore $op con $(length(operatore.up_portfolio)) UP trovate nel dataset"
        end
    end
    return operatori
end

# -------------------------------------------------------
# Metodi per le strutture dati
# -------------------------------------------------------

# ========== Metodi per UnitaProduzione ==========
function create_up(up_info::DataFrameRow)
    return UnitaProduzione(
        string(up_info.UP),
        string(up_info.OP),
        string(up_info.Type),
        string(up_info.Cluster),
        Float64(up_info.MCost),
        Float64(up_info.Capacity_MW)
    )
end

function fai_offerta_up(up::UnitaProduzione; markup::Float64=0.0)
    
    price = up.MCost * (1 + markup / 100)
    quantity = up.Capacity

    return Offer(
        up.Op, 
        up.UP, 
        "zona 1", 
        up.Type, 
        up.SubType, 
        up.MCost, 
        price, 
        quantity
    )
end

# ========== Metodi per Operatore ==========
function fai_offerta_operatore(
    operatore::Operatore; 
    markup::Float64=0.0, 
    markup_dict::Dict{String, Float64}=Dict{String, Float64}()
    )
    
    offerte_operatore = Offer[]
    for up in operatore.up_portfolio
        # Usa il markup specifico per SubType se presente, altrimenti quello globale
        up_markup = get(markup_dict, up.SubType, markup)
        offerta = fai_offerta_up(up, markup=up_markup)
        push!(offerte_operatore, offerta)
    end
    return offerte_operatore
end

# ========== Metodi per UnitaProduzione e Operatore ==========
function add_up_to_operator(operatore::Operatore, up::UnitaProduzione)
    push!(operatore.up_portfolio, up)
end

function presenta_offerte_mercato(
    operatori::Dict{String, Operatore}, 
    markups::Dict{String, Dict{String, Float64}}=Dict{String, Dict{String, Float64}}()
    )

    offerte_mercato = DataFrame(
        OP=String[],
        UP=String[],
        Zona=String[],
        Type=String[],
        SubType=String[],
        MCost=Float64[],
        P=Float64[],
        Q=Float64[],
        P_acc=Float64[],
        Q_acc=Float64[]
    )

    for (nome, operatore) in operatori
        # Estrai markup globale e dizionario SubType
        op_markups = get(markups, nome, Dict{String, Float64}())
        markup = get(op_markups, "global", 0.0)
        up_markups = filter(p -> p.first != "global", op_markups)  # Rimuovi "global" per ottenere solo SubType
        
        offerte_operatore = fai_offerta_operatore(operatore, markup=markup, markup_dict=up_markups)
        for offerta in offerte_operatore
            push!(offerte_mercato, (
                offerta.Op,
                offerta.UP,
                offerta.Zona,
                offerta.Type,
                offerta.SubType,
                offerta.MCost,
                offerta.P,
                offerta.Q,
                0.0, 0.0
            ))
        end
    end

    sort!(offerte_mercato, :P) 

    return offerte_mercato
end

function generate_random_markups(
    operatori::Dict{String, Operatore}; 
    max_global_markup::Float64=0.0, 
    max_specific_markup::Float64=0.0
    )

    markups = Dict{String, Dict{String, Float64}}()

    for op in keys(operatori)
        markups[op] = Dict{String, Float64}()
        
        # Aggiungi markup globale casuale (ignorato se è presente un markup specifico)
        markups[op]["global"] = round(rand() * max_global_markup)
        
        # Aggiungi markup specifici per tipi se presenti nel portfolio dell'operatore
        for up in operatori[op].up_portfolio
            tipo = up.SubType  
            if !(tipo in keys(markups[op]))
                markups[op][tipo] = round(rand() * max_specific_markup)
            end
        end
        
    end

    return markups
end

# -------------------------------------------------------
# Funzioni per simulare i mercati
# -------------------------------------------------------
function simulate_market_PaC(sim_offerte, D, PrintStdProb=false, plot_results=false; ifPaB=false, mute=true)  
    if ifPaB != true && mute != true 
        println("\n\033[1;33mRisoluzione del mercato PaC\033[0m\n")
    end

    # Offerte per PaC
    sim_offerte_PaC = deepcopy(sim_offerte)

    S, Offerte, P, Q = convert_dfoffers_for_SolveMyPaC(sim_offerte_PaC)

    sPaC, CostoTotPac, πPaC = SolveMyPaC(S, D, Offerte, PrintStdProb, P, Q);

    # Aggiornamento dataframe delle offerte con i risultati del mercato PaC
    sim_offerte_PaC.Q_acc = sPaC
    sim_offerte_PaC.P_acc = fill(πPaC, nrow(sim_offerte_PaC))

    # Evita di stampare i risultati se la funzione è chiamata dal mercato PaB
    if ifPaB != true
        sim_results = print_market_PaC_results(D, sPaC, CostoTotPac, πPaC, mute)
    else
        sim_results = Dict() # Dizionario vuoto se chiamato da PaB
    end

    plot_results ? p = PlotResultsPaC(sim_offerte_PaC, D) : nothing

    profitti = calcola_profitti(sim_offerte_PaC)

    if plot_results
        return RisultatiMercato(sim_offerte_PaC, sim_results, profitti), p
    else
        return RisultatiMercato(sim_offerte_PaC, sim_results, profitti)
    end
end

function simulate_market_PaB(sim_offerte, D, PrintStdProb=false, plot_results=false; mute=true)
    
    mute != true ? println("\n\033[1;33mRisoluzione del mercato PaB\033[0m\n") : nothing

    # Utililizzo la soluzione del mercato PaC come input per il mercato PaB, cambiano solo i prezzi di accettazione
    sim_offerte_PaC = simulate_market_PaC(sim_offerte, D, PrintStdProb, false, ifPaB=true, mute=mute).sim_offerte

    # Offerte per PaB
    sim_offerte_PaB = deepcopy(sim_offerte_PaC)

    # Aggiornamento dataframe delle offerte con i risultati del mercato PaB
    sim_offerte_PaB.P_acc = ifelse.(sim_offerte_PaB.Q_acc .!= 0.0, sim_offerte_PaB.P, 0.0)

    CostoTotPab = sum(sim_offerte_PaB.Q_acc .* sim_offerte_PaB.P_acc)
    PUN_PaB = sum(sim_offerte_PaB.P_acc .* sim_offerte_PaB.Q_acc) / sum(sim_offerte_PaB.Q_acc)

    sim_results = print_market_PaB_results(D, sim_offerte_PaB.Q_acc, CostoTotPab, PUN_PaB, mute)

    plot_results ? p = PlotResultsPaB(sim_offerte_PaB, D) : nothing

    profitti = calcola_profitti(sim_offerte_PaB)

    if plot_results
        return RisultatiMercato(sim_offerte_PaB, sim_results, profitti), p
    else
        return RisultatiMercato(sim_offerte_PaB, sim_results, profitti)
    end
end

function simulate_market_SPaC1(sim_offerte, D, PrintStdProb=false, plot_results=false; mute=true)

    mute!= true ? println("\n\033[1;33mRisoluzione del mercato SPaC\033[0m\n") : nothing

    # Offerte per SPaC
    sim_offerte_SPaC = deepcopy(sim_offerte)

    OfferteFCMT = findall(sim_offerte_SPaC.Type .== "FCMT")
    OfferteFCMNT = findall(sim_offerte_SPaC.Type .== "FCMNT")

    S, Offerte, P, Q = convert_dfoffers_for_SolveMyPaC(sim_offerte_SPaC)

    π, πr, Dr, s, costFCMT, costFCMNT = SolveMyBilevelProblem(
    UseSolver           =   UseSolver,
    OutputFlagGurobi    =   0,
    MyTimeLimit         =   MyTimeLimit,
    MyGAP               =   MyGAP,
    PrintStdProb        =   PrintStdProb,
    D                   =   D,              # domanda totale
    S                   =   S,              # vettore contenente le Offer
    πOfferedDec         =   P,              # vettore prezzi
    Q                   =   Q,              # vettore quantità
    OfferteFCMT         =   OfferteFCMT,
    OfferteFCMNT        =   OfferteFCMNT,
    Offerte             =   Offerte
    )

    # Aggiornamento dataframe delle offerte con i risultati del mercato SPaC
    sim_offerte_SPaC.Q_acc = s.data
    sim_offerte_SPaC.P_acc[sim_offerte_SPaC.Type .== "FCMT"] .= fill(π + πr, count(sim_offerte_SPaC.Type .== "FCMT"))
    sim_offerte_SPaC.P_acc[sim_offerte_SPaC.Type .== "FCMNT"] .= fill(π, count(sim_offerte_SPaC.Type .== "FCMNT"))

    PUN_SPaC = sum(sim_offerte_SPaC.P_acc .* sim_offerte_SPaC.Q_acc) / sum(sim_offerte_SPaC.Q_acc)

    sim_results = print_market_SPaC_results(D, s.data, costFCMT, costFCMNT, PUN_SPaC, sim_offerte_SPaC, π, πr, mute)

    plot_results ? p = PlotResultsSPaC(sim_offerte_SPaC, D, Dr, π, πr) : nothing

    profitti = calcola_profitti(sim_offerte_SPaC)

    if plot_results
        return RisultatiMercato(sim_offerte_SPaC, sim_results, profitti), p
    else
        return RisultatiMercato(sim_offerte_SPaC, sim_results, profitti)
    end
end

# Funzione per calcolare i profitti degli operatori
function calcola_profitti(sim_offerte::DataFrame)
    profitti = Dict{String, Float64}()

    for row in eachrow(sim_offerte)
        op = row.OP
        q_acc = row.Q_acc
        p_acc = row.P_acc
        mcost = row.MCost

        profitto = (p_acc - mcost) * q_acc

        profitti[op] = get(profitti, op, 0.0) + profitto
    end

    return profitti
end

function rescale_demand(y, D_MIN, D_MAX)
    old_min = minimum(y)
    old_max = maximum(y)
    new_min = D_MIN      # nuovo minimo desiderato
    new_max = D_MAX    # nuovo massimo desiderato
    y_rescaled = (y .- old_min) ./ (old_max - old_min) .* (new_max - new_min) .+ new_min

    return y_rescaled
end