# =======================================================
# Utils per la conversione dei dati
# Contiene funzioni per adattare dati agli script esistenti
# =======================================================

# -------------------------------------------------------
# Funzioni di conversione per script di Fabrizio
# -------------------------------------------------------

function convert_dfoffers_for_SolveMyPaC(df_offerte::DataFrame)
    
    sort!(df_offerte, :P) # ordinare per prezzo crescente

    S = Vector{Offer}(undef, nrow(df_offerte))

    for (i, row) in enumerate(eachrow(df_offerte))
        S[i] = Offer(
            string(row.OP),
            string(row.UP),
            string(row.Zona),
            string(row.Type),
            string(row.SubType),
            Float64(row.MCost),
            Float64(row.P),
            Float64(row.Q)
        )
    end

    Offerte = collect(1:length(S)) # indici per JuMP

    π = df_offerte.P   # vettore prezzi offerta
    Q = df_offerte.Q   # vettore quantità offerta

    return S, Offerte, π, Q

end