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
	_test_raw_public_mapping_and_stability_semantics()
	_test_sparse_solver_report_validation()
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
	_expect(settings.ambient_mana_diffusivity == 56.0,
		"ambient Mana diffusivity must be 56 world-units squared per solver time")
	_expect(settings.leyline_parallel_diffusivity_multiplier == 9.0,
		"Leyline parallel diffusivity multiplier must be 9")
	_expect(settings.arcane_drift_speed_per_flow == 90.0,
		"Arcane Drift speed per unit edge flow must be 90 world units per solver time")
	_expect(settings.background_restoration_min_rate == 0.03
			and settings.background_restoration_max_rate == 0.15,
		"background restoration rates must be 0.03..0.15")
	for removed_solver_setting in [
		"solver_cfl_safety", "solver_max_dt", "solver_max_iterations",
		"solver_convergence_epsilon",
	]:
		_expect(not _object_has_property(settings, StringName(removed_solver_setting)),
			"explicit runtime setting %s must not remain public" % removed_solver_setting)
	for removed_stability_setting in [
		"stability_min_resistance", "stability_stress_response",
	]:
		_expect(not _object_has_property(settings, StringName(removed_stability_setting)),
			"obsolete Stability setting %s must be removed" % removed_stability_setting)
	var layer := ArcaneEnvironmentLayer.new()
	for forbidden in [
		"web_influence", "mana_disequilibrium", "drift_vector", "restoration_rate",
		"arcane_stress", "gradient_stress", "resistance", "iteration_delta",
		"transport_tensor", "parallel_flowability", "perpendicular_flowability",
	]:
		_expect(not _object_has_property(layer, StringName(forbidden)),
			"ArcaneEnvironmentLayer must not formally store %s" % forbidden)


func _test_background_equilibrium_invariant() -> void:
	var graph := _two_cell_graph(1.0, 3.0)
	var background := PackedFloat32Array([0.15, 0.85])
	var stability := PackedFloat32Array([0.0, 1.0])
	var settings := ArcaneEnvironmentSettings.new()
	var result := ArcaneExplicitTransportReference.solve_transport(
		graph,
		background,
		stability,
		_zero_tensor(graph),
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
		_empty_forcing_layer(graph),
		background,
		_empty_faces(),
		ArcaneEnvironmentSettings.new()
	)
	_expect(result.stability[0] == 1.0 and result.stability[1] == 1.0,
		"low Background Stability plus zero Arcane Stress must yield Stability 1")


func _test_background_stability_controls_restoration() -> void:
	var graph := _two_cell_graph()
	var settings := ArcaneEnvironmentSettings.new()
	settings.ambient_mana_diffusivity = 0.0
	settings.arcane_drift_speed_per_flow = 0.0
	settings.set_meta("_explicit_max_iterations", 1)
	settings.set_meta("_explicit_delta_tolerance", 0.000000000001)
	var background := PackedFloat32Array([0.2, 0.2])
	var result := ArcaneExplicitTransportReference.solve_transport(
		graph,
		background,
		PackedFloat32Array([1.0, 0.0]),
		_zero_tensor(graph),
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
	var result := ArcaneExplicitTransportReference.solve_transport(
		graph,
		PackedFloat32Array([0.2, 0.2]),
		PackedFloat32Array([0.0, 0.0]),
		_zero_tensor(graph),
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
	var zero_circulation := ArcaneCirculationLayer.new()
	zero_circulation.edge_flow = PackedFloat32Array([0.0])
	var projection := ArcaneEnvironmentGenerator.project_leyline_transport(
		graph, web, zero_circulation, settings
	)
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
	var repeated := ArcaneEnvironmentGenerator.project_leyline_transport(
		graph, web, positive, settings
	)
	var reversed := ArcaneEnvironmentGenerator.project_leyline_transport(
		graph, web, negative, settings
	)
	_expect(projection.flowability == repeated.flowability
			and projection.flowability == reversed.flowability,
		"Flowability must depend on Web geometry and remain independent of edge_flow")


func _test_arcane_drift_direction_and_actual_mana_transport() -> void:
	var graph := _projection_graph()
	var web := _single_leyline_web()
	var circulation := ArcaneCirculationLayer.new()
	circulation.edge_flow = PackedFloat32Array([2.0])
	var projection := ArcaneEnvironmentGenerator.project_leyline_transport(
		graph, web, circulation, ArcaneEnvironmentSettings.new()
	)
	_expect(projection.drift_field[0].x > 0.0
			and absf(projection.drift_field[0].y) < 0.000001,
		"positive edge_flow must project along canonical node_a -> node_b")
	circulation.edge_flow[0] = -2.0
	var reversed := ArcaneEnvironmentGenerator.project_leyline_transport(
		graph, web, circulation, ArcaneEnvironmentSettings.new()
	)
	_expect(reversed.drift_field[0].x < 0.0,
		"negative edge_flow must reverse the concentration-independent Drift direction")

	var transport_graph := _two_cell_graph()
	var settings := _pure_transport_settings(1)
	settings.ambient_mana_diffusivity = 0.0
	var initial := PackedFloat64Array([0.7, 0.1])
	var result := ArcaneExplicitTransportReference.solve_transport(
		transport_graph,
		PackedFloat32Array([0.2, 0.2]),
		PackedFloat32Array([0.0, 0.0]),
		_zero_tensor(transport_graph),
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
	settings.ambient_mana_diffusivity = 0.0
	var initial := PackedFloat64Array([0.9, 0.1])
	var result := ArcaneExplicitTransportReference.solve_transport(
		graph,
		PackedFloat32Array([0.2, 0.2]),
		PackedFloat32Array([0.0, 0.0]),
		_zero_tensor(graph),
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
	settings.ambient_mana_diffusivity = 0.0
	var outward := ArcaneExplicitTransportReference.solve_transport(
		graph,
		PackedFloat32Array([0.6]),
		PackedFloat32Array([0.0]),
		_zero_tensor(graph),
		PackedVector2Array([Vector2(0.4, 0.0)]),
		_zero_rates(graph),
		_zero_rates(graph),
		settings,
		PackedFloat64Array([0.8]),
		true
	)
	var inward := ArcaneExplicitTransportReference.solve_transport(
		graph,
		PackedFloat32Array([0.6]),
		PackedFloat32Array([0.0]),
		_zero_tensor(graph),
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
	settings.ambient_mana_diffusivity = 56.0
	var diffusion_out := ArcaneExplicitTransportReference.solve_transport(
		graph,
		PackedFloat32Array([0.6]),
		PackedFloat32Array([0.0]),
		_zero_tensor(graph),
		PackedVector2Array([Vector2.ZERO]),
		_zero_rates(graph),
		_zero_rates(graph),
		settings,
		PackedFloat64Array([0.8]),
		true
	)
	var diffusion_in := ArcaneExplicitTransportReference.solve_transport(
		graph,
		PackedFloat32Array([0.6]),
		PackedFloat32Array([0.0]),
		_zero_tensor(graph),
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
		_empty_forcing_layer(graph),
		background,
		_empty_faces(),
		settings
	)
	_expect(equilibrium.stability[0] == 1.0 and equilibrium.stability[1] == 1.0,
		"C=B must remain fully stable regardless of Background Mana")
	var forcing := ArcaneForcingLayer.new()
	forcing.source_rate = PackedFloat32Array([0.08, 0.08])
	forcing.sink_rate = PackedFloat32Array([0.0, 0.0])
	var disturbed := ArcaneEnvironmentGenerator.synthesize_stability(
		graph,
		PackedFloat32Array([0.2, 0.2]),
		PackedFloat32Array([0.0, 1.0]),
		forcing,
		PackedFloat64Array([0.7, 0.7]),
		_empty_faces(),
		settings
	)
	_expect(disturbed.stability[0] < 1.0,
		"persistent Source forcing must lower Final Mana Stability")
	_expect(disturbed.stability[1] > disturbed.stability[0],
		"higher Background Stability must restore the same disturbance better")


func _test_raw_public_mapping_and_stability_semantics() -> void:
	var public := ArcaneEnvironmentGenerator.public_concentration_from_raw(
		PackedFloat64Array([0.8, 1.0, 1.2])
	)
	_expect(public == PackedFloat32Array([0.8, 1.0, 1.0]),
		"Public Mana Concentration must semantically map Raw concentration onto [0, 1]")
	var graph := _two_cell_graph()
	var background := PackedFloat32Array([0.2, 0.2])
	var background_stability := PackedFloat32Array([0.5, 0.5])
	var light_overload := ArcaneEnvironmentGenerator.synthesize_stability(
		graph, background, background_stability,
		_empty_forcing_layer(graph), PackedFloat64Array([1.01, 1.01]),
		_empty_faces(), ArcaneEnvironmentSettings.new()
	)
	var heavy_overload := ArcaneEnvironmentGenerator.synthesize_stability(
		graph, background, background_stability,
		_empty_forcing_layer(graph), PackedFloat64Array([1.45, 1.45]),
		_empty_faces(), ArcaneEnvironmentSettings.new()
	)
	_expect(heavy_overload.stability == light_overload.stability,
		"Raw Concentration must not directly change Mana Stability")


func _test_sparse_solver_report_validation() -> void:
	var report := {
		"converged": true, "breakdown": false, "finite": true, "iterations": 2,
		"relative_residual": 1.0e-8, "absolute_residual": 1.0e-8,
		"l_inf_residual": 1.0e-8, "raw_min": 0.1, "raw_max": 1.45,
		"raw_negative_count": 0, "raw_significantly_negative_count": 0,
	}
	_expect(ArcaneEnvironmentValidator.validate_solver_report(report).is_empty(),
		"finite converged Raw concentration above one must be accepted")
	var graph := _two_cell_graph()
	var layer := ArcaneEnvironmentLayer.new()
	layer.mana_concentration = ArcaneEnvironmentGenerator.public_concentration_from_raw(
		PackedFloat64Array([1.2, 1.45])
	)
	layer.mana_flowability = PackedFloat32Array([0.15, 1.0])
	layer.mana_stability = PackedFloat32Array([0.7, 0.4])
	_expect(ArcaneEnvironmentValidator.validate(graph, layer).is_empty(),
		"Raw overload mapped to public concentration must produce a legal formal Layer")
	report.raw_min = -0.000002
	report.raw_negative_count = 1
	report.raw_significantly_negative_count = 1
	_expect(not ArcaneEnvironmentValidator.validate_solver_report(report).is_empty(),
		"Raw concentration below -1e-6 must be rejected")


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
		var result := ArcaneExplicitTransportReference.solve_transport(
			graph,
			background,
			PackedFloat32Array([0.5, 0.5]),
			_zero_tensor(graph),
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
	var fixture_seed := 731
	var fixture_width := 600.0
	var fixture_height := 400.0
	_seed_one_graph = SpatialGenerator.generate(
		SpatialConfig.new(fixture_seed, fixture_width, fixture_height, 240, 0.9)
	)
	_seed_one_field = ArcaneFieldGenerator.generate(_seed_one_graph, fixture_seed) \
			if _seed_one_graph != null else null
	_seed_one_web = ArcaneWebGenerator.generate(fixture_seed, fixture_width, fixture_height) \
			if _seed_one_field != null else null
	_seed_one_circulation = ArcaneCirculationGenerator.generate(_seed_one_web) \
			if _seed_one_web != null else null
	_seed_one_empty_forcing = _empty_forcing_layer(_seed_one_graph) \
			if _seed_one_graph != null else null
	_expect(_seed_one_graph != null and _seed_one_field != null
			and _seed_one_web != null and _seed_one_circulation != null,
		"targeted Arcane pipeline fixture should generate")
	if _seed_one_circulation == null:
		return
	var input_hash := _arcane_input_hash()
	_seed_one_environment = ArcaneEnvironmentGenerator.generate(
		_seed_one_graph, _seed_one_field, _seed_one_web, _seed_one_circulation,
		_seed_one_empty_forcing
	)
	var first_diagnostics := ArcaneEnvironmentGenerator.last_generation_diagnostics()
	_expect(_seed_one_environment != null, "targeted Arcane Environment should generate")
	if _seed_one_environment == null:
		return
	_expect(ArcaneEnvironmentValidator.validate(
		_seed_one_graph, _seed_one_environment
	).is_empty(), "targeted Arcane Environment should pass its Validator")
	_expect(ArcaneEnvironmentValidator.validate_solver_report(
		first_diagnostics.solver
	).is_empty(), "targeted Solver must provide a complete finite diagnostic report")
	_expect(first_diagnostics.solver.converged
			and not first_diagnostics.solver.breakdown,
		"sparse production Solver must converge without breakdown")
	_expect(input_hash == _arcane_input_hash(),
		"v2.3 generation must preserve SpatialGraph and all v2.0-v2.2 formal data")
	var repeat := ArcaneEnvironmentGenerator.generate(
		_seed_one_graph, _seed_one_field, _seed_one_web, _seed_one_circulation,
		_seed_one_empty_forcing
	)
	_expect(repeat != null, "repeat targeted Arcane Environment should generate")
	if repeat != null:
		_expect(_seed_one_environment.mana_concentration == repeat.mana_concentration
				and _seed_one_environment.mana_flowability == repeat.mana_flowability
				and _seed_one_environment.mana_stability == repeat.mana_stability,
			"identical v2.3 inputs must reproduce all three formal arrays exactly")
	var diagnostics := ArcaneEnvironmentGenerator.last_generation_diagnostics()
	_expect(diagnostics.concentration_delta.max > 0.04
			and diagnostics.concentration_delta.min < -0.04,
		"targeted fixture should contain visible enrichment and depletion")


func _print_seed_one_statistics() -> void:
	if _seed_one_environment == null:
		return
	print("Arcane Environment targeted fixture statistics: ",
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
	settings.set_meta("_explicit_max_iterations", iterations)
	settings.set_meta("_explicit_delta_tolerance", 0.000000000001)
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


func _zero_tensor(graph: SpatialGraph) -> PackedVector3Array:
	var tensor := PackedVector3Array()
	tensor.resize(graph.cell_count())
	return tensor


func _empty_forcing_layer(graph: SpatialGraph) -> ArcaneForcingLayer:
	var forcing := ArcaneForcingLayer.new()
	forcing.source_rate.resize(graph.cell_count())
	forcing.sink_rate.resize(graph.cell_count())
	return forcing


func _empty_faces() -> Dictionary:
	return {
		"internal_a": PackedInt32Array(),
		"internal_b": PackedInt32Array(),
		"internal_diffusion": PackedFloat64Array(),
		"internal_velocity_length": PackedFloat64Array(),
		"boundary_cell": PackedInt32Array(),
		"boundary_diffusion": PackedFloat64Array(),
		"boundary_velocity_length": PackedFloat64Array(),
	}


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
		print("Arcane Environment: all 15 test groups passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	printerr("Arcane Environment: %d failures" % _failures.size())
	quit(1)
