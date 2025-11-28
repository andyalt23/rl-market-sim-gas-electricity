using ZipFile, EzXML, DataFrames, CSV, Dates

work_dir = @__DIR__
zip_dir = joinpath(work_dir, "data", "zip")
csv_dir = joinpath(work_dir, "data", "csv")
isdir(csv_dir) || mkpath(csv_dir)

zip_files = filter(f -> endswith(lowercase(f), ".zip"), readdir(zip_dir))
n_files = length(zip_files)

println("Trovati ", length(zip_files), " file .zip\n Iniziamo l'estrazione...")

timestamp = Dates.format(now(), "yyyy-mm-dd_HHMMSS")
csv_path = joinpath(csv_dir, "$timestamp-offerte.csv")
first_write = true
ultimo_file_ok = "nessuno"
 # Buffer per accumulare i DataFrame
 buffer_offers = DataFrame[]
 BUFFER_SIZE = 7

try
    for (i, zip_name) in enumerate(zip_files)
        zip_path = joinpath(zip_dir, zip_name)
        archive = ZipFile.Reader(zip_path)
        file_offers = DataFrame()

    percent = round(i / n_files * 100; digits=1)
    nowstr = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    println("[$nowstr] Estrazione file $i/$n_files ($percent%) - $zip_name")

        try
            for file in archive.files
                if endswith(lowercase(file.name), ".xml")
                    xml_content = read(file, String)
                    doc = EzXML.parsexml(xml_content)

                    for offerta in findall("//OfferteOperatori", doc)
                        row = Dict{Symbol,Any}()
                        for field in EzXML.elements(offerta)
                            row[Symbol(EzXML.nodename(field))] = EzXML.nodecontent(field)
                        end
                        push!(file_offers, row; cols=:union)
                    end
                end
            end
        finally
            close(archive)
            if nrow(file_offers) > 0
                # Conversione colonna data se presente
                if :BID_OFFER_DATE_DT in names(file_offers)
                    file_offers[!, :BID_OFFER_DATE_DT] = Date.(file_offers.BID_OFFER_DATE_DT, dateformat"yyyymmdd")
                end
                    push!(buffer_offers, file_offers)
            end
            # Scrivi ogni 7 file o all'ultimo giro
            if length(buffer_offers) == BUFFER_SIZE || i == n_files
                if !isempty(buffer_offers)
                    df_to_write = vcat(buffer_offers...; cols=:union)
                    CSV.write(csv_path, df_to_write; append = !first_write)
                    if first_write
                        global first_write = false
                    end
                    println("Aggiunte ", nrow(df_to_write), " righe al file CSV (ogni ", BUFFER_SIZE, ").")
                    empty!(buffer_offers)
                    # Aggiorna ultimo_file_ok solo dopo aver scritto su disco
                    global ultimo_file_ok = zip_name
                end
            end
            end
        end
catch e
    println("ERRORE: $(e)")
    println("Ultimo file estratto con successo: $ultimo_file_ok")
finally
    println("Salvato in: $csv_path")
end