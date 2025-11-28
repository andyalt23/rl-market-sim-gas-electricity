using CSV, DataFrames, Plots

#----------------------------------------------------------
# Impostazione cartella dati e stampa messaggio iniziale
#----------------------------------------------------------

data_folder_name = "2025-09-04T192552" * "_run_outputs"  # Update this to the correct folder name if needed
plotting = true
save_output = true 
associa_MCost_cluster = false # se attivo, associa ad ogni UP il costo marginale medio del cluster di appartenenza calcolato come P_weighted_mean_mean

println("Visualizzazione dei dati di clustering di alcune UP")

#----------------------------------------------------------
# Caricamento dati clustering delle UP
#----------------------------------------------------------

csv_UP = joinpath(@__DIR__, "output", data_folder_name, "up_clustering.csv")
df_UP = CSV.read(csv_UP, DataFrame)
display(first(df_UP, 5))

#----------------------------------------------------------
# Caricamento e visualizzazione statistiche dei cluster
#----------------------------------------------------------

println("\nStatistiche per cluster KMeans:")
csv_ClusterStats = joinpath(@__DIR__, "output", data_folder_name, "cluster_stats_kmeans.csv")
df_clusters = CSV.read(csv_ClusterStats, DataFrame)
sort!(df_clusters, :P_weighted_mean_mean)
display(df_clusters)

#----------------------------------------------------------
# Associazione costo marginale stimato a ciascuna UP
#----------------------------------------------------------

if associa_MCost_cluster
    cluster_to_cost = Dict(row.Cluster => row.P_weighted_mean_mean for row in eachrow(df_clusters))
    df_UP.MCost = [cluster_to_cost[cl] for cl in df_UP.Cluster]
else
    df_UP.MCost = round.(df_UP.MCost, digits=2)
end

#----------------------------------------------------------
# Classificazione delle UP in base al costo marginale stimato
#----------------------------------------------------------

if associa_MCost_cluster
    cluster_name = Dict(row.Cluster => (row.P_weighted_mean_mean ≤ 100 ? "FCMT" : "FCMNT") for row in eachrow(df_clusters))
    df_UP.Type = [string(cluster_name[cl]) for cl in df_UP.Cluster]
else
    df_UP.Type = [row.MCost ≤ 110 ? "FCMT" : "FCMNT" for row in eachrow(df_UP)]
end

#----------------------------------------------------------
# Selezione e rinomina colonne rilevanti per simulazioni di mercato
#----------------------------------------------------------

df_UP = df_UP[:, [:OP, :UP, :Type, :Cluster, :MCost, :Q_mean]]
rename!(df_UP, Dict(:Q_mean => :Capacity_MW))
df_UP.MCost = round.(df_UP.MCost, digits=2)
df_UP.Capacity_MW = round.(df_UP.Capacity_MW, digits=3)

#----------------------------------------------------------
# Visualizzazione e salvataggio del dataset finale
#----------------------------------------------------------

println("\nDataframe finale delle UP categorizzate con i loro costi marginali stimati:")
display(first(df_UP, 5))

if save_output
    println("\nSalvataggio del dataset in 'up_dataset_for_market_simulations.csv'")
    CSV.write(joinpath(@__DIR__, "output", data_folder_name, "up_dataset_for_market_simulations.csv"), df_UP)
end

#----------------------------------------------------------
# Visualizzazione della curva di offerta cumulativa
#----------------------------------------------------------

if plotting
    # Ordina per costo marginale
    df_sorted = sort(df_UP, :MCost)
    
    # Crea il plot base vuoto
    p = plot(
        xlabel = "Capacità cumulativa [MW]",
        ylabel = "Costo marginale [€/MWh]",
        # title = "Curva di offerta aggregata",
        legend = true,
        grid = true,
        ylims = (0, maximum(df_sorted.MCost) * 1.05)
    )
    
    # Colora le aree sotto la curva
    local start_cap = 0.0
    
    # Aggiungi ciascuna unità con il colore corrispondente al suo tipo
    for (i, row) in enumerate(eachrow(df_sorted))
        local end_cap = start_cap + row.Capacity_MW
        
        # Scegli il colore in base al tipo di unità
        fill_color = row.Type == "FCMT" ? :green : :orange
        line_color = row.Type == "FCMT" ? :green : :orange
        label_val = i == 1 ? (row.Type == "FCMT" ? "FCMT" : "FCMNT") : ""
        
        # Aggiungi l'area colorata per questa unità
        plot!(p, 
            [start_cap, end_cap, end_cap], 
            [row.MCost, row.MCost, row.MCost], 
            fillrange = 0, 
            fillalpha = 0.3, 
            fillcolor = fill_color, 
            linewidth = 0,
            label = label_val
        )
        
        # Aggiungi il contorno per visualizzare lo step
        plot!(p,
            [start_cap, end_cap],
            [row.MCost, row.MCost],
            linecolor = line_color,
            linewidth = 1,
            label = ""
        )
        
        # Aggiungi la linea verticale per ogni step
        if i < nrow(df_sorted)
            # Usa il colore della prossima unità per la linea verticale
            next_color = df_sorted[i+1, :Type] == "FCMT" ? :green : :orange
            
        end
        
        # Assicurati che le etichette per FCMT e FCMNT vengano mostrate correttamente
        if i == 1
            # Prima unità - mostriamo etichetta in base al tipo
            if row.Type == "FCMT"
                # Se la prima unità è FCMT, aggiungiamo anche etichetta per FCMNT se necessario
                if any(df_sorted.Type .== "FCMNT")
                    plot!(p, [0, 0], [0, 0], 
                        fillrange = 0, 
                        fillalpha = 0.3, 
                        fillcolor = :orange, 
                        linewidth = 0,
                        label = "FCMNT"
                    )
                end
            elseif row.Type == "FCMNT" && any(df_sorted.Type .== "FCMT")
                # Se la prima è FCMNT, aggiungiamo anche etichetta per FCMT
                plot!(p, [0, 0], [0, 0], 
                    fillrange = 0,
                    fillalpha = 0.3, 
                    fillcolor = :green, 
                    linewidth = 0,
                    label = "FCMT"
                )
            end
        end
        
        # Aggiorna start_cap per la prossima iterazione
        start_cap = end_cap
    end
    
    # Aggiungi la curva di costo marginale complessiva
    cumulative_capacity = [0.0; cumsum(df_sorted.Capacity_MW)]
    marginal_cost = [df_sorted.MCost[1]; df_sorted.MCost]
    
    plot!(p,
        cumulative_capacity,
        marginal_cost,
        seriestype = :steppost,
        lw = 1.5,
        color = :black,
        label = "Costo marginale"
    )
    
    # Linee di domanda
    domanda = [5e3, 1.5e4, 1e4, 7e3]
    vline!(p, domanda, linecolor=:red, linestyle=:dash, linewidth=2, label="Domande")
    
    display(p)

    if save_output
        println("\nSalvataggio del plot in 'curva_costi_marginali.pdf'")
        savefig(p, joinpath(@__DIR__, "output", data_folder_name, "curva_costi_marginali.pdf"))
    end
end
