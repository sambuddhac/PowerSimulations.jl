# Note to devs. Use HiGHS for models with linear constraints and linear cost functions
# Use OSQP for models with quadratic cost function and linear constraints and ipopt otherwise

@testset "All PowerModels models construction" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    for (network, solver) in NETWORKS_FOR_TESTING
        template = get_thermal_dispatch_template_network(
            NetworkModel(network; PTDF_matrix = PTDF(c_sys5)),
        )
        ps_model = DecisionModel(template, c_sys5; optimizer = solver)
        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        @test PSI.get_optimization_container(ps_model).pm !== nothing
        # TODO: Change test
        # @test :nodal_balance_active in keys(PSI.get_optimization_container(ps_model).expressions)
    end
end

@testset "Network Copper Plate" begin
    template = get_thermal_dispatch_template_network(CopperPlatePowerModel)
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    c_sys14 = PSB.build_system(PSITestSystems, "c_sys14")
    c_sys14_dc = PSB.build_system(PSITestSystems, "c_sys14_dc")
    systems = [c_sys5, c_sys14, c_sys14_dc]
    test_results = IdDict{System, Vector{Int}}(
        c_sys5 => [120, 0, 120, 120, 24],
        c_sys14 => [120, 0, 120, 120, 24],
        c_sys14_dc => [120, 0, 120, 120, 24],
    )
    constraint_keys = [PSI.ConstraintKey(CopperPlateBalanceConstraint, PSY.System)]
    objfuncs = [GAEVF, GQEVF, GQEVF]
    test_obj_values = IdDict{System, Float64}(
        c_sys5 => 240000.0,
        c_sys14 => 142000.0,
        c_sys14_dc => 142000.0,
    )

    for (ix, sys) in enumerate(systems)
        ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)

        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        psi_constraint_test(ps_model, constraint_keys)
        moi_tests(
            ps_model,
            test_results[sys][1],
            test_results[sys][2],
            test_results[sys][3],
            test_results[sys][4],
            test_results[sys][5],
            false,
        )
        psi_checkobjfun_test(ps_model, objfuncs[ix])
        psi_checksolve_test(ps_model, [MOI.OPTIMAL], test_obj_values[sys], 10000)
    end
    template = get_thermal_dispatch_template_network(
        NetworkModel(CopperPlatePowerModel; use_slacks = true),
    )
    ps_model_re = DecisionModel(
        template,
        PSB.build_system(PSITestSystems, "c_sys5_re");
        optimizer = HiGHS_optimizer,
    )
    @test build!(ps_model_re; output_dir = mktempdir(; cleanup = true)) ==
          PSI.ModelBuildStatus.BUILT
    psi_checksolve_test(ps_model_re, [MOI.OPTIMAL], 240000.0, 10000)
end

@testset "Network DC-PF with PTDF Model" begin
    template = get_thermal_dispatch_template_network(PTDFPowerModel)
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    c_sys14 = PSB.build_system(PSITestSystems, "c_sys14")
    c_sys14_dc = PSB.build_system(PSITestSystems, "c_sys14_dc")
    systems = [c_sys5, c_sys14, c_sys14_dc]
    objfuncs = [GAEVF, GQEVF, GQEVF]
    constraint_keys = [
        PSI.ConstraintKey(RateLimitConstraint, PSY.Line, "lb"),
        PSI.ConstraintKey(RateLimitConstraint, PSY.Line, "ub"),
        PSI.ConstraintKey(CopperPlateBalanceConstraint, PSY.System),
        PSI.ConstraintKey(NetworkFlowConstraint, PSY.Line),
    ]
    PTDF_ref = IdDict{System, PTDF}(
        c_sys5 => PTDF(c_sys5),
        c_sys14 => PTDF(c_sys14),
        c_sys14_dc => PTDF(c_sys14_dc),
    )
    test_results = IdDict{System, Vector{Int}}(
        c_sys5 => [264, 0, 264, 264, 168],
        c_sys14 => [600, 0, 600, 600, 504],
        c_sys14_dc => [600, 0, 648, 552, 456],
    )
    test_obj_values = IdDict{System, Float64}(
        c_sys5 => 340000.0,
        c_sys14 => 142000.0,
        c_sys14_dc => 142000.0,
    )
    for (ix, sys) in enumerate(systems)
        template = get_thermal_dispatch_template_network(
            NetworkModel(PTDFPowerModel; PTDF_matrix = PTDF_ref[sys]),
        )
        ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)

        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        psi_constraint_test(ps_model, constraint_keys)
        moi_tests(
            ps_model,
            test_results[sys][1],
            test_results[sys][2],
            test_results[sys][3],
            test_results[sys][4],
            test_results[sys][5],
            false,
        )
        psi_checkobjfun_test(ps_model, objfuncs[ix])
        psi_checksolve_test(
            ps_model,
            [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL],
            test_obj_values[sys],
            10000,
        )
    end
    # PTDF input Error testing
    ps_model = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)
    @test build!(
        ps_model;
        console_level = Logging.AboveMaxLevel,  # Ignore expected errors.
        output_dir = mktempdir(; cleanup = true),
    ) == PSI.ModelBuildStatus.FAILED
end

@testset "Network DC-PF with VirtualPTDF Model" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    c_sys14 = PSB.build_system(PSITestSystems, "c_sys14")
    c_sys14_dc = PSB.build_system(PSITestSystems, "c_sys14_dc")
    systems = [c_sys5, c_sys14, c_sys14_dc]
    objfuncs = [GAEVF, GQEVF, GQEVF]
    constraint_keys = [
        PSI.ConstraintKey(RateLimitConstraint, PSY.Line, "lb"),
        PSI.ConstraintKey(RateLimitConstraint, PSY.Line, "ub"),
        PSI.ConstraintKey(CopperPlateBalanceConstraint, PSY.System),
        PSI.ConstraintKey(NetworkFlowConstraint, PSY.Line),
    ]
    PTDF_ref = IdDict{System, VirtualPTDF}(
        c_sys5 => VirtualPTDF(c_sys5),
        c_sys14 => VirtualPTDF(c_sys14),
        c_sys14_dc => VirtualPTDF(c_sys14_dc),
    )
    test_results = IdDict{System, Vector{Int}}(
        c_sys5 => [264, 0, 264, 264, 168],
        c_sys14 => [600, 0, 600, 600, 504],
        c_sys14_dc => [600, 0, 648, 552, 456],
    )
    test_obj_values = IdDict{System, Float64}(
        c_sys5 => 340000.0,
        c_sys14 => 142000.0,
        c_sys14_dc => 142000.0,
    )
    for (ix, sys) in enumerate(systems)
        template = get_thermal_dispatch_template_network(PTDFPowerModel)
        template = get_thermal_dispatch_template_network(
            NetworkModel(PTDFPowerModel; PTDF_matrix = PTDF_ref[sys]),
        )
        ps_model = DecisionModel(template, sys; optimizer = HiGHS_optimizer)

        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        psi_constraint_test(ps_model, constraint_keys)
        moi_tests(
            ps_model,
            test_results[sys][1],
            test_results[sys][2],
            test_results[sys][3],
            test_results[sys][4],
            test_results[sys][5],
            false,
        )
        psi_checkobjfun_test(ps_model, objfuncs[ix])
        psi_checksolve_test(
            ps_model,
            [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL],
            test_obj_values[sys],
            10000,
        )
    end
end

@testset "Network DC lossless -PF network with PowerModels DCPlosslessForm" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    c_sys14 = PSB.build_system(PSITestSystems, "c_sys14")
    c_sys14_dc = PSB.build_system(PSITestSystems, "c_sys14_dc")
    systems = [c_sys5, c_sys14, c_sys14_dc]
    objfuncs = [GAEVF, GQEVF, GQEVF]
    constraint_keys = [
        PSI.ConstraintKey(PSI.RateLimitConstraint, PSY.Line, "ub"),
        PSI.ConstraintKey(PSI.RateLimitConstraint, PSY.Line, "lb"),
        PSI.ConstraintKey(PSI.NodalBalanceActiveConstraint, PSY.ACBus),
    ]
    test_results = IdDict{System, Vector{Int}}(
        c_sys5 => [384, 144, 264, 264, 288],
        c_sys14 => [936, 480, 600, 600, 840],
        c_sys14_dc => [984, 432, 648, 552, 840],
    )
    test_obj_values = IdDict{System, Float64}(
        c_sys5 => 342000.0,
        c_sys14 => 142000.0,
        c_sys14_dc => 135000.0,
    )
    for (ix, sys) in enumerate(systems)
        template = get_thermal_dispatch_template_network(DCPPowerModel)
        ps_model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        psi_constraint_test(ps_model, constraint_keys)
        moi_tests(
            ps_model,
            test_results[sys][1],
            test_results[sys][2],
            test_results[sys][3],
            test_results[sys][4],
            test_results[sys][5],
            false,
        )
        psi_checkobjfun_test(ps_model, objfuncs[ix])
        psi_checksolve_test(
            ps_model,
            [MOI.OPTIMAL, MOI.LOCALLY_SOLVED],
            test_obj_values[sys],
            1000,
        )
    end
end

@testset "Network Solve AC-PF PowerModels StandardACPModel" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    c_sys14 = PSB.build_system(PSITestSystems, "c_sys14")
    c_sys14_dc = PSB.build_system(PSITestSystems, "c_sys14_dc")
    systems = [c_sys5, c_sys14, c_sys14_dc]
    objfuncs = [GAEVF, GQEVF, GQEVF]
    # Check for voltage and angle constraints
    constraint_keys = [
        PSI.ConstraintKey(RateLimitConstraintFromTo, PSY.Line),
        PSI.ConstraintKey(RateLimitConstraintToFrom, PSY.Line),
        PSI.ConstraintKey(PSI.NodalBalanceActiveConstraint, PSY.ACBus),
        PSI.ConstraintKey(PSI.NodalBalanceReactiveConstraint, PSY.ACBus),
    ]
    test_results = IdDict{System, Vector{Int}}(
        c_sys5 => [1056, 144, 240, 240, 264],
        c_sys14 => [2832, 480, 240, 240, 696],
        c_sys14_dc => [2832, 432, 336, 240, 744],
    )
    test_obj_values = IdDict{System, Float64}(
        c_sys5 => 340000.0,
        c_sys14 => 142000.0,
        c_sys14_dc => 142000.0,
    )
    for (ix, sys) in enumerate(systems)
        template = get_thermal_dispatch_template_network(ACPPowerModel)
        ps_model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        psi_constraint_test(ps_model, constraint_keys)
        moi_tests(
            ps_model,
            test_results[sys][1],
            test_results[sys][2],
            test_results[sys][3],
            test_results[sys][4],
            test_results[sys][5],
            false,
        )
        psi_checkobjfun_test(ps_model, objfuncs[ix])
        psi_checksolve_test(
            ps_model,
            [MOI.TIME_LIMIT, MOI.OPTIMAL, MOI.LOCALLY_SOLVED],
            test_obj_values[sys],
            10000,
        )
    end
end

@testset "Network Solve AC-PF PowerModels NFAPowerModel" begin
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    c_sys14 = PSB.build_system(PSITestSystems, "c_sys14")
    c_sys14_dc = PSB.build_system(PSITestSystems, "c_sys14_dc")
    systems = [c_sys5, c_sys14, c_sys14_dc]
    objfuncs = [GAEVF, GQEVF, GQEVF]
    constraint_keys = [PSI.ConstraintKey(PSI.NodalBalanceActiveConstraint, PSY.ACBus)]
    test_results = Dict{System, Vector{Int}}(
        c_sys5 => [264, 0, 264, 264, 120],
        c_sys14 => [600, 0, 600, 600, 336],
        c_sys14_dc => [648, 0, 648, 552, 384],
    )
    test_obj_values = IdDict{System, Float64}(
        c_sys5 => 300000.0,
        c_sys14 => 142000.0,
        c_sys14_dc => 142000.0,
    )
    for (ix, sys) in enumerate(systems)
        template = get_thermal_dispatch_template_network(NFAPowerModel)
        ps_model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        psi_constraint_test(ps_model, constraint_keys)
        moi_tests(
            ps_model,
            test_results[sys][1],
            test_results[sys][2],
            test_results[sys][3],
            test_results[sys][4],
            test_results[sys][5],
            false,
        )
        psi_checkobjfun_test(ps_model, objfuncs[ix])
        psi_checksolve_test(
            ps_model,
            [MOI.OPTIMAL, MOI.LOCALLY_SOLVED],
            test_obj_values[sys],
            10000,
        )
    end
end

@testset "Other Network AC PowerModels models" begin
    networks = [#ACPPowerModel, Already tested
        ACRPowerModel,
        ACTPowerModel,
    ]
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    c_sys14 = PSB.build_system(PSITestSystems, "c_sys14")
    c_sys14_dc = PSB.build_system(PSITestSystems, "c_sys14_dc")
    systems = [c_sys5, c_sys14, c_sys14_dc]
    # TODO: add model specific constraints to this list. Voltages, etc.
    constraint_keys = [
        PSI.ConstraintKey(PSI.NodalBalanceActiveConstraint, PSY.ACBus),
        PSI.ConstraintKey(PSI.NodalBalanceReactiveConstraint, PSY.ACBus),
    ]
    ACR_test_results = Dict{System, Vector{Int}}(
        c_sys5 => [1056, 0, 240, 240, 264],
        c_sys14 => [2832, 0, 240, 240, 696],
        c_sys14_dc => [2832, 0, 336, 240, 744],
    )
    ACT_test_results = Dict{System, Vector{Int}}(
        c_sys5 => [1344, 144, 240, 240, 840],
        c_sys14 => [3792, 480, 240, 240, 2616],
        c_sys14_dc => [3696, 432, 336, 240, 2472],
    )
    test_results = Dict(zip(networks, [ACR_test_results, ACT_test_results]))
    for network in networks, sys in systems
        template = get_thermal_dispatch_template_network(network)
        ps_model = DecisionModel(template, sys; optimizer = fast_ipopt_optimizer)
        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        psi_constraint_test(ps_model, constraint_keys)
        moi_tests(
            ps_model,
            test_results[network][sys][1],
            test_results[network][sys][2],
            test_results[network][sys][3],
            test_results[network][sys][4],
            test_results[network][sys][5],
            false,
        )
        @test PSI.get_optimization_container(ps_model).pm !== nothing
    end
end

# TODO: Add constraint tests for these models, other is redundant with first test
@testset "Network DC-PF PowerModels quadratic loss approximations models" begin
    networks = [DCPLLPowerModel, LPACCPowerModel]
    c_sys5 = PSB.build_system(PSITestSystems, "c_sys5")
    c_sys14 = PSB.build_system(PSITestSystems, "c_sys14")
    c_sys14_dc = PSB.build_system(PSITestSystems, "c_sys14_dc")
    systems = [c_sys5, c_sys14, c_sys14_dc]
    # TODO: add model specific constraints to this list. Bi-directional flows etc
    constraint_keys = [PSI.ConstraintKey(PSI.NodalBalanceActiveConstraint, PSY.ACBus)]
    test_obj_values = IdDict{System, Float64}(
        c_sys5 => 340000.0,
        c_sys14 => 142000.0,
        c_sys14_dc => 142000.0,
    )
    DCPLL_test_results = Dict{System, Vector{Int}}(
        c_sys5 => [528, 144, 264, 264, 288],
        c_sys14 => [1416, 480, 600, 600, 840],
        c_sys14_dc => [1416, 432, 648, 552, 840],
    )
    LPACC_test_results = Dict{System, Vector{Int}}(
        c_sys5 => [1200, 144, 240, 240, 840],
        c_sys14 => [3312, 480, 240, 240, 2616],
        c_sys14_dc => [3264, 432, 336, 240, 2472],
    )
    test_results = Dict(zip(networks, [DCPLL_test_results, LPACC_test_results]))
    for network in networks, (ix, sys) in enumerate(systems)
        template = get_thermal_dispatch_template_network(network)
        ps_model = DecisionModel(template, sys; optimizer = ipopt_optimizer)
        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        psi_constraint_test(ps_model, constraint_keys)
        moi_tests(
            ps_model,
            test_results[network][sys][1],
            test_results[network][sys][2],
            test_results[network][sys][3],
            test_results[network][sys][4],
            test_results[network][sys][5],
            false,
        )
        @test PSI.get_optimization_container(ps_model).pm !== nothing
        psi_checksolve_test(
            ps_model,
            [MOI.OPTIMAL, MOI.LOCALLY_SOLVED],
            test_obj_values[sys],
            10000,
        )
    end
end

@testset "Network Unsupported Power Model Formulations" begin
    for network in PSI.UNSUPPORTED_POWERMODELS
        template = get_thermal_dispatch_template_network(network)
        ps_model = DecisionModel(
            template,
            PSB.build_system(PSITestSystems, "c_sys5");
            optimizer = ipopt_optimizer,
        )
        @test build!(
            ps_model;
            console_level = Logging.AboveMaxLevel,  # Ignore expected errors.
            output_dir = mktempdir(; cleanup = true),
        ) == PSI.ModelBuildStatus.FAILED
    end
end

@testset "2 Subnetworks HVDC DC-PF with CopperPlatePowerModel" begin
    c_sys5 = PSB.build_system(PSISystems, "2Area 5 Bus System")
    # Test passing a VirtualPTDF Model
    template = get_thermal_dispatch_template_network(NetworkModel(CopperPlatePowerModel))
    ps_model = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)

    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          PSI.ModelBuildStatus.BUILT
    solve!(ps_model)

    moi_tests(ps_model, 264, 0, 288, 240, 48, false)

    opt_container = PSI.get_optimization_container(ps_model)
    copper_plate_constraints =
        PSI.get_constraint(opt_container, CopperPlateBalanceConstraint(), PSY.System)
    @test size(copper_plate_constraints) == (2, 24)

    psi_checksolve_test(ps_model, [MOI.OPTIMAL], 480288, 100)

    results = OptimizationProblemResults(ps_model)
    hvdc_flow = read_variable(results, "FlowActivePowerVariable__TwoTerminalHVDCLine")
    @test all(hvdc_flow[!, "nodeC-nodeC2"] .<= 200)
    @test all(hvdc_flow[!, "nodeC-nodeC2"] .>= -200)

    load = read_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")
    thermal_gen = read_variable(results, "ActivePowerVariable__ThermalStandard")

    zone_1_load = sum(eachcol(load[!, ["Load-nodeC", "Load-nodeD", "Load-nodeB"]]))
    zone_1_gen = sum(
        eachcol(thermal_gen[!, ["Solitude", "Park City", "Sundance", "Brighton", "Alta"]]),
    )
    @test all(
        isapprox.(
            sum(zone_1_gen .+ zone_1_load .- hvdc_flow[!, "nodeC-nodeC2"]; dims = 2),
            0.0;
            atol = 1e-3,
        ),
    )

    zone_2_load = sum(eachcol(load[!, ["Load-nodeC2", "Load-nodeD2", "Load-nodeB2"]]))
    zone_2_gen = sum(
        eachcol(
            thermal_gen[
                !,
                ["Solitude-2", "Park City-2", "Sundance-2", "Brighton-2", "Alta-2"],
            ],
        ),
    )
    @test all(
        isapprox.(
            sum(zone_2_gen .+ zone_2_load .+ hvdc_flow[!, "nodeC-nodeC2"]; dims = 2),
            0.0;
            atol = 1e-3,
        ),
    )

    # Test forcing flows to 0.0
    hvdc_link = get_component(TwoTerminalHVDCLine, c_sys5, "nodeC-nodeC2")
    set_active_power_limits_from!(hvdc_link, (min = 0.0, max = 0.0))
    set_active_power_limits_to!(hvdc_link, (min = 0.0, max = 0.0))

    # Test not passing the PTDF to the Template
    template = get_thermal_dispatch_template_network(NetworkModel(PTDFPowerModel))
    ps_model = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)
    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          PSI.ModelBuildStatus.BUILT
    solve!(ps_model)

    opt_container = PSI.get_optimization_container(ps_model)
    copper_plate_constraints =
        PSI.get_constraint(opt_container, CopperPlateBalanceConstraint(), PSY.System)

    results = OptimizationProblemResults(ps_model)
    hvdc_flow = read_variable(results, "FlowActivePowerVariable__TwoTerminalHVDCLine")
    @test all(hvdc_flow[!, "nodeC-nodeC2"] .== 0.0)
    @test all(hvdc_flow[!, "nodeC-nodeC2"] .== 0.0)

    load = read_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")
    thermal_gen = read_variable(results, "ActivePowerVariable__ThermalStandard")

    zone_1_load = sum(eachcol(load[!, ["Load-nodeC", "Load-nodeD", "Load-nodeB"]]))
    zone_1_gen = sum(
        eachcol(thermal_gen[!, ["Solitude", "Park City", "Sundance", "Brighton", "Alta"]]),
    )
    @test all(isapprox.(sum(zone_1_gen .+ zone_1_load; dims = 2), 0.0; atol = 1e-3))

    zone_2_load = sum(eachcol(load[!, ["Load-nodeC2", "Load-nodeD2", "Load-nodeB2"]]))
    zone_2_gen = sum(
        eachcol(
            thermal_gen[
                !,
                ["Solitude-2", "Park City-2", "Sundance-2", "Brighton-2", "Alta-2"],
            ],
        ),
    )
    @test all(isapprox.(sum(zone_2_gen .+ zone_2_load; dims = 2), 0.0; atol = 1e-3))
end

@testset "2 Subnetworks DC-PF with PTDF Model" begin
    c_sys5 = PSB.build_system(PSISystems, "2Area 5 Bus System")
    # Test passing a VirtualPTDF Model
    template = get_thermal_dispatch_template_network(
        NetworkModel(PTDFPowerModel; PTDF_matrix = VirtualPTDF(c_sys5)),
    )
    ps_model = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)

    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          PSI.ModelBuildStatus.BUILT
    solve!(ps_model)

    moi_tests(ps_model, 552, 0, 576, 528, 336, false)

    opt_container = PSI.get_optimization_container(ps_model)
    copper_plate_constraints =
        PSI.get_constraint(opt_container, CopperPlateBalanceConstraint(), PSY.System)
    @test size(copper_plate_constraints) == (2, 24)

    psi_checksolve_test(ps_model, [MOI.OPTIMAL], 684763, 100)

    results = OptimizationProblemResults(ps_model)
    hvdc_flow = read_variable(results, "FlowActivePowerVariable__TwoTerminalHVDCLine")
    @test all(hvdc_flow[!, "nodeC-nodeC2"] .<= 200 + PSI.ABSOLUTE_TOLERANCE)
    @test all(hvdc_flow[!, "nodeC-nodeC2"] .>= -200 - PSI.ABSOLUTE_TOLERANCE)

    load = read_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")
    thermal_gen = read_variable(results, "ActivePowerVariable__ThermalStandard")

    zone_1_load = sum(eachcol(load[!, ["Load-nodeC", "Load-nodeD", "Load-nodeB"]]))
    zone_1_gen = sum(
        eachcol(thermal_gen[!, ["Solitude", "Park City", "Sundance", "Brighton", "Alta"]]),
    )
    @test all(
        isapprox.(
            sum(zone_1_gen .+ zone_1_load .- hvdc_flow[!, "nodeC-nodeC2"]; dims = 2),
            0.0;
            atol = 1e-3,
        ),
    )

    zone_2_load = sum(eachcol(load[!, ["Load-nodeC2", "Load-nodeD2", "Load-nodeB2"]]))
    zone_2_gen = sum(
        eachcol(
            thermal_gen[
                !,
                ["Solitude-2", "Park City-2", "Sundance-2", "Brighton-2", "Alta-2"],
            ],
        ),
    )
    @test all(
        isapprox.(
            sum(zone_2_gen .+ zone_2_load .+ hvdc_flow[!, "nodeC-nodeC2"]; dims = 2),
            0.0;
            atol = 1e-3,
        ),
    )

    # Test forcing flows to 0.0
    hvdc_link = get_component(PSY.TwoTerminalHVDCLine, c_sys5, "nodeC-nodeC2")
    set_active_power_limits_from!(hvdc_link, (min = 0.0, max = 0.0))
    set_active_power_limits_to!(hvdc_link, (min = 0.0, max = 0.0))

    # Test not passing the PTDF to the Template
    template = get_thermal_dispatch_template_network(NetworkModel(PTDFPowerModel))
    ps_model = DecisionModel(template, c_sys5; optimizer = HiGHS_optimizer)
    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          PSI.ModelBuildStatus.BUILT
    solve!(ps_model)

    opt_container = PSI.get_optimization_container(ps_model)
    copper_plate_constraints =
        PSI.get_constraint(opt_container, CopperPlateBalanceConstraint(), PSY.System)

    results = OptimizationProblemResults(ps_model)
    hvdc_flow = read_variable(results, "FlowActivePowerVariable__TwoTerminalHVDCLine")
    @test all(hvdc_flow[!, "nodeC-nodeC2"] .== 0.0)
    @test all(hvdc_flow[!, "nodeC-nodeC2"] .== 0.0)

    load = read_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")
    thermal_gen = read_variable(results, "ActivePowerVariable__ThermalStandard")

    zone_1_load = sum(eachcol(load[!, ["Load-nodeC", "Load-nodeD", "Load-nodeB"]]))
    zone_1_gen = sum(
        eachcol(thermal_gen[!, ["Solitude", "Park City", "Sundance", "Brighton", "Alta"]]),
    )
    @test all(isapprox.(sum(zone_1_gen .+ zone_1_load; dims = 2), 0.0; atol = 1e-3))

    zone_2_load = sum(eachcol(load[!, ["Load-nodeC2", "Load-nodeD2", "Load-nodeB2"]]))
    zone_2_gen = sum(
        eachcol(
            thermal_gen[
                !,
                ["Solitude-2", "Park City-2", "Sundance-2", "Brighton-2", "Alta-2"],
            ],
        ),
    )
    @test all(isapprox.(sum(zone_2_gen .+ zone_2_load; dims = 2), 0.0; atol = 1e-3))
end

# These models are easier to test due to their lossless nature
@testset "StandardPTDF/DCPPowerModel Radial Branches Test" begin
    new_sys = PSB.build_system(PSITestSystems, "c_sys5_radial")

    for net_model in [DCPPowerModel, PTDFPowerModel]
        template_uc = template_unit_commitment(;
            network = NetworkModel(net_model;
                reduce_radial_branches = true,
                use_slacks = false,
            ),
        )
        thermal_model = ThermalStandardUnitCommitment
        set_device_model!(template_uc, ThermalStandard, thermal_model)

        ##### Solve Reduced Model ####
        solver = HiGHS_optimizer
        uc_model_red = DecisionModel(
            template_uc,
            new_sys;
            optimizer = solver,
            name = "UC_RED",
            store_variable_names = true,
        )

        @test build!(uc_model_red; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        solve!(uc_model_red)

        res_red = OptimizationProblemResults(uc_model_red)

        flow_lines = read_variable(res_red, "FlowActivePowerVariable__Line")
        line_names = DataFrames.names(flow_lines)[2:end]

        ##### Solve Original Model ####
        template_uc_orig = template_unit_commitment(;
            network = NetworkModel(net_model;
                reduce_radial_branches = false,
                use_slacks = false,
            ),
        )
        set_device_model!(template_uc_orig, ThermalStandard, thermal_model)

        uc_model_orig = DecisionModel(
            template_uc_orig,
            new_sys;
            optimizer = solver,
            name = "UC_ORIG",
            store_variable_names = true,
        )

        @test build!(uc_model_orig; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        solve!(uc_model_orig)

        res_orig = OptimizationProblemResults(uc_model_orig)

        flow_lines_orig = read_variable(res_orig, "FlowActivePowerVariable__Line")

        for line in line_names
            @test isapprox(flow_lines[!, line], flow_lines_orig[!, line])
        end
    end
end

@testset "All PowerModels models construction with reduced radial branches" begin
    new_sys = PSB.build_system(PSITestSystems, "c_sys5_radial")
    for (network, solver) in NETWORKS_FOR_TESTING
        if network ∈ PSI.INCOMPATIBLE_WITH_RADIAL_BRANCHES_POWERMODELS
            continue
        end
        template = get_thermal_dispatch_template_network(
            NetworkModel(network;
                PTDF_matrix = PTDF(new_sys),
                reduce_radial_branches = true,
                use_slacks = true),
        )
        ps_model = DecisionModel(template, new_sys; optimizer = solver)
        @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
              PSI.ModelBuildStatus.BUILT
        @test PSI.get_optimization_container(ps_model).pm !== nothing
    end
end

@testset "2 Areas AreaBalance PowerModel - with slacks" begin
    c_sys = build_system(PSITestSystems, "c_sys5_uc")
    # Extend the system with two areas
    areas = [Area("Area_1", 0, 0, 0), Area("Area_2", 0, 0, 0)]
    add_components!(c_sys, areas)
    for (i, comp) in enumerate(get_components(ACBus, c_sys))
        (i < 3) ? set_area!(comp, areas[1]) : set_area!(comp, areas[2])
    end
    # Deactivate generators on Area 1: as there is no area interchange defined,
    # slacks will be required for feasibility
    for gen in get_components(x -> (get_area(get_bus(x)) == areas[1]), Generator, c_sys)
        set_available!(gen, false)
    end

    template = get_thermal_dispatch_template_network(
        NetworkModel(AreaBalancePowerModel; use_slacks = true),
    )
    ps_model = DecisionModel(template, c_sys; optimizer = HiGHS_optimizer)

    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          PSI.ModelBuildStatus.BUILT
    @test solve!(ps_model) == PSI.RunStatus.SUCCESSFULLY_FINALIZED

    opt_container = PSI.get_optimization_container(ps_model)
    copper_plate_constraints =
        PSI.get_constraint(opt_container, CopperPlateBalanceConstraint(), PSY.Area)
    @test size(copper_plate_constraints) == (2, 24)

    results = OptimizationProblemResults(ps_model)
    slacks_up = read_variable(results, "SystemBalanceSlackUp__Area")
    @test all(slacks_up[!, "Area_1"] .> 0.0)
    @test all(slacks_up[!, "Area_2"] .≈ 0.0)
end

@testset "2 Areas AreaBalance PowerModel" begin
    c_sys = PSB.build_system(PSISystems, "two_area_pjm_DA")
    transform_single_time_series!(c_sys, Hour(24), Hour(1))
    template = get_thermal_dispatch_template_network(NetworkModel(AreaBalancePowerModel))
    set_device_model!(template, AreaInterchange, StaticBranch)
    ps_model =
        DecisionModel(template, c_sys; resolution = Hour(1), optimizer = HiGHS_optimizer)

    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          PSI.ModelBuildStatus.BUILT
    @test solve!(ps_model) == PSI.RunStatus.SUCCESSFULLY_FINALIZED

    moi_tests(ps_model, 264, 0, 264, 264, 48, false)

    opt_container = PSI.get_optimization_container(ps_model)
    copper_plate_constraints =
        PSI.get_constraint(opt_container, CopperPlateBalanceConstraint(), PSY.Area)
    @test size(copper_plate_constraints) == (2, 24)

    psi_checksolve_test(ps_model, [MOI.OPTIMAL], 482055, 1)

    results = OptimizationProblemResults(ps_model)
    interarea_flow = read_variable(results, "FlowActivePowerVariable__AreaInterchange")
    # The values for these tests come from the data
    @test all(interarea_flow[!, "1_2"] .<= 150)
    @test all(interarea_flow[!, "1_2"] .>= -150)

    load = read_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")
    thermal_gen = read_variable(results, "ActivePowerVariable__ThermalStandard")

    zone_1_load = sum(eachcol(load[!, ["Bus4_1", "Bus3_1", "Bus2_1"]]))
    zone_1_gen = sum(
        eachcol(
            thermal_gen[
                !,
                ["Solitude_1", "Park City_1", "Sundance_1", "Brighton_1", "Alta_1"],
            ],
        ),
    )
    @test all(
        isapprox.(
            sum(zone_1_gen .+ zone_1_load .- interarea_flow[!, "1_2"]; dims = 2),
            0.0;
            atol = 1e-3,
        ),
    )

    zone_2_load = sum(eachcol(load[!, ["Bus4_2", "Bus3_2", "Bus2_2"]]))
    zone_2_gen = sum(
        eachcol(
            thermal_gen[
                !,
                ["Solitude_2", "Park City_2", "Sundance_2", "Brighton_2", "Alta_2"],
            ],
        ),
    )
    @test all(
        isapprox.(
            sum(zone_2_gen .+ zone_2_load .+ interarea_flow[!, "1_2"]; dims = 2),
            0.0;
            atol = 1e-3,
        ),
    )
end

@testset "2 Areas AreaBalance PowerModel with TimeSeries" begin
    c_sys = PSB.build_system(PSISystems, "two_area_pjm_DA")
    load = first(get_components(PowerLoad, c_sys))
    ts_array = get_time_series_array(SingleTimeSeries, load, "max_active_power")
    tstamp = timestamp(ts_array)
    area_int = first(get_components(AreaInterchange, c_sys))
    day_data = [
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
    ]
    weekly_data = repeat(day_data, 7)
    ts_from_to = SingleTimeSeries(
        "from_to_flow_limit",
        TimeArray(tstamp, weekly_data);
        scaling_factor_multiplier = get_from_to_flow_limit,
    )
    ts_to_from = SingleTimeSeries(
        "to_from_flow_limit",
        TimeArray(tstamp, weekly_data);
        scaling_factor_multiplier = get_from_to_flow_limit,
    )
    add_time_series!(c_sys, area_int, ts_from_to)
    add_time_series!(c_sys, area_int, ts_to_from)
    ## Transform Time Series ##
    transform_single_time_series!(c_sys, Hour(24), Hour(24))
    template = get_thermal_dispatch_template_network(NetworkModel(AreaBalancePowerModel))
    set_device_model!(template, AreaInterchange, StaticBranch)
    ps_model =
        DecisionModel(template, c_sys; resolution = Hour(1), optimizer = HiGHS_optimizer)

    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          PSI.ModelBuildStatus.BUILT
    @test solve!(ps_model) == PSI.RunStatus.SUCCESSFULLY_FINALIZED

    moi_tests(ps_model, 264, 0, 264, 264, 48, false)

    opt_container = PSI.get_optimization_container(ps_model)
    copper_plate_constraints =
        PSI.get_constraint(opt_container, CopperPlateBalanceConstraint(), PSY.Area)
    @test size(copper_plate_constraints) == (2, 24)

    psi_checksolve_test(ps_model, [MOI.OPTIMAL], 482055, 1)

    results = OptimizationProblemResults(ps_model)
    interarea_flow = read_variable(results, "FlowActivePowerVariable__AreaInterchange")
    # The values for these tests come from the data
    @test interarea_flow[4, "1_2"] != 0.0
    @test interarea_flow[5, "1_2"] == 0.0
    @test interarea_flow[6, "1_2"] == 0.0
end

@testset "2 Areas AreaPTDFPowerModel" begin
    c_sys = PSB.build_system(PSISystems, "two_area_pjm_DA")
    transform_single_time_series!(c_sys, Hour(24), Hour(1))
    set_flow_limits!(
        get_component(AreaInterchange, c_sys, "1_2"),
        (from_to = 1.0, to_from = 1.0),
    )
    template = get_thermal_dispatch_template_network(NetworkModel(AreaPTDFPowerModel))
    set_device_model!(template, AreaInterchange, StaticBranch)
    set_device_model!(template, MonitoredLine, StaticBranchUnbounded)
    ps_model =
        DecisionModel(template, c_sys; resolution = Hour(1), optimizer = HiGHS_optimizer)

    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          PSI.ModelBuildStatus.BUILT
    @test solve!(ps_model) == PSI.RunStatus.SUCCESSFULLY_FINALIZED

    moi_tests(ps_model, 576, 0, 576, 576, 360, false)

    opt_container = PSI.get_optimization_container(ps_model)
    copper_plate_constraints =
        PSI.get_constraint(opt_container, CopperPlateBalanceConstraint(), PSY.Area)
    @test size(copper_plate_constraints) == (2, 24)

    psi_checksolve_test(ps_model, [MOI.OPTIMAL], 666147, 1)

    results = OptimizationProblemResults(ps_model)
    interarea_flow = read_variable(results, "FlowActivePowerVariable__AreaInterchange")
    # The values for these tests come from the data
    @test all(interarea_flow[!, "1_2"] .<= 100.0 + PSI.ABSOLUTE_TOLERANCE)
    @test all(interarea_flow[!, "1_2"] .>= -100.0 - PSI.ABSOLUTE_TOLERANCE)

    load = read_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")
    thermal_gen = read_variable(results, "ActivePowerVariable__ThermalStandard")

    zone_1_load = sum(eachcol(load[!, ["Bus4_1", "Bus3_1", "Bus2_1"]]))
    zone_1_gen = sum(
        eachcol(
            thermal_gen[
                !,
                ["Solitude_1", "Park City_1", "Sundance_1", "Brighton_1", "Alta_1"],
            ],
        ),
    )
    @test all(
        isapprox.(
            sum(zone_1_gen .+ zone_1_load .- interarea_flow[!, "1_2"]; dims = 2),
            0.0;
            atol = 1e-3,
        ),
    )

    zone_2_load = sum(eachcol(load[!, ["Bus4_2", "Bus3_2", "Bus2_2"]]))
    zone_2_gen = sum(
        eachcol(
            thermal_gen[
                !,
                ["Solitude_2", "Park City_2", "Sundance_2", "Brighton_2", "Alta_2"],
            ],
        ),
    )
    @test all(
        isapprox.(
            sum(zone_2_gen .+ zone_2_load .+ interarea_flow[!, "1_2"]; dims = 2),
            0.0;
            atol = 1e-3,
        ),
    )
end

@testset "2 Areas AreaPTDFPowerModel with Time Series" begin
    c_sys = PSB.build_system(PSISystems, "two_area_pjm_DA")
    load = first(get_components(PowerLoad, c_sys))
    new_line = Line(;
        name = "C2_D1",
        available = true,
        active_power_flow = 0.0,
        reactive_power_flow = 0.0,
        arc = Arc(;
            from = get_component(ACBus, c_sys, "Bus_nodeC_2"),
            to = get_component(ACBus, c_sys, "Bus_nodeD_1"),
        ),
        r = 0.00297,
        x = 0.0297,
        b = (from = 0.00337, to = 0.00337),
        rating = 40.53,
        angle_limits = (min = -0.7, max = 0.7),
    )
    add_component!(c_sys, new_line)
    ts_array = get_time_series_array(SingleTimeSeries, load, "max_active_power")
    tstamp = timestamp(ts_array)
    area_int = first(get_components(AreaInterchange, c_sys))
    day_data = [
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
        0.9, 0.85, 0.95, 0.2, 0.0, 0.0,
    ]
    weekly_data = repeat(day_data, 7)
    ts_from_to = SingleTimeSeries(
        "from_to_flow_limit",
        TimeArray(tstamp, weekly_data);
        scaling_factor_multiplier = get_from_to_flow_limit,
    )
    ts_to_from = SingleTimeSeries(
        "to_from_flow_limit",
        TimeArray(tstamp, weekly_data);
        scaling_factor_multiplier = get_from_to_flow_limit,
    )
    add_time_series!(c_sys, area_int, ts_from_to)
    add_time_series!(c_sys, area_int, ts_to_from)
    ## Transform Time Series ##
    transform_single_time_series!(c_sys, Hour(24), Hour(24))
    set_flow_limits!(
        get_component(AreaInterchange, c_sys, "1_2"),
        (from_to = 1.0, to_from = 1.0),
    )
    template = get_thermal_dispatch_template_network(NetworkModel(AreaPTDFPowerModel))
    set_device_model!(template, AreaInterchange, StaticBranch)
    set_device_model!(template, MonitoredLine, StaticBranchUnbounded)
    ps_model =
        DecisionModel(template, c_sys; resolution = Hour(1), optimizer = HiGHS_optimizer)

    @test build!(ps_model; output_dir = mktempdir(; cleanup = true)) ==
          PSI.ModelBuildStatus.BUILT
    @test solve!(ps_model) == PSI.RunStatus.SUCCESSFULLY_FINALIZED

    moi_tests(ps_model, 600, 0, 600, 600, 384, false)

    opt_container = PSI.get_optimization_container(ps_model)
    copper_plate_constraints =
        PSI.get_constraint(opt_container, CopperPlateBalanceConstraint(), PSY.Area)
    @test size(copper_plate_constraints) == (2, 24)

    psi_checksolve_test(ps_model, [MOI.OPTIMAL], 671937, 1)

    results = OptimizationProblemResults(ps_model)
    interarea_flow = read_variable(results, "FlowActivePowerVariable__AreaInterchange")
    # The values for these tests come from the data
    @test interarea_flow[1, "1_2"] != 0.0
    @test interarea_flow[5, "1_2"] == 0.0
    @test interarea_flow[6, "1_2"] == 0.0
end
