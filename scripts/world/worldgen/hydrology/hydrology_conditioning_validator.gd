class_name HydrologyConditioningValidator
extends RefCounted


static func validate(
		graph: SpatialGraph,
		original_height: PackedFloat32Array,
		result: HydrologyConditioningResult
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or result == null:
		errors.append("graph and conditioning result must not be null")
		return errors
	var count := graph.cell_count()
	if original_height.size() != count \
			or result.terrain_height.size() != count \
			or result.closed_basin_id.size() != count:
		errors.append("all hydrology arrays must contain one value per Cell")
		return errors
	for cell_id in count:
		var height := result.terrain_height[cell_id]
		if not is_finite(height) or height < -100.0 or height > 100.0:
			errors.append("terrain_height[%d] must be finite and inside [-100, 100]" % cell_id)
		if (original_height[cell_id] >= 0.0) != (height >= 0.0):
			errors.append("Land / Water topology changed at Cell %d" % cell_id)
	var drains := _cells_reaching_a_terminal(graph, result)
	var unresolved := 0
	for cell_id in count:
		if result.terrain_height[cell_id] >= 0.0 and drains[cell_id] == 0:
			unresolved += 1
	if unresolved > 0:
		errors.append("%d Land Cells have no strictly descending path to Water, boundary, or Closed Basin" % unresolved)
	return errors


static func _cells_reaching_a_terminal(
		graph: SpatialGraph,
		result: HydrologyConditioningResult
) -> PackedByteArray:
	var drains := PackedByteArray()
	drains.resize(graph.cell_count())
	var queue := PackedInt32Array()
	for cell_id in graph.cell_count():
		if result.terrain_height[cell_id] < 0.0 \
				or graph.cell_is_border[cell_id] != 0 \
				or result.closed_basin_id[cell_id] >= 0:
			drains[cell_id] = 1
			queue.append(cell_id)
	var queue_index := 0
	while queue_index < queue.size():
		var cell_id := queue[queue_index]
		queue_index += 1
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if drains[neighbor_id] == 0 \
					and result.terrain_height[neighbor_id] > result.terrain_height[cell_id]:
				drains[neighbor_id] = 1
				queue.append(neighbor_id)
	return drains
