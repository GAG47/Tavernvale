extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_flow_direction_uses_steepest_slope()
	_test_flow_accumulation_confluence()
	_test_river_strahler_hierarchy()
	_test_formal_rivers_are_filtered_without_removing_hydrology()
	_test_natural_main_upstream_tracing()
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
		graph,
		terrain,
		climate,
		PackedInt32Array([-1, -1, -1, -1]),
		WorldHydrologySettings.new(1.0, 1.0, 3, 0.0)
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
		graph, terrain, climate, closed, WorldHydrologySettings.new(1.0, 0.5, 3, 0.0)
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


func _test_formal_rivers_are_filtered_without_removing_hydrology() -> void:
	var graph := _graph(
		[
			PackedInt32Array([1]),
			PackedInt32Array([0]),
			PackedInt32Array([3]),
			PackedInt32Array([2, 4]),
			PackedInt32Array([3]),
			PackedInt32Array([6]),
			PackedInt32Array([5, 7]),
			PackedInt32Array([6]),
		],
		_unit_distances([1, 1, 1, 2, 1, 1, 2, 1]),
		PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]),
		PackedByteArray([0, 1, 0, 0, 1, 0, 0, 1])
	)
	var terrain := _terrain([10.0, 0.0, 20.0, 10.0, 0.0, 20.0, 10.0, 0.0])
	var climate := _climate(
		[1.0, 1.0, 1.0, 1.0, 1.0, 10000.0, 10000.0, 10000.0],
		[10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0]
	)
	var closed := PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1])
	var unfiltered := WorldHydrologyGenerator.generate(
		graph, terrain, climate, closed, WorldHydrologySettings.new(1.0, 0.5, 1, 0.0)
	)
	var length_filtered := WorldHydrologyGenerator.generate(
		graph, terrain, climate, closed, WorldHydrologySettings.new(1.0, 0.5, 3, 0.0)
	)
	var formal_filtered := WorldHydrologyGenerator.generate(
		graph, terrain, climate, closed, WorldHydrologySettings.new(1.0, 0.5, 3, 20000.0)
	)
	_expect(
		unfiltered != null and length_filtered != null and formal_filtered != null,
		"formal River filtering cases should generate"
	)
	if unfiltered == null or length_filtered == null or formal_filtered == null:
		return
	_expect(unfiltered.river_networks.size() == 3, "unfiltered case should contain all candidates")
	_expect(
		length_filtered.river_networks.size() == 2,
		"minimum length must remove only the two-Cell candidate"
	)
	_expect(
		formal_filtered.river_networks.size() == 1,
		"formal filter must retain only the long-enough high-discharge Network"
	)
	_expect(
		formal_filtered.river_network_id[0] == -1 \
				and formal_filtered.river_network_id[1] == -1,
		"filtered creek Cells must not retain formal River Network IDs"
	)
	_expect(
		formal_filtered.river_network_id[2] == -1 \
				and formal_filtered.river_network_id[3] == -1 \
				and formal_filtered.river_network_id[4] == -1,
		"long-enough low-discharge Network must not retain formal identity"
	)
	_expect(
		formal_filtered.river_order[0] == -1 \
				and formal_filtered.river_order[1] == -1 \
				and formal_filtered.river_order[2] == -1 \
				and formal_filtered.river_order[3] == -1 \
				and formal_filtered.river_order[4] == -1,
		"filtered creek Cells must not retain formal Strahler Order"
	)
	_expect(
		formal_filtered.river_network_id[5] == 0 \
				and formal_filtered.river_network_id[6] == 0 \
				and formal_filtered.river_network_id[7] == 0,
		"qualifying Network must remain consistently renumbered"
	)
	_expect(
		formal_filtered.river_order[5] == 1 \
				and formal_filtered.river_order[6] == 1 \
				and formal_filtered.river_order[7] == 1,
		"formal Strahler must be recomputed only on the retained World River"
	)
	_expect(
		formal_filtered.local_runoff == unfiltered.local_runoff,
		"filtering must preserve Local Runoff"
	)
	_expect(
		formal_filtered.flow_to == unfiltered.flow_to,
		"filtering must preserve Flow Direction"
	)
	_expect(
		formal_filtered.flow_accumulation == unfiltered.flow_accumulation,
		"filtering must preserve Flow Accumulation"
	)
	_expect(
		formal_filtered.watershed_id == unfiltered.watershed_id,
		"filtering must preserve Watersheds"
	)
	_expect(
		EcologyGenerator.river_strength_for(
			formal_filtered.flow_accumulation[4],
			formal_filtered.settings.river_runoff_threshold
		) > 0.0,
		"filtered creek must retain accumulation-based Ecology and Soil influence"
	)


func _test_natural_main_upstream_tracing() -> void:
	# Two candidate Sources (4 and 5) merge at 6. Source 4 chooses the larger
	# predecessor 0 and continues to 9; Source 5 breaks the 2/3 tie by Cell ID.
	# The separate 10 -> 11 -> 12 candidate has insufficient mouth discharge.
	var neighbors := [
		PackedInt32Array([9, 4]),
		PackedInt32Array([4]),
		PackedInt32Array([5]),
		PackedInt32Array([5]),
		PackedInt32Array([0, 1, 6]),
		PackedInt32Array([2, 3, 6]),
		PackedInt32Array([4, 5, 7]),
		PackedInt32Array([6, 8]),
		PackedInt32Array([7]),
		PackedInt32Array([0]),
		PackedInt32Array([11]),
		PackedInt32Array([10, 12]),
		PackedInt32Array([11]),
	]
	var graph := _graph(
		neighbors,
		_unit_distances([2, 1, 1, 1, 3, 3, 3, 2, 1, 1, 1, 2, 1]),
		PackedFloat64Array([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]),
		PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1])
	)
	var terrain := _terrain([80, 80, 80, 80, 60, 60, 40, 20, 0, 90, 30, 20, 10])
	var climate := _climate(
		[4000, 3000, 2000, 2000, 1000, 1000, 1000, 1000, 5000, 500, 5000, 0, 0],
		[10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10]
	)
	var closed := PackedInt32Array()
	closed.resize(13)
	closed.fill(-1)
	var settings := WorldHydrologySettings.new(1.0, 5000.0, 3, 20000.0)
	var control := WorldHydrologyGenerator.generate(
		graph,
		terrain,
		climate,
		closed,
		WorldHydrologySettings.new(1.0, 5000.0, 3, 30000.0)
	)
	var layer := WorldHydrologyGenerator.generate(graph, terrain, climate, closed, settings)
	_expect(control != null and layer != null, "Natural headwater cases should generate")
	if control == null or layer == null:
		return
	_expect(layer.river_networks.size() == 1, "tracing must not create another Network")
	for traced_cell in [0, 2, 4, 5, 6, 7, 8, 9]:
		_expect(
			layer.river_network_id[traced_cell] == 0,
			"Cell %d should belong to the retained World River" % traced_cell
		)
	for excluded_cell in [1, 3, 10, 11, 12]:
		_expect(
			layer.river_network_id[excluded_cell] == -1,
			"Cell %d must remain outside the formal World River" % excluded_cell
		)
	_expect(
		layer.river_network_id[0] == 0 and layer.river_network_id[9] == 0,
		"the maximum-accumulation predecessor must trace to its Natural Headwater"
	)
	_expect(
		layer.river_network_id[1] == -1,
		"Natural tracing must not add the lower-accumulation side branch"
	)
	_expect(
		layer.river_network_id[2] == 0 and layer.river_network_id[3] == -1,
		"equal accumulation must deterministically choose the smaller Cell ID"
	)
	_expect(
		layer.river_network_id[10] == -1 \
				and layer.river_network_id[11] == -1 \
				and layer.river_network_id[12] == -1,
		"a low-discharge candidate Network must not reappear through tracing"
	)
	_expect(
		layer.river_order[6] == 2 and layer.river_networks[0].order == 2,
		"Strahler Order must be recomputed from the final traced River mask"
	)
	_expect(layer.flow_to == control.flow_to, "tracing must preserve flow_to")
	_expect(
		layer.flow_accumulation == control.flow_accumulation,
		"tracing must preserve flow_accumulation"
	)
	_expect(layer.watershed_id == control.watershed_id, "tracing must preserve Watersheds")
	_expect(
		WorldHydrologyValidator.validate(graph, terrain, climate, closed, layer).is_empty(),
		"Natural Main-Upstream output should pass Validator"
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
		is_equal_approx(layer.settings.river_runoff_threshold, 5000.0),
		"default river runoff threshold should be 5000"
	)
	_expect(
		layer.settings.formal_river_min_cells == 3,
		"default formal minimum River Network length should be 3 Cells"
	)
	_expect(
		is_equal_approx(layer.settings.formal_river_min_discharge, 20000.0),
		"default formal minimum River Network discharge should be 20000"
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
		print("Formal Hydrology: all 8 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Formal Hydrology: %d failures" % _failures.size())
		quit(1)
