# =======================================================
# Utils per la visualizzazione dei risultati
# Contiene funzioni per generare grafici delle simulazioni
# =======================================================

# using Plots, DataFrames

function PlotResultsPaC(sim_offerte::DataFrame, D::Float64)
    # Ordina sim_offerte per prezzo crescente
    sim_offerte_sorted = sort(sim_offerte, :P)
    prezzi = sim_offerte_sorted.P
    quantita = sim_offerte_sorted.Q
    clearing_price = unique(sim_offerte_sorted.P_acc)[1]

    # Gradino parte da 0 MWh e dal primo prezzo
    quantita_cum = vcat(0.0, cumsum(quantita))
    prezzi_ext = vcat(prezzi[1], prezzi)

    min_prezzo = minimum(prezzi)
    max_prezzo = maximum(prezzi)

    ymin_plot = min_prezzo == 0 ? -50 : (min_prezzo < 0 ? min_prezzo * 1.1 : min_prezzo * 0.8)
    ymax_plot = max_prezzo * 1.1

    plt = plot(
        quantita_cum, prezzi_ext,
        seriestype = :steppre,
        label = "Curva di offerta",
        xlabel = "Energia [MWh]",
        ylabel = "Prezzo [€/MWh]",
        linewidth = 2,
        title = "Risultati PaC",
        ylims = (ymin_plot, ymax_plot)
    )
    vline!([D], color = :red, linewidth = 2, linestyle = :dash, label = "Domanda $D MWh")
    hline!([clearing_price], color = :green, linewidth = 2, linestyle = :dash, label = "Clearing price $clearing_price €/MWh")
    display(plt)
    return plt
end

function PlotResultsPaB(sim_offerte::DataFrame, D::Float64)
    # Ordina sim_offerte per prezzo crescente
    sim_offerte_sorted = sort(sim_offerte, :P)
    prezzi = sim_offerte_sorted.P
    quantita = sim_offerte_sorted.Q
    prezzi_assegnati = sim_offerte_sorted.P_acc

    # Gradino parte da 0 MWh e dal primo prezzo
    quantita_cum = vcat(0.0, cumsum(quantita))
    prezzi_ext = vcat(prezzi[1], prezzi)

    min_prezzo = minimum(prezzi)
    max_prezzo = maximum(prezzi)

    ymin_plot = min_prezzo == 0 ? -50 : (min_prezzo < 0 ? min_prezzo * 1.1 : min_prezzo * 0.8)
    ymax_plot = max_prezzo * 1.1

    plt = plot(
        quantita_cum, prezzi_ext,
        seriestype = :steppre,
        label = "Curva di offerta",
        xlabel = "Energia [MWh]",
        ylabel = "Prezzo [€/MWh]",
        linewidth = 2,
        title = "Risultati PaB",
        ylims = (ymin_plot, ymax_plot)
    )
    vline!([D], color = :red, linewidth = 2, linestyle = :dash, label = "Domanda $D MWh")
    first_line = true
    for p in prezzi_assegnati
        if abs(p) < 1e-8
            continue  # Salta i prezzi nulli
        end
        hline!([p],
            color = :green,
            linewidth = 2,
            linestyle = :dash,
            label = first_line ? "Prezzi assegnati" : "",
            alpha = 0.5
        )
        first_line = false
    end
    display(plt)
    return plt
end

function PlotResultsSPaC(sim_offerte::DataFrame, D::Float64, Dr::Float64, π::Float64, πr::Float64)
    # Filtra le offerte per tipo (FCMT e FCMNT)
    fcmt_offers = filter(row -> row.Type == "FCMT", sim_offerte)
    fcmnt_offers = filter(row -> row.Type == "FCMNT", sim_offerte)
    
    # Ordina per prezzo crescente
    fcmt_sorted = sort(fcmt_offers, :P)
    fcmnt_sorted = sort(fcmnt_offers, :P)
    
    # Calcola i valori cumulativi per entrambe le curve
    fcmt_prezzi = fcmt_sorted.P
    fcmt_quantita = fcmt_sorted.Q
    fcmt_quantita_cum = vcat(0.0, cumsum(fcmt_quantita))
    fcmt_prezzi_ext = vcat(fcmt_prezzi[1], fcmt_prezzi)
    
    fcmnt_prezzi = fcmnt_sorted.P
    fcmnt_quantita = fcmnt_sorted.Q
    fcmnt_quantita_cum = vcat(0.0, cumsum(fcmnt_quantita))
    fcmnt_prezzi_ext = vcat(fcmnt_prezzi[1], fcmnt_prezzi)
    
    # Calcola i limiti per gli assi y
    min_prezzo_fcmt = isempty(fcmt_prezzi) ? 0 : minimum(fcmt_prezzi)
    max_prezzo_fcmt = isempty(fcmt_prezzi) ? 100 : maximum(fcmt_prezzi)
    min_prezzo_fcmnt = isempty(fcmnt_prezzi) ? 0 : minimum(fcmnt_prezzi)
    max_prezzo_fcmnt = isempty(fcmnt_prezzi) ? 100 : maximum(fcmnt_prezzi)
    
    ymin_plot_fcmt = min_prezzo_fcmt == 0 ? -50 : (min_prezzo_fcmt < 0 ? min_prezzo_fcmt * 1.1 : min_prezzo_fcmt * 0.8)
    ymax_plot_fcmt = max_prezzo_fcmt * 1.1
    ymin_plot_fcmnt = min_prezzo_fcmnt == 0 ? -50 : (min_prezzo_fcmnt < 0 ? min_prezzo_fcmnt * 1.1 : min_prezzo_fcmnt * 0.8)
    ymax_plot_fcmnt = max_prezzo_fcmnt * 1.1
    
    # Calcola il clearing price totale per FCMT
    fcmt_clearing_price = π + πr
    
    # Crea un subplot con 2 righe e 1 colonna
    plt = plot(layout = (2, 1), size = (800, 1000), left_margin = 10Plots.mm)
    
    # Plot superiore per FCMT
    plot!(
        plt[1],
        fcmt_quantita_cum, fcmt_prezzi_ext,
        seriestype = :steppre,
        label = "Curva di offerta FCMT",
        xlabel = "Energia [MWh]",
        ylabel = "Prezzo [€/MWh]",
        linewidth = 2,
        title = "Risultati SPaC - FCMT",
        ylims = (ymin_plot_fcmt, ymax_plot_fcmt)
    )
    vline!(plt[1], [Dr], color = :red, linewidth = 2, linestyle = :dash, label = "Domanda $Dr MWh")
    hline!(plt[1], [fcmt_clearing_price], color = :green, linewidth = 2, linestyle = :dash, label = "Clearing price $(round(fcmt_clearing_price, digits=2)) €/MWh")
    
    # Plot inferiore per FCMNT
    plot!(
        plt[2],
        fcmnt_quantita_cum, fcmnt_prezzi_ext,
        seriestype = :steppre,
        label = "Curva di offerta FCMNT",
        xlabel = "Energia [MWh]",
        ylabel = "Prezzo [€/MWh]",
        linewidth = 2,
        title = "Risultati SPaC - FCMNT",
        ylims = (ymin_plot_fcmnt, ymax_plot_fcmnt)
    )
    vline!(plt[2], [D - Dr], color = :red, linewidth = 2, linestyle = :dash, label = "Domanda $(round(D - Dr, digits=2)) MWh")
    hline!(plt[2], [π], color = :green, linewidth = 2, linestyle = :dash, label = "Clearing price $(round(π, digits=2)) €/MWh")
    
    display(plt)
    return plt
end

# Funzione semplice per media mobile
function moving_average(vec, window)
    n = length(vec)
    out = similar(vec)
    for i in 1:n
        left = max(1, i - window ÷ 2)
        right = min(n, i + window ÷ 2)
        out[i] = mean(vec[left:right])
    end
    return out
end

# Funzione per plottare la policy ottimale degli operatori usando legenda_azioni (heatmap cluster vs domanda)
function plot_op_policy(op_policy::Dict, legenda_azioni::Dict, nome_mercato::String; print_legend::Bool=false)
    palette = [RGB(0.7,0.85,0.92), RGB(0.5,0.7,0.5), RGB(0.95,0.85,0.5), RGB(0.8,0.3,0.3)]
    labels = ["Markup nullo", "Markup basso", "Markup medio", "Markup alto"]

    markup_to_cat(m) = m == 0.0 ? 1 : m <= 5.0 ? 2 : m <= 15.0 ? 3 : 4

    op_names = collect(keys(op_policy))
    n_ops = length(op_names)
    plots = Vector{Any}(undef, print_legend ? n_ops+1 : n_ops)
    if print_legend
        plegend = plot(legend=:top, grid=false, framestyle=:none, xaxis=false, yaxis=false, size=(800,80), title="Legenda markup")
        for i in 1:4
            scatter!(plegend, [NaN], [NaN], label=labels[i], color=palette[i], markerstrokecolor=:black, markersize=10)
        end
        plots[1] = plegend
    end
    for (k, op) in enumerate(op_names)
        a = op_policy[op]
        legendₐ = legenda_azioni[op]
        domande = collect(keys(a)) |> sort
        num_cluster = length(legendₐ)
        mat_markup = zeros(length(domande), num_cluster)
        for (i, d) in enumerate(domande)
            markups = a[d]
            for (j, m) in enumerate(markups)
                mat_markup[i, j] = m
            end
        end
        mat_cat = map(markup_to_cat, mat_markup)
        p = heatmap(
            domande, 1:num_cluster, mat_cat',
            xlabel = "Domanda [MW]",
            ylabel = "Cluster",
            yticks = (1:num_cluster, legendₐ),
            color = palette,
            colorbar = false,
            title = "Policy ottimale $(op) - $(nome_mercato)",
            size = (800, 250)
        )
        plots[print_legend ? k+1 : k] = p
    end
    display(plot(plots..., layout=(length(plots),1), size=(800, 80*print_legend+250*n_ops)))
    return plot(plots..., layout=(length(plots),1), size=(800, 80*print_legend+250*n_ops))
end

function plot_profitti_RL_training(profitti)
    grouped = groupby(profitti, :operator)
    n_ops = length(grouped)
    plt = plot(layout = (n_ops, 1), size=(800, 250*n_ops))
    for (i, g) in enumerate(grouped)
        y = moving_average(g.profit, 100)
        plot!(plt[i], g.episode, y, label="", lw=2)
        xlabel!(plt[i], "Episodi")
        ylabel!(plt[i], "Profitto [€]")
        title!(plt[i], string(g.operator[1]))
    end
    display(plt)
    return plt
end

function plot_PUN_RL_training_PaB_PaC(pun)
    y = moving_average(pun, 100)
    plt = plot(1:length(pun), y, label="PUN", lw=2, color=:blue)
    xlabel!("Episodi")
    ylabel!("PUN [€/MWh]")
    display(plt)
    return plt
end

function plot_PUN_RL_training_SPaC(pun)
    y1 = moving_average(pun[:, 1], 100)
    y2 = moving_average(pun[:, 2], 100)
    y3 = moving_average(pun[:, 3], 100)
    n = size(pun, 1)
    plt = plot(layout = (3, 1), size = (800, 900), legend = :topright)

    plot!(plt[1], 1:n, y1, lw = 2, color = :blue, legend=false)
    ylabel!(plt[1], "PUN [€/MWh]")

    plot!(plt[2], 1:n, y2, lw = 2, color = :red, legend=false)
    ylabel!(plt[2], "Clearing price FCMT [€/MWh]")

    plot!(plt[3], 1:n, y3, lw = 2, color = :green, legend=false)
    xlabel!(plt[3], "Episodi")
    ylabel!(plt[3], "Clearing price FCMNT [€/MWh]")

    display(plt)
    return plt
end

function plot_curva_domanda(x, y)
    # x rappresenta i 96 quarti d'ora di un giorno (24 ore)
    # Per i tick delle ore, ogni 4 step è un'ora (4*15min = 1h)
    xticks_pos = 1:4:96
    xticks_labels = ["$(Int((i-1)/4))" for i in xticks_pos]  # Etichette ore: 0,1,...,23
    pd = plot(
        x, y,
        title = "Curva di domanda giornaliera",
        xlabel = "Ora del giorno",
        ylabel = "Domanda [MW]",
        legend = false,
        lw = 2,
        color = :blue,
        size = (800, 400),
        xticks = (xticks_pos, xticks_labels),
        left_margin = 10Plots.mm,
        bottom_margin = 10Plots.mm
    )
    display(pd)
    return pd
end

function plot_PUN_giornaliero(costi_mercati::DataFrame, yₛ::Vector{Float64})
    xticks_pos = 1:4:96
    xticks_labels = ["$(Int((i-1)/4))" for i in xticks_pos]  # Etichette ore: 0,1,...,23
    p = plot(xlabel="Ora del giorno", ylabel="PUN [€/MWh]", legend=:topright, xticks = (xticks_pos, xticks_labels), lw=2, size=(800,400))
    for mkt in ["PaB", "PaC", "SPaC"]
        pun_values = costi_mercati.PUN[costi_mercati.mercato .== mkt]
        plot!(p, 1:length(yₛ), pun_values, label=mkt, lw=2)
    end
    # display(p)
    return p
end

