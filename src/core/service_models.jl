"""
Abstract type for Service Formulations (a.k.a Models)

# Example
```julia
import PowerSimulations
const PSI = PowerSimulations
struct MyServiceFormulation <: PSI.AbstractServiceFormulation
```
"""
abstract type AbstractServiceFormulation end
abstract type AbstractReservesFormulation <: AbstractServiceFormulation end

function _check_service_formulation(
    ::Type{D},
) where {D <: Union{AbstractServiceFormulation, PSY.Service}}
    if !isconcretetype(D)
        throw(
            ArgumentError(
                "The service model must contain only concrete types, $(D) is an Abstract Type",
            ),
        )
    end
end

"""
Establishes the model for a particular services specified by type. Uses the keyword argument
`use_service_name` to assign the model to a service with the same name as the label in the
template. Uses the keyword argument feedforward to enable passing values between operation
model at simulation time

# Arguments
-`::Type{D}`: Power System Service Type
-`::Type{B}`: Abstract Service Formulation

# Accepted Key Words
- `feedforward::Array{<:AbstractAffectFeedForward}` : use to pass parameters between models
- `use_service_name::Bool` : use the label as the name for the service

# Example
```julia
reserves = ServiceModel(PSY.VariableReserve{PSY.ReserveUp}, RangeReserve)
```
"""
mutable struct ServiceModel{D <: PSY.Service, B <: AbstractServiceFormulation}
    component_type::Type{D}
    formulation::Type{B}
    feedforward::Union{Nothing, AbstractAffectFeedForward}
    use_service_name::Bool
    function ServiceModel(
        ::Type{D},
        ::Type{B};
        feedforward::Union{Nothing, AbstractAffectFeedForward} = nothing,
        use_service_name::Bool = false,
    ) where {D <: PSY.Service, B <: AbstractServiceFormulation}
        _check_service_formulation(D)
        _check_service_formulation(B)
        new{D, B}(D, B, feedforward, use_service_name)
    end
end

get_component_type(m::ServiceModel) = m.component_type
get_formulation(m::ServiceModel) = m.formulation
get_feedforward(m::ServiceModel) = m.feedforward

function _set_model!(dict::Dict, key::Tuple{String, Symbol}, model::ServiceModel)
    if haskey(dict, key)
        @info("Overwriting $(key) existing model")
    end
    dict[key] = model
    return
end

function _set_model!(
    dict::Dict,
    service_name::String,
    model::ServiceModel{D, B},
) where {D <: PSY.Service, B <: AbstractServiceFormulation}
    if !model.use_service_name
        throw(
            IS.ConflictingInputsError(
                "The model provided has use_service_name false. This method can't be used",
            ),
        )
    end
    _set_model!(dict, (service_name, Symbol(D)), model)
    return
end

function _set_model!(
    dict::Dict,
    model::ServiceModel{D, B},
) where {D <: PSY.Service, B <: AbstractServiceFormulation}
    if model.use_service_name
        throw(
            IS.ConflictingInputsError(
                "The model provided has use_service_name set to true and no service name was provided. This method can't be used",
            ),
        )
    end
    _set_model!(dict, (NO_SERVICE_NAME_PROVIDED, Symbol(D)), model)
    return
end
