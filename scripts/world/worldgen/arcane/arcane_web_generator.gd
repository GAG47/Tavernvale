class_name ArcaneWebGenerator
extends RefCounted

const ARCANE_WEB_SEED_SALT := 0x41574542 # "AWEB"
const BRIDSON_CANDIDATES := 30
const WEIGHT_RADIUS_MIN_FACTOR := 0.15
const WEIGHT_RADIUS_MAX_FACTOR := 1.00
const _TWO_PI := PI * 2.0
const _LINE_EPSILON := 1.0e-10


static func generate(
		world_seed: int,
		world_width: float,
		world_height: float,
		settings: ArcaneWebSettings = null
) -> ArcaneWebLayer:
	var total_started := Time.get_ticks_usec()
	var actual_settings := settings if settings != null else ArcaneWebSettings.new()
	if not is_finite(world_width) or not is_finite(world_height) \
			or world_width <= 0.0 or world_height <= 0.0:
		push_error("ArcaneWebGenerator: world extent must be finite and positive")
		return null
	var settings_errors := actual_settings.validate()
	if not settings_errors.is_empty():
		push_error("ArcaneWebGenerator: invalid settings: " + "; ".join(settings_errors))
		return null

	var layer := ArcaneWebLayer.new()
	layer.world_seed = world_seed
	layer.world_width = world_width
	layer.world_height = world_height
	layer.settings = actual_settings.duplicate_settings()
	var generation_rect := Rect2(
		Vector2(-actual_settings.web_generation_margin, -actual_settings.web_generation_margin),
		Vector2(
			world_width + actual_settings.web_generation_margin * 2.0,
			world_height + actual_settings.web_generation_margin * 2.0
		)
	)
	var world_rect := Rect2(Vector2.ZERO, Vector2(world_width, world_height))

	var generation_started := Time.get_ticks_usec()
	var nuclei := sample_weighted_nuclei(
		world_seed, generation_rect, actual_settings.web_nucleus_min_separation
	)
	layer.generated_nucleus_count = nuclei.size()
	layer.generation_time_ms = float(Time.get_ticks_usec() - generation_started) / 1000.0

	var diagram_started := Time.get_ticks_usec()
	layer.domains = _build_domains(nuclei, generation_rect, world_rect)
	var segments := _build_true_ley_segments(nuclei, generation_rect, world_rect)
	_build_nodes_and_edges(layer, segments)
	layer.power_diagram_time_ms = float(Time.get_ticks_usec() - diagram_started) / 1000.0

	var importance_started := Time.get_ticks_usec()
	ArcaneWebCentrality.apply(layer)
	layer.importance_time_ms = float(Time.get_ticks_usec() - importance_started) / 1000.0
	layer.rebuild_incidence()
	layer.total_generation_time_ms = float(Time.get_ticks_usec() - total_started) / 1000.0

	var validation_errors := ArcaneWebValidator.validate(layer)
	if not validation_errors.is_empty():
		push_error("Arcane Web validation failed: " + "; ".join(validation_errors))
		return null
	return layer


static func sample_weighted_nuclei(
		world_seed: int, generation_rect: Rect2, minimum_separation: float
) -> Array[Dictionary]:
	var rng := DeterministicRng.new(
		DeterministicRng.stable_mix(world_seed, ARCANE_WEB_SEED_SALT)
	)
	var cell_size := minimum_separation / sqrt(2.0)
	var columns := maxi(1, ceili(generation_rect.size.x / cell_size))
	var rows := maxi(1, ceili(generation_rect.size.y / cell_size))
	var grid := PackedInt32Array()
	grid.resize(columns * rows)
	grid.fill(-1)
	var positions := PackedVector2Array()
	var active := PackedInt32Array()
	var first := generation_rect.position + Vector2(
		rng.next_float() * generation_rect.size.x,
		rng.next_float() * generation_rect.size.y
	)
	_add_poisson_position(first, positions, active, grid, columns, rows, cell_size, generation_rect)
	var separation_squared := minimum_separation * minimum_separation
	while not active.is_empty():
		var active_slot := mini(floori(rng.next_float() * active.size()), active.size() - 1)
		var source := positions[active[active_slot]]
		var accepted := false
		for attempt in BRIDSON_CANDIDATES:
			var angle := rng.next_float() * _TWO_PI
			var radius := minimum_separation * (1.0 + rng.next_float())
			var candidate := source + Vector2(cos(angle), sin(angle)) * radius
			if not generation_rect.has_point(candidate):
				continue
			if not _poisson_candidate_is_clear(
				candidate, positions, grid, columns, rows, cell_size,
				generation_rect, separation_squared
			):
				continue
			_add_poisson_position(
				candidate, positions, active, grid, columns, rows, cell_size, generation_rect
			)
			accepted = true
			break
		if not accepted:
			active.remove_at(active_slot)

	var sorted_positions: Array[Vector2] = []
	for position in positions:
		sorted_positions.append(position)
	sorted_positions.sort_custom(_position_less)
	var result: Array[Dictionary] = []
	for position in sorted_positions:
		var radius := minimum_separation * lerpf(
			WEIGHT_RADIUS_MIN_FACTOR, WEIGHT_RADIUS_MAX_FACTOR, rng.next_float()
		)
		result.append({"position": position, "weight": radius * radius})
	return result


static func build_power_cell(
		positions: PackedVector2Array,
		weights: PackedFloat64Array,
		nucleus_index: int,
		clip_rect: Rect2
) -> PackedVector2Array:
	var polygon := PackedVector2Array([
		clip_rect.position,
		Vector2(clip_rect.end.x, clip_rect.position.y),
		clip_rect.end,
		Vector2(clip_rect.position.x, clip_rect.end.y),
	])
	var nucleus := positions[nucleus_index]
	for other_index in positions.size():
		if other_index == nucleus_index:
			continue
		var normal := 2.0 * (positions[other_index] - nucleus)
		var limit := positions[other_index].length_squared() - nucleus.length_squared() \
				+ weights[nucleus_index] - weights[other_index]
		polygon = _clip_polygon_to_half_plane(polygon, normal, limit)
		if polygon.is_empty():
			break
	return polygon


static func power_value(point: Vector2, nucleus_position: Vector2, weight: float) -> float:
	return point.distance_squared_to(nucleus_position) - weight


static func power_bisector_segment(
		positions: PackedVector2Array,
		weights: PackedFloat64Array,
		first_index: int,
		second_index: int,
		generation_rect: Rect2,
		world_rect: Rect2
) -> PackedVector2Array:
	var first := positions[first_index]
	var second := positions[second_index]
	var normal := 2.0 * (second - first)
	var normal_squared := normal.length_squared()
	if normal_squared <= _LINE_EPSILON:
		return PackedVector2Array()
	var limit := second.length_squared() - first.length_squared() \
			+ weights[first_index] - weights[second_index]
	var line_point := normal * (limit / normal_squared)
	var direction := Vector2(-normal.y, normal.x).normalized()
	var interval := _line_rect_interval(line_point, direction, generation_rect)
	if not interval.valid:
		return PackedVector2Array()
	var minimum_t: float = interval.minimum
	var maximum_t: float = interval.maximum
	for other_index in positions.size():
		if other_index == first_index or other_index == second_index:
			continue
		var constraint_normal := 2.0 * (positions[other_index] - first)
		var constraint_limit := positions[other_index].length_squared() \
				- first.length_squared() + weights[first_index] - weights[other_index]
		var coefficient := constraint_normal.dot(direction)
		var remaining := constraint_limit - constraint_normal.dot(line_point)
		if absf(coefficient) <= _LINE_EPSILON:
			if remaining < -_LINE_EPSILON:
				return PackedVector2Array()
			continue
		var boundary_t := remaining / coefficient
		if coefficient > 0.0:
			maximum_t = minf(maximum_t, boundary_t)
		else:
			minimum_t = maxf(minimum_t, boundary_t)
		if maximum_t <= minimum_t:
			return PackedVector2Array()

	var world_interval := _line_rect_interval(line_point, direction, world_rect)
	if not world_interval.valid:
		return PackedVector2Array()
	minimum_t = maxf(minimum_t, float(world_interval.minimum))
	maximum_t = minf(maximum_t, float(world_interval.maximum))
	if maximum_t <= minimum_t:
		return PackedVector2Array()
	var start := _snap_to_world_boundary(line_point + direction * minimum_t, world_rect)
	var end := _snap_to_world_boundary(line_point + direction * maximum_t, world_rect)
	return PackedVector2Array([start, end])


static func _build_domains(
		nuclei: Array[Dictionary], generation_rect: Rect2, world_rect: Rect2
) -> Array[ArcaneWebDomain]:
	var positions := PackedVector2Array()
	var weights := PackedFloat64Array()
	for nucleus in nuclei:
		positions.append(nucleus.position)
		weights.append(nucleus.weight)
	var domains: Array[ArcaneWebDomain] = []
	for nucleus_index in nuclei.size():
		var extended_polygon := build_power_cell(
			positions, weights, nucleus_index, generation_rect
		)
		var polygon := _clip_polygon_to_rect(extended_polygon, world_rect)
		if polygon.size() < 3 or SpatialGeometry.polygon_area(polygon) <= 0.0:
			continue
		domains.append(ArcaneWebDomain.new(
			domains.size(), positions[nucleus_index], weights[nucleus_index], polygon
		))
	return domains


static func _clip_polygon_to_rect(
		polygon: PackedVector2Array, clip_rect: Rect2
) -> PackedVector2Array:
	var result := _clip_polygon_to_half_plane(
		polygon, Vector2(-1.0, 0.0), -clip_rect.position.x
	)
	result = _clip_polygon_to_half_plane(result, Vector2(1.0, 0.0), clip_rect.end.x)
	result = _clip_polygon_to_half_plane(
		result, Vector2(0.0, -1.0), -clip_rect.position.y
	)
	return _clip_polygon_to_half_plane(result, Vector2(0.0, 1.0), clip_rect.end.y)


static func _build_true_ley_segments(
		nuclei: Array[Dictionary], generation_rect: Rect2, world_rect: Rect2
) -> Array[PackedVector2Array]:
	var positions := PackedVector2Array()
	var weights := PackedFloat64Array()
	for nucleus in nuclei:
		positions.append(nucleus.position)
		weights.append(nucleus.weight)
	var epsilon := SpatialGeometry.epsilon_for_size(world_rect.size.x, world_rect.size.y)
	var segments: Array[PackedVector2Array] = []
	for first_index in nuclei.size():
		for second_index in range(first_index + 1, nuclei.size()):
			var segment := power_bisector_segment(
				positions, weights, first_index, second_index, generation_rect, world_rect
			)
			if segment.size() == 2 and segment[0].distance_to(segment[1]) > epsilon:
				segments.append(segment)
	return segments


static func _build_nodes_and_edges(
		layer: ArcaneWebLayer, segments: Array[PackedVector2Array]
) -> void:
	var epsilon := SpatialGeometry.epsilon_for_size(layer.world_width, layer.world_height)
	var canonical_positions: Array[Vector2] = []
	for segment in segments:
		for position in segment:
			if _find_position(canonical_positions, position, epsilon) < 0:
				canonical_positions.append(position)
	canonical_positions.sort_custom(_position_less)
	for node_id in canonical_positions.size():
		var position := canonical_positions[node_id]
		var kind := ArcaneWebNode.Kind.BOUNDARY_EXIT \
				if _is_on_world_boundary(position, layer.world_width, layer.world_height, epsilon) \
				else ArcaneWebNode.Kind.JUNCTION
		layer.nodes.append(ArcaneWebNode.new(node_id, position, kind))

	var edge_pairs: Array[Vector2i] = []
	var seen_pairs := {}
	for segment in segments:
		var first_id := _find_position(canonical_positions, segment[0], epsilon)
		var second_id := _find_position(canonical_positions, segment[1], epsilon)
		if first_id < 0 or second_id < 0 or first_id == second_id:
			continue
		var pair := Vector2i(mini(first_id, second_id), maxi(first_id, second_id))
		if seen_pairs.has(pair):
			continue
		seen_pairs[pair] = true
		edge_pairs.append(pair)
	edge_pairs.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		return first.x < second.x if first.x != second.x else first.y < second.y
	)
	for edge_id in edge_pairs.size():
		var pair := edge_pairs[edge_id]
		layer.edges.append(ArcaneWebEdge.new(
			edge_id, pair.x, pair.y,
			layer.nodes[pair.x].world_position.distance_to(layer.nodes[pair.y].world_position)
		))


static func _clip_polygon_to_half_plane(
		polygon: PackedVector2Array, normal: Vector2, limit: float
) -> PackedVector2Array:
	var result := PackedVector2Array()
	if polygon.is_empty():
		return result
	var previous := polygon[polygon.size() - 1]
	var previous_value := normal.dot(previous) - limit
	for current in polygon:
		var current_value := normal.dot(current) - limit
		var previous_inside := previous_value <= _LINE_EPSILON
		var current_inside := current_value <= _LINE_EPSILON
		if previous_inside != current_inside:
			var denominator := previous_value - current_value
			if absf(denominator) > _LINE_EPSILON:
				result.append(previous.lerp(current, previous_value / denominator))
		if current_inside:
			result.append(current)
		previous = current
		previous_value = current_value
	return result


static func _line_rect_interval(point: Vector2, direction: Vector2, rect: Rect2) -> Dictionary:
	var minimum_t := -INF
	var maximum_t := INF
	for axis in 2:
		var coordinate := point[axis]
		var delta := direction[axis]
		var lower := rect.position[axis]
		var upper := rect.end[axis]
		if absf(delta) <= _LINE_EPSILON:
			if coordinate < lower - _LINE_EPSILON or coordinate > upper + _LINE_EPSILON:
				return {"valid": false}
			continue
		var first_t := (lower - coordinate) / delta
		var second_t := (upper - coordinate) / delta
		if first_t > second_t:
			var temporary := first_t
			first_t = second_t
			second_t = temporary
		minimum_t = maxf(minimum_t, first_t)
		maximum_t = minf(maximum_t, second_t)
		if maximum_t < minimum_t:
			return {"valid": false}
	return {"valid": true, "minimum": minimum_t, "maximum": maximum_t}


static func _add_poisson_position(
		position: Vector2,
		positions: PackedVector2Array,
		active: PackedInt32Array,
		grid: PackedInt32Array,
		columns: int,
		rows: int,
		cell_size: float,
		generation_rect: Rect2
) -> void:
	var position_id := positions.size()
	positions.append(position)
	active.append(position_id)
	var coordinate := _poisson_grid_coordinate(position, cell_size, generation_rect)
	var x := clampi(coordinate.x, 0, columns - 1)
	var y := clampi(coordinate.y, 0, rows - 1)
	grid[y * columns + x] = position_id


static func _poisson_candidate_is_clear(
		candidate: Vector2,
		positions: PackedVector2Array,
		grid: PackedInt32Array,
		columns: int,
		rows: int,
		cell_size: float,
		generation_rect: Rect2,
		separation_squared: float
) -> bool:
	var coordinate := _poisson_grid_coordinate(candidate, cell_size, generation_rect)
	for y in range(maxi(0, coordinate.y - 2), mini(rows - 1, coordinate.y + 2) + 1):
		for x in range(maxi(0, coordinate.x - 2), mini(columns - 1, coordinate.x + 2) + 1):
			var position_id := grid[y * columns + x]
			if position_id >= 0 \
					and candidate.distance_squared_to(positions[position_id]) < separation_squared:
				return false
	return true


static func _poisson_grid_coordinate(
		position: Vector2, cell_size: float, generation_rect: Rect2
) -> Vector2i:
	return Vector2i(
		floori((position.x - generation_rect.position.x) / cell_size),
		floori((position.y - generation_rect.position.y) / cell_size)
	)


static func _find_position(positions: Array[Vector2], target: Vector2, epsilon: float) -> int:
	for index in positions.size():
		if positions[index].distance_to(target) <= epsilon:
			return index
	return -1


static func _position_less(first: Vector2, second: Vector2) -> bool:
	return first.x < second.x if first.x != second.x else first.y < second.y


static func _is_on_world_boundary(
		position: Vector2, width: float, height: float, epsilon: float
) -> bool:
	return absf(position.x) <= epsilon or absf(position.x - width) <= epsilon \
			or absf(position.y) <= epsilon or absf(position.y - height) <= epsilon


static func _snap_to_world_boundary(position: Vector2, world_rect: Rect2) -> Vector2:
	var result := position
	var epsilon := SpatialGeometry.epsilon_for_size(world_rect.size.x, world_rect.size.y)
	if absf(result.x - world_rect.position.x) <= epsilon:
		result.x = world_rect.position.x
	elif absf(result.x - world_rect.end.x) <= epsilon:
		result.x = world_rect.end.x
	if absf(result.y - world_rect.position.y) <= epsilon:
		result.y = world_rect.position.y
	elif absf(result.y - world_rect.end.y) <= epsilon:
		result.y = world_rect.end.y
	return result
