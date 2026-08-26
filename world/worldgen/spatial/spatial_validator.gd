class_name SpatialValidator
extends RefCounted


static func validate(graph: SpatialGraph) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null:
		errors.append("graph is null")
		return errors
	var count := graph.cell_count()
	if count <= 0:
		errors.append("cell count must be greater than zero")
		return errors
	var width := graph.config.world_width
	var height := graph.config.world_height
	var epsilon := SpatialGeometry.epsilon_for_size(width, height)
	_validate_array_sizes(graph, count, errors)
	if not errors.is_empty():
		return errors

	var area_sum := 0.0
	for cell_id in count:
		var center := graph.cell_centers[cell_id]
		var polygon: PackedVector2Array = graph.cell_polygons[cell_id]
		if not SpatialGeometry.point_in_world(center, width, height, epsilon):
			errors.append("cell %d center is outside the world rectangle" % cell_id)
		if polygon.size() < 3:
			errors.append("cell %d polygon has fewer than three vertices" % cell_id)
		elif not SpatialGeometry.point_in_polygon(center, polygon, epsilon):
			errors.append("cell %d center is outside its polygon" % cell_id)
		var area: float = graph.cell_areas[cell_id]
		if area <= epsilon:
			errors.append("cell %d area is not positive" % cell_id)
		area_sum += area
		var expected_border := SpatialGeometry.polygon_touches_border(
			polygon, width, height, epsilon
		)
		if bool(graph.cell_is_border[cell_id]) != expected_border:
			errors.append("cell %d has an incorrect border flag" % cell_id)
		_validate_neighbors(graph, cell_id, count, errors)
		for vertex_id in graph.cell_vertex_ids[cell_id]:
			if vertex_id < 0 or vertex_id >= graph.vertex_positions.size():
				errors.append("cell %d contains invalid vertex id %d" % [cell_id, vertex_id])

	for vertex_id in graph.vertex_positions.size():
		if not SpatialGeometry.point_in_world(
			graph.vertex_positions[vertex_id], width, height, epsilon
		):
			errors.append("vertex %d is outside the world rectangle" % vertex_id)

	_validate_connectivity(graph, errors)
	var expected_area := width * height
	var area_tolerance := maxf(expected_area * 0.00001, epsilon * count * 2.0)
	if absf(area_sum - expected_area) > area_tolerance:
		errors.append(
			"cell area sum %.9f does not cover world area %.9f (tolerance %.9f)"
			% [area_sum, expected_area, area_tolerance]
		)
	return errors


static func _validate_array_sizes(
		graph: SpatialGraph, count: int, errors: PackedStringArray
) -> void:
	var named_sizes := {
		"cell_polygons": graph.cell_polygons.size(),
		"cell_neighbors": graph.cell_neighbors.size(),
		"cell_neighbor_distances": graph.cell_neighbor_distances.size(),
		"cell_vertex_ids": graph.cell_vertex_ids.size(),
		"cell_areas": graph.cell_areas.size(),
		"cell_is_border": graph.cell_is_border.size(),
	}
	for array_name in named_sizes:
		if named_sizes[array_name] != count:
			errors.append("%s size does not match cell count" % array_name)
	if graph.vertex_cells.size() != graph.vertex_positions.size():
		errors.append("vertex_cells size does not match vertex_positions size")


static func _validate_neighbors(
		graph: SpatialGraph, cell_id: int, count: int, errors: PackedStringArray
) -> void:
	var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
	var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
	if neighbors.size() != distances.size():
		errors.append("cell %d neighbor and distance counts differ" % cell_id)
		return
	var seen := {}
	for index in neighbors.size():
		var neighbor_id := neighbors[index]
		if neighbor_id < 0 or neighbor_id >= count:
			errors.append("cell %d contains invalid neighbor %d" % [cell_id, neighbor_id])
			continue
		if neighbor_id == cell_id:
			errors.append("cell %d contains itself as a neighbor" % cell_id)
		if seen.has(neighbor_id):
			errors.append("cell %d contains duplicate neighbor %d" % [cell_id, neighbor_id])
		seen[neighbor_id] = true
		if not graph.cell_neighbors[neighbor_id].has(cell_id):
			errors.append("neighbor relation %d -> %d is not symmetric" % [cell_id, neighbor_id])
		if distances[index] <= 0.0:
			errors.append("neighbor distance %d -> %d is not positive" % [cell_id, neighbor_id])
		var expected := graph.cell_centers[cell_id].distance_to(graph.cell_centers[neighbor_id])
		if not is_equal_approx(distances[index], expected):
			errors.append("neighbor distance %d -> %d is incorrect" % [cell_id, neighbor_id])


static func _validate_connectivity(graph: SpatialGraph, errors: PackedStringArray) -> void:
	var visited := PackedByteArray()
	visited.resize(graph.cell_count())
	var queue := PackedInt32Array([0])
	visited[0] = 1
	var head := 0
	while head < queue.size():
		var cell_id := queue[head]
		head += 1
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if not visited[neighbor_id]:
				visited[neighbor_id] = 1
				queue.append(neighbor_id)
	if queue.size() != graph.cell_count():
		errors.append(
			"cell graph is disconnected: visited %d of %d cells"
			% [queue.size(), graph.cell_count()]
		)
