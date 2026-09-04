extends SceneTree

var _failures := PackedStringArray()
var _seed_one_graph: SpatialGraph
var _seed_one_forcing: ArcaneForcingLayer
var _seed_one_environment: ArcaneEnvironmentLayer
var _forcing_diagnostics := {}
var _environment_diagnostics := {}


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_settings_and_formal_contract()
	_test_fixed_total_power_and_radius_independence()
	_test_boundary_partial_power()
	_test_projected_power_resolution_behavior()
	_test_localized_core_support()
	_test_determinism_and_different_seed()
	_test_resolution_independent_sites()
	_test_poisson_separation_and_extended_boundary()
	_test_independent_from_arcane_web()
	_test_source_and_sink_equations()
	_test_source_sink_compete_with_restoration()
	_test_empty_forcing_v230_regression()
	_test_local_forcing_propagates_beyond_core()
	_test_web_transports_source_and_sink_anomalies()
	_test_drift_moves_source_anomaly()
	_test_forcing_does_not_change_flowability_web_or_circulation()
	_test_forcing_limits_timestep_and_avoids_overshoot()
	_test_seed_one_natural_forcing_pipeline()
	_print_seed_one_statistics()
	_finish()


func _test_settings_and_formal_contract() -> void:
	var settings := ArcaneForcingSettings.new()
	_expect(settings.validate().is_empty(), "default Arcane Forcing settings should validate")
	_expect(settings.forcing_min_separation == 420.0,
		"forcing minimum separation must be 420 world units")
	_expect(settings.forcing_poisson_k == 30, "Forcing Bridson k must be 30")
	_expect(settings.forcing_generation_margin == 420.0,
		"forcing generation margin must be 420 world units")
	_expect(settings.forcing_core_radius == 30.0 and settings.forcing_total_power == 70.0,
		"localized forcing Sites must use core radius 30 and total power 70")
	_expect(ArcaneForcingGenerator.FORCING_SEED_SALT == 0x46524345,
		"Arcane Forcing must use the independent FRCE seed salt")
	var site := ArcaneForcingSite.new()
	for required in ["id", "world_position", "kind", "core_radius", "total_power"]:
		_expect(_object_has_property(site, StringName(required)),
			"ArcaneForcingSite must formally store %s" % required)
	for forbidden in [
		"radius", "strength", "leyline_id", "junction_id", "domain_id",
		"structural_importance", "flow_direction",
	]:
		_expect(not _object_has_property(site, StringName(forbidden)),
			"ArcaneForcingSite must not formally store %s" % forbidden)
	var layer := ArcaneForcingLayer.new()
	for required in ["sites", "source_rate", "sink_rate"]:
		_expect(_object_has_property(layer, StringName(required)),
			"ArcaneForcingLayer must formally store %s" % required)
	_expect(not _object_has_property(layer, &"net_forcing"),
		"ArcaneForcingLayer must preserve separate source_rate and sink_rate")


func _test_fixed_total_power_and_radius_independence() -> void:
	var graph := _projection_grid_graph(300.0, 300.0, 2.0)
	var default_site := ArcaneForcingSite.new(
		0, Vector2(150.0, 150.0), ArcaneForcingSite.Kind.SOURCE, 30.0, 70.0
	)
	var wide_site := ArcaneForcingSite.new(
		0, Vector2(150.0, 150.0), ArcaneForcingSite.Kind.SOURCE, 60.0, 70.0
	)
	var default_power := _project_site_power(graph, default_site)
	var wide_power := _project_site_power(graph, wide_site)
	_expect(absf(default_power - default_site.total_power) / default_site.total_power < 0.01,
		"an interior localized Source must project approximately its fixed total power")
	_expect(absf(wide_power - wide_site.total_power) / wide_site.total_power < 0.01,
		"changing core radius must not change the Source's integrated total ability")
	_expect(absf(default_power - wide_power) / default_site.total_power < 0.01,
		"equal total_power with different radii must integrate to approximately equal power")


func _test_boundary_partial_power() -> void:
	var graph := _projection_grid_graph(300.0, 300.0, 2.0)
	var boundary_site := ArcaneForcingSite.new(
		0, Vector2(0.0, 150.0), ArcaneForcingSite.Kind.SOURCE, 30.0, 70.0
	)
	var projected := _project_site_power(graph, boundary_site)
	_expect(projected > 0.0 and projected < boundary_site.total_power * 0.60,
		"a boundary Core must contribute only its in-world partial power")
	_expect(absf(projected - boundary_site.total_power) > 1.0,
		"boundary power must not be discretely renormalized back to total_power")


func _test_projected_power_resolution_behavior() -> void:
	var site := ArcaneForcingSite.new(
		0, Vector2(150.0, 150.0), ArcaneForcingSite.Kind.SOURCE, 30.0, 70.0
	)
	var coarse_power := _project_site_power(
		_projection_grid_graph(300.0, 300.0, 10.0), site
	)
	var fine_power := _project_site_power(
		_projection_grid_graph(300.0, 300.0, 2.0), site
	)
	_expect(absf(coarse_power - site.total_power) / site.total_power < 0.12,
		"coarse Cell-center quadrature should preserve localized Source power reasonably")
	_expect(absf(fine_power - site.total_power) < absf(coarse_power - site.total_power),
		"denser SpatialGraph projection should converge toward the same total_power")


func _test_localized_core_support() -> void:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(1, 100.0, 100.0, 4, 0.9)
	graph.cell_centers = PackedVector2Array([
		Vector2(50.0, 50.0), Vector2(79.0, 50.0),
		Vector2(80.0, 50.0), Vector2(81.0, 50.0),
	])
	graph.cell_areas = PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
	var source_layer := ArcaneForcingLayer.new()
	source_layer.sites.append(ArcaneForcingSite.new(
		0, Vector2(50.0, 50.0), ArcaneForcingSite.Kind.SOURCE, 30.0, 70.0
	))
	ArcaneForcingGenerator.project_rates(graph, source_layer, ArcaneForcingSettings.new())
	var sink_layer := ArcaneForcingLayer.new()
	sink_layer.sites.append(ArcaneForcingSite.new(
		0, Vector2(50.0, 50.0), ArcaneForcingSite.Kind.SINK, 30.0, 70.0
	))
	ArcaneForcingGenerator.project_rates(graph, sink_layer, ArcaneForcingSettings.new())
	_expect(source_layer.source_rate[1] > 0.0 and source_layer.source_rate[2] == 0.0
			and source_layer.source_rate[3] == 0.0,
		"Source density must be exactly zero at and outside core_radius 30")
	_expect(sink_layer.sink_rate[1] > 0.0 and sink_layer.sink_rate[2] == 0.0
			and sink_layer.sink_rate[3] == 0.0,
		"Sink density must be exactly zero at and outside core_radius 30")


func _test_determinism_and_different_seed() -> void:
	var graph := SpatialGenerator.generate(SpatialConfig.new(1, 1000.0, 600.0, 500, 0.9))
	var first := ArcaneForcingGenerator.generate(graph, 1234)
	var repeat := ArcaneForcingGenerator.generate(graph, 1234)
	var different := ArcaneForcingGenerator.generate(graph, 1235)
	_expect(first != null and repeat != null and different != null,
		"Arcane Forcing determinism fixtures should generate")
	if first == null or repeat == null or different == null:
		return
	_expect(_site_signature(first) == _site_signature(repeat),
		"same World Seed/Extent must reproduce all forcing Sites exactly")
	_expect(first.source_rate == repeat.source_rate and first.sink_rate == repeat.sink_rate,
		"same inputs must reproduce projected source/sink rates exactly")
	_expect(_site_signature(first) != _site_signature(different),
		"a different World Seed must change the sparse forcing Sites")
	var formal_graph := SpatialGenerator.generate(SpatialConfig.new())
	var formal := ArcaneForcingGenerator.generate(formal_graph, 1)
	var expected_positions := [
		Vector2(146.8586, 308.0162), Vector2(268.6930, 761.4801),
		Vector2(620.4968, 357.9588), Vector2(1034.213, 758.6782),
		Vector2(1358.950, 295.4805), Vector2(1745.930, 928.4238),
		Vector2(1947.563, 481.9301),
	]
	var expected_kinds := [0, 1, 1, 0, 1, 0, 0]
	_expect(formal != null and formal.sites.size() == expected_positions.size(),
		"localized retention should keep the expected v2.3.1 FRCE-sampled interior Sites")
	if formal != null and formal.sites.size() == expected_positions.size():
		for site_id in formal.sites.size():
			_expect(formal.sites[site_id].world_position.distance_to(
				expected_positions[site_id]
			) < 0.001 and formal.sites[site_id].kind == expected_kinds[site_id],
			"v2.3.2 must preserve v2.3.1 sampled position and polarity")


func _test_resolution_independent_sites() -> void:
	var coarse_graph := SpatialGenerator.generate(
		SpatialConfig.new(10, 1200.0, 700.0, 400, 0.9)
	)
	var dense_graph := SpatialGenerator.generate(
		SpatialConfig.new(10, 1200.0, 700.0, 2400, 0.9)
	)
	var coarse := ArcaneForcingGenerator.generate(coarse_graph, 8080)
	var dense := ArcaneForcingGenerator.generate(dense_graph, 8080)
	_expect(coarse != null and dense != null,
		"resolution-independence forcing fixtures should generate")
	if coarse != null and dense != null:
		_expect(_site_signature(coarse) == _site_signature(dense),
			"forcing Site positions/kinds/core radii/total powers must ignore resolution")


func _test_poisson_separation_and_extended_boundary() -> void:
	var settings := ArcaneForcingSettings.new()
	var generation_rect := Rect2(
		Vector2(-settings.forcing_generation_margin, -settings.forcing_generation_margin),
		Vector2(
			1000.0 + settings.forcing_generation_margin * 2.0,
			600.0 + settings.forcing_generation_margin * 2.0
		)
	)
	var positions := ArcaneForcingGenerator.sample_positions(
		9090, generation_rect, settings.forcing_min_separation, settings.forcing_poisson_k
	)
	for first_id in positions.size():
		for second_id in range(first_id + 1, positions.size()):
			_expect(positions[first_id].distance_to(positions[second_id])
					>= settings.forcing_min_separation - 0.0001,
				"all sampled forcing centers must satisfy Poisson minimum separation")
	var artificial_positions: Array[Vector2] = [
		Vector2(-20.0, 50.0), Vector2(-50.0, 50.0), Vector2(50.0, 50.0),
	]
	var sites := ArcaneForcingGenerator.build_sites(
		9090, artificial_positions, 100.0, 100.0, settings
	)
	_expect(sites.size() == 2 and sites[0].world_position == Vector2(-20.0, 50.0),
		"an outside Site must be retained exactly when its core circle reaches the world")
	var graph := _single_cell_graph(Vector2(5.0, 50.0))
	var layer := ArcaneForcingLayer.new()
	layer.sites = sites
	ArcaneForcingGenerator.project_rates(graph, layer, settings)
	_expect(layer.source_rate[0] > 0.0 or layer.sink_rate[0] > 0.0,
		"a retained outside Site must project a non-zero rate onto nearby formal Cells")


func _test_independent_from_arcane_web() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/world/worldgen/arcane/arcane_forcing_generator.gd"
	)
	for forbidden in [
		"ArcaneWebLayer", "ArcaneCirculationLayer", "ArcaneWebGenerator",
		"leyline", "junction", "snap",
	]:
		_expect(source.find(forbidden) < 0,
			"forcing generation must remain independent of %s" % forbidden)


func _test_source_and_sink_equations() -> void:
	var graph := _single_cell_graph(Vector2.ZERO)
	var settings := ArcaneEnvironmentSettings.new()
	settings.ambient_mana_diffusivity = 0.0
	var background := PackedFloat32Array([0.5])
	var zero := PackedFloat64Array([0.0])
	var source := ArcaneEnvironmentGenerator.solve_transport(
		graph, background, PackedFloat32Array([0.5]), _zero_tensor(graph),
		PackedVector2Array([Vector2.ZERO]), PackedFloat64Array([0.08]), zero,
		settings, PackedFloat64Array(), false
	)
	var sink := ArcaneEnvironmentGenerator.solve_transport(
		graph, background, PackedFloat32Array([0.5]), _zero_tensor(graph),
		PackedVector2Array([Vector2.ZERO]), zero, PackedFloat64Array([0.08]),
		settings, PackedFloat64Array(), false
	)
	_expect(source.concentration[0] > background[0],
		"a persistent Source must raise equilibrium Mana above Background")
	_expect(sink.concentration[0] < background[0],
		"a persistent Sink must lower equilibrium Mana below Background")
	_expect(ArcaneEnvironmentGenerator.forcing_concentration_rate(0.08, 0.0, 0.99)
			< ArcaneEnvironmentGenerator.forcing_concentration_rate(0.08, 0.0, 0.20),
		"Source injection P(1-C) must weaken as C approaches one")
	_expect(absf(ArcaneEnvironmentGenerator.forcing_concentration_rate(0.0, 0.08, 0.01))
			< absf(ArcaneEnvironmentGenerator.forcing_concentration_rate(0.0, 0.08, 0.80)),
		"Sink extraction K*C must weaken as C approaches zero")


func _test_source_sink_compete_with_restoration() -> void:
	var graph := _two_isolated_cells_graph()
	var settings := ArcaneEnvironmentSettings.new()
	settings.ambient_mana_diffusivity = 0.0
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([0.4, 0.4]),
		PackedFloat32Array([0.0, 1.0]),
		_zero_tensor(graph),
		PackedVector2Array([Vector2.ZERO, Vector2.ZERO]),
		PackedFloat64Array([0.08, 0.08]),
		PackedFloat64Array([0.0, 0.0]),
		settings,
		PackedFloat64Array(),
		false
	)
	_expect(result.concentration[0] - 0.4 > result.concentration[1] - 0.4,
		"low Background Stability must allow the same Source to sustain a larger anomaly")


func _test_empty_forcing_v230_regression() -> void:
	var graph := _two_cell_graph()
	var settings := _pure_transport_settings(1)
	settings.ambient_mana_diffusivity = 0.0
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([0.2, 0.2]),
		PackedFloat32Array([0.0, 0.0]),
		_zero_tensor(graph),
		PackedVector2Array([Vector2.ZERO, Vector2.ZERO]),
		PackedFloat64Array([0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0]),
		settings,
		PackedFloat64Array([0.8, 0.2]),
		false
	)
	_expect(result.concentration == PackedFloat64Array([0.8, 0.2]),
		"P=K=0 must add no Natural Forcing mass to the v2.3 transport update")
	_expect(ArcaneEnvironmentGenerator.forcing_concentration_rate(0.0, 0.0, 0.8) == 0.0,
		"empty forcing must retain the exact zero Source/Sink term")


func _test_local_forcing_propagates_beyond_core() -> void:
	var graph := _localized_line_graph()
	var forcing := ArcaneForcingLayer.new()
	forcing.sites.append(ArcaneForcingSite.new(
		0, Vector2(40.0, 50.0), ArcaneForcingSite.Kind.SOURCE, 30.0, 70.0
	))
	ArcaneForcingGenerator.project_rates(graph, forcing, ArcaneForcingSettings.new())
	var settings := _pure_transport_settings(200)
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([0.2, 0.2, 0.2]),
		PackedFloat32Array([0.0, 0.0, 0.0]),
		_zero_tensor(graph),
		PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]),
		forcing.source_rate,
		forcing.sink_rate,
		settings,
		PackedFloat64Array(),
		false
	)
	_expect(forcing.source_rate[1] == 0.0 and result.concentration[1] > 0.2001,
		"diffusion must carry a localized Source anomaly beyond its 30-unit Core")


func _test_web_transports_source_and_sink_anomalies() -> void:
	var graph := _three_branch_graph()
	var settings := _pure_transport_settings(8)
	var transport_tensor := PackedVector3Array([
		Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
	])
	var zero_drift := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var background := PackedFloat32Array([0.5, 0.5, 0.5])
	var source := ArcaneEnvironmentGenerator.solve_transport(
		graph, background, PackedFloat32Array([0.0, 0.0, 0.0]), transport_tensor,
		zero_drift, PackedFloat64Array([0.08, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]), settings,
		PackedFloat64Array(), false
	)
	var sink := ArcaneEnvironmentGenerator.solve_transport(
		graph, background, PackedFloat32Array([0.0, 0.0, 0.0]), transport_tensor,
		zero_drift, PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.08, 0.0, 0.0]), settings,
		PackedFloat64Array(), false
	)
	_expect(source.concentration[1] - 0.5 > source.concentration[2] - 0.5,
		"a longitudinal Leyline branch must carry Source enrichment farther than ambient space")
	_expect(0.5 - sink.concentration[1] > 0.5 - sink.concentration[2],
		"Sink depletion/replenishment must propagate farther along the Leyline branch")


func _test_drift_moves_source_anomaly() -> void:
	var graph := _three_line_cells_graph()
	var settings := _pure_transport_settings(12)
	settings.ambient_mana_diffusivity = 0.0
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([0.2, 0.2, 0.2]),
		PackedFloat32Array([0.0, 0.0, 0.0]),
		_zero_tensor(graph),
		PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.2, 0.0), Vector2(0.2, 0.0)]),
		PackedFloat64Array([0.0, 0.08, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]),
		settings,
		PackedFloat64Array(),
		false
	)
	_expect(result.concentration[2] > result.concentration[0],
		"known positive Drift must shift/extend Source enrichment downstream")


func _test_forcing_does_not_change_flowability_web_or_circulation() -> void:
	var graph := SpatialGenerator.generate(SpatialConfig.new(4242, 800.0, 500.0, 500, 0.9))
	var web := ArcaneWebGenerator.generate(4242, 800.0, 500.0)
	var circulation := ArcaneCirculationGenerator.generate(web)
	var signature_before := _web_circulation_signature(web, circulation)
	var projection_before := ArcaneEnvironmentGenerator.project_leyline_transport(
		graph, web, circulation, ArcaneEnvironmentSettings.new()
	)
	var flowability_before: PackedFloat64Array = projection_before.flowability
	var forcing := ArcaneForcingGenerator.generate(graph, 4242)
	var projection_after := ArcaneEnvironmentGenerator.project_leyline_transport(
		graph, web, circulation, ArcaneEnvironmentSettings.new()
	)
	var flowability_after: PackedFloat64Array = projection_after.flowability
	_expect(forcing != null, "Flowability independence forcing fixture should generate")
	_expect(flowability_before == flowability_after,
		"adding Source/Sink must not change Mana Flowability")
	_expect(signature_before == _web_circulation_signature(web, circulation),
		"forcing generation must not change Arcane Web or Circulation")


func _test_forcing_limits_timestep_and_avoids_overshoot() -> void:
	var graph := _single_cell_graph(Vector2.ZERO)
	var settings := _pure_transport_settings(20)
	settings.ambient_mana_diffusivity = 0.0
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([0.5]),
		PackedFloat32Array([0.0]),
		_zero_tensor(graph),
		PackedVector2Array([Vector2.ZERO]),
		PackedFloat64Array([10.0]),
		PackedFloat64Array([5.0]),
		settings,
		PackedFloat64Array([0.5]),
		false
	)
	_expect(absf(result.report.dt - settings.solver_cfl_safety / 15.0) < 0.0000001,
		"strong forcing must add P+K to the explicit timestep removal rate")
	_expect(result.report.raw_min >= 0.0 and result.report.raw_max <= 1.0,
		"forcing-aware CFL must avoid overshoot without iterative concentration clamp")


func _test_seed_one_natural_forcing_pipeline() -> void:
	_seed_one_graph = SpatialGenerator.generate(SpatialConfig.new())
	var field := ArcaneFieldGenerator.generate(_seed_one_graph, 1) \
			if _seed_one_graph != null else null
	var web := ArcaneWebGenerator.generate(1, 2000.0, 1000.0) if field != null else null
	var circulation := ArcaneCirculationGenerator.generate(web) if web != null else null
	_seed_one_forcing = ArcaneForcingGenerator.generate(_seed_one_graph, 1) \
			if _seed_one_graph != null else null
	_forcing_diagnostics = ArcaneForcingGenerator.last_generation_diagnostics()
	_expect(_seed_one_forcing != null and not _seed_one_forcing.sites.is_empty(),
		"Seed 1 formal Natural Arcane Forcing should generate sparse Sites")
	if _seed_one_forcing == null:
		return
	var prior_hash := hash([
		field.background_mana, field.background_stability,
		_web_circulation_signature(web, circulation),
	])
	_seed_one_environment = ArcaneEnvironmentGenerator.generate(
		_seed_one_graph, field, web, circulation, _seed_one_forcing
	)
	_environment_diagnostics = ArcaneEnvironmentGenerator.last_generation_diagnostics()
	_expect(_seed_one_environment != null,
		"Seed 1 Arcane Environment with formal forcing should generate")
	if _seed_one_environment == null:
		return
	_expect(prior_hash == hash([
		field.background_mana, field.background_stability,
		_web_circulation_signature(web, circulation),
	]), "v2.3.2 must preserve v2.0 Field, v2.1 Web, and v2.2 Circulation")
	_expect(_environment_diagnostics.enriched_cells.count > 0
			and _environment_diagnostics.depleted_cells.count > 0,
		"Seed 1 forcing should naturally create both >0.05 enrichment and depletion")
	_expect(ArcaneEnvironmentValidator.validate_solver_report(
		_environment_diagnostics.solver
	).is_empty(), "Seed 1 forcing Solver must provide a complete finite report")
	_expect(_environment_diagnostics.solver.hit_iteration_cap
			and not _environment_diagnostics.solver.converged
			and _environment_diagnostics.solver.iterations == 1200,
		"Seed 1 forcing must transparently report the strict-parameter Solver cap")
	var expected_projection := ArcaneEnvironmentGenerator.project_leyline_transport(
		_seed_one_graph, web, circulation, ArcaneEnvironmentSettings.new()
	)
	var expected_flowability: PackedFloat64Array = expected_projection.flowability
	_expect(_seed_one_environment.mana_flowability == _float32(expected_flowability),
		"formal forcing must not modify the v2.3 Flowability projection")


func _print_seed_one_statistics() -> void:
	if _seed_one_environment == null:
		return
	print("Localized Arcane Forcing Seed 1 statistics: ", _forcing_diagnostics)
	print("Arcane Environment v2.3.3 Seed 1 statistics: ", _environment_diagnostics)


func _single_cell_graph(center: Vector2) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(1, 100.0, 100.0, 1, 0.9)
	graph.cell_centers = PackedVector2Array([center])
	graph.cell_areas = PackedFloat64Array([1.0])
	graph.edge_vertex_ids = []
	graph.edge_cells = []
	graph.cell_neighbors = [PackedInt32Array()]
	return graph


func _projection_grid_graph(
		world_width: float, world_height: float, spacing: float
) -> SpatialGraph:
	var graph := SpatialGraph.new()
	var columns := floori(world_width / spacing)
	var rows := floori(world_height / spacing)
	graph.config = SpatialConfig.new(1, world_width, world_height, columns * rows, 0.9)
	graph.cell_centers.resize(columns * rows)
	graph.cell_areas.resize(columns * rows)
	var cell_id := 0
	for row in rows:
		for column in columns:
			graph.cell_centers[cell_id] = Vector2(
				(column + 0.5) * spacing, (row + 0.5) * spacing
			)
			graph.cell_areas[cell_id] = spacing * spacing
			cell_id += 1
	return graph


func _localized_line_graph() -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(1, 160.0, 100.0, 3, 0.9)
	graph.cell_centers = PackedVector2Array([
		Vector2(40.0, 50.0), Vector2(80.0, 50.0), Vector2(120.0, 50.0),
	])
	graph.cell_areas = PackedFloat64Array([100.0, 100.0, 100.0])
	graph.vertex_positions = PackedVector2Array([
		Vector2(60.0, 30.0), Vector2(60.0, 70.0),
		Vector2(100.0, 30.0), Vector2(100.0, 70.0),
	])
	graph.edge_vertex_ids = [Vector2i(0, 1), Vector2i(2, 3)]
	graph.edge_cells = [PackedInt32Array([0, 1]), PackedInt32Array([1, 2])]
	graph.cell_neighbors = [
		PackedInt32Array([1]), PackedInt32Array([0, 2]), PackedInt32Array([1]),
	]
	return graph


func _project_site_power(graph: SpatialGraph, site: ArcaneForcingSite) -> float:
	var layer := ArcaneForcingLayer.new()
	layer.sites.append(site)
	ArcaneForcingGenerator.project_rates(graph, layer, ArcaneForcingSettings.new())
	var rates := layer.source_rate \
			if site.kind == ArcaneForcingSite.Kind.SOURCE else layer.sink_rate
	var power := 0.0
	for cell_id in graph.cell_count():
		power += graph.cell_areas[cell_id] * rates[cell_id]
	return power


func _two_isolated_cells_graph() -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.cell_centers = PackedVector2Array([Vector2.ZERO, Vector2(2.0, 0.0)])
	graph.cell_areas = PackedFloat64Array([1.0, 1.0])
	graph.edge_vertex_ids = []
	graph.edge_cells = []
	graph.cell_neighbors = [PackedInt32Array(), PackedInt32Array()]
	return graph


func _two_cell_graph() -> SpatialGraph:
	var graph := _two_isolated_cells_graph()
	graph.vertex_positions = PackedVector2Array([Vector2(1.0, -0.5), Vector2(1.0, 0.5)])
	graph.edge_vertex_ids = [Vector2i(0, 1)]
	graph.edge_cells = [PackedInt32Array([0, 1])]
	graph.cell_neighbors = [PackedInt32Array([1]), PackedInt32Array([0])]
	return graph


func _three_branch_graph() -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.cell_centers = PackedVector2Array([
		Vector2.ZERO, Vector2(40.0, 0.0), Vector2(0.0, 40.0),
	])
	graph.cell_areas = PackedFloat64Array([100.0, 100.0, 100.0])
	graph.vertex_positions = PackedVector2Array([
		Vector2(20.0, -20.0), Vector2(20.0, 20.0),
		Vector2(-20.0, 20.0), Vector2(20.0, 20.0),
	])
	graph.edge_vertex_ids = [Vector2i(0, 1), Vector2i(2, 3)]
	graph.edge_cells = [PackedInt32Array([0, 1]), PackedInt32Array([0, 2])]
	graph.cell_neighbors = [
		PackedInt32Array([1, 2]), PackedInt32Array([0]), PackedInt32Array([0]),
	]
	return graph


func _three_line_cells_graph() -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.cell_centers = PackedVector2Array([
		Vector2(-40.0, 0.0), Vector2.ZERO, Vector2(40.0, 0.0),
	])
	graph.cell_areas = PackedFloat64Array([100.0, 100.0, 100.0])
	graph.vertex_positions = PackedVector2Array([
		Vector2(-20.0, -20.0), Vector2(-20.0, 20.0),
		Vector2(20.0, -20.0), Vector2(20.0, 20.0),
	])
	graph.edge_vertex_ids = [Vector2i(0, 1), Vector2i(2, 3)]
	graph.edge_cells = [PackedInt32Array([0, 1]), PackedInt32Array([1, 2])]
	graph.cell_neighbors = [
		PackedInt32Array([1]), PackedInt32Array([0, 2]), PackedInt32Array([1]),
	]
	return graph


func _pure_transport_settings(iterations: int) -> ArcaneEnvironmentSettings:
	var settings := ArcaneEnvironmentSettings.new()
	settings.background_restoration_min_rate = 0.0
	settings.background_restoration_max_rate = 0.0
	settings.solver_max_iterations = iterations
	settings.solver_convergence_epsilon = 0.000000000001
	return settings


func _zero_tensor(graph: SpatialGraph) -> PackedVector3Array:
	var tensor := PackedVector3Array()
	tensor.resize(graph.cell_count())
	return tensor


func _site_signature(layer: ArcaneForcingLayer) -> Array:
	var signature := []
	for site in layer.sites:
		signature.append([
			site.id, site.world_position, site.kind, site.core_radius, site.total_power,
		])
	return signature


func _float32(values) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(values.size())
	for index in values.size():
		result[index] = float(values[index])
	return result


func _web_circulation_signature(
		web: ArcaneWebLayer, circulation: ArcaneCirculationLayer
) -> int:
	var signature: Array = []
	for domain in web.domains:
		signature.append([domain.id, domain.nucleus_position, domain.power_weight, domain.polygon])
	for node in web.nodes:
		signature.append([node.id, node.world_position, node.kind])
	for edge in web.edges:
		signature.append([edge.id, edge.node_a_id, edge.node_b_id, edge.length])
	signature.append(circulation.edge_flow)
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
		print("Localized Arcane Forcing: all 18 test groups passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	printerr("Localized Arcane Forcing: %d failures" % _failures.size())
	quit(1)
