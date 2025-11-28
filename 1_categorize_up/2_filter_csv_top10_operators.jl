using CSV, DataFrames, Dates

# ----------------------------------------
# INPUT
csv_name = "2025-08-28_132205-offerte" # CSV contenente TUTTE le offerte del GME con le colonne originali
flag_save_csv = true # [true, false] solo se si vuole salvare il CSV intermedio contenente tutte le offerte filtrate secondo la funzione "clean_data"

#--------------------------------------------------------
#= Filtriamo il CSV con tutte le offerte per tenere:
    1. solo le offerte ACCETTATE e RIFIUTATE (vettore status_cd_values)
    2. solo le offerte di vendita rimuovendo quelle di acquisto (vettore purpose_cd_values)    
    3. solo i 10 operatori principali (vettore operatori_values)
    4. rimuoviamo le unità di produzione il cui nome inizia con "UPV_" corrispondenti ad offerte virtuali estere
=#

# Carica il CSV output dello script estrai-offerte-zip2csv.jl
csv_path = joinpath(@__DIR__, "data", "csv", csv_name * ".csv")
df = DataFrame()
try
    println("Caricamento del CSV contenente TUTTE le offerte \n$csv_path")
    global df = CSV.read(csv_path, DataFrame,
        debug=false,
        ignoreemptyrows=true,
        delim=',',
        decimal='.',
        ignorerepeated=true,
        silencewarnings=true,
        ntasks=Sys.CPU_THREADS,
    )
    println("Caricamento completato con successo.")
catch e
    println("Errore durante la lettura del file: ", e)
end

println("\nNumero di righe PRIMA di rimuovere quelle con valori missing: ", nrow(df))
dropmissing!(df) # rimuoviamo le righe con valori missing
println("Numero di righe DOPO aver rimosso quelle con valori missing: ", nrow(df))

function clean_data(df::DataFrame)
    # Filtri secondo i nomi del file XML originale dal GME Offerte Pubbliche
    status_cd_values = ["ACC", "REJ"]
    purpose_cd_values = ["OFF"]
    operatori_values = [
        "A2A ENERGIEFUTURE S.P.A.",
        "A2A SPA",
        "ENEL PRODUZIONE S.P.A.",
        "EDISON SPA",
        "ENI PLENITUDE S.P.A. SOCIETA' BENEFIT",
        "ENI SPA",
        "EP PRODUZIONE SPA",
        "SORGENIA S.P.A.",
        "IREN ENERGIA SPA",
        "AXPO ITALIA SPA",
        "TIRRENO POWER S.P.A.",
        "DXT COMMODITIES SA"
    ]

    # Applica i filtri step by step
    df = filter(row -> row.STATUS_CD in status_cd_values, df)
    df = filter(row -> row.PURPOSE_CD in purpose_cd_values, df)
    df = filter(row -> row.OPERATORE in operatori_values, df)
    println("Dopo i filtri STATUS, PURPOSE e OPERATORE: ", nrow(df), " righe.")
    println("Filtriamo le UPV corrispondenti ad offerte virtuali dell'estero...")
    df = filter(row -> !startswith(row.UNIT_REFERENCE_NO, "UPV_"), df)
    println("Dopo il filtro delle UPV: ", nrow(df), " righe.")

    return df
end

df_clean = clean_data(df) # applichiamo i filtri

# Salva il CSV pulito se si vuole
if flag_save_csv
    clean_csv_name = csv_name * "_top10op"
    clean_csv_path = joinpath(@__DIR__, "data", "csv", clean_csv_name * ".csv")
    println("\nSalvataggio del CSV filtrato in $clean_csv_path")
    CSV.write(clean_csv_path, df_clean)
    println("Salvataggio completato.")
end

#--------------------------------------------------------
# Dal DataFrame filtrato ne otteniamo uno più comodo per le successive elaborazioni
println("\nCreazione di un DataFrame più comodo per le successive elaborazioni...")

# selezioniamo solo le colonne utili secondo i nomi del file XML originale dal GME Offerte Pubbliche
df_final = df_clean[:, [:ENERGY_PRICE_NO, :QUANTITY_NO, :INTERVAL_NO, :BID_OFFER_DATE_DT, :OPERATORE, :UNIT_REFERENCE_NO]]

# cambiamo i nomi delle colonne per comodità
rename!(df_final, Dict(
    :ENERGY_PRICE_NO => :P,
    :QUANTITY_NO => :Q,
    :INTERVAL_NO => :hour,
    :BID_OFFER_DATE_DT => :day,
    :OPERATORE => :OP,
    :UNIT_REFERENCE_NO => :UP)
)

# Uniamo data (formato da XML = yyyymmdd, modificare se necessario) e ora in un unico campo DateTime e rimuoviamo le colonne originali
df_final.time = DateTime.(string.(df_final.day), dateformat"yyyymmdd") .+ Hour.(df_final.hour)
select!(df_final, Not([:hour, :day])) # rimuoviamo le colonne originali di data e ora
sort!(df_final, [:UP, :time]) # Ordiniamo per UP e time

# Uniamo le unità di A2A e A2A ENERGIEFUTURE e di ENI e ENI PLENITUDE
println("\nTotale UP uniche PRIMA dell'unione: ", length(unique(df_final.UP)))
println("Uniamo A2A ENERGIEFUTURE S.P.A. e A2A SPA")
replace!(df_final.OP, "A2A ENERGIEFUTURE S.P.A." => "A2A SPA")
println("Uniamo ENI PLENITUDE S.P.A. SOCIETA' BENEFIT e ENI SPA")
replace!(df_final.OP, "ENI PLENITUDE S.P.A. SOCIETA' BENEFIT" => "ENI SPA")
println("Check totale UP uniche DOPO l'unione: ", length(unique(df_final.UP)))

# ----------------------------------------
# Alcuni output sul DataFrame finale

println("\n" * "-"^40)
println("    Riepilogo del DataFrame finale    ")
println("-"^40)

println("\nDimensioni del DataFrame finale: ", size(df_final)) # (numero di righe, numero di colonne)
println("Colonne del DataFrame finale: ", names(df_final))
println("Numero di offerte totali: ", nrow(df_final))

# Periodo dei dati
println("\nPeriodo di osservazione: ", minimum(df_final.time), " - ", maximum(df_final.time))
println("Numero di giorni di osservazione: ", length(unique(Date.(df_final.time))))

# Mostra il numero di UP uniche per ogni operatore
println("\nOperatori e numero di UP uniche:")
println(combine(groupby(df_final, :OP), :UP => x -> length(unique(x))))

# Mostra alcune righe del DataFrame finale
println("\nEsempio di righe del DataFrame finale:")
println(first(df_final, 10)) # mostra le prime 5 righe del DataFrame finale

# --------------------------
# Salviamo il DataFrame finale in un nuovo CSV

final_csv_name = csv_name * "_top10op_final"
final_csv_path = joinpath(@__DIR__, "data", "csv", final_csv_name * ".csv")
println("\nSalvataggio del CSV finale in $final_csv_path")
CSV.write(final_csv_path, df_final)
println("Salvataggio completato.")