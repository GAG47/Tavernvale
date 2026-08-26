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
	graph.cell_centers = _create_centers(graph.config, graph.columns, graph.rows)

	var delaunay := DelaunayGraph.build(graph.cell_centers)
	graph.delaunay_triangles = delaunay.triangles
	var candidate_neighbors: Array = delaunay.neighbors
	var epsilon := SpatialGeometry.epsilon_for_size(config.world_width, config.world_height)
	graph.cell_polygons = VoronoiBuilder.build_all(
		graph.cell_centers,
		candidate_neighbors,
		config.world_width,
		config.world_height,
		epsilon
	)
	_build_cell_geometry_metrics(graph, epsilon)
	var vertex_merge_epsilon := SpatialGeometry.vertex_merge_epsilon_for_size(
		config.world_width, config.world_height
	)
	_build_shared_vertices(graph, vertex_merge_epsilon)
	_build_edge_registry_and_final_neighbors(
		graph,
		SpatialGeometry.edge_epsilon_for_size(config.world_width, config.world_height)
	)
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


static func _build_cell_geometry_metrics(graph: SpatialGraph, epsilon: float) -> void:
	var count := graph.cell_count()
	graph.cell_areas.resize(count)
	graph.cell_is_border.resize(count)
	for cell_id in count:
		var polygon: PackedVector2Array = graph.cell_polygons[cell_id]
		graph.cell_areas[cell_id] = SpatialGeometry.polygon_area(polygon)
		graph.cell_is_border[cell_id] = int(SpatialGeometry.polygon_touches_border(
			polygon, graph.config.world_width, graph.config.world_height, epsilon
		))


static func _build_shared_vertices(graph: SpatialGraph, vertex_merge_epsilon: float) -> void:
	var vertex_buckets := {}
	var positions := PackedVector2Array()
	var mutable_vertex_cells: Array = []
	graph.cell_vertex_ids.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		var ids := PackedInt32Array()
		for position in graph.cell_polygons[cell_id]:
			var bucket := Vector2i(
				floori(position.x / vertex_merge_epsilon),
				floori(position.y / vertex_merge_epsilon)
			)
			var vertex_id := _find_matching_vertex(
				position, bucket, vertex_buckets, positions, vertex_merge_epsilon
			)
			if vertex_id < 0:
				vertex_id = positions.size()
				positions.append(position)
				mutable_vertex_cells.append(PackedInt32Array())
				if not vertex_buckets.has(bucket):
					vertex_buckets[bucket] = PackedInt32Array()
				vertex_buckets[bucket].append(vertex_id)
			ids.append(vertex_id)
			if not mutable_vertex_cells[vertex_id].has(cell_id):
				mutable_vertex_cells[vertex_id].append(cell_id)
		graph.cell_vertex_ids[cell_id] = ids
	graph.vertex_positions = positions
	graph.vertex_cells = mutable_vertex_cells


static func _find_matching_vertex(
		position: Vector2,
		bucket: Vector2i,
		vertex_buckets: Dictionary,
		positions: PackedVector2Array,
		vertex_merge_epsilon: float
) -> int:
	var best_vertex_id := -1
	var best_distance_squared := vertex_merge_epsilon * vertex_merge_epsilon
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var nearby_bucket := bucket + Vector2i(offset_x, offset_y)
			if not vertex_buckets.has(nearby_bucket):
				continue
			for vertex_id in vertex_buckets[nearby_bucket]:
				var distance_squared := position.distance_squared_to(positions[vertex_id])
				if (
					distance_squared <= best_distance_squared
					and (best_vertex_id < 0 or distance_squared < best_distance_squared or vertex_id < best_vertex_id)
				):
					best_vertex_id = vertex_id
					best_distance_squared = distance_squared
	return best_vertex_id


static func _build_edge_registry_and_final_neighbors(
		graph: SpatialGraph, edge_epsilon: float
) -> void:
	var edge_lookup := {}
	var edge_vertex_ids: Array = []
	var mutable_edge_cells: Array = []
	for cell_id in graph.cell_count():
		var vertex_ids: PackedInt32Array = graph.cell_vertex_ids[cell_id]
		for vertex_index in vertex_ids.size():
			var next_index := (vertex_index + 1) % vertex_ids.size()
			var edge := SpatialGeometry.canonical_edge(
				vertex_ids[vertex_index], vertex_ids[next_index]
			)
			var edge_id: int
			if edge_lookup.has(edge):
				edge_id = edge_lookup[edge]
			else:
				edge_id = edge_vertex_ids.size()
				edge_lookup[edge] = edge_id
				edge_vertex_ids.append(edge)
				mutable_edge_cells.append(PackedInt32Array())
			if not mutable_edge_cells[edge_id].has(cell_id):
				mutable_edge_cells[edge_id].append(cell_id)

	graph.edge_vertex_ids = edge_vertex_ids
	graph.edge_cells = mutable_edge_cells
	var neighbor_sets: Array = []
	neighbor_sets.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		neighbor_sets[cell_id] = {}
	for edge_id in graph.edge_count():
		var cells: PackedInt32Array = graph.edge_cells[edge_id]
		var edge: Vector2i = graph.edge_vertex_ids[edge_id]
		if (
			cells.size() == 2
			and graph.vertex_positions[edge.x].distance_to(graph.vertex_positions[edge.y])
				> edge_epsilon
		):
			neighbor_sets[cells[0]][cells[1]] = true
			neighbor_sets[cells[1]][cells[0]] = true

	graph.cell_neighbors.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		var neighbor_ids: Array = neighbor_sets[cell_id].keys()
		neighbor_ids.sort()
		graph.cell_neighbors[cell_id] = PackedInt32Array(neighbor_ids)


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
