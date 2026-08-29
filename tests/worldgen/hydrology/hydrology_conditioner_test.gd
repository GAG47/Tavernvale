extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_normal_slope_is_unchanged()
	_test_single_cell_pit_is_filled()
	_test_blocked_valley_is_breached()
	_test_deep_basin_is_closed()
	_test_flat_gets_strict_drainage()
	_test_topology_range_and_final_drainage()
	_finish()


func _test_normal_slope_is_unchanged() -> void:
	var graph := _line_graph(4)
	var terrain := _terrain([30.0, 20.0, 10.0, -10.0])
	var result := HydrologyConditioner.condition(graph, terrain)
	_expect(result != null, "normal slope should produce a conditioning result")
	if result == null:
		return
	_expect(
		result.terrain_height == terrain.terrain_height,
		"30 -> 20 -> 10 -> Water should remain completely unchanged"
	)
	_expect(result.modified_cell_ratio == 0.0, "normal slope should report no modified Cells")


func _test_single_cell_pit_is_filled() -> void:
	var graph := _line_graph(4)
	var terrain := _terrain([9.5, 10.0, 5.0, -10.0])
	var result := HydrologyConditioner.condition(graph, terrain)
	_expect(result != null, "single pit should produce a conditioning result")
	if result == null:
		return
	_expect(
		result.conditioning_action[0] == HydrologyConditioningResult.Action.FILL,
		"small single-Cell pit should use Fill"
	)
	_expect(result.terrain_height[0] > result.terrain_height[1], "filled pit should have a strict outlet slope")
	_expect(result.filled_depression_count == 1, "single pit should count as one filled depression")


func _test_blocked_valley_is_breached() -> void:
	var graph := _line_graph(4)
	var terrain := _terrain([5.0, 10.0, 4.0, -10.0])
	var result := HydrologyConditioner.condition(graph, terrain)
	_expect(result != null, "blocked valley should produce a conditioning result")
	if result == null:
		return
	_expect(
		result.conditioning_action[1] == HydrologyConditioningResult.Action.CARVE,
		"small blocking ridge should be carved"
	)
	_expect(
		result.terrain_height[0] > result.terrain_height[1] \
				and result.terrain_height[1] > result.terrain_height[2],
		"breach path should be strictly descending"
	)
	_expect(result.breached_depression_count == 1, "blocked valley should count one breach")
	_expect(result.max_cut < 6.0, "breach should remain a limited terrain cut")


func _test_deep_basin_is_closed() -> void:
	var graph := _graph(
		[
			PackedInt32Array([1, 2]),
			PackedInt32Array([0, 2]),
			PackedInt32Array([0, 1, 3]),
			PackedInt32Array([2, 4]),
			PackedInt32Array([3, 5]),
			PackedInt32Array([4]),
		],
		PackedByteArray([0, 0, 0, 0, 0, 1])
	)
	var terrain := _terrain([5.0, 4.0, 3.0, 100.0, 10.0, -10.0])
	var result := HydrologyConditioner.condition(graph, terrain)
	_expect(result != null, "deep basin should produce a conditioning result")
	if result == null:
		return
	_expect(result.closed_basin_count == 1, "deep expensive basin should become one Closed Basin")
	_expect(result.closed_basin_id[0] >= 0, "deep basin Cells should receive a Closed Basin ID")
	_expect(result.closed_basin_id[1] == result.closed_basin_id[0], "connected basin Cells should share an ID")
	_expect(result.closed_basin_id[2] == result.closed_basin_id[0], "basin low point should share the ID")
	_expect(result.terrain_height[3] == 100.0, "expensive mountain wall must not be carved")
	_expect(result.filled_depression_count == 0, "deep basin must not be broadly filled")


func _test_flat_gets_strict_drainage() -> void:
	var graph := _line_graph(4)
	var terrain := _terrain([10.0, 10.0, 5.0, -10.0])
	var result := HydrologyConditioner.condition(graph, terrain)
	_expect(result != null, "flat should produce a conditioning result")
	if result == null:
		return
	_expect(
		result.terrain_height[0] > result.terrain_height[1],
		"flat should receive a Float32-stable strict gradient"
	)
	_expect(
		result.terrain_height[0] - result.terrain_height[1] >= 0.0009,
		"flat gradient should preserve the configured 0.001 epsilon"
	)


func _test_topology_range_and_final_drainage() -> void:
	var cases := [
		[_line_graph(4), _terrain([30.0, 20.0, 10.0, -100.0])],
		[_line_graph(4), _terrain([9.5, 10.0, 5.0, -10.0])],
		[_line_graph(4), _terrain([5.0, 10.0, 4.0, -10.0])],
	]
	for case_index in cases.size():
		var graph: SpatialGraph = cases[case_index][0]
		var terrain: TerrainHeightLayer = cases[case_index][1]
		var result := HydrologyConditioner.condition(graph, terrain)
		if result == null:
			_expect(false, "case %d should produce a result" % case_index)
			continue
		for cell_id in graph.cell_count():
			var was_land := terrain.terrain_height[cell_id] >= 0.0
			var is_land := result.terrain_height[cell_id] >= 0.0
			_expect(was_land == is_land, "conditioning must preserve topology at Cell %d" % cell_id)
			_expect(
				result.terrain_height[cell_id] >= -100.0 and result.terrain_height[cell_id] <= 100.0,
				"conditioned height must remain inside [-100, 100]"
			)
		_expect(
			_all_land_drains(graph, result),
			"case %d should have no loop or unmarked sink" % case_index
		)
		_expect(
			HydrologyConditioningValidator.validate(graph, terrain.terrain_height, result).is_empty(),
			"case %d should pass formal Hydrology validation" % case_index
		)


func _all_land_drains(graph: SpatialGraph, result: HydrologyConditioningResult) -> bool:
	for start_id in graph.cell_count():
		if result.terrain_height[start_id] < 0.0:
			continue
		var path_seen := {}
		var cell_id := start_id
		while true:
			if result.terrain_height[cell_id] < 0.0 \
					or graph.cell_is_border[cell_id] != 0 \
					or result.closed_basin_id[cell_id] >= 0:
				break
			if path_seen.has(cell_id):
				return false
			path_seen[cell_id] = true
			var next_id := -1
			var next_height := result.terrain_height[cell_id]
			for neighbor_id in graph.cell_neighbors[cell_id]:
				if result.terrain_height[neighbor_id] < next_height:
					next_height = result.terrain_height[neighbor_id]
					next_id = neighbor_id
			if next_id < 0:
				return false
			cell_id = next_id
	return true


func _line_graph(cell_count: int) -> SpatialGraph:
	var neighbors: Array = []
	for cell_id in cell_count:
		var adjacent := PackedInt32Array()
		if cell_id > 0:
			adjacent.append(cell_id - 1)
		if cell_id + 1 < cell_count:
			adjacent.append(cell_id + 1)
		neighbors.append(adjacent)
	var border := PackedByteArray()
	border.resize(cell_count)
	border[cell_count - 1] = 1
	return _graph(neighbors, border)


func _graph(neighbors: Array, border: PackedByteArray) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(1, float(neighbors.size()), 1.0, neighbors.size(), 0.9)
	graph.cell_centers.resize(neighbors.size())
	for cell_id in neighbors.size():
		graph.cell_centers[cell_id] = Vector2(cell_id, 0.5)
	graph.cell_neighbors = neighbors
	graph.cell_is_border = border
	return graph


func _terrain(values: Array) -> TerrainHeightLayer:
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = PackedFloat32Array(values)
	return terrain


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Hydrology Conditioning: all 6 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Hydrology Conditioning: %d failures" % _failures.size())
		quit(1)
