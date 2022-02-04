"""
Provides storage of simulation data
"""
abstract type SimulationStore end

# Required methods:
# - open_store
# - Base.isopen(store::SimulationStore)
# - Base.close(store::SimulationStore)
# - Base.flush(store::SimulationStore)
# - get_params(store::SimulationStore)
# - initialize_problem_storage!
# - list_fields(store::SimulationStore, problem::Symbol, container_type::Symbol)
# - list_problems(store::SimulationStore)
# - log_cache_hit_percentages(store::SimulationStore)
# - write_result!
# - read_result!
# - write_optimizer_stats!
# - read_optimizer_stats
# - get_dm_data
# - get_em_data

get_dm_data(store::SimulationStore) = store.dm_data
get_em_data(store::SimulationStore) = store.em_data