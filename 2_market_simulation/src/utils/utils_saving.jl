function save_simulation_data(sim_results, dir_output)
    file_name = "$(sim_results[:sim_name]).jdl2"
    
    @save "$dir_output\\$file_name" sim_results
    @info "Dati della simulazione salvati in in: $(file_name)"
    return nothing
end

function save_Q_table(Q, counts, output_dir, Q_table_name)
    JLD2.@save joinpath(output_dir, Q_table_name) Q counts
    println("Q-table salvata in $(joinpath(output_dir, Q_table_name))")
end

function save_figure(figure_counter::Int, plot, dir_output::String, filename::String)
    global figure_counter += 1
    try
        savefig(plot, joinpath(dir_output, string(figure_counter)*"_"*filename))
    catch e
        @error "Errore durante il salvataggio della figura: $e"
    end
    return nothing
end
