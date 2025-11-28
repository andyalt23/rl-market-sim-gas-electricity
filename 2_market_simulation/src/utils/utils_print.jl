# =======================================================
# Utils per la stampa dei risultati delle simulazioni
# Contiene funzioni per stampare statistiche e risultati
# =======================================================

# -------------------------------------------------------
# Funzioni per stampare statistiche del dataset
# -------------------------------------------------------

# using PrettyTables

# Funzione per stampare le statistiche generali sul dataset delle UP
function print_up_dataset_stats(up_dataset)
    # print("\n", "="^50)
    # print("\nStatistiche generali sul dataset delle UP")
    # println("\n", "="^50)    

    # Statistiche per mercato PaC e PaB (generali per operatore)
    statistiche_dataset = combine(groupby(up_dataset, :OP), :Capacity_MW => sum => :Totale_Capacita)
    statistiche_dataset.Quota_Mercato = statistiche_dataset.Totale_Capacita ./ sum(statistiche_dataset.Totale_Capacita) * 100
    num_up_operatori = combine(groupby(up_dataset, :OP), nrow => :Numero_UP)
    statistiche_dataset = leftjoin(statistiche_dataset, num_up_operatori, on=:OP)
    sort!(statistiche_dataset, :Totale_Capacita, rev=true)

    println("\n--- Statistiche per operatore ---")
    # Calcola le somme delle colonne
    totale_capacita = sum(statistiche_dataset.Totale_Capacita)
    totale_quota = sum(statistiche_dataset.Quota_Mercato)
    totale_num_up = sum(statistiche_dataset.Numero_UP)
    # Crea una riga di somma
    riga_somma = ("Totale", totale_capacita, totale_quota, totale_num_up)
    # Stampa la tabella con la riga di somma
    pretty_table(
        vcat(statistiche_dataset, DataFrame([riga_somma], [:OP, :Totale_Capacita, :Quota_Mercato, :Numero_UP])),
        header=["Operatore", "Capacità Totale [MWh]", "Quota Mercato [%]", "Numero UP"]
    )
    
    # Statistiche per mercato SPaC (suddivisione per tipo FCMT/FCMNT)
    stats2 = combine(groupby(up_dataset, [:OP, :Type]), :Capacity_MW => sum => :Totale_Capacita)

    stats_FCMT = filter(row -> row.Type == "FCMT", stats2)
    stats_FCMT.Quota_Mercato = stats_FCMT.Totale_Capacita ./ sum(stats_FCMT.Totale_Capacita) * 100
    num_up_FCMT = combine(groupby(filter(row -> row.Type == "FCMT", up_dataset), :OP), nrow => :Numero_UP)
    stats_FCMT = leftjoin(stats_FCMT, num_up_FCMT, on=:OP)
    sort!(stats_FCMT, :Totale_Capacita, rev=true)
    # Calcola le somme delle colonne
    totale_capacita_FCMT = sum(stats_FCMT.Totale_Capacita)
    totale_quota_FCMT = sum(stats_FCMT.Quota_Mercato)
    totale_num_up_FCMT = sum(stats_FCMT.Numero_UP)
    # Crea una riga di somma
    riga_somma_FCMT = ("Totale", "FCMT", totale_capacita_FCMT, totale_quota_FCMT, totale_num_up_FCMT)
    # Stampa la tabella con la riga di somma
    pretty_table(
        vcat(stats_FCMT, DataFrame([riga_somma_FCMT], [:OP, :Type, :Totale_Capacita, :Quota_Mercato, :Numero_UP])),
        header=["Operatore", "Tipo", "Capacità Totale [MWh]", "Quota Mercato [%]", "Numero UP"]
    )

    stats_FCMNT = filter(row -> row.Type == "FCMNT", stats2)
    stats_FCMNT.Quota_Mercato = stats_FCMNT.Totale_Capacita ./ sum(stats_FCMNT.Totale_Capacita) * 100
    num_up_FCMNT = combine(groupby(filter(row -> row.Type == "FCMNT", up_dataset), :OP), nrow => :Numero_UP)
    stats_FCMNT = leftjoin(stats_FCMNT, num_up_FCMNT, on=:OP)
    sort!(stats_FCMNT, :Totale_Capacita, rev=true)
    # Calcola le somme delle colonne
    totale_capacita_FCMNT = sum(stats_FCMNT.Totale_Capacita)
    totale_quota_FCMNT = sum(stats_FCMNT.Quota_Mercato)
    totale_num_up_FCMNT = sum(stats_FCMNT.Numero_UP)
    # Crea una riga di somma
    riga_somma_FCMNT = ("Totale", "FCMNT", totale_capacita_FCMNT, totale_quota_FCMNT, totale_num_up_FCMNT)
    # Stampa la tabella con la riga di somma
    pretty_table(
        vcat(stats_FCMNT, DataFrame([riga_somma_FCMNT], [:OP, :Type, :Totale_Capacita, :Quota_Mercato, :Numero_UP])),
        header=["Operatore", "Tipo", "Capacità Totale [MWh]", "Quota Mercato [%]", "Numero UP"]
    )
end

# Funzione per stampare il portafoglio di un operatore
function print_op_portfolio(op::Operatore)
    println("\nPortafoglio operatore: ", op.Op)
    df = DataFrame(op.up_portfolio)
    pretty_table(df, header=names(df))
end

# Funzione per stampare i markup applicati dagli operatori
function print_applied_markups(markups::Dict{String, Dict{String, Float64}})
    # Trova tutti i cluster presenti
    clusters = Set{String}()
    for m in values(markups)
        for k in keys(m)
            if k != "global"
                push!(clusters, k)
            end
        end
    end
    clusters = sort(collect(clusters))

    # Prepara header
    header = ["Operatore", "Globale", clusters...]

    # Prepara righe
    data = []
    for op in sort(collect(keys(markups)))
        op_markups = markups[op]
        row = [op, get(op_markups, "global", 0.0)]
        for cl in clusters
            val = haskey(op_markups, cl) ? op_markups[cl] : get(op_markups, "global", 0.0)
            push!(row, val)
        end
        push!(data, row)
    end

    # Crea DataFrame per PrettyTables
    df = DataFrame([header[i] => [row[i] for row in data] for i in 1:length(header)])

    println("\nMarkup applicati:")
    pretty_table(df)
end

# -------------------------------------------------------
# Funzioni per stampare risultati di mercato
# -------------------------------------------------------

# Funzione per stampare la tabella con i risultati di mercato PaC
function print_market_PaC_results(D, sPaC, CostoTotPac, πPaC, mute=true)
    
    mute != true ? println("\nRisultati simulazione PaC:") : nothing

    sim_results = [D sum(sPaC) CostoTotPac πPaC]

    if mute != true
        pretty_table(sim_results, header=[
            "Domanda [MWh]", 
            "Offerta accettata [MWh]", 
            "Costo tot [€]", 
            "PUN [€/MWh]"],
            tf = tf_unicode_rounded,
        )
    end

    sim_results = Dict(
        "Domanda [MWh]" => D,
        "Offerta accettata [MWh]" => sum(sPaC),
        "Costo tot [€]" => CostoTotPac,
        "PUN [€/MWh]" => πPaC
    )
    return sim_results
end

# Funzione per stampare la tabella con i risultati di mercato PaB
function print_market_PaB_results(D, sPaB, CostoTotPab, PUN_PaB, mute=true)
    
    mute != true ? println("\nRisultati simulazione PaB:") : nothing

    sim_results = [D sum(sPaB) CostoTotPab PUN_PaB]

    if mute != true
        pretty_table(sim_results, header=[
            "Domanda [MWh]", 
            "Offerta accettata [MWh]", 
            "Costo tot [€]", 
            "PUN [€/MWh]"],
            tf = tf_unicode_rounded,
        )
    end

    sim_results = Dict(
        "Domanda [MWh]" => D,
        "Offerta accettata [MWh]" => sum(sPaB),
        "Costo tot [€]" => CostoTotPab,
        "PUN [€/MWh]" => PUN_PaB
    )
    return sim_results
end

# Funzione per stampare la tabella con i risultati di mercato SPaC
function print_market_SPaC_results(D, s, costFCMT, costFCMNT, PUN_SPaC, sim_offerte_SPaC, π, πr, mute=true)
    
    mute != true ? println("\nRisultati simulazione SPaC 1:") : nothing

    table1 = [D sum(s) costFCMT + costFCMNT PUN_SPaC]
    header1 = [
        "Domanda [MWh]", 
        "Offerta accettata [MWh]", 
        "Costo tot [€]", 
        "PUN [€/MWh]"
    ]

    mute != true ? pretty_table(table1, header=header1, tf = tf_unicode_rounded) : nothing

    FCMT_Q_acc = sum(sim_offerte_SPaC.Q_acc[sim_offerte_SPaC.Type .== "FCMT"])
    FCMNT_Q_acc = sum(sim_offerte_SPaC.Q_acc[sim_offerte_SPaC.Type .== "FCMNT"])

    table2 = ["FCMT"    FCMT_Q_acc      costFCMT    π + πr  ;
              "FCMNT"   FCMNT_Q_acc     costFCMNT   π       ]
    header2 = [
        "Categoria", 
        "Offerta accettata [MWh]",
        "Costo totale [€]",
        "PUN [€/MWh]"
    ]

    mute != true ? pretty_table(table2, header=header2, tf = tf_unicode_rounded) : nothing

    sim_results = Dict(
        "Domanda [MWh]" => D,
        "Offerta accettata [MWh]" => sum(s),
        "Costo tot [€]" => costFCMT + costFCMNT,
        "PUN [€/MWh]" => PUN_SPaC,
        "FCMT Offerta accettata [MWh]" => FCMT_Q_acc,
        "FCMT Costo totale [€]" => costFCMT,
        "FCMT Clearing price [€/MWh]" => π + πr,
        "FCMNT Offerta accettata [MWh]" => FCMNT_Q_acc,
        "FCMNT Costo totale [€]" => costFCMNT,
        "FCMNT Clearing price [€/MWh]" => π
    )
    return sim_results
end

function print_Q_table_stats(Q, state_space, action_space)
    # Trova la Q table di dimensione maggiore
    max_op = argmax(op -> length(Q[op]), keys(Q))
    
    # Calcola le dimensioni per quell'operatore
    num_stati = length(state_space)
    num_azioni = length(action_space[max_op])
    totale_elementi = num_stati * num_azioni
    
    println("\nQ table di dimensioni maggiori [$num_stati x $num_azioni] = $totale_elementi elementi")
    
    return nothing
end

# Funzione helper per stampare la policy ottimale per un mercato
function print_optimal_policy(op_policy, market_name, D, legenda_azioni)
    println("\nPolicy ottimale per ogni operatore ($market_name):")
    for (op, policy) in op_policy
        action = policy[D]
        println("Operatore: $op -> Azione ottimale $(legenda_azioni[op]): $action")
    end
end