@testset "Simulation Build Tests" begin
    problems = create_simulation_build_test_problems(get_template_basic_uc_simulation())
    sequence = SimulationSequence(
        problems = problems,
        feedforward_chronologies = Dict(("UC" => "ED") => Synchronize(periods = 24)),
        intervals = Dict(
            "UC" => (Hour(24), Consecutive()),
            "ED" => (Hour(1), Consecutive()),
        ),
        feedforward = Dict(
            ("ED", :devices, :ThermalStandard) => SemiContinuousFF(
                binary_source_problem = PSI.ON,
                affected_variables = [PSI.ACTIVE_POWER],
            ),
        ),
        ini_cond_chronology = InterProblemChronology(),
    )
    sim = Simulation(
        name = "test",
        steps = 1,
        problems = problems,
        sequence = sequence,
        simulation_folder = mktempdir(cleanup = true),
    )

    build_out = build!(sim)
    @test build_out == PSI.BuildStatus.BUILT

    @test isempty(values(sim.internal.simulation_cache))
    for field in fieldnames(SimulationSequence)
        if fieldtype(SimulationSequence, field) == Union{Dates.DateTime, Nothing}
            @test !isnothing(getfield(sim.sequence, field))
        end
    end
    @test isa(sim.sequence, SimulationSequence)

    @test length(findall(x -> x == 2, sequence.execution_order)) == 24
    @test length(findall(x -> x == 1, sequence.execution_order)) == 1
end

@testset "Simulation with provided initial time" begin
    problems = create_simulation_build_test_problems(get_template_basic_uc_simulation())
    sequence = SimulationSequence(
        problems = problems,
        feedforward_chronologies = Dict(("UC" => "ED") => Synchronize(periods = 24)),
        intervals = Dict(
            "UC" => (Hour(24), Consecutive()),
            "ED" => (Hour(1), Consecutive()),
        ),
        feedforward = Dict(
            ("ED", :devices, :ThermalStandard) => SemiContinuousFF(
                binary_source_problem = PSI.ON,
                affected_variables = [PSI.ACTIVE_POWER],
            ),
        ),
        ini_cond_chronology = InterProblemChronology(),
    )
    second_day = DateTime("1/1/2024  23:00:00", "d/m/y  H:M:S") + Hour(1)
    sim = Simulation(
        name = "test",
        steps = 1,
        problems = problems,
        sequence = sequence,
        simulation_folder = mktempdir(cleanup = true),
        initial_time = second_day,
    )
    build_out = build!(sim)
    @test build_out == PSI.BuildStatus.BUILT

    for (_, problem) in PSI.get_problems(sim)
        @test PSI.get_initial_time(problem) == second_day
    end
end

@testset "Negative Tests (Bad Parametrization)" begin
    problems = create_simulation_build_test_problems(get_template_basic_uc_simulation())
    sequence = SimulationSequence(
        problems = problems,
        feedforward_chronologies = Dict(("UC" => "ED") => Synchronize(periods = 24)),
        intervals = Dict(
            "UC" => (Hour(24), Consecutive()),
            "ED" => (Hour(1), Consecutive()),
        ),
        feedforward = Dict(
            ("ED", :devices, :ThermalStandard) => SemiContinuousFF(
                binary_source_problem = PSI.ON,
                affected_variables = [PSI.ACTIVE_POWER],
            ),
        ),
        ini_cond_chronology = InterProblemChronology(),
    )

    @test_throws UndefKeywordError sim = Simulation(name = "test", steps = 1)

    sim = Simulation(
        name = "test",
        steps = 1,
        problems = problems,
        sequence = sequence,
        simulation_folder = mktempdir(cleanup = true),
        initial_time = Dates.now(),
    )

    @test_throws IS.ConflictingInputsError build!(sim)

    sim = Simulation(
        name = "fake_path",
        steps = 1,
        problems = problems,
        sequence = sequence,
        simulation_folder = "fake_path",
    )

    @test_throws IS.ConflictingInputsError PSI._check_folder(sim)

    sequence.feedforward_chronologies = Dict(("UC" => "ED") => Synchronize(periods = 30))
    sim = Simulation(
        name = "look_ahead",
        steps = 1,
        problems = problems,
        sequence = sequence,
        simulation_folder = mktempdir(cleanup = true),
    )
    @test_throws IS.ConflictingInputsError PSI._check_feedforward_chronologies(sim)

    sequence.feedforward_chronologies = Dict(("UC" => "ED") => Synchronize(periods = 24))
    sim = Simulation(
        name = "look_ahead",
        steps = 5,
        problems = problems,
        sequence = sequence,
        simulation_folder = mktempdir(cleanup = true),
    )
    @test_throws IS.ConflictingInputsError build!(sim)

    sequence.feedforward_chronologies = Dict(("UC" => "ED") => Synchronize(periods = 30))
    sim = Simulation(
        name = "look_ahead",
        steps = 1,
        problems = problems,
        sequence = sequence,
        simulation_folder = mktempdir(cleanup = true),
    )
    @test_throws IS.ConflictingInputsError PSI._check_feedforward_chronologies(sim)

    @test_throws IS.ConflictingInputsError sim = Simulation(
        name = "disconnected problems",
        steps = 5,
        problems = create_simulation_build_test_problems(),
        sequence = sequence,
        simulation_folder = mktempdir(cleanup = true),
    )
end

# Pending tests to update

# @testset "Test Creation of Simulations with Cache" begin
#     stages_definition = create_stages(template_standard_uc, c_sys5_uc, c_sys5_ed)
#
#     # Cache is not defined all together
#     sequence_no_cache = SimulationSequence(
#         step_resolution = Hour(24),
#         order = Dict(1 => "UC", 2 => "ED"),
#         feedforward_chronologies = Dict(("UC" => "ED") => Synchronize(periods = 24)),
#         horizons = Dict("UC" => 24, "ED" => 12),
#         intervals = Dict(
#             "UC" => (Hour(24), Consecutive()),
#             "ED" => (Hour(1), Consecutive()),
#         ),
#         feedforward = Dict(
#             ("ED", :devices, :Generators) => SemiContinuousFF(
#                 binary_source_stage = PSI.ON,
#                 affected_variables = [PSI.ACTIVE_POWER],
#             ),
#         ),
#         ini_cond_chronology = InterProblemChronology(),
#     )
#     sim = Simulation(
#         name = "cache",
#         steps = 1,
#         stages = stages_definition,
#         stages_sequence = sequence_no_cache,
#         simulation_folder = file_path,
#     )
#     build!(sim)
#
#     @test !isempty(sim.internal.simulation_cache)
#
#     stages_definition = create_stages(template_standard_uc, c_sys5_uc, c_sys5_ed)
#     sequence = SimulationSequence(
#         step_resolution = Hour(24),
#         order = Dict(1 => "UC", 2 => "ED"),
#         feedforward_chronologies = Dict(("UC" => "ED") => Synchronize(periods = 24)),
#         horizons = Dict("UC" => 24, "ED" => 12),
#         intervals = Dict(
#             "UC" => (Hour(24), Consecutive()),
#             "ED" => (Hour(1), Consecutive()),
#         ),
#         feedforward = Dict(
#             ("ED", :devices, :Generators) => SemiContinuousFF(
#                 binary_source_stage = PSI.ON,
#                 affected_variables = [PSI.ACTIVE_POWER],
#             ),
#         ),
#         cache = Dict(("UC",) => TimeStatusChange(PSY.ThermalStandard, PSI.ON)),
#         ini_cond_chronology = InterProblemChronology(),
#     )
#     sim = Simulation(
#         name = "caches",
#         steps = 2,
#         stages = stages_definition,
#         stages_sequence = sequence,
#         simulation_folder = file_path,
#     )
#
#     build!(sim)
#
#     @test !isempty(sim.internal.simulation_cache)
#
#     stages_definition = create_stages(template_standard_uc, c_sys5_uc, c_sys5_ed)
#     # Uses IntraProblem but the cache is defined in the wrong stage
#     sequence_bad_cache = SimulationSequence(
#         step_resolution = Hour(24),
#         order = Dict(1 => "UC", 2 => "ED"),
#         feedforward_chronologies = Dict(("UC" => "ED") => Synchronize(periods = 24)),
#         horizons = Dict("UC" => 24, "ED" => 12),
#         intervals = Dict(
#             "UC" => (Hour(24), Consecutive()),
#             "ED" => (Hour(1), Consecutive()),
#         ),
#         feedforward = Dict(
#             ("ED", :devices, :Generators) => SemiContinuousFF(
#                 binary_source_stage = PSI.ON,
#                 affected_variables = [PSI.ACTIVE_POWER],
#             ),
#         ),
#         cache = Dict(("ED",) => TimeStatusChange(PSY.ThermalStandard, PSI.ON)),
#         ini_cond_chronology = IntraProblemChronology(),
#     )
#
#     sim = Simulation(
#         name = "test",
#         steps = 1,
#         stages = stages_definition,
#         stages_sequence = sequence_bad_cache,
#         simulation_folder = file_path,
#     )
#     @test_throws IS.InvalidValue build!(sim)
# end
