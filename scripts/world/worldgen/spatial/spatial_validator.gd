class_name SpatialValidator
extends RefCounted

## Validates the shared Delaunay/Voronoi topology. World bounds constrain real
## seeds only; Voronoi vertices and polygons may extend outside the logical map.


static func validate(graph: SpatialGraph) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null:
		errors.append("graph is null")
		return errors
	if graph.config == null:
		errors.append("graph config is null")
		return errors
	var cell_count := graph.cell_count()
	if cell_count <= 0:
		errors.append("real cell count must be greater than zero")
		return errors
	_validate_array_sizes(graph, cell_count, errors)
	if not errors.is_empty():
		return errors

	var epsilon := SpatialGeometry.epsilon_for_size(
		graph.config.world_width, graph.config.world_height
	)
	var edge_epsilon := SpatialGeometry.edge_epsilon_for_size(
		graph.config.world_width, graph.config.world_height
	)
	var topology := _reconstruct_delaunay_topology(graph, errors)
	var point_triangles: Array = topology.point_triangles
	var delaunay_edge_triangles: Dictionary = topology.edge_triangles

	_validate_seeds_and_cells(graph, point_triangles, epsilon, errors)
	_validate_triangle_vertices(graph, errors)
	var expected := _validate_dual_edge_registry(
		graph, delaunay_edge_triangles, edge_epsilon, errors
	)
	_validate_neighbors(graph, expected.neighbor_pairs, errors)
	_validate_border_flags(graph, expected.border_cells, errors)
	_validate_connectivity(graph, errors)
	return errors


static func validate_determinism(config: SpatialConfig) -> PackedStringArray:
	var errors := PackedStringArray()
	if config == null:
		errors.append("determinism config is null")
		return errors
	var first := SpatialGenerator.generate(config)
	var second := SpatialGenerator.generate(config)
	if first == null or second == null:
		errors.append("determinism validation could not generate both SpatialGraphs")
	elif not _graphs_equal(first, second):
		errors.append("same Seed + SpatialConfig produced different spatial topology")
	return errors


static func _graphs_equal(first: SpatialGraph, second: SpatialGraph) -> bool:
	return (
		first.config.to_dict() == second.config.to_dict()
		and first.columns == second.columns
		and first.rows == second.rows
		and first.spacing == second.spacing
		and first.cell_centers == second.cell_centers
		and first.boundary_seed_positions == second.boundary_seed_positions
		and first.cell_polygons == second.cell_polygons
		and first.cell_neighbors == second.cell_neighbors
		and first.cell_neighbor_distances == second.cell_neighbor_distances
		and first.cell_vertex_ids == second.cell_vertex_ids
		and first.cell_areas == second.cell_areas
		and first.cell_is_border == second.cell_is_border
		and first.vertex_positions == second.vertex_positions
		and first.vertex_position_x64 == second.vertex_position_x64
		and first.vertex_position_y64 == second.vertex_position_y64
		and first.vertex_cells == second.vertex_cells
		and first.edge_vertex_ids == second.edge_vertex_ids
		and first.edge_cells == second.edge_cells
		and first.edge_seed_ids == second.edge_seed_ids
		and first.delaunay_triangles == second.delaunay_triangles
	)


static func _validate_array_sizes(
		graph: SpatialGraph, cell_count: int, errors: PackedStringArray
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
		if named_sizes[array_name] != cell_count:
			errors.append("%s size does not match real cell count" % array_name)
	if graph.vertex_cells.size() != graph.vertex_positions.size():
		errors.append("vertex_cells size does not match vertex_positions size")
	if graph.vertex_position_x64.size() != graph.vertex_positions.size():
		errors.append("vertex_position_x64 size does not match vertex_positions size")
	if graph.vertex_position_y64.size() != graph.vertex_positions.size():
		errors.append("vertex_position_y64 size does not match vertex_positions size")
	if graph.edge_cells.size() != graph.edge_vertex_ids.size():
		errors.append("edge_cells size does not match edge_vertex_ids size")
	if graph.edge_seed_ids.size() != graph.edge_vertex_ids.size():
		errors.append("edge_seed_ids size does not match edge_vertex_ids size")


static func _reconstruct_delaunay_topology(
		graph: SpatialGraph, errors: PackedStringArray
) -> Dictionary:
	var point_triangles: Array = []
	point_triangles.resize(graph.all_seed_count())
	for point_id in graph.all_seed_count():
		point_triangles[point_id] = PackedInt32Array()
	var edge_triangles := {}
	if graph.delaunay_triangles.size() % 3 != 0:
		errors.append("Delaunay triangle index count is not divisible by three")
		return {"point_triangles": point_triangles, "edge_triangles": edge_triangles}
	var triangle_count := graph.delaunay_triangles.size() / 3
	if graph.vertex_positions.size() != triangle_count:
		errors.append(
			"Voronoi vertex count %d does not equal Delaunay triangle count %d"
			% [graph.vertex_positions.size(), triangle_count]
		)
	for triangle_id in triangle_count:
		var start := triangle_id * 3
		var points := PackedInt32Array([
			graph.delaunay_triangles[start],
			graph.delaunay_triangles[start + 1],
			graph.delaunay_triangles[start + 2],
		])
		var valid := true
		var seen := {}
		for point_id in points:
			if point_id < 0 or point_id >= graph.all_seed_count():
				errors.append(
					"Delaunay triangle %d contains invalid seed id %d" % [triangle_id, point_id]
				)
				valid = false
			elif seen.has(point_id):
				errors.append(
					"Delaunay triangle %d repeats seed id %d" % [triangle_id, point_id]
				)
				valid = false
			seen[point_id] = true
		if not valid:
			continue
		for point_id in points:
			point_triangles[point_id].append(triangle_id)
		_add_edge_triangle(edge_triangles, points[0], points[1], triangle_id)
		_add_edge_triangle(edge_triangles, points[1], points[2], triangle_id)
		_add_edge_triangle(edge_triangles, points[2], points[0], triangle_id)
	return {"point_triangles": point_triangles, "edge_triangles": edge_triangles}


static func _add_edge_triangle(
		edge_triangles: Dictionary, first: int, second: int, triangle_id: int
) -> void:
	var edge := SpatialGeometry.canonical_edge(first, second)
	if not edge_triangles.has(edge):
		edge_triangles[edge] = PackedInt32Array()
	edge_triangles[edge].append(triangle_id)


static func _validate_seeds_and_cells(
		graph: SpatialGraph,
		point_triangles: Array,
		epsilon: float,
		errors: PackedStringArray
) -> void:
	for cell_id in graph.cell_count():
		var center := graph.cell_centers[cell_id]
		if not _is_finite_vector(center):
			errors.append("real seed %d is not finite" % cell_id)
		elif not SpatialGeometry.point_in_world(
			center, graph.config.world_width, graph.config.world_height, epsilon
		):
			errors.append("real seed %d is outside the logical world" % cell_id)

		var vertex_ids: PackedInt32Array = graph.cell_vertex_ids[cell_id]
		var polygon: PackedVector2Array = graph.cell_polygons[cell_id]
		if vertex_ids.size() < 3:
			errors.append("cell %d has fewer than three Voronoi vertices" % cell_id)
		if vertex_ids.size() != polygon.size():
			errors.append("cell %d polygon and vertex id counts differ" % cell_id)
		var seen_vertices := {}
		for vertex_index in vertex_ids.size():
			var vertex_id := vertex_ids[vertex_index]
			if vertex_id < 0 or vertex_id >= graph.vertex_positions.size():
				errors.append("cell %d contains invalid vertex id %d" % [cell_id, vertex_id])
				continue
			if seen_vertices.has(vertex_id):
				errors.append("cell %d repeats vertex id %d" % [cell_id, vertex_id])
			seen_vertices[vertex_id] = true
			if vertex_index < polygon.size() and polygon[vertex_index] != graph.vertex_positions[vertex_id]:
				errors.append(
					"cell %d polygon point %d does not match Voronoi vertex %d"
					% [cell_id, vertex_index, vertex_id]
				)
		if cell_id < point_triangles.size() and not _same_int_set(
			vertex_ids, point_triangles[cell_id]
		):
			errors.append(
				"cell %d vertices are not exactly its incident Delaunay triangle IDs" % cell_id
			)
		var area := SpatialGeometry.polygon_area(polygon)
		if not is_finite(area) or area <= epsilon:
			errors.append("cell %d polygon area is not positive" % cell_id)
		if not is_equal_approx(graph.cell_areas[cell_id], area):
			errors.append("cell %d stored area does not match its polygon" % cell_id)
		if polygon.size() >= 3 and not SpatialGeometry.point_in_polygon(center, polygon, epsilon):
			errors.append("cell %d polygon does not contain its real seed" % cell_id)

	for boundary_index in graph.boundary_seed_count():
		var boundary_seed := graph.boundary_seed_positions[boundary_index]
		if not _is_finite_vector(boundary_seed):
			errors.append("boundary seed %d is not finite" % boundary_index)


static func _validate_triangle_vertices(
		graph: SpatialGraph, errors: PackedStringArray
) -> void:
	for vertex_id in graph.vertex_positions.size():
		if not _is_finite_vector(graph.vertex_positions[vertex_id]):
			errors.append("Voronoi vertex %d is not finite" % vertex_id)
		if (
			vertex_id >= graph.vertex_position_x64.size()
			or vertex_id >= graph.vertex_position_y64.size()
			or not is_finite(graph.vertex_position_x64[vertex_id])
			or not is_finite(graph.vertex_position_y64[vertex_id])
		):
			errors.append("Voronoi vertex %d float64 circumcenter is not finite" % vertex_id)
		if vertex_id >= graph.vertex_cells.size():
			continue
		var start := vertex_id * 3
		if start + 2 >= graph.delaunay_triangles.size():
			continue
		var expected_cells := PackedInt32Array()
		for offset in 3:
			var point_id := graph.delaunay_triangles[start + offset]
			if point_id >= 0 and point_id < graph.cell_count():
				expected_cells.append(point_id)
		var cells: PackedInt32Array = graph.vertex_cells[vertex_id]
		if not _same_int_set(cells, expected_cells):
			errors.append(
				"Voronoi vertex %d cells do not match its Delaunay triangle's real seeds"
				% vertex_id
			)
		var seen_cells := {}
		for cell_id in cells:
			if cell_id < 0 or cell_id >= graph.cell_count():
				errors.append(
					"Voronoi vertex %d contains boundary/invalid cell id %d"
					% [vertex_id, cell_id]
				)
			elif seen_cells.has(cell_id):
				errors.append("Voronoi vertex %d repeats cell id %d" % [vertex_id, cell_id])
			elif not graph.cell_vertex_ids[cell_id].has(vertex_id):
				errors.append(
					"Voronoi vertex %d -> cell %d is not reciprocal" % [vertex_id, cell_id]
				)
			seen_cells[cell_id] = true


static func _validate_dual_edge_registry(
		graph: SpatialGraph,
		delaunay_edge_triangles: Dictionary,
		edge_epsilon: float,
		errors: PackedStringArray
) -> Dictionary:
	var polygon_edge_cells := _collect_polygon_edge_cells(graph, errors)
	var registered_seed_edges := {}
	var registered_vertex_edges := {}
	var neighbor_pairs := {}
	var border_cells := {}
	for edge_id in graph.edge_count():
		var vertex_edge: Vector2i = graph.edge_vertex_ids[edge_id]
		var seed_edge: Vector2i = graph.edge_seed_ids[edge_id]
		var cells: PackedInt32Array = graph.edge_cells[edge_id]
		if seed_edge.x >= seed_edge.y:
			errors.append("edge %d Delaunay seed pair is not canonical: %s" % [edge_id, seed_edge])
		if registered_seed_edges.has(seed_edge):
			errors.append("duplicate dual for Delaunay edge %s" % seed_edge)
		registered_seed_edges[seed_edge] = edge_id
		if vertex_edge.x >= vertex_edge.y:
			errors.append("edge %d Voronoi vertex pair is degenerate/non-canonical: %s" % [edge_id, vertex_edge])
		if registered_vertex_edges.has(vertex_edge):
			errors.append("duplicate Voronoi edge %s" % vertex_edge)
		registered_vertex_edges[vertex_edge] = edge_id

		if (
			seed_edge.x < 0
			or seed_edge.y < 0
			or seed_edge.x >= graph.all_seed_count()
			or seed_edge.y >= graph.all_seed_count()
		):
			errors.append("edge %d contains an invalid Delaunay seed id" % edge_id)
			continue
		if (
			vertex_edge.x < 0
			or vertex_edge.y < 0
			or vertex_edge.x >= graph.vertex_positions.size()
			or vertex_edge.y >= graph.vertex_positions.size()
		):
			errors.append("edge %d contains an invalid Voronoi vertex id" % edge_id)
			continue
		var length := graph.vertex_positions[vertex_edge.x].distance_to(
			graph.vertex_positions[vertex_edge.y]
		)
		if not is_finite(length) or length <= edge_epsilon:
			errors.append(
				"edge %d (%d-%d) is degenerate: length %.9f <= %.9f"
				% [edge_id, vertex_edge.x, vertex_edge.y, length, edge_epsilon]
			)

		if not delaunay_edge_triangles.has(seed_edge):
			errors.append("edge %d seed pair %s is not a Delaunay edge" % [edge_id, seed_edge])
			continue
		var adjacent: PackedInt32Array = delaunay_edge_triangles[seed_edge]
		if adjacent.size() != 2:
			errors.append(
				"edge %d seed pair %s has %d adjacent triangles; expected 2"
				% [edge_id, seed_edge, adjacent.size()]
			)
		elif not _same_int_set(PackedInt32Array([vertex_edge.x, vertex_edge.y]), adjacent):
			errors.append(
				"edge %d Voronoi vertices are not its adjacent Delaunay triangle IDs" % edge_id
			)

		var first_real := seed_edge.x < graph.cell_count()
		var second_real := seed_edge.y < graph.cell_count()
		var expected_cells := PackedInt32Array()
		if first_real:
			expected_cells.append(seed_edge.x)
		if second_real:
			expected_cells.append(seed_edge.y)
		if expected_cells.is_empty():
			errors.append("boundary-boundary Delaunay edge %s leaked into final edge data" % seed_edge)
		elif not _same_int_set(cells, expected_cells):
			errors.append("edge %d real-cell ownership does not match its Delaunay seed pair" % edge_id)
		if expected_cells.size() == 2:
			neighbor_pairs[SpatialGeometry.canonical_edge(expected_cells[0], expected_cells[1])] = edge_id
		elif expected_cells.size() == 1:
			border_cells[expected_cells[0]] = true

		if not polygon_edge_cells.has(vertex_edge):
			errors.append("edge %d is not used by a real cell polygon" % edge_id)
		elif not _same_int_set(cells, polygon_edge_cells[vertex_edge]):
			errors.append("edge %d cell ownership does not match ordered cell polygons" % edge_id)

	for seed_edge in delaunay_edge_triangles:
		var first_real: bool = seed_edge.x < graph.cell_count()
		var second_real: bool = seed_edge.y < graph.cell_count()
		if not first_real and not second_real:
			continue
		var adjacent: PackedInt32Array = delaunay_edge_triangles[seed_edge]
		if adjacent.size() != 2:
			errors.append(
				"Delaunay edge %s touching a real seed has %d triangles; expected 2"
				% [seed_edge, adjacent.size()]
			)
		if not registered_seed_edges.has(seed_edge):
			errors.append("Delaunay edge %s touching a real seed has no final dual edge" % seed_edge)

	for vertex_edge in polygon_edge_cells:
		if not registered_vertex_edges.has(vertex_edge):
			errors.append("ordered cell polygons use unregistered Voronoi edge %s" % vertex_edge)
	return {"neighbor_pairs": neighbor_pairs, "border_cells": border_cells}


static func _collect_polygon_edge_cells(
		graph: SpatialGraph, errors: PackedStringArray
) -> Dictionary:
	var result := {}
	for cell_id in graph.cell_count():
		var vertex_ids: PackedInt32Array = graph.cell_vertex_ids[cell_id]
		var seen := {}
		for vertex_index in vertex_ids.size():
			var first := vertex_ids[vertex_index]
			var second := vertex_ids[(vertex_index + 1) % vertex_ids.size()]
			if (
				first < 0
				or second < 0
				or first >= graph.vertex_positions.size()
				or second >= graph.vertex_positions.size()
			):
				continue
			var edge := SpatialGeometry.canonical_edge(first, second)
			if first == second or seen.has(edge):
				errors.append("cell %d repeats/degenerates polygon edge %s" % [cell_id, edge])
			seen[edge] = true
			if not result.has(edge):
				result[edge] = PackedInt32Array()
			result[edge].append(cell_id)
	return result


static func _validate_neighbors(
		graph: SpatialGraph, neighbor_pairs: Dictionary, errors: PackedStringArray
) -> void:
	var actual_pairs := {}
	for cell_id in graph.cell_count():
		var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
		var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
		if neighbors.size() != distances.size():
			errors.append("cell %d neighbor and distance counts differ" % cell_id)
		var seen := {}
		for index in neighbors.size():
			var neighbor_id := neighbors[index]
			if neighbor_id < 0 or neighbor_id >= graph.cell_count():
				errors.append("cell %d contains boundary/invalid neighbor %d" % [cell_id, neighbor_id])
				continue
			if neighbor_id == cell_id:
				errors.append("cell %d contains itself as a neighbor" % cell_id)
			if seen.has(neighbor_id):
				errors.append("cell %d contains duplicate neighbor %d" % [cell_id, neighbor_id])
			seen[neighbor_id] = true
			if not graph.cell_neighbors[neighbor_id].has(cell_id):
				errors.append("neighbor relation %d -> %d is not symmetric" % [cell_id, neighbor_id])
			var pair := SpatialGeometry.canonical_edge(cell_id, neighbor_id)
			actual_pairs[pair] = true
			if not neighbor_pairs.has(pair):
				errors.append("neighbor relation %d <-> %d has no real-real dual edge" % [cell_id, neighbor_id])
			if index < distances.size():
				var expected_distance := graph.cell_centers[cell_id].distance_to(
					graph.cell_centers[neighbor_id]
				)
				if distances[index] <= 0.0 or not is_equal_approx(distances[index], expected_distance):
					errors.append("neighbor distance %d -> %d is invalid" % [cell_id, neighbor_id])
	for pair in neighbor_pairs:
		if not actual_pairs.has(pair):
			errors.append("real-real dual edge %s does not create a neighbor relation" % pair)


static func _validate_border_flags(
		graph: SpatialGraph, border_cells: Dictionary, errors: PackedStringArray
) -> void:
	for cell_id in graph.cell_count():
		var expected := border_cells.has(cell_id)
		if bool(graph.cell_is_border[cell_id]) != expected:
			errors.append(
				"cell %d border flag does not match real-boundary Delaunay adjacency" % cell_id
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
			if neighbor_id >= 0 and neighbor_id < graph.cell_count() and not visited[neighbor_id]:
				visited[neighbor_id] = 1
				queue.append(neighbor_id)
	if queue.size() != graph.cell_count():
		errors.append(
			"real cell graph is disconnected: visited %d of %d cells"
			% [queue.size(), graph.cell_count()]
		)


static func _same_int_set(first: PackedInt32Array, second: PackedInt32Array) -> bool:
	if first.size() != second.size():
		return false
	for value in first:
		if not second.has(value):
			return false
	return true


static func _is_finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)
