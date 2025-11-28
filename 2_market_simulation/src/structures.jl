mutable struct Offer
    Op::String
    UP::String
    Zona::String
    Type::String
    SubType::String
    MCost::Float64
    P::Float64
    Q::Float64
end

struct UnitaProduzione
    UP::String
    Op::String
    Type::String
    SubType::String
    MCost::Float64
    Capacity::Float64
end

mutable struct Operatore
    Op::String
    up_portfolio::Vector{UnitaProduzione}
    function Operatore(name::String)
        new(name, UnitaProduzione[])
    end
end

mutable struct RisultatiMercato
    sim_offerte::DataFrame
    results::Dict{String, Any}
    profitti::Dict{String, Float64}
end

struct SimulationResults
    description::String
    operatori::Dict{String, Operatore}
    D::Float64
    simulations::Dict{String, Any}  # Generico: chiave = nome simulazione, valore (es. RisultatiMercato, DataFrame, ecc.)
end
