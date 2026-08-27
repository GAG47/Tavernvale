extends SceneTree

var _failures := PackedStringArray()
var _default_generation_ms := 0
var _default_cell_count := 0
var _default_vertex_count := 0
var _default_edge_count := 0
var _default_border_cell_count := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	var test_groups: Array[Callable] = [
		_test_determinism,
		_test_different_seed,
		_test_real_seed_grid_without_jitter,
		_test_default_jitter,
		_test_neighbor_symmetry_and_connectivity,
		_test_unclipped_polygons,
		_test_serialization_regeneration,
		_test_dual_edges_and_border_semantics,
		_test_triangle_vertex_identity,
		_test_default_scale_and_validator,
	]
	for test_group in test_groups:
		test_group.call()

	if _failures.is_empty():
		print("Spatial Skeleton: all %d test groups passed" % test_groups.size())
		print(
			"Default graph: cells=%d vertices=%d edges=%d border_cells=%d generated=%d ms"
			% [
				_default_cell_count,
				_default_vertex_count,
				_default_edge_count,
				_default_border_cell_count,
				_default_generation_ms,
			]
		)
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Spatial Skeleton: %d failures" % _failures.size())
		quit(1)


func _test_determinism() -> void:
	var config := SpatialConfig.new(123456, 320.0, 180.0, 360, 0.9)
	var first := SpatialGenerator.generate(config)
	var second := SpatialGenerator.generate(config)
	_expect(first != null and second != null, "determinism graphs should generate")
	if first != null and second != null:
		_expect(_graphs_equal(first, second), "same Seed + Config must reproduce every spatial array")
	_expect(
		SpatialValidator.validate_determinism(config).is_empty(),
		"SpatialValidator determinism check must pass"
	)


func _test_different_seed() -> void:
	var first := SpatialGenerator.generate(SpatialConfig.new(11, 300.0, 200.0, 300, 0.9))
	var second := SpatialGenerator.generate(SpatialConfig.new(12, 300.0, 200.0, 300, 0.9))
	_expect(first != null and second != null, "different-seed graphs should generate")
	if first != null and second != null:
		_expect(first.cell_count() == second.cell_count(), "different seeds should keep the same cell count")
		_expect(first.cell_centers != second.cell_centers, "different seeds should change centers")
		_expect(first.cell_polygons != second.cell_polygons, "different seeds should change polygons")


func _test_real_seed_grid_without_jitter() -> void:
	var config := SpatialConfig.new(99, 240.0, 120.0, 128, 0.0)
	var dimensions := SpatialGenerator._calculate_grid_dimensions(config)
	var centers := SpatialGenerator._create_centers(config, dimensions.x, dimensions.y)
	var spacing_x := config.world_width / dimensions.x
	var spacing_y := config.world_height / dimensions.y
	for row in dimensions.y:
		for column in dimensions.x:
			var expected := Vector2((column + 0.5) * spacing_x, (row + 0.5) * spacing_y)
			_expect(
				centers[row * dimensions.x + column].is_equal_approx(expected),
				"jitter=0 real seed %d must remain on the regular lattice"
				% (row * dimensions.x + column)
			)


func _test_default_jitter() -> void:
	var graph := SpatialGenerator.generate(SpatialConfig.new(777, 320.0, 320.0, 1024, 0.9))
	_expect(graph != null, "default-jitter graph should generate")
	if graph == null:
		return
	var minimum := INF
	var maximum := 0.0
	for area in graph.cell_areas:
		minimum = minf(minimum, area)
		maximum = maxf(maximum, area)
	_expect(minimum > 0.000001, "default jitter must not create near-zero cells")
	_expect(maximum - minimum > 0.01, "default jitter should create irregular cell areas")


func _test_neighbor_symmetry_and_connectivity() -> void:
	var graph := SpatialGenerator.generate(SpatialConfig.new(808, 250.0, 250.0, 625, 0.9))
	_expect(graph != null, "neighbor test graph should generate")
	if graph == null:
		return
	for cell_id in graph.cell_count():
		for neighbor_id in graph.cell_neighbors[cell_id]:
			_expect(
				graph.cell_neighbors[neighbor_id].has(cell_id),
				"neighbor relation %d -> %d must be symmetric" % [cell_id, neighbor_id]
			)
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
	_expect(queue.size() == graph.cell_count(), "Delaunay cell graph must be connected")


func _test_unclipped_polygons() -> void:
	var graph := SpatialGenerator.generate(SpatialConfig.new(4321, 360.0, 210.0, 756, 0.9))
	_expect(graph != null, "polygon test graph should generate")
	if graph == null:
		return
	var outside_vertex_count := 0
	var epsilon := SpatialGeometry.epsilon_for_size(
		graph.config.world_width, graph.config.world_height
	)
	for cell_id in graph.cell_count():
		var polygon: PackedVector2Array = graph.cell_polygons[cell_id]
		_expect(polygon.size() >= 3, "cell %d polygon must have at least 3 vertices" % cell_id)
		_expect(graph.cell_areas[cell_id] > 0.0, "cell %d area must be positive" % cell_id)
		_expect(
			SpatialGeometry.point_in_polygon(graph.cell_centers[cell_id], polygon, epsilon),
			"cell %d polygon must contain its center" % cell_id
		)
		for vertex in polygon:
			if not SpatialGeometry.point_in_world(
				vertex, graph.config.world_width, graph.config.world_height, 0.0
			):
				outside_vertex_count += 1
	_expect(
		outside_vertex_count > 0,
		"boundary-seed Voronoi polygons should be allowed beyond the logical rectangle"
	)


func _test_serialization_regeneration() -> void:
	var original_config := SpatialConfig.new(-91234, 333.0, 177.0, 450, 0.75)
	var restored_config := SpatialConfig.from_dict(original_config.to_dict())
	var first := SpatialGenerator.generate(original_config)
	var second := SpatialGenerator.generate(restored_config)
	_expect(first != null and second != null, "serialized-config graphs should generate")
	if first != null and second != null:
		_expect(_graphs_equal(first, second), "config data round-trip must regenerate the same graph")


func _test_dual_edges_and_border_semantics() -> void:
	var graph := SpatialGenerator.generate(SpatialConfig.new(2025, 420.0, 240.0, 840, 0.9))
	_expect(graph != null, "border-topology graph should generate")
	if graph == null:
		return
	var shared_pairs := _build_shared_cell_pair_lookup(graph)
	var candidate_pairs := _build_delaunay_cell_pair_lookup(graph)
	_expect(
		shared_pairs.size() == candidate_pairs.size(),
		"every real-real Delaunay edge must be exactly one final shared edge"
	)
	var border_count := 0
	for cell_id in graph.cell_count():
		if graph.cell_is_border[cell_id]:
			border_count += 1
			var has_boundary_edge := false
			for edge_id in graph.edge_count():
				var seed_edge: Vector2i = graph.edge_seed_ids[edge_id]
				if graph.edge_cells[edge_id].size() == 1 and graph.edge_cells[edge_id][0] == cell_id:
					has_boundary_edge = (
						seed_edge.x >= graph.cell_count() or seed_edge.y >= graph.cell_count()
					)
					if has_boundary_edge:
						break
			_expect(
				has_boundary_edge,
				"border cell %d must own a real-boundary dual edge" % cell_id
			)
	_expect(border_count > 0, "border-topology graph should contain border cells")
	for pair in candidate_pairs:
		_expect(shared_pairs.has(pair), "real-real Delaunay pair %s must be a final neighbor" % pair)


func _test_triangle_vertex_identity() -> void:
	var graph := SpatialGenerator.generate(SpatialConfig.new(3030, 320.0, 320.0, 1024, 0.9))
	_expect(graph != null, "vertex-topology graph should generate")
	if graph == null:
		return
	_expect(
		graph.vertex_positions.size() * 3 == graph.delaunay_triangles.size(),
		"each Delaunay triangle ID must be exactly one Voronoi vertex ID"
	)
	var shared_pairs := _build_shared_cell_pair_lookup(graph)
	for edge_id in graph.edge_count():
		var edge: Vector2i = graph.edge_vertex_ids[edge_id]
		var seed_edge: Vector2i = graph.edge_seed_ids[edge_id]
		var cells: PackedInt32Array = graph.edge_cells[edge_id]
		_expect(cells.size() == 1 or cells.size() == 2, "edge %d must have one or two cells" % edge_id)
		_expect(
			edge.x != edge.y,
			"dual edge %d for Delaunay seed edge %s must use two triangle identities"
			% [edge_id, seed_edge]
		)
		if cells.size() == 2:
			_expect(
				_cell_uses_edge(graph, cells[0], edge) and _cell_uses_edge(graph, cells[1], edge),
				"shared edge %d endpoints must use identical vertex IDs in both cells" % edge_id
			)
	for vertex_id in graph.vertex_cells.size():
		var cells_seen := {}
		var cells: PackedInt32Array = graph.vertex_cells[vertex_id]
		for cell_id in cells:
			_expect(not cells_seen.has(cell_id), "vertex %d must not repeat cell %d" % [vertex_id, cell_id])
			cells_seen[cell_id] = true
			_expect(
				graph.cell_vertex_ids[cell_id].has(vertex_id),
				"vertex %d -> cell %d must be reciprocal" % [vertex_id, cell_id]
			)
		for first_index in cells.size():
			for second_index in range(first_index + 1, cells.size()):
				var first_cell := cells[first_index]
				var second_cell := cells[second_index]
				var pair := SpatialGeometry.canonical_edge(first_cell, second_cell)
				if not shared_pairs.has(pair):
					_expect(
						not graph.cell_neighbors[first_cell].has(second_cell),
						"cells %d and %d sharing only vertex %d must not be neighbors"
						% [first_cell, second_cell, vertex_id]
					)


func _test_default_scale_and_validator() -> void:
	var default_config := SpatialConfig.new()
	_expect(default_config.world_width == 2000.0, "default world width must be 2000")
	_expect(default_config.world_height == 1000.0, "default world height must be 1000")
	_expect(
		default_config.world_width / default_config.world_height == 2.0,
		"default world aspect ratio must be 2:1"
	)
	_expect(default_config.target_cell_count == 20000, "default target real Cell Count must be 20000")
	var started := Time.get_ticks_msec()
	var graph := SpatialGenerator.generate(default_config)
	_default_generation_ms = Time.get_ticks_msec() - started
	_expect(graph != null, "default 20k graph should generate")
	if graph == null:
		return
	_default_cell_count = graph.cell_count()
	_default_vertex_count = graph.vertex_positions.size()
	_default_edge_count = graph.edge_count()
	for is_border in graph.cell_is_border:
		_default_border_cell_count += int(bool(is_border))
	_expect(graph.cell_count() == 20000, "default config should produce exactly 20000 real cells")
	_expect(graph.columns == 200 and graph.rows == 100, "default 2:1 grid must be 200 by 100")
	_expect(graph.boundary_seed_count() == 300, "default Azgaar-style boundary ring must contain 300 seeds")
	_expect(
		graph.all_seed_count() == graph.cell_count() + graph.boundary_seed_count(),
		"boundary seeds must remain outside the real cell arrays"
	)
	var errors := SpatialValidator.validate(graph)
	_expect(errors.is_empty(), "default 20k graph validator should pass: " + "; ".join(errors))


func _graphs_equal(first: SpatialGraph, second: SpatialGraph) -> bool:
	return (
		first.spacing == second.spacing
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


func _build_shared_cell_pair_lookup(graph: SpatialGraph) -> Dictionary:
	var result := {}
	var edge_epsilon := SpatialGeometry.edge_epsilon_for_size(
		graph.config.world_width, graph.config.world_height
	)
	for edge_id in graph.edge_count():
		var cells: PackedInt32Array = graph.edge_cells[edge_id]
		var edge: Vector2i = graph.edge_vertex_ids[edge_id]
		if (
			cells.size() == 2
			and graph.vertex_positions[edge.x].distance_to(graph.vertex_positions[edge.y])
				> edge_epsilon
		):
			result[SpatialGeometry.canonical_edge(cells[0], cells[1])] = edge_id
	return result


func _build_delaunay_cell_pair_lookup(graph: SpatialGraph) -> Dictionary:
	var result := {}
	for triangle_start in range(0, graph.delaunay_triangles.size(), 3):
		var first := graph.delaunay_triangles[triangle_start]
		var second := graph.delaunay_triangles[triangle_start + 1]
		var third := graph.delaunay_triangles[triangle_start + 2]
		for pair in [
			SpatialGeometry.canonical_edge(first, second),
			SpatialGeometry.canonical_edge(second, third),
			SpatialGeometry.canonical_edge(third, first),
		]:
			if pair.x < graph.cell_count() and pair.y < graph.cell_count():
				result[pair] = true
	return result


func _cell_uses_edge(graph: SpatialGraph, cell_id: int, edge: Vector2i) -> bool:
	var vertex_ids: PackedInt32Array = graph.cell_vertex_ids[cell_id]
	for vertex_index in vertex_ids.size():
		if SpatialGeometry.canonical_edge(
			vertex_ids[vertex_index], vertex_ids[(vertex_index + 1) % vertex_ids.size()]
		) == edge:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
