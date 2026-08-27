class_name DelaunayGraph
extends RefCounted

## Builds identity-based topology directly from Godot's Delaunay triangle
## indices. Coordinates never participate in deciding triangle or edge IDs.


static func build(points: PackedVector2Array, real_point_count: int = -1) -> Dictionary:
	var triangles := _triangulate_with_stable_ids(points, real_point_count)
	var point_triangles: Array = []
	point_triangles.resize(points.size())
	for point_id in points.size():
		point_triangles[point_id] = PackedInt32Array()
	var edge_triangles := {}
	var errors := PackedStringArray()

	if triangles.size() % 3 != 0:
		errors.append("Delaunay triangle index count is not divisible by three")
		return {
			"triangles": triangles,
			"point_triangles": point_triangles,
			"edge_triangles": edge_triangles,
			"errors": errors,
		}

	for triangle_start in range(0, triangles.size(), 3):
		var triangle_id: int = triangle_start / 3
		var first := triangles[triangle_start]
		var second := triangles[triangle_start + 1]
		var third := triangles[triangle_start + 2]
		if first == second or second == third or third == first:
			errors.append(
				"Delaunay triangle %d repeats point IDs [%d, %d, %d]"
				% [triangle_id, first, second, third]
			)
			continue
		point_triangles[first].append(triangle_id)
		point_triangles[second].append(triangle_id)
		point_triangles[third].append(triangle_id)
		_add_edge_triangle(edge_triangles, first, second, triangle_id)
		_add_edge_triangle(edge_triangles, second, third, triangle_id)
		_add_edge_triangle(edge_triangles, third, first, triangle_id)

	for edge in edge_triangles:
		if edge_triangles[edge].size() > 2:
			errors.append(
				"Delaunay edge %s is nonmanifold with triangle IDs %s"
				% [edge, edge_triangles[edge]]
			)
	return {
		"triangles": triangles,
		"point_triangles": point_triangles,
		"edge_triangles": edge_triangles,
		"errors": errors,
	}


static func _triangulate_with_stable_ids(
		points: PackedVector2Array, real_point_count: int
) -> PackedInt32Array:
	if real_point_count <= 0 or real_point_count >= points.size():
		return Geometry2D.triangulate_delaunay(points)

	# Geometry2D is insertion-order sensitive for large float32 point sets with
	# a collinear outer ring. Feeding that ring first avoids rare overlapping
	# triangle artifacts. The mapping immediately restores the required stable
	# IDs (real points first, boundary points appended), and triangulation still
	# happens once over the complete point set.
	var engine_points := PackedVector2Array()
	var stable_ids := PackedInt32Array()
	for stable_id in range(real_point_count, points.size()):
		engine_points.append(points[stable_id])
		stable_ids.append(stable_id)
	for stable_id in real_point_count:
		engine_points.append(points[stable_id])
		stable_ids.append(stable_id)
	var engine_triangles := Geometry2D.triangulate_delaunay(engine_points)
	var triangles := PackedInt32Array()
	triangles.resize(engine_triangles.size())
	for index in engine_triangles.size():
		triangles[index] = stable_ids[engine_triangles[index]]
	return triangles


static func _add_edge_triangle(
		edge_triangles: Dictionary, first: int, second: int, triangle_id: int
) -> void:
	var edge := SpatialGeometry.canonical_edge(first, second)
	if not edge_triangles.has(edge):
		edge_triangles[edge] = PackedInt32Array()
	edge_triangles[edge].append(triangle_id)
