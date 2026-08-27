class_name CompositionOperations
extends RefCounted

const COMPOSITION_LAND_REFERENCE := 20
const _MAX_START_ATTEMPTS := 50

var graph: SpatialGraph
var continental_value: PackedInt32Array
var rng: CompositionRng
var blob_power: float
var line_power: float


func _init(
		spatial_graph: SpatialGraph,
		values: PackedInt32Array,
		composition_rng: CompositionRng
) -> void:
	graph = spatial_graph
	continental_value = values
	rng = composition_rng
	blob_power = get_blob_power(graph.cell_count())
	line_power = get_line_power(graph.cell_count())


static func get_blob_power(cell_count: int) -> float:
	return {
		1000: 0.93,
		2000: 0.95,
		5000: 0.97,
		10000: 0.98,
		20000: 0.99,
		30000: 0.991,
		40000: 0.993,
		50000: 0.994,
		60000: 0.995,
		70000: 0.9955,
		80000: 0.996,
		90000: 0.9964,
		100000: 0.9973,
	}.get(cell_count, 0.98)


static func get_line_power(cell_count: int) -> float:
	return {
		1000: 0.75,
		2000: 0.77,
		5000: 0.79,
		10000: 0.81,
		20000: 0.82,
		30000: 0.83,
		40000: 0.84,
		50000: 0.86,
		60000: 0.87,
		70000: 0.88,
		80000: 0.91,
		90000: 0.92,
		100000: 0.93,
	}.get(cell_count, 0.81)


static func uint8_value(value: float) -> int:
	# Uint8Array-style write for the v1.1 0..100 domain: clamp first, then
	# truncate the non-negative fractional part rather than rounding it.
	return int(clampf(value, 0.0, 100.0))


func execute(operation: Dictionary) -> Dictionary:
	var operation_type := StringName(operation.get("type", &""))
	var metadata: Dictionary
	match operation_type:
		&"Hill":
			metadata = add_hill(operation)
		&"Pit":
			metadata = add_pit(operation)
		&"Range":
			metadata = add_range(operation)
		&"Trough":
			metadata = add_trough(operation)
		&"Strait":
			metadata = add_strait(operation)
		&"Multiply":
			metadata = multiply(operation)
		&"Smooth":
			metadata = smooth(operation)
		&"Mask":
			metadata = mask(operation)
		_:
			metadata = {"success": false, "error": "unsupported operation: " + String(operation_type)}
	metadata["type"] = operation_type
	return metadata


func add_hill(operation: Dictionary) -> Dictionary:
	var instances: Array[Dictionary] = []
	var desired_count := _number_in_range(String(operation["count"]))
	for _hill_index in desired_count:
		var strength := uint8_value(float(_number_in_range(String(operation["strength"]))))
		var start := -1
		var attempts := 0
		while attempts < _MAX_START_ATTEMPTS:
			start = _random_cell_in_ranges(String(operation["range_x"]), String(operation["range_y"]))
			attempts += 1
			if continental_value[start] + strength <= 90:
				break

		var change := PackedInt32Array()
		change.resize(graph.cell_count())
		change[start] = strength
		var queue := PackedInt32Array([start])
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			for neighbor_id in graph.cell_neighbors[current]:
				if change[neighbor_id] != 0:
					continue
				change[neighbor_id] = uint8_value(
					pow(float(change[current]), blob_power) * rng.range_float(0.9, 1.1)
				)
				if change[neighbor_id] > 1:
					queue.append(neighbor_id)

		var changed_cells := 0
		for cell_id in graph.cell_count():
			if change[cell_id] > 0:
				changed_cells += 1
			continental_value[cell_id] = uint8_value(
				float(continental_value[cell_id] + change[cell_id])
			)
		instances.append({
			"start": start,
			"strength": strength,
			"start_attempts": attempts,
			"changed_cells": changed_cells,
		})
	return {
		"success": true,
		"algorithm": &"change_array_neighbor_propagation",
		"instances": instances,
	}


func add_pit(operation: Dictionary) -> Dictionary:
	var instances: Array[Dictionary] = []
	var desired_count := _number_in_range(String(operation["count"]))
	for _pit_index in desired_count:
		var used := PackedByteArray()
		used.resize(graph.cell_count())
		var strength := uint8_value(float(_number_in_range(String(operation["strength"]))))
		var height := float(strength)
		var start := -1
		var attempts := 0
		while attempts < _MAX_START_ATTEMPTS:
			start = _random_cell_in_ranges(String(operation["range_x"]), String(operation["range_y"]))
			attempts += 1
			if continental_value[start] >= COMPOSITION_LAND_REFERENCE:
				break

		var queue := PackedInt32Array([start])
		var head := 0
		var changed_cells := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			height = pow(height, blob_power) * rng.range_float(0.9, 1.1)
			if height < 1.0:
				break
			for neighbor_id in graph.cell_neighbors[current]:
				if used[neighbor_id]:
					continue
				continental_value[neighbor_id] = uint8_value(
					float(continental_value[neighbor_id]) - height * rng.range_float(0.9, 1.1)
				)
				used[neighbor_id] = 1
				changed_cells += 1
				queue.append(neighbor_id)
		instances.append({
			"start": start,
			"strength": strength,
			"start_attempts": attempts,
			"changed_cells": changed_cells,
		})
	return {
		"success": true,
		"algorithm": &"shared_h_neighbor_queue",
		"instances": instances,
	}


func add_range(operation: Dictionary) -> Dictionary:
	return _add_wandering_feature(operation, false)


func add_trough(operation: Dictionary) -> Dictionary:
	return _add_wandering_feature(operation, true)


func _add_wandering_feature(operation: Dictionary, is_trough: bool) -> Dictionary:
	var randomness := 0.2 if is_trough else 0.15
	var instances: Array[Dictionary] = []
	var desired_count := _number_in_range(String(operation["count"]))
	for _feature_index in desired_count:
		var used := PackedByteArray()
		used.resize(graph.cell_count())
		var strength := uint8_value(float(_number_in_range(String(operation["strength"]))))
		var height := float(strength)
		var start_point := Vector2.ZERO
		var start := -1
		var start_attempts := 0
		while start_attempts < _MAX_START_ATTEMPTS:
			start_point = Vector2(
				_random_coordinate(String(operation["range_x"]), graph.config.world_width),
				_random_coordinate(String(operation["range_y"]), graph.config.world_height)
			)
			start = _nearest_cell(start_point)
			start_attempts += 1
			if not is_trough or continental_value[start] >= COMPOSITION_LAND_REFERENCE:
				break

		var endpoint := _choose_wandering_endpoint(start_point, is_trough)
		var end := _nearest_cell(endpoint.point)
		var path := _build_wandering_path(start, end, used, randomness, true)
		var expansion_iterations := 0
		var queue := path.duplicate()
		while not queue.is_empty():
			var frontier := queue.duplicate()
			queue = PackedInt32Array()
			expansion_iterations += 1
			for cell_id in frontier:
				var delta := height * rng.range_float(0.85, 1.15)
				if is_trough:
					continental_value[cell_id] = uint8_value(
						float(continental_value[cell_id]) - delta
					)
				else:
					continental_value[cell_id] = uint8_value(
						float(continental_value[cell_id]) + delta
					)
			height = pow(height, line_power) - 1.0
			if height < 2.0:
				break
			for cell_id in frontier:
				for neighbor_id in graph.cell_neighbors[cell_id]:
					if used[neighbor_id]:
						continue
					queue.append(neighbor_id)
					used[neighbor_id] = 1

		var prominence_writes := _apply_prominence(path, expansion_iterations)
		instances.append({
			"start": start,
			"end": end,
			"start_attempts": start_attempts,
			"end_attempts": endpoint.attempts,
			"path": path,
			"path_continuous": _path_is_continuous(path, start),
			"expansion_iterations": expansion_iterations,
			"prominence_writes": prominence_writes,
			"strength": strength,
		})
	return {
		"success": true,
		"algorithm": &"wandering_neighbor_path",
		"wandering_bias": randomness,
		"prominence_executed": true,
		"instances": instances,
	}


func add_strait(operation: Dictionary) -> Dictionary:
	var requested_width := _number_in_range(String(operation["width"]))
	var desired_width := minf(float(requested_width), float(graph.columns) / 3.0)
	if desired_width < 1.0 and rng.chance(desired_width):
		return {
			"success": true,
			"algorithm": &"wandering_neighbor_path_query_width",
			"requested_width": requested_width,
			"desired_width": desired_width,
			"width_iterations": 0,
			"path": PackedInt32Array(),
			"skipped": true,
		}

	var vertical := StringName(operation.get("direction", &"vertical")) == &"vertical"
	var world_width := graph.config.world_width
	var world_height := graph.config.world_height
	var start_x := floorf(rng.range_float(world_width * 0.3, world_width * 0.7)) if vertical else 5.0
	var start_y := 5.0 if vertical else floorf(rng.range_float(world_height * 0.3, world_height * 0.7))
	var end_x := (
		floorf(world_width - start_x - world_width * 0.1 + rng.next_float() * world_width * 0.2)
		if vertical else world_width - 5.0
	)
	var end_y := (
		world_height - 5.0
		if vertical else floorf(world_height - start_y - world_height * 0.1 + rng.next_float() * world_height * 0.2)
	)
	var start := _nearest_cell(Vector2(start_x, start_y))
	var end := _nearest_cell(Vector2(end_x, end_y))
	var path_result := _build_strait_path(start, end)
	var path: PackedInt32Array = path_result.path
	if not path_result.success:
		return {
			"success": false,
			"error": path_result.error,
			"algorithm": &"wandering_neighbor_path_query_width",
			"path": path,
		}

	var used := PackedByteArray()
	used.resize(graph.cell_count())
	var query := PackedInt32Array()
	var step := 0.1 / desired_width
	var width_iterations := 0
	var query_sizes := PackedInt32Array()
	var added_per_iteration := PackedInt32Array()
	while float(width_iterations) < desired_width:
		var remaining_width := desired_width - float(width_iterations)
		var exponent := 0.9 - step * remaining_width
		var size_before := query.size()
		for path_cell in path:
			for neighbor_id in graph.cell_neighbors[path_cell]:
				if used[neighbor_id]:
					continue
				used[neighbor_id] = 1
				query.append(neighbor_id)
				continental_value[neighbor_id] = uint8_value(
					pow(float(continental_value[neighbor_id]), exponent)
				)
		added_per_iteration.append(query.size() - size_before)
		query_sizes.append(query.size())
		path = query.duplicate()
		width_iterations += 1

	return {
		"success": true,
		"algorithm": &"wandering_neighbor_path_query_width",
		"requested_width": requested_width,
		"desired_width": desired_width,
		"width_iterations": width_iterations,
		"query_sizes": query_sizes,
		"added_per_iteration": added_per_iteration,
		"path": path_result.path,
		"path_continuous": _path_is_continuous(path_result.path, start),
		"start": start,
		"end": end,
	}


func multiply(operation: Dictionary) -> Dictionary:
	if StringName(operation.get("target", &"")) != &"land":
		return {"success": false, "error": "v1.1 Multiply only supports the land reference range"}
	var factor := float(operation["factor"])
	var changed_cells := 0
	for cell_id in graph.cell_count():
		var value := continental_value[cell_id]
		if value < COMPOSITION_LAND_REFERENCE:
			continue
		continental_value[cell_id] = uint8_value(
			float(value - COMPOSITION_LAND_REFERENCE) * factor + COMPOSITION_LAND_REFERENCE
		)
		changed_cells += 1
	return {
		"success": true,
		"reference": COMPOSITION_LAND_REFERENCE,
		"changed_cells": changed_cells,
	}


func smooth(operation: Dictionary) -> Dictionary:
	var factor := float(operation.get("factor", 2))
	if factor <= 0.0:
		return {"success": false, "error": "Smooth factor must be greater than zero"}
	var old_values := continental_value.duplicate()
	var new_values := PackedInt32Array()
	new_values.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		var sum := float(old_values[cell_id])
		for neighbor_id in graph.cell_neighbors[cell_id]:
			sum += old_values[neighbor_id]
		var mean := sum / float(graph.cell_neighbors[cell_id].size() + 1)
		var value := mean if factor == 1.0 else (
			(float(old_values[cell_id]) * (factor - 1.0) + mean) / factor
		)
		new_values[cell_id] = uint8_value(value)
	continental_value = new_values
	return {"success": true, "simultaneous": true, "factor": factor}


func mask(operation: Dictionary) -> Dictionary:
	var power := float(operation.get("power", 1.0))
	var factor := absf(power) if power != 0.0 else 1.0
	var world_width := graph.config.world_width
	var world_height := graph.config.world_height
	for cell_id in graph.cell_count():
		var center := graph.cell_centers[cell_id]
		var normalized_x := 2.0 * center.x / world_width - 1.0
		var normalized_y := 2.0 * center.y / world_height - 1.0
		var distance := (1.0 - pow(normalized_x, 2.0)) * (1.0 - pow(normalized_y, 2.0))
		if power < 0.0:
			distance = 1.0 - distance
		var value := float(continental_value[cell_id])
		var masked := value * distance
		continental_value[cell_id] = uint8_value(
			(value * (factor - 1.0) + masked) / factor
		)
	return {"success": true, "power": power}


func _apply_prominence(path: PackedInt32Array, iterations: int) -> int:
	var writes := 0
	for path_index in path.size():
		if path_index % 6 != 0:
			continue
		var current := path[path_index]
		for _iteration in iterations:
			var neighbors: PackedInt32Array = graph.cell_neighbors[current]
			if neighbors.is_empty():
				continue
			var lowest := neighbors[0]
			for neighbor_id in neighbors:
				if continental_value[neighbor_id] < continental_value[lowest]:
					lowest = neighbor_id
			continental_value[lowest] = uint8_value(
				(float(continental_value[current]) * 2.0 + continental_value[lowest]) / 3.0
			)
			current = lowest
			writes += 1
	return writes


func _build_wandering_path(
		start: int,
		end: int,
		used: PackedByteArray,
		wandering_bias: float,
		exclude_used: bool
) -> PackedInt32Array:
	var path := PackedInt32Array([start])
	used[start] = 1
	var current := start
	while current != end:
		var chosen := -1
		var minimum_difference := INF
		for neighbor_id in graph.cell_neighbors[current]:
			if exclude_used and used[neighbor_id]:
				continue
			var difference := graph.cell_centers[neighbor_id].distance_squared_to(
				graph.cell_centers[end]
			)
			if rng.chance(wandering_bias):
				difference /= 2.0
			if difference < minimum_difference:
				minimum_difference = difference
				chosen = neighbor_id
		if chosen < 0:
			break
		current = chosen
		path.append(current)
		used[current] = 1
	return path


func _build_strait_path(start: int, end: int) -> Dictionary:
	var path := PackedInt32Array()
	var current := start
	var steps := 0
	var step_guard := maxi(graph.cell_count() * 20, 1000)
	while current != end:
		var chosen := -1
		var minimum_difference := INF
		for neighbor_id in graph.cell_neighbors[current]:
			var difference := graph.cell_centers[neighbor_id].distance_squared_to(
				graph.cell_centers[end]
			)
			if rng.chance(0.2):
				difference /= 2.0
			if difference < minimum_difference:
				minimum_difference = difference
				chosen = neighbor_id
		if chosen < 0:
			return {"success": false, "error": "Strait path reached a cell without neighbors", "path": path}
		current = chosen
		path.append(current)
		steps += 1
		if steps > step_guard:
			return {"success": false, "error": "Strait path exceeded its safety step guard", "path": path}
	return {"success": true, "path": path}


func _choose_wandering_endpoint(start_point: Vector2, is_trough: bool) -> Dictionary:
	var maximum_distance := graph.config.world_width / (2.0 if is_trough else 3.0)
	var endpoint := Vector2.ZERO
	var attempts := 0
	while attempts < _MAX_START_ATTEMPTS:
		endpoint = Vector2(
			rng.range_float(graph.config.world_width * 0.1, graph.config.world_width * 0.9),
			rng.range_float(graph.config.world_height * 0.15, graph.config.world_height * 0.85)
		)
		attempts += 1
		var distance := absf(endpoint.x - start_point.x) + absf(endpoint.y - start_point.y)
		if distance >= graph.config.world_width / 8.0 and distance <= maximum_distance:
			break
	return {"point": endpoint, "attempts": attempts}


func _path_is_continuous(path: PackedInt32Array, initial_cell: int) -> bool:
	var previous := initial_cell
	for cell_id in path:
		if cell_id == previous:
			continue
		if not graph.cell_neighbors[previous].has(cell_id):
			return false
		previous = cell_id
	return true


func _random_cell_in_ranges(range_x: String, range_y: String) -> int:
	return _nearest_cell(Vector2(
		_random_coordinate(range_x, graph.config.world_width),
		_random_coordinate(range_y, graph.config.world_height)
	))


func _random_coordinate(range_spec: String, length: float) -> float:
	var limits := _parse_range(range_spec)
	var minimum := limits.x / 100.0 * length
	var maximum := limits.y / 100.0 * length
	# Azgaar's rand is inclusive and floors the random span before adding min.
	return floorf(rng.next_float() * (maximum - minimum + 1.0)) + minimum


func _nearest_cell(point: Vector2) -> int:
	var nearest := 0
	var nearest_distance := INF
	for cell_id in graph.cell_count():
		var distance := point.distance_squared_to(graph.cell_centers[cell_id])
		if distance < nearest_distance:
			nearest = cell_id
			nearest_distance = distance
	return nearest


func _number_in_range(range_spec: String) -> int:
	if range_spec.is_valid_float():
		var value := range_spec.to_float()
		var integer_part := int(value)
		return integer_part + int(rng.chance(value - float(integer_part)))
	var limits := _parse_range(range_spec)
	return rng.range_int(int(limits.x), int(limits.y))


func _parse_range(range_spec: String) -> Vector2:
	var separator := range_spec.find("-", 1)
	if separator < 0:
		var single := range_spec.to_float()
		return Vector2(single, single)
	return Vector2(
		range_spec.left(separator).to_float(),
		range_spec.substr(separator + 1).to_float()
	)
