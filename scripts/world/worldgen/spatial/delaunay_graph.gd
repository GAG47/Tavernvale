class_name DelaunayGraph
extends RefCounted


static func build(points: PackedVector2Array) -> Dictionary:
	var triangles := Geometry2D.triangulate_delaunay(points)
	var neighbor_sets: Array = []
	neighbor_sets.resize(points.size())
	for cell_id in points.size():
		neighbor_sets[cell_id] = {}

	for triangle_start in range(0, triangles.size(), 3):
		_add_edge(neighbor_sets, triangles[triangle_start], triangles[triangle_start + 1])
		_add_edge(neighbor_sets, triangles[triangle_start + 1], triangles[triangle_start + 2])
		_add_edge(neighbor_sets, triangles[triangle_start + 2], triangles[triangle_start])
	# Geometry2D correctly returns no triangles for fewer than three points and
	# for a fully collinear lattice. The one-dimensional Delaunay graph is the
	# sorted chain of adjacent sites, which also gives the required half-planes.
	if triangles.is_empty() and points.size() > 1:
		_add_collinear_edges(points, neighbor_sets)

	var neighbors: Array = []
	neighbors.resize(points.size())
	for cell_id in points.size():
		var ids: Array = neighbor_sets[cell_id].keys()
		ids.sort()
		neighbors[cell_id] = PackedInt32Array(ids)
	return {"triangles": triangles, "neighbors": neighbors}


static func _add_edge(neighbor_sets: Array, first: int, second: int) -> void:
	if first == second:
		return
	neighbor_sets[first][second] = true
	neighbor_sets[second][first] = true


static func _add_collinear_edges(points: PackedVector2Array, neighbor_sets: Array) -> void:
	var ids: Array = range(points.size())
	var use_x := _coordinate_span(points, true) >= _coordinate_span(points, false)
	ids.sort_custom(func(first: int, second: int) -> bool:
		var first_primary: float = points[first].x if use_x else points[first].y
		var second_primary: float = points[second].x if use_x else points[second].y
		if not is_equal_approx(first_primary, second_primary):
			return first_primary < second_primary
		var first_secondary: float = points[first].y if use_x else points[first].x
		var second_secondary: float = points[second].y if use_x else points[second].x
		return first_secondary < second_secondary
	)
	for index in ids.size() - 1:
		_add_edge(neighbor_sets, ids[index], ids[index + 1])


static func _coordinate_span(points: PackedVector2Array, use_x: bool) -> float:
	var minimum := INF
	var maximum := -INF
	for point in points:
		var value: float = point.x if use_x else point.y
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	return maximum - minimum
