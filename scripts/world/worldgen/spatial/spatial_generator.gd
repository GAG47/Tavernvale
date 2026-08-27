class_name SpatialGenerator
extends RefCounted


static func generate(config: SpatialConfig) -> SpatialGraph:
	if config == null:
		push_error("SpatialGenerator: config is null")
		return null
	var config_errors := config.validate()
	if not config_errors.is_empty():
		push_error("SpatialGenerator: invalid config: " + "; ".join(config_errors))
		return null

	var graph := SpatialGraph.new()
	graph.config = config.duplicate_config()
	var dimensions := _calculate_grid_dimensions(config)
	graph.columns = dimensions.x
	graph.rows = dimensions.y
	graph.spacing = _calculate_spacing(config)
	graph.cell_centers = _create_centers(graph.config, graph.columns, graph.rows)
	graph.boundary_seed_positions = _create_boundary_seeds(graph.config, graph.spacing)

	var all_points := graph.cell_centers.duplicate()
	all_points.append_array(graph.boundary_seed_positions)
	var delaunay := DelaunayGraph.build(all_points, graph.cell_count())
	var topology_errors: PackedStringArray = delaunay.errors
	if delaunay.triangles.is_empty():
		topology_errors.append("Delaunay triangulation produced no triangles")
	if not topology_errors.is_empty():
		push_error("SpatialGenerator: Delaunay topology failed:\n" + "\n".join(topology_errors))
		return null
	graph.delaunay_triangles = delaunay.triangles

	topology_errors = _build_triangle_vertices(graph, all_points)
	if topology_errors.is_empty():
		topology_errors = _separate_vector2_projection_collisions(
			graph, delaunay.edge_triangles
		)
	if topology_errors.is_empty():
		topology_errors = _build_real_cells(
			graph, delaunay.point_triangles, delaunay.edge_triangles
		)
	if topology_errors.is_empty():
		topology_errors = _build_dual_edges_and_neighbors(graph, delaunay.edge_triangles)
	if not topology_errors.is_empty():
		push_error("SpatialGenerator: shared Voronoi topology failed:\n" + "\n".join(topology_errors))
		return null
	_build_neighbor_distances(graph)

	var graph_errors := SpatialValidator.validate(graph)
	if not graph_errors.is_empty():
		push_error("SpatialGenerator: generated invalid graph:\n" + "\n".join(graph_errors))
		return null
	return graph


static func _calculate_grid_dimensions(config: SpatialConfig) -> Vector2i:
	var aspect := config.world_width / config.world_height
	var columns := maxi(1, roundi(sqrt(float(config.target_cell_count) * aspect)))
	var rows := maxi(1, roundi(float(config.target_cell_count) / columns))
	return Vector2i(columns, rows)


static func _calculate_spacing(config: SpatialConfig) -> float:
	return roundf(sqrt(
		config.world_width * config.world_height / float(config.target_cell_count)
	) * 100.0) / 100.0


static func _create_centers(config: SpatialConfig, columns: int, rows: int) -> PackedVector2Array:
	var centers := PackedVector2Array()
	centers.resize(columns * rows)
	var spacing_x := config.world_width / columns
	var spacing_y := config.world_height / rows
	var maximum_x := spacing_x * 0.5 * config.jitter
	var maximum_y := spacing_y * 0.5 * config.jitter
	var rng := DeterministicRng.new(DeterministicRng.spatial_seed(config.seed))
	for row in rows:
		for column in columns:
			var center := Vector2(
				(column + 0.5) * spacing_x + rng.range_float(-maximum_x, maximum_x),
				(row + 0.5) * spacing_y + rng.range_float(-maximum_y, maximum_y)
			)
			center.x = clampf(center.x, 0.0, config.world_width)
			center.y = clampf(center.y, 0.0, config.world_height)
			centers[row * columns + column] = center
	return centers


static func _create_boundary_seeds(
		config: SpatialConfig, spacing: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var offset := roundf(-spacing)
	var boundary_spacing := spacing * 2.0
	var extended_width := config.world_width - offset * 2.0
	var extended_height := config.world_height - offset * 2.0
	var number_x := ceili(extended_width / boundary_spacing) - 1
	var number_y := ceili(extended_height / boundary_spacing) - 1

	var index := 0.5
	while index < number_x:
		var x := ceilf(extended_width * index / number_x + offset)
		points.append(Vector2(x, offset))
		points.append(Vector2(x, extended_height + offset))
		index += 1.0
	index = 0.5
	while index < number_y:
		var y := ceilf(extended_height * index / number_y + offset)
		points.append(Vector2(offset, y))
		points.append(Vector2(extended_width + offset, y))
		index += 1.0
	return points


static func _build_triangle_vertices(
		graph: SpatialGraph, all_points: PackedVector2Array
) -> PackedStringArray:
	var errors := PackedStringArray()
	var triangle_count := graph.delaunay_triangles.size() / 3
	graph.vertex_positions.resize(triangle_count)
	graph.vertex_position_x64.resize(triangle_count)
	graph.vertex_position_y64.resize(triangle_count)
	graph.vertex_cells.resize(triangle_count)
	var reliable_denominator := pow(
		maxf(graph.config.world_width, graph.config.world_height), 2.0
	) * 0.000000000001

	for triangle_id in triangle_count:
		var triangle_start := triangle_id * 3
		var point_ids := PackedInt32Array([
			graph.delaunay_triangles[triangle_start],
			graph.delaunay_triangles[triangle_start + 1],
			graph.delaunay_triangles[triangle_start + 2],
		])
		var first := all_points[point_ids[0]]
		var second := all_points[point_ids[1]]
		var third := all_points[point_ids[2]]
		var denominator := 2.0 * (
			first.x * (second.y - third.y)
			+ second.x * (third.y - first.y)
			+ third.x * (first.y - second.y)
		)
		if absf(denominator) <= reliable_denominator:
			errors.append(
				"triangle %d is degenerate: point IDs %s at %s, %s, %s; denominator=%.12f"
				% [triangle_id, point_ids, first, second, third, denominator]
			)
			continue

		var first_squared := first.length_squared()
		var second_squared := second.length_squared()
		var third_squared := third.length_squared()
		var circumcenter_x := (
				first_squared * (second.y - third.y)
				+ second_squared * (third.y - first.y)
				+ third_squared * (first.y - second.y)
			) / denominator
		var circumcenter_y := (
				first_squared * (third.x - second.x)
				+ second_squared * (first.x - third.x)
				+ third_squared * (second.x - first.x)
			) / denominator
		if not is_finite(circumcenter_x) or not is_finite(circumcenter_y):
			errors.append(
				"triangle %d circumcenter is not finite: point IDs %s at %s, %s, %s"
				% [triangle_id, point_ids, first, second, third]
			)
			continue
		graph.vertex_position_x64[triangle_id] = circumcenter_x
		graph.vertex_position_y64[triangle_id] = circumcenter_y
		var circumcenter := Vector2(circumcenter_x, circumcenter_y)
		graph.vertex_positions[triangle_id] = circumcenter
		var real_cells := PackedInt32Array()
		for point_id in point_ids:
			if point_id < graph.cell_count():
				real_cells.append(point_id)
		graph.vertex_cells[triangle_id] = real_cells
	return errors


static func _separate_vector2_projection_collisions(
		graph: SpatialGraph, edge_triangles: Dictionary
) -> PackedStringArray:
	# GDScript floats keep the standard circumcenter at float64 precision, while
	# this engine build stores Vector2 components as float32. Two distinct centers
	# can therefore project to the same Vector2. Resolve only those topology-known
	# dual edges by one small, deterministic representable step; IDs never depend
	# on this projection and the unmodified circumcenters remain in the x64/y64 arrays.
	var errors := PackedStringArray()
	var edge_epsilon := SpatialGeometry.edge_epsilon_for_size(
		graph.config.world_width, graph.config.world_height
	)
	var projection_step := maxf(
		maxf(graph.config.world_width, graph.config.world_height) * 0.0000001,
		edge_epsilon * 2.0
	)
	var seed_edges: Array = edge_triangles.keys()
	seed_edges.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		return first.x < second.x or (first.x == second.x and first.y < second.y)
	)
	for pass_index in 3:
		var changed := false
		for seed_edge: Vector2i in seed_edges:
			if seed_edge.x >= graph.cell_count() and seed_edge.y >= graph.cell_count():
				continue
			var adjacent: PackedInt32Array = edge_triangles[seed_edge]
			if adjacent.size() != 2:
				continue
			var first_triangle := adjacent[0]
			var second_triangle := adjacent[1]
			if graph.vertex_positions[first_triangle].distance_to(
				graph.vertex_positions[second_triangle]
			) > edge_epsilon:
				continue
			var delta_x := (
				graph.vertex_position_x64[second_triangle]
				- graph.vertex_position_x64[first_triangle]
			)
			var delta_y := (
				graph.vertex_position_y64[second_triangle]
				- graph.vertex_position_y64[first_triangle]
			)
			if delta_x == 0.0 and delta_y == 0.0:
				errors.append(
					"Delaunay edge %s has mathematically coincident circumcenters %d and %d"
					% [seed_edge, first_triangle, second_triangle]
				)
				continue
			var first_position := graph.vertex_positions[first_triangle]
			var second_position := graph.vertex_positions[second_triangle]
			if absf(delta_x) >= absf(delta_y):
				var direction_x := 1.0 if delta_x > 0.0 else -1.0
				first_position.x -= direction_x * projection_step
				second_position.x += direction_x * projection_step
			else:
				var direction_y := 1.0 if delta_y > 0.0 else -1.0
				first_position.y -= direction_y * projection_step
				second_position.y += direction_y * projection_step
			graph.vertex_positions[first_triangle] = first_position
			graph.vertex_positions[second_triangle] = second_position
			changed = true
		if not changed:
			break

	for seed_edge: Vector2i in seed_edges:
		if seed_edge.x >= graph.cell_count() and seed_edge.y >= graph.cell_count():
			continue
		var adjacent: PackedInt32Array = edge_triangles[seed_edge]
		if adjacent.size() != 2:
			continue
		var length := graph.vertex_positions[adjacent[0]].distance_to(
			graph.vertex_positions[adjacent[1]]
		)
		if length <= edge_epsilon:
			errors.append(
				"Delaunay edge %s remains degenerate after Vector2 projection: %.12f"
				% [seed_edge, length]
			)
	return errors


static func _build_real_cells(
		graph: SpatialGraph, point_triangles: Array, edge_triangles: Dictionary
) -> PackedStringArray:
	var errors := PackedStringArray()
	graph.cell_vertex_ids.resize(graph.cell_count())
	graph.cell_polygons.resize(graph.cell_count())
	graph.cell_areas.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		var vertex_ids := _order_triangles_around_seed(
			cell_id, point_triangles[cell_id], graph.delaunay_triangles, edge_triangles, errors
		)
		var polygon := PackedVector2Array()
		polygon.resize(vertex_ids.size())
		for vertex_index in vertex_ids.size():
			polygon[vertex_index] = graph.vertex_positions[vertex_ids[vertex_index]]
		graph.cell_vertex_ids[cell_id] = vertex_ids
		graph.cell_polygons[cell_id] = polygon
		graph.cell_areas[cell_id] = SpatialGeometry.polygon_area(polygon)
	return errors


static func _order_triangles_around_seed(
		seed_id: int,
		incident_triangles: PackedInt32Array,
		triangles: PackedInt32Array,
		edge_triangles: Dictionary,
		errors: PackedStringArray
) -> PackedInt32Array:
	var initial_error_count := errors.size()
	var triangle_neighbors := {}
	for triangle_id in incident_triangles:
		var start := triangle_id * 3
		var other_points := PackedInt32Array()
		for offset in 3:
			var point_id := triangles[start + offset]
			if point_id != seed_id:
				other_points.append(point_id)
		if other_points.size() != 2:
			errors.append(
				"real seed %d has malformed incident triangle %d" % [seed_id, triangle_id]
			)
			continue
		var neighbors := PackedInt32Array()
		for other_point_id in other_points:
			var seed_edge := SpatialGeometry.canonical_edge(seed_id, other_point_id)
			if not edge_triangles.has(seed_edge):
				errors.append(
					"real seed %d triangle %d is missing Delaunay edge %s"
					% [seed_id, triangle_id, seed_edge]
				)
				continue
			var adjacent: PackedInt32Array = edge_triangles[seed_edge]
			if adjacent.size() != 2:
				errors.append(
					"real seed %d edge %s has %d adjacent triangles; expected 2"
					% [seed_id, seed_edge, adjacent.size()]
				)
				continue
			var neighbor_triangle := adjacent[1] if adjacent[0] == triangle_id else adjacent[0]
			if neighbor_triangle == triangle_id or not incident_triangles.has(neighbor_triangle):
				errors.append(
					"real seed %d edge %s has invalid triangle adjacency"
					% [seed_id, seed_edge]
				)
				continue
			neighbors.append(neighbor_triangle)
		triangle_neighbors[triangle_id] = neighbors

	if incident_triangles.size() < 3 or errors.size() != initial_error_count:
		if incident_triangles.size() < 3:
			errors.append(
				"real seed %d has %d incident triangles; expected at least 3"
				% [seed_id, incident_triangles.size()]
			)
		return PackedInt32Array()
	var first_triangle := incident_triangles[0]
	for triangle_id in incident_triangles:
		first_triangle = mini(first_triangle, triangle_id)
		if not triangle_neighbors.has(triangle_id) or triangle_neighbors[triangle_id].size() != 2:
			errors.append(
				"real seed %d triangle %d does not have two around-seed neighbors"
				% [seed_id, triangle_id]
			)
	if errors.size() != initial_error_count:
		return PackedInt32Array()

	var first_neighbors: PackedInt32Array = triangle_neighbors[first_triangle]
	var previous := -1
	var current := first_triangle
	var next := mini(first_neighbors[0], first_neighbors[1])
	var ordered := PackedInt32Array([current])
	var visited := {current: true}
	while next != first_triangle:
		if visited.has(next) or not triangle_neighbors.has(next):
			errors.append("real seed %d incident triangles do not form one cycle" % seed_id)
			return PackedInt32Array()
		visited[next] = true
		ordered.append(next)
		previous = current
		current = next
		var neighbors: PackedInt32Array = triangle_neighbors[current]
		next = neighbors[1] if neighbors[0] == previous else neighbors[0]
	if ordered.size() != incident_triangles.size():
		errors.append(
			"real seed %d triangle cycle visits %d of %d incident triangles"
			% [seed_id, ordered.size(), incident_triangles.size()]
		)
		return PackedInt32Array()
	return ordered


static func _build_dual_edges_and_neighbors(
		graph: SpatialGraph, edge_triangles: Dictionary
) -> PackedStringArray:
	var errors := PackedStringArray()
	graph.cell_is_border.resize(graph.cell_count())
	var neighbor_sets: Array = []
	neighbor_sets.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		neighbor_sets[cell_id] = {}

	var delaunay_edges: Array = edge_triangles.keys()
	delaunay_edges.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		return first.x < second.x or (first.x == second.x and first.y < second.y)
	)
	for seed_edge: Vector2i in delaunay_edges:
		var first_is_real := seed_edge.x < graph.cell_count()
		var second_is_real := seed_edge.y < graph.cell_count()
		if not first_is_real and not second_is_real:
			continue
		var adjacent_triangles: PackedInt32Array = edge_triangles[seed_edge]
		if adjacent_triangles.size() != 2:
			errors.append(
				"Delaunay edge %s touching a real Cell has %d adjacent triangles; expected 2"
				% [seed_edge, adjacent_triangles.size()]
			)
			continue
		var vertex_edge := SpatialGeometry.canonical_edge(
			adjacent_triangles[0], adjacent_triangles[1]
		)
		if vertex_edge.x == vertex_edge.y:
			errors.append("Delaunay edge %s maps to one Voronoi vertex" % seed_edge)
			continue

		graph.edge_seed_ids.append(seed_edge)
		graph.edge_vertex_ids.append(vertex_edge)
		if first_is_real and second_is_real:
			graph.edge_cells.append(PackedInt32Array([seed_edge.x, seed_edge.y]))
			neighbor_sets[seed_edge.x][seed_edge.y] = true
			neighbor_sets[seed_edge.y][seed_edge.x] = true
		else:
			var real_cell := seed_edge.x if first_is_real else seed_edge.y
			graph.edge_cells.append(PackedInt32Array([real_cell]))
			graph.cell_is_border[real_cell] = 1

	graph.cell_neighbors.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		var neighbor_ids: Array = neighbor_sets[cell_id].keys()
		neighbor_ids.sort()
		graph.cell_neighbors[cell_id] = PackedInt32Array(neighbor_ids)
	return errors


static func _build_neighbor_distances(graph: SpatialGraph) -> void:
	graph.cell_neighbor_distances.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		var distances := PackedFloat64Array()
		distances.resize(graph.cell_neighbors[cell_id].size())
		for neighbor_index in graph.cell_neighbors[cell_id].size():
			var neighbor_id: int = graph.cell_neighbors[cell_id][neighbor_index]
			distances[neighbor_index] = graph.cell_centers[cell_id].distance_to(
				graph.cell_centers[neighbor_id]
			)
		graph.cell_neighbor_distances[cell_id] = distances
