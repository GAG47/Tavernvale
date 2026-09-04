extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_concentration_does_not_directly_affect_stability()
	_test_flowability_does_not_directly_affect_stability()
	_test_off_web_source_creates_low_flow_instability()
	_test_background_stability_controls_recovery()
	_test_balanced_high_throughput_is_stable()
	_test_transport_imbalance_lowers_stability()
	_test_source_and_sink_both_count()
	_test_flowability_removed_from_signature()
	_finish()


func _test_concentration_does_not_directly_affect_stability() -> void:
	var graph := _isolated_graph(2)
	var forcing := _forcing([0.0, 0.0], [0.0, 0.0])
	var result := ArcaneEnvironmentGenerator.synthesize_stability(
		graph,
		PackedFloat32Array([0.2, 0.8]),
		PackedFloat32Array([0.5, 0.5]),
		forcing,
		PackedFloat64Array([0.2, 0.8]),
		_empty_faces(),
		ArcaneEnvironmentSettings.new()
	)
	_expect(_approximately(result.stability[0], 1.0)
			and _approximately(result.stability[1], 1.0),
		"C=B must be fully stable at both low and high absolute Mana")


func _test_flowability_does_not_directly_affect_stability() -> void:
	var graph := _isolated_graph(3)
	var web := ArcaneWebLayer.new()
	web.nodes = [
		ArcaneWebNode.new(0, Vector2(-10.0, 0.0), ArcaneWebNode.Kind.BOUNDARY_EXIT),
		ArcaneWebNode.new(1, Vector2(30.0, 0.0), ArcaneWebNode.Kind.BOUNDARY_EXIT),
	]
	web.edges = [ArcaneWebEdge.new(0, 0, 1, 40.0)]
	web.rebuild_incidence()
	var circulation := ArcaneCirculationLayer.new()
	circulation.edge_flow = PackedFloat32Array([0.0])
	var projection := ArcaneEnvironmentGenerator.project_leyline_transport(
		graph, web, circulation, ArcaneEnvironmentSettings.new()
	)
	var result := _balanced_transport_result()
	_expect(projection.flowability[1] >= 0.5
			and _approximately(result.stability[1], 1.0),
		"high Flowability with zero net transport imbalance must remain stable")


func _test_off_web_source_creates_low_flow_instability() -> void:
	var graph := _isolated_graph(1)
	graph.cell_centers[0] = Vector2(100.0, 100.0)
	var web := ArcaneWebLayer.new()
	web.world_width = 200.0
	web.world_height = 200.0
	web.nodes = [
		ArcaneWebNode.new(0, Vector2(0.0, 0.0), ArcaneWebNode.Kind.BOUNDARY_EXIT),
		ArcaneWebNode.new(1, Vector2(200.0, 0.0), ArcaneWebNode.Kind.BOUNDARY_EXIT),
	]
	web.edges = [ArcaneWebEdge.new(0, 0, 1, 200.0)]
	web.rebuild_incidence()
	var circulation := ArcaneCirculationLayer.new()
	circulation.edge_flow = PackedFloat32Array([0.0])
	var settings := ArcaneEnvironmentSettings.new()
	var projection := ArcaneEnvironmentGenerator.project_leyline_transport(
		graph, web, circulation, settings
	)
	var source := ArcaneEnvironmentGenerator.synthesize_stability(
		graph, PackedFloat32Array([0.2]), PackedFloat32Array([0.0]),
		_forcing([0.08], [0.0]), PackedFloat64Array([0.6]), _empty_faces(), settings
	)
	var calm := ArcaneEnvironmentGenerator.synthesize_stability(
		graph, PackedFloat32Array([0.2]), PackedFloat32Array([0.0]),
		_forcing([0.0], [0.0]), PackedFloat64Array([0.2]), _empty_faces(), settings
	)
	_expect(_approximately(projection.flowability[0], settings.ambient_flowability)
			and source.forcing_disturbance[0] > 0.0
			and source.stability[0] < calm.stability[0],
		"an off-Web Source must create low-Flowability, lower-Stability terrain")


func _test_background_stability_controls_recovery() -> void:
	var result := ArcaneEnvironmentGenerator.synthesize_stability(
		_isolated_graph(2), PackedFloat32Array([0.2, 0.2]),
		PackedFloat32Array([0.0, 1.0]), _forcing([0.08, 0.08], [0.0, 0.0]),
		PackedFloat64Array([0.6, 0.6]), _empty_faces(), ArcaneEnvironmentSettings.new()
	)
	_expect(result.restoration_rate[1] > result.restoration_rate[0]
			and result.stability[1] > result.stability[0],
		"higher Background Stability must recover better under equal disturbance")


func _test_balanced_high_throughput_is_stable() -> void:
	var result := _balanced_transport_result()
	_expect(absf(result.transport_net_amount[0]) > 50.0
			and absf(result.transport_net_amount[1]) < 0.0000001
			and result.transport_imbalance[1] < 0.0000001
			and _approximately(result.stability[1], 1.0),
		"signed inflow/outflow must cancel before absolute transport imbalance")


func _test_transport_imbalance_lowers_stability() -> void:
	var graph := _isolated_graph(1)
	var faces := _empty_faces()
	faces.boundary_cell = PackedInt32Array([0])
	faces.boundary_diffusion = PackedFloat64Array([0.0])
	faces.boundary_velocity_length = PackedFloat64Array([1.0])
	var result := ArcaneEnvironmentGenerator.synthesize_stability(
		graph, PackedFloat32Array([0.0]), PackedFloat32Array([0.5]),
		_forcing([0.0], [0.0]), PackedFloat64Array([1.0]), faces,
		ArcaneEnvironmentSettings.new()
	)
	_expect(result.transport_imbalance[0] > 0.0 and result.stability[0] < 0.5,
		"net transport divergence must lower Stability without forcing")


func _test_source_and_sink_both_count() -> void:
	var graph := _isolated_graph(2)
	var result := ArcaneEnvironmentGenerator.synthesize_stability(
		graph, PackedFloat32Array([0.5, 0.5]), PackedFloat32Array([0.5, 0.5]),
		_forcing([0.08, 0.0], [0.0, 0.08]), PackedFloat64Array([0.7, 0.3]),
		_empty_faces(), ArcaneEnvironmentSettings.new()
	)
	_expect(_approximately(result.forcing_disturbance[0], 0.08)
			and _approximately(result.forcing_disturbance[1], 0.08)
			and result.stability[0] < 1.0 and result.stability[1] < 1.0,
		"Source and Sink coefficients must both contribute to persistent disturbance")


func _test_flowability_removed_from_signature() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/world/worldgen/arcane/arcane_environment_generator.gd"
	)
	var signature_start := source.find("static func synthesize_stability(")
	var signature_end := source.find(") -> Dictionary:", signature_start)
	var signature := source.substr(signature_start, signature_end - signature_start)
	_expect(signature.find("flowability") < 0,
		"synthesize_stability must not accept Mana Flowability")


func _balanced_transport_result() -> Dictionary:
	var faces := _empty_faces()
	faces.internal_a = PackedInt32Array([0, 1])
	faces.internal_b = PackedInt32Array([1, 2])
	faces.internal_diffusion = PackedFloat64Array([0.0, 0.0])
	faces.internal_velocity_length = PackedFloat64Array([100.0, 100.0])
	return ArcaneEnvironmentGenerator.synthesize_stability(
		_isolated_graph(3), PackedFloat32Array([0.0, 0.0, 0.0]),
		PackedFloat32Array([0.5, 0.5, 0.5]),
		_forcing([0.0, 0.0, 0.0], [0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 1.0, 1.0]), faces,
		ArcaneEnvironmentSettings.new()
	)


func _isolated_graph(count: int) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.cell_centers.resize(count)
	graph.cell_areas.resize(count)
	graph.cell_neighbors.resize(count)
	for cell_id in count:
		graph.cell_centers[cell_id] = Vector2(cell_id * 10.0, 0.0)
		graph.cell_areas[cell_id] = 1.0
		graph.cell_neighbors[cell_id] = PackedInt32Array()
	return graph


func _forcing(source_values: Array, sink_values: Array) -> ArcaneForcingLayer:
	var forcing := ArcaneForcingLayer.new()
	forcing.source_rate = PackedFloat32Array(source_values)
	forcing.sink_rate = PackedFloat32Array(sink_values)
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


func _approximately(first: float, second: float) -> bool:
	return absf(first - second) < 0.000001


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Mana Stability Decoupling: all 8 targeted groups passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	printerr("Mana Stability Decoupling: %d failures" % _failures.size())
	quit(1)
