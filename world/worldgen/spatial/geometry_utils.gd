class_name SpatialGeometry
extends RefCounted


static func epsilon_for_size(width: float, height: float) -> float:
	return maxf(maxf(width, height) * 0.000001, 0.000001)


static func vertex_merge_epsilon_for_size(width: float, height: float) -> float:
	return epsilon_for_size(width, height)


static func edge_epsilon_for_size(width: float, height: float) -> float:
	return epsilon_for_size(width, height)


static func canonical_edge(first_vertex_id: int, second_vertex_id: int) -> Vector2i:
	return Vector2i(
		mini(first_vertex_id, second_vertex_id), maxi(first_vertex_id, second_vertex_id)
	)


static func remove_consecutive_duplicate_points(
		polygon: PackedVector2Array, epsilon: float
) -> PackedVector2Array:
	var result := PackedVector2Array()
	var epsilon_squared := epsilon * epsilon
	for point in polygon:
		if result.is_empty() or point.distance_squared_to(result[result.size() - 1]) > epsilon_squared:
			result.append(point)
	if result.size() > 1 and result[0].distance_squared_to(result[result.size() - 1]) <= epsilon_squared:
		result.resize(result.size() - 1)
	return result


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


static func polygon_touches_border(
		polygon: PackedVector2Array, width: float, height: float, epsilon: float
) -> bool:
	for point in polygon:
		if (
			absf(point.x) <= epsilon
			or absf(point.y) <= epsilon
			or absf(point.x - width) <= epsilon
			or absf(point.y - height) <= epsilon
		):
			return true
	return false


static func edge_lies_on_world_border(
		start: Vector2, end: Vector2, width: float, height: float, epsilon: float
) -> bool:
	return (
		(absf(start.x) <= epsilon and absf(end.x) <= epsilon)
		or (absf(start.y) <= epsilon and absf(end.y) <= epsilon)
		or (absf(start.x - width) <= epsilon and absf(end.x - width) <= epsilon)
		or (absf(start.y - height) <= epsilon and absf(end.y - height) <= epsilon)
	)


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
