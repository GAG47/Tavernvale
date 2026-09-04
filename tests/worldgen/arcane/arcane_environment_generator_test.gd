extends SceneTree

var _failures := PackedStringArray()
var _seed_one_graph: SpatialGraph
var _seed_one_field: ArcaneFieldLayer
var _seed_one_web: ArcaneWebLayer
var _seed_one_circulation: ArcaneCirculationLayer
var _seed_one_empty_forcing: ArcaneForcingLayer
var _seed_one_environment: ArcaneEnvironmentLayer


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_settings_and_formal_layer_contract()
	_test_background_equilibrium_invariant()
	_test_no_stress_means_high_final_stability()
	_test_background_stability_controls_restoration()
	_test_natural_disequilibrium_diffusion_and_mass_conservation()
	_test_leyline_flowability_and_flow_independence()
	_test_arcane_drift_direction_and_actual_mana_transport()
	_test_internal_drift_conservation()
	_test_open_boundary()
	_test_stability_response_and_natural_background_gradient()
	_test_resolution_behavior()
	_test_no_new_randomness()
	_test_seed_one_generation_determinism_and_zero_regression()
	_print_seed_one_statistics()
	_finish()


func _test_settings_and_formal_layer_contract() -> void:
	var settings := ArcaneEnvironmentSettings.new()
	_expect(settings.validate().is_empty(), "default Arcane Environment settings should validate")
	_expect(settings.leyline_influence_radius == 55.0, "Leyline influence radius must be 55")
	_expect(settings.ambient_flowability == 0.15, "ambient Flowability must be 0.15")
	_expect(settings.diffusion_rate == 1.0, "diffusion rate must be 1.0")
	_expect(settings.arcane_drift_speed == 0.75,
		"calibrated Arcane Drift speed must be 0.75")
	_expect(settings.background_restoration_min_rate == 0.03
			and settings.background_restoration_max_rate == 0.15,
		"background restoration rates must be 0.03..0.15")
	_expect(settings.solver_cfl_safety == 0.40 and settings.solver_max_dt == 1.0,
		"Solver CFL safety/max dt must be 0.40/1.0")
	_expect(settings.solver_max_iterations == 400
			and settings.solver_convergence_epsilon == 0.00001,
		"Solver iteration cap/epsilon must be 400/1e-5")
	_expect(settings.stability_min_resistance == 0.15
			and settings.stability_stress_response == 2.0,
		"stability resistance/response must be 0.15/2.0")
	var layer := ArcaneEnvironmentLayer.new()
	for forbidden in [
		"web_influence", "mana_disequilibrium", "drift_vector", "restoration_rate",
		"arcane_stress", "gradient_stress", "resistance", "iteration_delta",
	]:
		_expect(not _object_has_property(layer, StringName(forbidden)),
			"ArcaneEnvironmentLayer must not formally store %s" % forbidden)


func _test_background_equilibrium_invariant() -> void:
	var graph := _two_cell_graph(1.0, 3.0)
	var background := PackedFloat32Array([0.15, 0.85])
	var stability := PackedFloat32Array([0.0, 1.0])
	var settings := ArcaneEnvironmentSettings.new()
	settings.arcane_drift_speed = 0.0
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		background,
		stability,
		PackedFloat64Array([1.0, 1.0]),
		PackedVector2Array([Vector2.ZERO, Vector2.ZERO]),
		_zero_rates(graph),
		_zero_rates(graph),
		settings,
		PackedFloat64Array(),
		false
	)
	_expect(bool(result.report.converged), "C=B equilibrium fixture should converge")
	_expect(_arrays_approximately_equal(result.concentration, background, 0.0000001),
		"non-uniform Background Mana must remain invariant when C=B")


func _test_no_stress_means_high_final_stability() -> void:
	var graph := _two_cell_graph()
	var background := PackedFloat32Array([0.1, 0.9])
	var result := ArcaneEnvironmentGenerator.synthesize_stability(
		graph,
		background,
		PackedFloat32Array([0.0, 0.0]),
		background,
		PackedFloat64Array([1.0, 1.0]),
		ArcaneEnvironmentSettings.new()
	)
	_expect(result.stability[0] == 1.0 and result.stability[1] == 1.0,
		"low Background Stability plus zero Arcane Stress must yield Stability 1")


func _test_background_stability_controls_restoration() -> void:
	var graph := _two_cell_graph()
	var settings := ArcaneEnvironmentSettings.new()
	settings.diffusion_rate = 0.0
	settings.arcane_drift_speed = 0.0
	settings.solver_max_iterations = 1
	settings.solver_convergence_epsilon = 0.000000000001
	var background := PackedFloat32Array([0.2, 0.2])
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		background,
		PackedFloat32Array([1.0, 0.0]),
		PackedFloat64Array([0.15, 0.15]),
		PackedVector2Array([Vector2.ZERO, Vector2.ZERO]),
		_zero_rates(graph),
		_zero_rates(graph),
		settings,
		PackedFloat64Array([0.8, 0.8]),
		false
	)
	_expect(absf(result.concentration[0] - background[0])
			< absf(result.concentration[1] - background[1]),
		"high Background Stability must restore the same disturbance faster")


func _test_natural_disequilibrium_diffusion_and_mass_conservation() -> void:
	var graph := _two_cell_graph(1.0, 3.0)
	var settings := _pure_transport_settings(1)
	var initial := PackedFloat64Array([0.8, 0.2])
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([0.2, 0.2]),
		PackedFloat32Array([0.0, 0.0]),
		PackedFloat64Array([1.0, 1.0]),
		PackedVector2Array([Vector2.ZERO, Vector2.ZERO]),
		_zero_rates(graph),
		_zero_rates(graph),
		settings,
		initial,
		false
	)
	_expect(result.concentration[0] < initial[0] and result.concentration[1] > initial[1],
		"positive Mana disequilibrium must diffuse to the neighboring equilibrium Cell")
	_expect(absf(_total_mass(graph, result.concentration) - _total_mass(graph, initial)) < 0.0000001,
		"internal diffusion must conserve concentration times Cell area")


func _test_leyline_flowability_and_flow_independence() -> void:
	var graph := _projection_graph()
	var web := _single_leyline_web()
	var settings := ArcaneEnvironmentSettings.new()
	var projection := ArcaneEnvironmentGenerator.project_flowability(graph, web, settings)
	_expect(projection.flowability[0] > projection.flowability[1],
		"a Cell on a Leyline must have higher Flowability than a far Cell")
	_expect(absf(projection.flowability[0] - 1.0) < 0.000001,
		"a Cell on the Leyline core should have Flowability 1")
	_expect(absf(projection.flowability[1] - settings.ambient_flowability) < 0.000001,
		"a Cell outside the radius should retain ambient Flowability")
	var positive := ArcaneCirculationLayer.new()
	positive.edge_flow = PackedFloat32Array([2.0])
	var negative := ArcaneCirculationLayer.new()
	negative.edge_flow = PackedFloat32Array([-2.0])
	var repeated := ArcaneEnvironmentGenerator.project_flowability(graph, web, settings)
	_expect(projection.flowability == repeated.flowability
			and positive.edge_flow != negative.edge_flow,
		"Flowability must depend on Web geometry and remain independent of edge_flow")


func _test_arcane_drift_direction_and_actual_mana_transport() -> void:
	var graph := _projection_graph()
	var web := _single_leyline_web()
	var circulation := ArcaneCirculationLayer.new()
	circulation.edge_flow = PackedFloat32Array([2.0])
	var drift := ArcaneEnvironmentGenerator.project_drift_field(
		graph, web, circulation, ArcaneEnvironmentSettings.new()
	)
	_expect(drift[0].x > 0.0 and absf(drift[0].y) < 0.000001,
		"positive edge_flow must project along canonical node_a -> node_b")
	circulation.edge_flow[0] = -2.0
	var reversed := ArcaneEnvironmentGenerator.project_drift_field(
		graph, web, circulation, ArcaneEnvironmentSettings.new()
	)
	_expect(reversed[0].x < 0.0,
		"negative edge_flow must reverse the concentration-independent Drift direction")

	var transport_graph := _two_cell_graph()
	var settings := _pure_transport_settings(1)
	settings.diffusion_rate = 0.0
	var initial := PackedFloat64Array([0.7, 0.1])
	var result := ArcaneEnvironmentGenerator.solve_transport(
		transport_graph,
		PackedFloat32Array([0.2, 0.2]),
		PackedFloat32Array([0.0, 0.0]),
		PackedFloat64Array([1.0, 1.0]),
		PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.5, 0.0)]),
		_zero_rates(transport_graph),
		_zero_rates(transport_graph),
		settings,
		initial,
		false
	)
	_expect(result.concentration[0] < initial[0] and result.concentration[1] > initial[1],
		"upwind Drift must transport actual Mana along its fixed direction")


func _test_internal_drift_conservation() -> void:
	var graph := _two_cell_graph(1.0, 3.0)
	var settings := _pure_transport_settings(20)
	settings.diffusion_rate = 0.0
	var initial := PackedFloat64Array([0.9, 0.1])
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([0.2, 0.2]),
		PackedFloat32Array([0.0, 0.0]),
		PackedFloat64Array([1.0, 1.0]),
		PackedVector2Array([Vector2(0.4, 0.0), Vector2(0.4, 0.0)]),
		_zero_rates(graph),
		_zero_rates(graph),
		settings,
		initial,
		false
	)
	_expect(absf(_total_mass(graph, result.concentration) - _total_mass(graph, initial)) < 0.0000001,
		"internal upwind Drift must conserve concentration times Cell area")


func _test_open_boundary() -> void:
	var graph := _boundary_cell_graph()
	var settings := _pure_transport_settings(1)
	settings.diffusion_rate = 0.0
	var outward := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([0.6]),
		PackedFloat32Array([0.0]),
		PackedFloat64Array([1.0]),
		PackedVector2Array([Vector2(0.4, 0.0)]),
		_zero_rates(graph),
		_zero_rates(graph),
		settings,
		PackedFloat64Array([0.8]),
		true
	)
	var inward := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([0.6]),
		PackedFloat32Array([0.0]),
		PackedFloat64Array([1.0]),
		PackedVector2Array([Vector2(-0.4, 0.0)]),
		_zero_rates(graph),
		_zero_rates(graph),
		settings,
		PackedFloat64Array([0.2]),
		true
	)
	_expect(outward.concentration[0] < 0.8,
		"outward boundary Drift must allow actual Mana to leave the world")
	_expect(inward.concentration[0] > 0.2,
		"inward boundary Drift must use local Background Mana as the ghost inflow state")
	settings.diffusion_rate = 1.0
	var diffusion_out := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([0.6]),
		PackedFloat32Array([0.0]),
		PackedFloat64Array([1.0]),
		PackedVector2Array([Vector2.ZERO]),
		_zero_rates(graph),
		_zero_rates(graph),
		settings,
		PackedFloat64Array([0.8]),
		true
	)
	var diffusion_in := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([0.6]),
		PackedFloat32Array([0.0]),
		PackedFloat64Array([1.0]),
		PackedVector2Array([Vector2.ZERO]),
		_zero_rates(graph),
		_zero_rates(graph),
		settings,
		PackedFloat64Array([0.4]),
		true
	)
	_expect(diffusion_out.concentration[0] < 0.8
			and diffusion_in.concentration[0] > 0.4,
		"boundary diffusion must exchange disequilibrium with the zero-anomaly ghost state")


func _test_stability_response_and_natural_background_gradient() -> void:
	var graph := _two_cell_graph()
	var settings := ArcaneEnvironmentSettings.new()
	var background := PackedFloat32Array([0.2, 0.8])
	var equilibrium := ArcaneEnvironmentGenerator.synthesize_stability(
		graph,
		background,
		PackedFloat32Array([0.0, 1.0]),
		background,
		PackedFloat64Array([1.0, 1.0]),
		settings
	)
	_expect(equilibrium.arcane_stress[0] == 0.0 and equilibrium.arcane_stress[1] == 0.0,
		"a natural Background gradient must not count as Arcane Stress")
	_expect(equilibrium.stability[0] == 1.0 and equilibrium.stability[1] == 1.0,
		"C=B must remain fully stable regardless of Background gradient or resistance")
	var disturbed := ArcaneEnvironmentGenerator.synthesize_stability(
		graph,
		PackedFloat32Array([0.2, 0.2]),
		PackedFloat32Array([0.0, 1.0]),
		PackedFloat64Array([0.7, 0.7]),
		PackedFloat64Array([0.5, 0.5]),
		settings
	)
	_expect(disturbed.stability[0] < 0.25,
		"strong excess Mana against low resistance must produce low Final Mana Stability")
	_expect(disturbed.stability[1] > disturbed.stability[0],
		"higher Background Stability must resist the same Arcane Stress better")


func _test_resolution_behavior() -> void:
	var settings := ArcaneEnvironmentSettings.new()
	var samples := [0.0, 13.75, 27.5, 41.25, 55.0, 80.0]
	for distance in samples:
		var first := ArcaneEnvironmentGenerator.leyline_influence(distance, settings.leyline_influence_radius)
		var second := ArcaneEnvironmentGenerator.leyline_influence(distance, settings.leyline_influence_radius)
		_expect(first == second, "world-space Leyline falloff must not depend on Cell resolution")
	var coarse := _two_cell_graph(2.0, 2.0)
	var dense := _two_cell_graph(0.5, 0.5)
	var background := PackedFloat32Array([0.25, 0.75])
	for graph in [coarse, dense]:
		var result := ArcaneEnvironmentGenerator.solve_transport(
			graph,
			background,
			PackedFloat32Array([0.5, 0.5]),
			PackedFloat64Array([0.15, 0.15]),
			PackedVector2Array([Vector2.ZERO, Vector2.ZERO]),
			_zero_rates(graph),
			_zero_rates(graph),
			settings,
			PackedFloat64Array(),
			false
		)
		_expect(_arrays_approximately_equal(result.concentration, background, 0.0000001),
			"Background equilibrium must remain invariant across synthetic Cell areas")


func _test_no_new_randomness() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/world/worldgen/arcane/arcane_environment_generator.gd"
	)
	for forbidden in ["FastNoiseLite", "RandomNumberGenerator", "DeterministicRng", "world_seed"]:
		_expect(source.find(forbidden) < 0,
			"v2.3 Generator must not introduce %s" % forbidden)


func _test_seed_one_generation_determinism_and_zero_regression() -> void:
	_seed_one_graph = SpatialGenerator.generate(SpatialConfig.new())
	_seed_one_field = ArcaneFieldGenerator.generate(_seed_one_graph, 1) \
			if _seed_one_graph != null else null
	_seed_one_web = ArcaneWebGenerator.generate(1, 2000.0, 1000.0) \
			if _seed_one_field != null else null
	_seed_one_circulation = ArcaneCirculationGenerator.generate(_seed_one_web) \
			if _seed_one_web != null else null
	_seed_one_empty_forcing = _empty_forcing_layer(_seed_one_graph) \
			if _seed_one_graph != null else null
	_expect(_seed_one_graph != null and _seed_one_field != null
			and _seed_one_web != null and _seed_one_circulation != null,
		"Seed 1 v2.2.1 fixture should generate")
	if _seed_one_circulation == null:
		return
	var input_hash := _arcane_input_hash()
	_seed_one_environment = ArcaneEnvironmentGenerator.generate(
		_seed_one_graph, _seed_one_field, _seed_one_web, _seed_one_circulation,
		_seed_one_empty_forcing
	)
	var first_diagnostics := ArcaneEnvironmentGenerator.last_generation_diagnostics()
	_expect(_seed_one_environment != null, "Seed 1 Arcane Environment should generate")
	if _seed_one_environment == null:
		return
	_expect(ArcaneEnvironmentValidator.validate(
		_seed_one_graph, _seed_one_environment
	).is_empty(), "Seed 1 Arcane Environment should pass its Validator")
	_expect(ArcaneEnvironmentValidator.validate_solver_report(
		first_diagnostics.solver
	).is_empty(), "Seed 1 Solver must converge and report a finite accepted result")
	_expect(input_hash == _arcane_input_hash(),
		"v2.3 generation must preserve SpatialGraph and all v2.0-v2.2 formal data")
	var repeat := ArcaneEnvironmentGenerator.generate(
		_seed_one_graph, _seed_one_field, _seed_one_web, _seed_one_circulation,
		_seed_one_empty_forcing
	)
	_expect(repeat != null, "repeat Seed 1 Arcane Environment should generate")
	if repeat != null:
		_expect(_seed_one_environment.mana_concentration == repeat.mana_concentration
				and _seed_one_environment.mana_flowability == repeat.mana_flowability
				and _seed_one_environment.mana_stability == repeat.mana_stability,
			"identical v2.3 inputs must reproduce all three formal arrays exactly")
	var diagnostics := ArcaneEnvironmentGenerator.last_generation_diagnostics()
	_expect(diagnostics.concentration_delta.max > 0.04
			and diagnostics.concentration_delta.min < -0.04,
		"Seed 1 should contain visible Mana enrichment and depletion in both directions")


func _print_seed_one_statistics() -> void:
	if _seed_one_environment == null:
		return
	print("Arcane Environment Seed 1 statistics: ",
		ArcaneEnvironmentGenerator.last_generation_diagnostics())


func _two_cell_graph(first_area: float = 1.0, second_area: float = 1.0) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.cell_centers = PackedVector2Array([Vector2(0.0, 0.0), Vector2(2.0, 0.0)])
	graph.cell_areas = PackedFloat64Array([first_area, second_area])
	graph.vertex_positions = PackedVector2Array([Vector2(1.0, -0.5), Vector2(1.0, 0.5)])
	graph.edge_vertex_ids = [Vector2i(0, 1)]
	graph.edge_cells = [PackedInt32Array([0, 1])]
	graph.cell_neighbors = [PackedInt32Array([1]), PackedInt32Array([0])]
	return graph


func _boundary_cell_graph() -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.cell_centers = PackedVector2Array([Vector2.ZERO])
	graph.cell_areas = PackedFloat64Array([1.0])
	graph.vertex_positions = PackedVector2Array([Vector2(1.0, -0.5), Vector2(1.0, 0.5)])
	graph.edge_vertex_ids = [Vector2i(0, 1)]
	graph.edge_cells = [PackedInt32Array([0])]
	graph.cell_neighbors = [PackedInt32Array()]
	return graph


func _projection_graph() -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.cell_centers = PackedVector2Array([Vector2(50.0, 50.0), Vector2(50.0, 130.0)])
	graph.cell_areas = PackedFloat64Array([1.0, 1.0])
	return graph


func _single_leyline_web() -> ArcaneWebLayer:
	var web := ArcaneWebLayer.new()
	web.nodes = [
		ArcaneWebNode.new(0, Vector2(0.0, 50.0), ArcaneWebNode.Kind.BOUNDARY_EXIT),
		ArcaneWebNode.new(1, Vector2(100.0, 50.0), ArcaneWebNode.Kind.BOUNDARY_EXIT),
	]
	web.edges = [ArcaneWebEdge.new(0, 0, 1, 100.0)]
	web.rebuild_incidence()
	return web


func _pure_transport_settings(iterations: int) -> ArcaneEnvironmentSettings:
	var settings := ArcaneEnvironmentSettings.new()
	settings.background_restoration_min_rate = 0.0
	settings.background_restoration_max_rate = 0.0
	settings.solver_max_iterations = iterations
	settings.solver_convergence_epsilon = 0.000000000001
	return settings


func _total_mass(graph: SpatialGraph, concentrations) -> float:
	var total := 0.0
	for cell_id in graph.cell_count():
		total += float(concentrations[cell_id]) * graph.cell_areas[cell_id]
	return total


func _zero_rates(graph: SpatialGraph) -> PackedFloat64Array:
	var rates := PackedFloat64Array()
	rates.resize(graph.cell_count())
	return rates


func _empty_forcing_layer(graph: SpatialGraph) -> ArcaneForcingLayer:
	var forcing := ArcaneForcingLayer.new()
	forcing.source_rate.resize(graph.cell_count())
	forcing.sink_rate.resize(graph.cell_count())
	return forcing


func _arrays_approximately_equal(first, second, tolerance: float) -> bool:
	if first.size() != second.size():
		return false
	for index in first.size():
		if absf(float(first[index]) - float(second[index])) > tolerance:
			return false
	return true


func _arcane_input_hash() -> int:
	var signature: Array = [
		_seed_one_graph.cell_centers,
		_seed_one_graph.cell_areas,
		_seed_one_graph.edge_vertex_ids,
		_seed_one_graph.edge_cells,
		_seed_one_field.background_mana,
		_seed_one_field.background_stability,
	]
	for domain in _seed_one_web.domains:
		signature.append([domain.id, domain.nucleus_position, domain.power_weight, domain.polygon])
	for node in _seed_one_web.nodes:
		signature.append([node.id, node.world_position, node.kind])
	for edge in _seed_one_web.edges:
		signature.append([edge.id, edge.node_a_id, edge.node_b_id, edge.length])
	signature.append(_seed_one_circulation.edge_flow)
	return hash(signature)


func _object_has_property(object: Object, property_name: StringName) -> bool:
	for property in object.get_property_list():
		if StringName(property.name) == property_name:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Arcane Environment: all 13 test groups passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	printerr("Arcane Environment: %d failures" % _failures.size())
	quit(1)
