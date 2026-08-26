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
	graph.cell_neighbors = delaunay.neighbors
	var epsilon := SpatialGeometry.epsilon_for_size(config.world_width, config.world_height)
	graph.cell_polygons = VoronoiBuilder.build_all(
		graph.cell_centers,
		graph.cell_neighbors,
		config.world_width,
		config.world_height,
		epsilon
	)
	_build_cell_metrics(graph, epsilon)
	_build_shared_vertices(graph, epsilon)

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


static func _build_cell_metrics(graph: SpatialGraph, epsilon: float) -> void:
	var count := graph.cell_count()
	graph.cell_areas.resize(count)
	graph.cell_is_border.resize(count)
	graph.cell_neighbor_distances.resize(count)
	for cell_id in count:
		var polygon: PackedVector2Array = graph.cell_polygons[cell_id]
		graph.cell_areas[cell_id] = SpatialGeometry.polygon_area(polygon)
		graph.cell_is_border[cell_id] = int(SpatialGeometry.polygon_touches_border(
			polygon, graph.config.world_width, graph.config.world_height, epsilon
		))
		var distances := PackedFloat64Array()
		distances.resize(graph.cell_neighbors[cell_id].size())
		for neighbor_index in graph.cell_neighbors[cell_id].size():
			var neighbor_id: int = graph.cell_neighbors[cell_id][neighbor_index]
			distances[neighbor_index] = graph.cell_centers[cell_id].distance_to(
				graph.cell_centers[neighbor_id]
			)
		graph.cell_neighbor_distances[cell_id] = distances


static func _build_shared_vertices(graph: SpatialGraph, epsilon: float) -> void:
	var vertex_lookup := {}
	var positions := PackedVector2Array()
	var mutable_vertex_cells: Array = []
	graph.cell_vertex_ids.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		var ids := PackedInt32Array()
		for position in graph.cell_polygons[cell_id]:
			var key := "%d:%d" % [roundi(position.x / epsilon), roundi(position.y / epsilon)]
			var vertex_id: int
			if vertex_lookup.has(key):
				vertex_id = vertex_lookup[key]
			else:
				vertex_id = positions.size()
				vertex_lookup[key] = vertex_id
				positions.append(position)
				mutable_vertex_cells.append(PackedInt32Array())
			ids.append(vertex_id)
			mutable_vertex_cells[vertex_id].append(cell_id)
		graph.cell_vertex_ids[cell_id] = ids
	graph.vertex_positions = positions
	graph.vertex_cells = mutable_vertex_cells
