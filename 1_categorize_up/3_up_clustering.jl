using CSV, DataFrames, Plots, Dates, Clustering, Random, Distances, PrettyTables, LaTeXStrings, Statistics
using StatsBase: skewness, mode

# ----------------------------------------------------------------------
# Carica il CSV finale output dello script 2_filter_csv_top10_operators.jl
# ----------------------------------------------------------------------

csv_name = "2025-08-28_132205-offerte_top10op_final.csv" # Cambiare se si vuole usare un altro file
csv_path = joinpath(@__DIR__, "data", "csv", csv_name)
println("Caricamento del file CSV: $csv_path")
df = CSV.read(csv_path, DataFrame)
println("Caricamento completato. Numero di righe: ", nrow(df))

# Mostra il numero di UP uniche per ogni operatore
println("\nOperatori e numero di UP uniche:")
println(combine(groupby(df, :OP), :UP => x -> length(unique(x))))

# -----------------------------------------------
# Filtra le unità di produzione con poche offerte
# -----------------------------------------------

# Conta il numero di offerte per ciascuna UP
offerte_per_up = combine(groupby(df, :UP), nrow => :n_offerte)

println("\nNumero di unità di produzione (UP): ", nrow(offerte_per_up))

# Calcola statistiche
mediana = median(offerte_per_up.n_offerte)

percentile_scelto = 0.2 # Valore modificabile tra 0 e 1

qx = quantile(offerte_per_up.n_offerte, percentile_scelto)
q25 = quantile(offerte_per_up.n_offerte, 0.25)
media = mean(offerte_per_up.n_offerte)

p1 = histogram(
    offerte_per_up.n_offerte,
    bins=100,   # :auto,
    xlabel="Numero di Offerte",
    ylabel="Frequenza",
    title="Distribuzione delle Offerte per UP",
    legend=:topright
)
vline!([mediana], color=:green, linestyle=:solid, linewidth=2, label="Mediana")
vline!([qx], color=:red, linestyle=:dash, linewidth=2, label="Q$(round(Int, percentile_scelto*100))")
vline!([q25], color=:orange, linestyle=:dot, linewidth=2, label="Q25")
vline!([media], color=:purple, linestyle=:dashdot, linewidth=2, label="Media")
display(p1)

min_offerte = round(Int, qx)
println("Escludiamo le UP con meno del $(round(Int, percentile_scelto*100))° percentile ovvero $min_offerte offerte")

# Filtra le UP con almeno min_offerte offerte
up_valide = offerte_per_up.UP[offerte_per_up.n_offerte .>= min_offerte]
df = df[in.(df.UP, Ref(up_valide)), :]
println("Numero di unità di produzione (UP): ", length(unique(df.UP)), " (con almeno $min_offerte offerte)")

# Mostra il numero di UP uniche per ogni operatore
println("\nOperatori e numero di UP uniche dopo aver rimosso quelle con poche offerte:")
println(combine(groupby(df, :OP), :UP => x -> length(unique(x))))

# ----------------------------------------------------------------
# Clustering delle UP in base alle caratteristiche delle offerte
# ----------------------------------------------------------------

# Definzione delle features per il clustering e delle loro funzioni

function bid_skew(P)
    if length(P) < 3 || std(P) == 0
        return 0
    end
    return skewness(P)
end

# Raggruppiamo per UP e calcoliamo le features per ogni singola UP, si può esplorare il dataframe stats per vedere le features calcolate
df_grouped = groupby(df, :UP) 
stats = combine(df_grouped, 

    # Statistiche sui prezzi
    :P => mean => :P_mean, 
    :P => median => :P_median,
    :P => (x -> mode(x)) => :P_mode,
    :P => (x -> quantile(x, 0.0)) => :P_q0,
    :P => (x -> quantile(x, 0.2)) => :P_q20,
    :P => (x -> quantile(x, 0.4)) => :P_q40,
    :P => (x -> quantile(x, 0.6)) => :P_q60,
    :P => (x -> quantile(x, 0.8)) => :P_q80,
    :P => (x -> quantile(x, 1.0)) => :P_q100,
    :P => minimum => :P_min,
    :P => maximum => :P_max,
    [:P, :Q] => ((p, q) -> sum(p .* q) / sum(q)) => :P_weighted_mean,

    # Statistiche sulla quantità
    :Q => mean => :Q_mean, 
    :Q => maximum => :Q_max,
    :Q => std => :Q_std,
    :Q => (x -> mean(x)/maximum(x)) => :Q_Cf, # Capacity factor
    :Q => (q -> std(q) / mean(q)) => :CV_capacita, # Coefficiente di variazione della capacità
    :Q => (q -> (maximum(q) - minimum(q)) / maximum(q)) => :Flessibilita_Q,

    # Statistiche comportamentali
    [:P, :Q] => ((p, q) -> begin
                                if length(p) < 2 || std(p) == 0 || std(q) == 0
                                    return 0.0  # Valore di default per casi problematici
                                else
                                    return abs(cor(p, q))
                                end
                            end) => :Corr_PQ,

    # Variabilità oraria: deviazione standard della quantità media per ora del giorno
    [:Q, :time] => ((q, t) -> begin
        h = hour.(t)
        q_per_hour = [mean(q[h .== hh]) for hh in 0:23 if any(h .== hh)]
        isempty(q_per_hour) ? 0.0 : std(q_per_hour)
    end) => :Variabilita_oraria,

    # Variabilità stagionale: deviazione standard della quantità media mensile
    [:Q, :time] => ((q, t) -> begin
        m = month.(t)
        q_per_month = [mean(q[m .== mm]) for mm in 1:12 if any(m .== mm)]
        isempty(q_per_month) ? 0.0 : std(q_per_month)
    end) => :Variabilita_stagionale,

    :time => (t -> 100 * count(x -> hour(x) >= 22 || hour(x) <= 6, t) / length(t)) => :Perc_notte,
    :time => (t -> 100 * count(x -> (9 <= hour(x) <= 12) || (18 <= hour(x) <= 20), t) / length(t)) => :Perc_picco,
    
    :P => bid_skew => :BidSkew,

    # Per stimare il costo marginale
    [:P, :Q] => ((p, q) -> begin
        # First try with positive prices only
        pos_indices = p .>= 0
        
        if !any(pos_indices) || sum(q[pos_indices]) == 0
            # All prices negative or no quantity for positive prices
            # Use 20th percentile as fallback for negative-only units
            return max(5.0, quantile(p, 0.2))
        else
            # Calculate weighted average of positive prices
            weighted_avg = sum(p[pos_indices] .* q[pos_indices]) / sum(q[pos_indices])
            
            # Apply technology-based minimum thresholds
            if weighted_avg < 0.1
                # For near-zero marginal cost: likely renewables or must-run
                return 10.0  # Set minimum reasonable value
            elseif weighted_avg < 10.0
                # For very low marginal cost: likely hydro or efficient CCGT
                return max(weighted_avg, 30.0)  
            else
                # For normal thermal units, keep as is
                return weighted_avg
            end
        end
    end) => :MCost,
)

println("\nFeatures di alcune UP:")
display(stats[randperm(nrow(stats))[1:5], :])

features = [
    # :P_mean, 
    # :P_median, 
    # :P_mode, 
    # :P_q0, 
    # :P_q20, :P_q40, :P_q60, :P_q80, :P_q100,
    # :P_min, 
    # :P_max,
    :P_weighted_mean,
    :Q_max, 
    # :Q_std,
    # :Q_Cf, 
    :CV_capacita, 
    :Flessibilita_Q,
    # :Corr_PQ,
    :Variabilita_oraria, 
    :Variabilita_stagionale, 
    :Perc_notte, 
    :Perc_picco, 
    # :BidSkew,

] # Seleziona le feature da usare per il clustering

println("\nFeatures usate per il clustering: ", features)
X = hcat([stats[!, f] for f in features]...) # crea la matrice delle feature (UPs x features)

# Controlliamo se ci sono valori NaN che possono dare problemi al clustering, questo DEVE essere eseguito senza valori NaN
if any(isnan.(X))
    error("\n\033[31mValori NaN trovati nelle features, guardare il DataFrame 'stats' e rimuovere la feature interessata dal vettore 'features' \033[0m\n")
else
    println("\n\033[32mNessun valore NaN trovato nelle features USATE per il clustering, procediamo\033[0m")
end

X_norm = (X .- mean(X, dims=1)) ./ std(X, dims=1) # Normalizzazione Z-score

weights = ones(size(X, 2)) # Eventualmente si possono scegliere pesi diversi per ogni feature
# weights[2] = 1.5

X_norm .= X_norm .* weights' # Applica i pesi alle feature normalizzate

Random.seed!(1234) # Per riproducibilità 

# ---------------------
# K-means clustering
# ---------------------

println("\nK-means clustering...")

k_min = 3
k_max = round(Int, sqrt(size(stats, 1)/2)) # Regola empirica per il numero massimo di cluster

println("\nValutazione del numero di cluster k-means da $k_min a $k_max...")

# Prealloca un vettore per salvare i risultati di kmeans per ogni k
results_kmeans = Vector{Any}(undef, k_max - k_min + 1)
scores = zeros(k_max - k_min + 1, 6)
for (i, k) in enumerate(k_min:k_max)
    # println("k = $k")
    results_kmeans[i] = kmeans(X_norm', k, init=:kmpp, display=:final)

    scores[i, 1] = k
    scores[i, 2] = clustering_quality(X_norm', results_kmeans[i].centers, results_kmeans[i].assignments, quality_index=:calinski_harabasz, metric=SqEuclidean())
    scores[i, 3] = clustering_quality(X_norm', results_kmeans[i], quality_index=:silhouettes, metric=SqEuclidean())
    scores[i, 4] = clustering_quality(X_norm', results_kmeans[i], quality_index=:dunn, metric=SqEuclidean())
    scores[i, 5] = clustering_quality(X_norm', results_kmeans[i].centers, results_kmeans[i].assignments, quality_index=:davies_bouldin, metric=SqEuclidean())
    scores[i, 6] = clustering_quality(X_norm', results_kmeans[i].centers, results_kmeans[i].assignments, quality_index=:xie_beni, metric=SqEuclidean())
end

# Visualizza i punteggi per ogni k
p2 = plot(scores[:, 1], scores[:, 2], title="calinski_harabasz", legend=false)
p3 = plot(scores[:, 1], scores[:, 3], title="silhouette", legend=false)
p4 = plot(scores[:, 1], scores[:, 4], title="dunn", legend=false)
p5 = plot(scores[:, 1], scores[:, 5], title="davies_bouldin", legend=false)
p6 = plot(scores[:, 1], scores[:, 6], title="xie_beni", legend=false)
p7 = plot(p2, p3, p4, p5, p6, 
    layout=(5,1), 
    size=(900, 1200), 
    xlabel="N cluster", 
    ylabel="Quality", 
    marker=:circle,
    left_margin=10Plots.mm,
)
display(p7)

# Scelta del numeri di cluster migliore secondo gli indicatori
# Calcola un indicatore medio per ogni k (usando silhouette, calinski_harabasz, dunn positivi e davies_bouldin, xie_beni negativi)
# Normalizza ogni colonna tra 0 e 1 (max-min scaling) per confrontabilità
norm_scores = copy(scores)
for j in 2:6
    col = scores[:, j]
    if j in (5, 6)  # davies_bouldin, xie_beni: min è meglio
        norm_scores[:, j] = (maximum(col) .- col) ./ (maximum(col) - minimum(col) + eps())
    else             # silhouette, calinski_harabasz, dunn: max è meglio
        norm_scores[:, j] = (col .- minimum(col)) ./ (maximum(col) - minimum(col) + eps())
    end
end

mean_indicator = mean(norm_scores[:, 2:6], dims=2)
best_k_idx = argmax(mean_indicator)
k_best = round(Int, scores[best_k_idx, 1])
println("\nk scelto in base all'indicatore medio normalizzato: $k_best")

# Associa la colonna OP a stats_kmeans tramite join con stats (che ha UP e OP)
stats_kmeans = copy(stats)
stats_kmeans.Cluster = results_kmeans[k_best - k_min + 1].assignments
stats_kmeans = leftjoin(stats_kmeans, unique(df[:, [:UP, :OP]]), on=:UP)

# Calcola le statistiche per ogni cluster (k = kbest) usando features per cluster
println("\nStatistiche medie per cluster k-means con k = $k_best:")
agg_funs = [mean for _ in features]
cluster_stats_kmeans = combine(groupby(stats_kmeans, :Cluster),
    nrow => :N,
    (features .=> agg_funs)...
)
pretty_table(cluster_stats_kmeans)

# ---------------------------------------------------------------
# DBSCAN clustering SOLO per confronto, meno sensibile a outlier
# ---------------------------------------------------------------

println("\nDBSCAN clustering (per confronto)...")

results_dbscan = dbscan(X_norm', 0.5, metric=Euclidean(), min_neighbors=2*length(features), min_cluster_size=1) # Andrebbe scelto per bene eps e min_cluster_size
stats_dbscan = copy(stats)
stats_dbscan.Cluster = results_dbscan.assignments
stats_dbscan = leftjoin(stats_dbscan, unique(df[:, [:UP, :OP]]), on=:UP)

println("\nStatistiche per cluster DBSCAN:")
agg_funs = [mean for _ in features]
cluster_stats_dbscan = combine(groupby(stats_dbscan, :Cluster),
    nrow => :N,
    (features .=> agg_funs)...
)
pretty_table(cluster_stats_dbscan)

# ----------------------------------------
# Plotta i risultati del clustering
# ----------------------------------------

# Grafico k-means
p8 = scatter(
    stats_kmeans.Q_mean,
    stats_kmeans.P_weighted_mean,
    group=stats_kmeans.Cluster,
    title="k-means Clustering for k = $k_best",
    legend=false
)

# Grafico DBSCAN
p9 = scatter(
    stats_dbscan.Q_mean,
    stats_dbscan.P_weighted_mean,
    group=stats_dbscan.Cluster,
    title="DBSCAN clustering",
    legend=false
)

# Plotta i grafici del clustering insieme
p10 = plot(p8, p9, 
    layout=(2,1),
    xlabel=L"Q_{mean} \ [MWh]", 
    ylabel=L"P_{w,mean} \ [€/MWh]", 
    legend=false,
    size=(800,600)
)
display(p10)

# ---------------------------------------------------
# Tabella con operatori e tipo di UP in ogni cluster
# ---------------------------------------------------

println("\nRisultati final del clustering k-means (k = $k_best):")

# Tabella pivot: righe=cluster, colonne=operatori, valori=numero di UP
cluster_op = combine(groupby(stats_kmeans, [:Cluster, :OP]), nrow => :N)
cluster_op_pivot = unstack(cluster_op, :OP, :N, fill=0)
sort!(cluster_op_pivot, :Cluster)
println("\nTabella: numero di UP per operatore in ogni cluster (righe=cluster, colonne=operatori):")
pretty_table(cluster_op_pivot)

# --------------------------------
# Salvare gli output dello script
# --------------------------------

save_output = true  # Se true, salva tutto nella cartella /output
fig_format = :pdf 
timestamp = Dates.format(Dates.now(), "yyyy-mm-ddTHHMMSS") # Timestamp per i file di output

if save_output
    outdir = joinpath(@__DIR__, "output", string(timestamp, "_run_outputs"))
    mkpath(outdir)  # Crea la cartella se non esiste

    # Parametri script
    param_path = joinpath(outdir, "parametri_script.txt")
    open(param_path, "w") do io
        println(io, "============================\nPARAMETRI SCRIPT CLUSTERING\n============================\n")
        println(io, "File CSV usato: $csv_name")
        println(io, "Percentile scelto per filtro offerte: $percentile_scelto")
        println(io, "Numero minimo offerte per UP: $min_offerte")
        println(io, "Features usate per clustering: $(join(string.(features), ", "))")
        println(io, "Range k-means: k_min = $k_min, k_max = $k_max")
        println(io, "k scelto per k-means: $k_best")
        println(io, "Seed random: 1234")
        println(io, "Data esecuzione: $(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM"))")
    end
    println("\nSalvataggio dei parametri dello script in: $param_path")

    # Figure
    savepath = joinpath(outdir, string("offerte_per_up_distribution.$fig_format"))
    println("\nSalvataggio del grafico della distribuzione delle offerte per UP in: $savepath")
    savefig(p1, savepath)

    savepath = joinpath(outdir, string("kmeans_quality_indices.$fig_format"))
    println("\nSalvataggio del grafico degli indici di qualità del clustering in: $savepath")
    savefig(p7, savepath)

    savepath = joinpath(outdir, string("clustering_results.$fig_format"))
    println("\nSalvataggio del grafico del clustering in: $savepath")
    savefig(p10, savepath)

    # CSV con unità di produzione, operatore, tipo (cluster), capacità, costo marginale stimato
    up_output_df = stats_kmeans[:, [:OP, :UP, :Cluster, :Q_mean, :MCost]]

    csv_UP = joinpath(outdir, string("up_clustering.csv"))
    println("\nSalvataggio del CSV delle UP in: $csv_UP")
    CSV.write(csv_UP, up_output_df)

    csv_ClusterStats = joinpath(outdir, string("cluster_stats_kmeans.csv"))
    println("\nSalvataggio del CSV delle statistiche per cluster in: $csv_ClusterStats")
    CSV.write(csv_ClusterStats, cluster_stats_kmeans)
end