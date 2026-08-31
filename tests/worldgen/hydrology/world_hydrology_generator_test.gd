extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_flow_direction_uses_steepest_slope()
	_test_flow_accumulation_confluence()
	_test_river_strahler_hierarchy()
	_test_short_formal_rivers_are_filtered_without_removing_hydrology()
	_test_two_watersheds()
	_test_closed_basin_inflow()
	_test_lengths_values_and_loop_validation()
	_finish()


func _test_flow_direction_uses_steepest_slope() -> void:
	var graph := _graph(
		[
			PackedInt32Array([1, 2]),
			PackedInt32Array([0]),
			PackedInt32Array([0]),
		],
		[
			PackedFloat64Array([100.0, 1.0]),
			PackedFloat64Array([100.0]),
			PackedFloat64Array([1.0]),
		],
		PackedFloat64Array([2.0, 3.0, 4.0]),
		PackedByteArray([0, 1, 1])
	)
	var terrain := _terrain([10.0, 0.0, 5.0])
	var before := terrain.terrain_height.duplicate()
	var climate := _climate([2.0, 2.0, 2.0], [10.0, 10.0, 10.0])
	var layer := WorldHydrologyGenerator.generate(
		graph, terrain, climate, PackedInt32Array([-1, -1, -1]), WorldHydrologySettings.new(1.0, 1000.0)
	)
	_expect(layer != null, "slope test should generate Formal Hydrology")
	if layer == null:
		return
	_expect(
		layer.flow_to[0] == 2,
		"flow should choose height 5 at distance 1, not lower height 0 at distance 100"
	)
	_expect(is_equal_approx(layer.local_runoff[0], 4.0), "runoff must include Cell area")
	_expect(terrain.terrain_height == before, "Formal Hydrology must not modify terrain_height")


func _test_flow_accumulation_confluence() -> void:
	var graph := _graph(
		[
			PackedInt32Array([2]),
			PackedInt32Array([2]),
			PackedInt32Array([0, 1, 3]),
			PackedInt32Array([2]),
		],
		_unit_distances([1, 1, 3, 1]),
		PackedFloat64Array([2.0, 2.0, 2.0, 2.0]),
		PackedByteArray([0, 0, 0, 1])
	)
	var terrain := _terrain([30.0, 25.0, 20.0, 10.0])
	var climate := _climate([1.0, 2.0, 3.0, 4.0], [10.0, 10.0, 10.0, 10.0])
	var layer := WorldHydrologyGenerator.generate(
		graph, terrain, climate, PackedInt32Array([-1, -1, -1, -1]), WorldHydrologySettings.new(1.0, 1.0)
	)
	_expect(layer != null, "confluence test should generate Formal Hydrology")
	if layer == null:
		return
	_expect(is_equal_approx(layer.local_runoff[2], 6.0), "C local runoff should be 3 x area 2")
	_expect(is_equal_approx(layer.flow_accumulation[2], 12.0), "C should accumulate A + B + C")
	_expect(is_equal_approx(layer.flow_accumulation[3], 20.0), "D should receive the full confluence")
	_expect(
		layer.river_network_id[2] >= 0,
		"a threshold-qualified confluence should be in a River Network"
	)


func _test_river_strahler_hierarchy() -> void:
	# (0 + 1 -> 2) gives Order 2; (Order 2 + Cell 3 -> 4) remains 2;
	# (5 + 6 -> 7) gives another Order 2; (4 + 7 -> 8) gives Order 3.
	var neighbors := [
		PackedInt32Array([2]),
		PackedInt32Array([2]),
		PackedInt32Array([0, 1, 4]),
		PackedInt32Array([4]),
		PackedInt32Array([2, 3, 8]),
		PackedInt32Array([7]),
		PackedInt32Array([7]),
		PackedInt32Array([5, 6, 8]),
		PackedInt32Array([4, 7, 9]),
		PackedInt32Array([8]),
	]
	var graph := _graph(
		neighbors,
		_unit_distances([1, 1, 3, 1, 3, 1, 1, 3, 3, 1]),
		PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]),
		PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
	)
	var terrain := _terrain([60.0, 60.0, 50.0, 50.0, 40.0, 60.0, 60.0, 40.0, 20.0, 10.0])
	var climate := _climate(
		[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
		[10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0]
	)
	var closed := PackedInt32Array()
	closed.resize(10)
	closed.fill(-1)
	var layer := WorldHydrologyGenerator.generate(
		graph, terrain, climate, closed, WorldHydrologySettings.new(1.0, 0.5)
	)
	_expect(layer != null, "Strahler test should generate Formal Hydrology")
	if layer == null:
		return
	_expect(layer.river_order[2] == 2, "1 + 1 should produce Strahler Order 2")
	_expect(layer.river_order[4] == 2, "1 + 2 should remain Strahler Order 2")
	_expect(layer.river_order[7] == 2, "the second 1 + 1 branch should be Order 2")
	_expect(layer.river_order[8] == 3, "2 + 2 should produce Strahler Order 3")
	_expect(layer.river_networks.size() == 1, "connected tributaries should form one River Network")
	_expect(
		layer.river_networks[0].order == 3,
		"River Network metadata should expose maximum Strahler Order"
	)


func _test_short_formal_rivers_are_filtered_without_removing_hydrology() -> void:
	var graph := _graph(
		[
			PackedInt32Array([1]),
			PackedInt32Array([0]),
			PackedInt32Array([3]),
			PackedInt32Array([2, 4]),
			PackedInt32Array([3]),
		],
		_unit_distances([1, 1, 1, 2, 1]),
		PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0]),
		PackedByteArray([0, 1, 0, 0, 1])
	)
	var terrain := _terrain([10.0, 0.0, 20.0, 10.0, 0.0])
	var climate := _climate(
		[1.0, 1.0, 1.0, 1.0, 1.0], [10.0, 10.0, 10.0, 10.0, 10.0]
	)
	var closed := PackedInt32Array([-1, -1, -1, -1, -1])
	var unfiltered := WorldHydrologyGenerator.generate(
		graph, terrain, climate, closed, WorldHydrologySettings.new(1.0, 0.5, 1)
	)
	var filtered := WorldHydrologyGenerator.generate(
		graph, terrain, climate, closed, WorldHydrologySettings.new(1.0, 0.5, 3)
	)
	_expect(unfiltered != null and filtered != null, "short River filtering cases should generate")
	if unfiltered == null or filtered == null:
		return
	_expect(unfiltered.river_networks.size() == 2, "unfiltered case should contain both candidates")
	_expect(filtered.river_networks.size() == 1, "two-Cell candidate must be absent formally")
	_expect(
		filtered.river_network_id[0] == -1 and filtered.river_network_id[1] == -1,
		"filtered creek Cells must not retain formal River Network IDs"
	)
	_expect(
		filtered.river_order[0] == -1 and filtered.river_order[1] == -1,
		"filtered creek Cells must not retain formal Strahler Order"
	)
	_expect(
		filtered.river_network_id[2] == 0 \
				and filtered.river_network_id[3] == 0 \
				and filtered.river_network_id[4] == 0,
		"three-Cell candidate must remain one consistently renumbered formal Network"
	)
	_expect(filtered.local_runoff == unfiltered.local_runoff, "filtering must preserve Local Runoff")
	_expect(filtered.flow_to == unfiltered.flow_to, "filtering must preserve Flow Direction")
	_expect(
		filtered.flow_accumulation == unfiltered.flow_accumulation,
		"filtering must preserve Flow Accumulation"
	)
	_expect(filtered.watershed_id == unfiltered.watershed_id, "filtering must preserve Watersheds")
	_expect(
		EcologyGenerator.river_strength_for(
			filtered.flow_accumulation[1], filtered.settings.river_runoff_threshold
		) > 0.0,
		"filtered creek must retain accumulation-based Ecology and Soil influence"
	)


func _test_two_watersheds() -> void:
	var graph := _graph(
		[
			PackedInt32Array([1]),
			PackedInt32Array([0, 2]),
			PackedInt32Array([1, 3]),
			PackedInt32Array([2]),
		],
		_unit_distances([1, 2, 2, 1]),
		PackedFloat64Array([1.0, 1.0, 1.0, 1.0]),
		PackedByteArray([1, 0, 0, 1])
	)
	var terrain := _terrain([0.0, 10.0, 10.0, 0.0])
	var climate := _climate([1.0, 1.0, 1.0, 1.0], [10.0, 10.0, 10.0, 10.0])
	var layer := WorldHydrologyGenerator.generate(
		graph, terrain, climate, PackedInt32Array([-1, -1, -1, -1])
	)
	_expect(layer != null, "watershed test should generate Formal Hydrology")
	if layer == null:
		return
	_expect(layer.watershed_count == 2, "two boundary outlets should create two Watersheds")
	_expect(layer.watershed_id[0] == layer.watershed_id[1], "left slope should share its outlet")
	_expect(layer.watershed_id[2] == layer.watershed_id[3], "right slope should share its outlet")
	_expect(layer.watershed_id[1] != layer.watershed_id[2], "different outlets need different IDs")


func _test_closed_basin_inflow() -> void:
	var graph := _graph(
		[PackedInt32Array([1]), PackedInt32Array([0])],
		_unit_distances([1, 1]),
		PackedFloat64Array([4.0, 5.0]),
		PackedByteArray([0, 0])
	)
	var terrain := _terrain([10.0, 0.0])
	var climate := _climate([2.0, 3.0], [10.0, 20.0])
	var layer := WorldHydrologyGenerator.generate(
		graph, terrain, climate, PackedInt32Array([-1, 0]), WorldHydrologySettings.new(1.0, 1000.0)
	)
	_expect(layer != null, "Closed Basin test should generate Formal Hydrology")
	if layer == null:
		return
	_expect(layer.closed_basin_inflows.size() == 1, "one Closed Basin should have one inflow record")
	var basin: ClosedBasinInflow = layer.closed_basin_inflows[0]
	_expect(is_equal_approx(basin.catchment_area, 9.0), "basin catchment area should include upstream Cells")
	_expect(is_equal_approx(basin.total_inflow, 23.0), "basin inflow should sum catchment local runoff once")
	_expect(
		is_equal_approx(basin.mean_temperature, 140.0 / 9.0),
		"basin mean temperature should be area weighted"
	)


func _test_lengths_values_and_loop_validation() -> void:
	var graph := _graph(
		[PackedInt32Array([1]), PackedInt32Array([0, 2]), PackedInt32Array([1])],
		_unit_distances([1, 2, 1]),
		PackedFloat64Array([1.0, 1.0, 1.0]),
		PackedByteArray([0, 0, 1])
	)
	var terrain := _terrain([20.0, 10.0, 0.0])
	var climate := _climate([1.0, 2.0, 3.0], [10.0, 10.0, 10.0])
	var closed := PackedInt32Array([-1, -1, -1])
	var layer := WorldHydrologyGenerator.generate(graph, terrain, climate, closed)
	_expect(layer != null, "validation test should generate Formal Hydrology")
	if layer == null:
		return
	_expect(
		is_equal_approx(layer.settings.river_runoff_threshold, 3000.0),
		"default river runoff threshold should be 3000"
	)
	_expect(
		layer.settings.formal_river_min_cells == 3,
		"default formal minimum River Network length should be 3 Cells"
	)
	for values in [
		layer.local_runoff,
		layer.flow_to,
		layer.flow_accumulation,
		layer.watershed_id,
		layer.river_network_id,
		layer.river_order,
	]:
		_expect(values.size() == graph.cell_count(), "every formal PackedArray should match Cell Count")
	for cell_id in graph.cell_count():
		_expect(is_finite(layer.local_runoff[cell_id]), "local runoff should be finite")
		_expect(layer.local_runoff[cell_id] >= 0.0, "local runoff should be non-negative")
		_expect(is_finite(layer.flow_accumulation[cell_id]), "accumulation should be finite")
		_expect(
			layer.flow_accumulation[cell_id] >= layer.local_runoff[cell_id],
			"accumulation should include local runoff"
		)
	_expect(
		WorldHydrologyValidator.validate(graph, terrain, climate, closed, layer).is_empty(),
		"generated Formal Hydrology should pass Validator"
	)
	layer.flow_to[0] = 1
	layer.flow_to[1] = 0
	var errors := WorldHydrologyValidator.validate(graph, terrain, climate, closed, layer)
	var found_loop := false
	for error in errors:
		if "loop" in error:
			found_loop = true
			break
	_expect(found_loop, "Validator should reject a flow_to loop")


func _graph(
		neighbors: Array,
		distances: Array,
		areas: PackedFloat64Array,
		border: PackedByteArray
) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(1, float(neighbors.size()), 1.0, neighbors.size(), 0.9)
	graph.cell_centers.resize(neighbors.size())
	for cell_id in neighbors.size():
		graph.cell_centers[cell_id] = Vector2(cell_id, 0.5)
	graph.cell_neighbors = neighbors
	graph.cell_neighbor_distances = distances
	graph.cell_areas = areas
	graph.cell_is_border = border
	return graph


func _unit_distances(neighbor_counts: Array) -> Array:
	var distances: Array = []
	for neighbor_count in neighbor_counts:
		var values := PackedFloat64Array()
		values.resize(neighbor_count)
		values.fill(1.0)
		distances.append(values)
	return distances


func _terrain(values: Array) -> TerrainHeightLayer:
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = PackedFloat32Array(values)
	return terrain


func _climate(precipitation: Array, temperature: Array) -> WorldClimateLayer:
	var climate := WorldClimateLayer.new()
	climate.precipitation = PackedFloat32Array(precipitation)
	climate.temperature = PackedFloat32Array(temperature)
	return climate


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Formal Hydrology: all 7 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Formal Hydrology: %d failures" % _failures.size())
		quit(1)
