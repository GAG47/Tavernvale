extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_unconditioned_sink_accumulates_and_stops()
	_test_preliminary_and_formal_flow_share_results()
	_finish()


func _test_unconditioned_sink_accumulates_and_stops() -> void:
	var graph := _line_graph(4)
	var terrain := _terrain([30.0, 20.0, 10.0, 40.0])
	var climate := _climate([1.0, 2.0, 3.0, 4.0])
	var flow := PreliminaryFlowGenerator.generate(
		graph, terrain, climate, WorldHydrologySettings.new(1.0, 5000.0)
	)
	_expect(flow != null, "Preliminary Flow should accept an unconditioned Sink")
	if flow == null:
		return
	_expect(flow.flow_to[0] == 1 and flow.flow_to[1] == 2, "upstream Cells should drain downhill")
	_expect(
		flow.flow_to[2] == HydrologyFlowResult.FLOW_TO_SINK,
		"unconditioned local minimum should remain a Sink"
	)
	_expect(is_equal_approx(flow.local_runoff[2], 6.0), "Sink local runoff should use precipitation x area")
	_expect(is_equal_approx(flow.flow_accumulation[2], 12.0), "Sink should retain all upstream runoff")
	for cell_id in flow.cell_count():
		_expect(is_finite(flow.flow_accumulation[cell_id]), "Preliminary accumulation should be finite")
		_expect(flow.flow_accumulation[cell_id] >= 0.0, "Preliminary accumulation should be non-negative")


func _test_preliminary_and_formal_flow_share_results() -> void:
	var graph := _line_graph(4)
	var terrain := _terrain([30.0, 20.0, 10.0, 0.0])
	var climate := _climate([1.0, 2.0, 3.0, 4.0])
	var settings := WorldHydrologySettings.new(1.5, 100000.0)
	var preliminary := PreliminaryFlowGenerator.generate(graph, terrain, climate, settings)
	var closed_basin_id := PackedInt32Array([-1, -1, -1, -1])
	var formal := WorldHydrologyGenerator.generate(
		graph, terrain, climate, closed_basin_id, settings
	)
	_expect(preliminary != null and formal != null, "both Flow consumers should generate")
	if preliminary == null or formal == null:
		return
	_expect(
		preliminary.local_runoff == formal.local_runoff,
		"identical input must produce identical shared local runoff"
	)
	_expect(
		preliminary.flow_to == formal.flow_to,
		"identical drainable terrain must produce identical shared Flow Direction"
	)
	_expect(
		preliminary.flow_accumulation == formal.flow_accumulation,
		"identical input must produce identical shared Flow Accumulation"
	)


func _line_graph(cell_count: int) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(1, float(cell_count), 1.0, cell_count, 0.9)
	graph.cell_centers.resize(cell_count)
	graph.cell_neighbors.resize(cell_count)
	graph.cell_neighbor_distances.resize(cell_count)
	graph.cell_areas.resize(cell_count)
	graph.cell_areas.fill(2.0)
	graph.cell_is_border.resize(cell_count)
	graph.cell_is_border[cell_count - 1] = 1
	for cell_id in cell_count:
		graph.cell_centers[cell_id] = Vector2(cell_id, 0.5)
		var neighbors := PackedInt32Array()
		if cell_id > 0:
			neighbors.append(cell_id - 1)
		if cell_id + 1 < cell_count:
			neighbors.append(cell_id + 1)
		graph.cell_neighbors[cell_id] = neighbors
		var distances := PackedFloat64Array()
		distances.resize(neighbors.size())
		distances.fill(1.0)
		graph.cell_neighbor_distances[cell_id] = distances
	return graph


func _terrain(values: Array) -> TerrainHeightLayer:
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = PackedFloat32Array(values)
	return terrain


func _climate(precipitation: Array) -> WorldClimateLayer:
	var climate := WorldClimateLayer.new()
	climate.precipitation = PackedFloat32Array(precipitation)
	climate.temperature.resize(precipitation.size())
	climate.temperature.fill(10.0)
	return climate


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Preliminary Flow Integration: all 2 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Preliminary Flow Integration: %d failures" % _failures.size())
		quit(1)
