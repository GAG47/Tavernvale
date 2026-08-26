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
	var edge_epsilon := SpatialGeometry.edge_epsilon_for_size(width, height)
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
		if graph.cell_vertex_ids[cell_id].size() != polygon.size():
			errors.append("cell %d polygon and vertex id counts differ" % cell_id)
		var area: float = graph.cell_areas[cell_id]
		if area <= epsilon:
			errors.append("cell %d area is not positive" % cell_id)
		area_sum += area
		var expected_border := SpatialGeometry.polygon_touches_border(
			polygon, width, height, epsilon
		)
		if bool(graph.cell_is_border[cell_id]) != expected_border:
			errors.append("cell %d has an incorrect border flag" % cell_id)
		for vertex_id in graph.cell_vertex_ids[cell_id]:
			if vertex_id < 0 or vertex_id >= graph.vertex_positions.size():
				errors.append("cell %d contains invalid vertex id %d" % [cell_id, vertex_id])

	for vertex_id in graph.vertex_positions.size():
		if not SpatialGeometry.point_in_world(
			graph.vertex_positions[vertex_id], width, height, epsilon
		):
			errors.append("vertex %d is outside the world rectangle" % vertex_id)

	_validate_vertex_cell_reciprocity(graph, errors)
	var shared_cell_pairs := _validate_edge_registry(graph, edge_epsilon, errors)
	for cell_id in count:
		_validate_neighbors(graph, cell_id, count, shared_cell_pairs, errors)
	_validate_shared_edges_create_neighbors(graph, shared_cell_pairs, errors)
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
	if graph.edge_cells.size() != graph.edge_vertex_ids.size():
		errors.append("edge_cells size does not match edge_vertex_ids size")


static func _validate_vertex_cell_reciprocity(
		graph: SpatialGraph, errors: PackedStringArray
) -> void:
	for cell_id in graph.cell_count():
		for vertex_id in graph.cell_vertex_ids[cell_id]:
			if vertex_id < 0 or vertex_id >= graph.vertex_cells.size():
				continue
			if not graph.vertex_cells[vertex_id].has(cell_id):
				errors.append(
					"cell %d references vertex %d, but vertex does not reference the cell"
					% [cell_id, vertex_id]
				)

	for vertex_id in graph.vertex_cells.size():
		var seen_cells := {}
		for cell_id in graph.vertex_cells[vertex_id]:
			if cell_id < 0 or cell_id >= graph.cell_count():
				errors.append("vertex %d contains invalid cell id %d" % [vertex_id, cell_id])
				continue
			if seen_cells.has(cell_id):
				errors.append("vertex %d contains duplicate cell id %d" % [vertex_id, cell_id])
			seen_cells[cell_id] = true
			if not graph.cell_vertex_ids[cell_id].has(vertex_id):
				errors.append(
					"vertex %d references cell %d, but cell does not reference the vertex"
					% [vertex_id, cell_id]
				)


static func _validate_edge_registry(
		graph: SpatialGraph, edge_epsilon: float, errors: PackedStringArray
) -> Dictionary:
	var expected_edge_cells := {}
	for cell_id in graph.cell_count():
		var vertex_ids: PackedInt32Array = graph.cell_vertex_ids[cell_id]
		var cell_edges_seen := {}
		for vertex_index in vertex_ids.size():
			var first_vertex_id := vertex_ids[vertex_index]
			var second_vertex_id := vertex_ids[(vertex_index + 1) % vertex_ids.size()]
			if (
				first_vertex_id < 0
				or first_vertex_id >= graph.vertex_positions.size()
				or second_vertex_id < 0
				or second_vertex_id >= graph.vertex_positions.size()
			):
				continue
			var edge := SpatialGeometry.canonical_edge(first_vertex_id, second_vertex_id)
			if cell_edges_seen.has(edge):
				errors.append("cell %d uses edge %s more than once" % [cell_id, edge])
			else:
				cell_edges_seen[edge] = true
			if not expected_edge_cells.has(edge):
				expected_edge_cells[edge] = PackedInt32Array()
			if not expected_edge_cells[edge].has(cell_id):
				expected_edge_cells[edge].append(cell_id)

	var registered_edges := {}
	var shared_cell_pairs := {}
	for edge_id in graph.edge_count():
		var edge: Vector2i = graph.edge_vertex_ids[edge_id]
		var cells: PackedInt32Array = graph.edge_cells[edge_id]
		if edge.x > edge.y:
			errors.append("edge %d is not canonical: %s" % [edge_id, edge])
		if registered_edges.has(edge):
			errors.append("edge registry contains duplicate edge %s" % edge)
		registered_edges[edge] = edge_id
		if (
			edge.x < 0
			or edge.y < 0
			or edge.x >= graph.vertex_positions.size()
			or edge.y >= graph.vertex_positions.size()
		):
			errors.append("edge %d contains an invalid vertex id" % edge_id)
			continue
		var edge_length := graph.vertex_positions[edge.x].distance_to(
			graph.vertex_positions[edge.y]
		)
		if edge_length <= edge_epsilon:
			errors.append(
				"edge %d (%d-%d) is degenerate: length %.9f <= %.9f"
				% [edge_id, edge.x, edge.y, edge_length, edge_epsilon]
			)
		if cells.size() < 1 or cells.size() > 2:
			errors.append("edge %d is used by %d cells; expected 1 or 2" % [edge_id, cells.size()])
		elif cells.size() == 1 and not SpatialGeometry.edge_lies_on_world_border(
			graph.vertex_positions[edge.x],
			graph.vertex_positions[edge.y],
			graph.config.world_width,
			graph.config.world_height,
			edge_epsilon
		):
			errors.append(
				"edge %d (%d-%d, %s -> %s) is used only by cell %d but is not on the world border"
				% [
					edge_id,
					edge.x,
					edge.y,
					graph.vertex_positions[edge.x],
					graph.vertex_positions[edge.y],
					cells[0],
				]
			)
		var seen_cells := {}
		for cell_id in cells:
			if cell_id < 0 or cell_id >= graph.cell_count():
				errors.append("edge %d contains invalid cell id %d" % [edge_id, cell_id])
			elif seen_cells.has(cell_id):
				errors.append("edge %d contains duplicate cell id %d" % [edge_id, cell_id])
			else:
				seen_cells[cell_id] = true
		if not expected_edge_cells.has(edge):
			errors.append("edge registry contains edge %s not used by a cell polygon" % edge)
		elif not _same_int_set(cells, expected_edge_cells[edge]):
			errors.append("edge %s cell usage does not match cell polygons" % edge)
		if cells.size() == 2 and edge_length > edge_epsilon:
			shared_cell_pairs[SpatialGeometry.canonical_edge(cells[0], cells[1])] = edge_id

	for edge in expected_edge_cells:
		if not registered_edges.has(edge):
			errors.append("cell polygons use edge %s missing from edge registry" % edge)
		if expected_edge_cells[edge].size() > 2:
			errors.append(
				"cell polygon edge %s is used by %d cells"
				% [edge, expected_edge_cells[edge].size()]
			)
	return shared_cell_pairs


static func _validate_neighbors(
		graph: SpatialGraph,
		cell_id: int,
		count: int,
		shared_cell_pairs: Dictionary,
		errors: PackedStringArray
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
		var cell_pair := SpatialGeometry.canonical_edge(cell_id, neighbor_id)
		if not shared_cell_pairs.has(cell_pair):
			errors.append("neighbor relation %d <-> %d has no valid shared edge" % [cell_id, neighbor_id])
		if distances[index] <= 0.0:
			errors.append("neighbor distance %d -> %d is not positive" % [cell_id, neighbor_id])
		var expected := graph.cell_centers[cell_id].distance_to(graph.cell_centers[neighbor_id])
		if not is_equal_approx(distances[index], expected):
			errors.append("neighbor distance %d -> %d is incorrect" % [cell_id, neighbor_id])


static func _validate_shared_edges_create_neighbors(
		graph: SpatialGraph, shared_cell_pairs: Dictionary, errors: PackedStringArray
) -> void:
	for cell_pair in shared_cell_pairs:
		if (
			not graph.cell_neighbors[cell_pair.x].has(cell_pair.y)
			or not graph.cell_neighbors[cell_pair.y].has(cell_pair.x)
		):
			errors.append(
				"valid shared edge does not create neighbor relation %d <-> %d"
				% [cell_pair.x, cell_pair.y]
			)


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


static func _same_int_set(first: PackedInt32Array, second: PackedInt32Array) -> bool:
	if first.size() != second.size():
		return false
	for value in first:
		if not second.has(value):
			return false
	return true
