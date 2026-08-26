class_name VoronoiBuilder
extends RefCounted


static func build_all(
		centers: PackedVector2Array,
		neighbors: Array,
		width: float,
		height: float,
		epsilon: float
) -> Array:
	var polygons: Array = []
	polygons.resize(centers.size())
	for cell_id in centers.size():
		var polygon := PackedVector2Array([
			Vector2.ZERO,
			Vector2(width, 0.0),
			Vector2(width, height),
			Vector2(0.0, height),
		])
		var center := centers[cell_id]
		for neighbor_id in neighbors[cell_id]:
			polygon = _clip_to_nearer_half_plane(
				polygon, center, centers[neighbor_id], epsilon
			)
			if polygon.is_empty():
				break
		polygons[cell_id] = polygon
	return polygons


static func _clip_to_nearer_half_plane(
		polygon: PackedVector2Array, center: Vector2, other: Vector2, epsilon: float
) -> PackedVector2Array:
	if polygon.is_empty():
		return polygon
	var result := PackedVector2Array()
	var normal := other - center
	var threshold := (other.length_squared() - center.length_squared()) * 0.5
	var previous := polygon[polygon.size() - 1]
	var previous_value := previous.dot(normal) - threshold
	var previous_inside := previous_value <= epsilon

	for current in polygon:
		var current_value := current.dot(normal) - threshold
		var current_inside := current_value <= epsilon
		if current_inside != previous_inside:
			var denominator := previous_value - current_value
			if absf(denominator) > 0.000000000001:
				var weight := clampf(previous_value / denominator, 0.0, 1.0)
				result.append(previous.lerp(current, weight))
		if current_inside:
			result.append(current)
		previous = current
		previous_value = current_value
		previous_inside = current_inside
	return result
