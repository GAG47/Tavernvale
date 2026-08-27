class_name SpatialGeometry
extends RefCounted


static func epsilon_for_size(width: float, height: float) -> float:
	return maxf(maxf(width, height) * 0.000001, 0.000001)


static func edge_epsilon_for_size(width: float, height: float) -> float:
	# Edge validity only guards numerically coincident circumcenters. It is not a
	# coordinate merge tolerance and must remain well below a float32 world-space
	# unit at normal map scales.
	return maxf(maxf(width, height) * 0.00000001, 0.000000001)


static func canonical_edge(first_vertex_id: int, second_vertex_id: int) -> Vector2i:
	return Vector2i(
		mini(first_vertex_id, second_vertex_id), maxi(first_vertex_id, second_vertex_id)
	)


static func polygon_signed_area(polygon: PackedVector2Array) -> float:
	var twice_area := 0.0
	for index in polygon.size():
		var next_index := (index + 1) % polygon.size()
		twice_area += polygon[index].x * polygon[next_index].y
		twice_area -= polygon[next_index].x * polygon[index].y
	return twice_area * 0.5


static func polygon_area(polygon: PackedVector2Array) -> float:
	return absf(polygon_signed_area(polygon))


static func point_in_polygon(point: Vector2, polygon: PackedVector2Array, epsilon: float) -> bool:
	if polygon.size() < 3:
		return false
	var inside := false
	var previous := polygon[polygon.size() - 1]
	for current in polygon:
		if _point_on_segment(point, previous, current, epsilon):
			return true
		var crosses := (current.y > point.y) != (previous.y > point.y)
		if crosses:
			var intersection_x := (previous.x - current.x) * (point.y - current.y) \
				/ (previous.y - current.y) + current.x
			if point.x < intersection_x:
				inside = not inside
		previous = current
	return inside


static func point_in_world(point: Vector2, width: float, height: float, epsilon: float) -> bool:
	return (
		point.x >= -epsilon
		and point.y >= -epsilon
		and point.x <= width + epsilon
		and point.y <= height + epsilon
	)


static func _point_on_segment(point: Vector2, start: Vector2, end: Vector2, epsilon: float) -> bool:
	var edge := end - start
	var relative := point - start
	if absf(edge.cross(relative)) > epsilon * maxf(1.0, edge.length()):
		return false
	return relative.dot(point - end) <= epsilon * epsilon
