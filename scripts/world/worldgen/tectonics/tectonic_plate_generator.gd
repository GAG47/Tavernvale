class_name TectonicPlateGenerator
extends RefCounted

const PLATE_SEED_SALT := 0x504c4154 # "PLAT"
const ANGLE_SALT := 0x414e474c # "ANGL"
const SPEED_SALT := 0x53504544 # "SPED"

static var _last_generation_diagnostics := {}


static func generate(
		graph: SpatialGraph,
		composition: WorldCompositionLayer,
		terrain: TerrainHeightLayer,
		world_seed: int,
		settings: TectonicPlateSettings = null
) -> TectonicPlateLayer:
	_last_generation_diagnostics = {}
	var actual_settings := settings if settings != null else TectonicPlateSettings.new()
	if not _inputs_are_valid(graph, composition, terrain, actual_settings):
		return null
	var macro_passes := maxi(1, roundi(actual_settings.macro_radius / graph.spacing))
	var regional_passes := maxi(1, roundi(actual_settings.regional_radius / graph.spacing))
	var macro_height := smooth_values(graph, terrain.terrain_height, macro_passes)
	var regional_height := smooth_values(graph, terrain.terrain_height, regional_passes)
	var terrain_structure := terrain_structure_field(
		graph, macro_height, regional_height
	)
	var anchor_weight := anchor_weight_field(composition, terrain_structure)
	var anchor_cells := _select_anchor_cells(
		graph, anchor_weight, world_seed, actual_settings
	)
	if anchor_cells.size() != actual_settings.plate_count:
		push_error("Tectonic Plate generation could not select every anchor")
		return null
	var plates := TectonicPlateLayer.new()
	plates.plate_id = _partition_plates(
		graph, anchor_cells, terrain_structure, actual_settings.partition_terrain_weight
	)
	plates.plate_velocity = _initial_velocities(world_seed, actual_settings)
	var boundary_pairs := _collect_boundary_pairs(
		graph, plates.plate_id, terrain_structure, actual_settings
	)
	_relax_velocities(plates.plate_velocity, boundary_pairs, actual_settings)
	var validation_errors := TectonicPlateValidator.validate(graph, plates, actual_settings)
	if not validation_errors.is_empty():
		push_error("Tectonic Plate validation failed: " + "; ".join(validation_errors))
		return null
	_last_generation_diagnostics = {
		"anchor_cell_ids": anchor_cells.duplicate(),
		"macro_height": macro_height.duplicate(),
		"regional_height": regional_height.duplicate(),
		"terrain_structure": terrain_structure.duplicate(),
		"macro_passes": macro_passes,
		"regional_passes": regional_passes,
		"boundary_pair_count": boundary_pairs.size(),
	}
	return plates


static func last_generation_diagnostics() -> Dictionary:
	return _last_generation_diagnostics.duplicate(true)


static func smooth_values(
		graph: SpatialGraph, values: PackedFloat32Array, passes: int
) -> PackedFloat32Array:
	var current := values.duplicate()
	for _pass_index in maxi(0, passes):
		var next := PackedFloat32Array()
		next.resize(current.size())
		for cell_id in current.size():
			var weighted_sum := 0.0
			var weight_sum := 0.0
			var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
			var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
			for neighbor_index in neighbors.size():
				var weight := 1.0 / distances[neighbor_index]
				weighted_sum += current[neighbors[neighbor_index]] * weight
				weight_sum += weight
			var neighbor_mean := current[cell_id] if weight_sum <= 0.0 \
					else weighted_sum / weight_sum
			next[cell_id] = 0.50 * current[cell_id] + 0.50 * neighbor_mean
		current = next
	return current


static func terrain_structure_field(
		graph: SpatialGraph,
		macro_height: PackedFloat32Array,
		regional_height: PackedFloat32Array
) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		var highland := smoothstep(15.0, 50.0, macro_height[cell_id])
		var relative_height := maxf(0.0, macro_height[cell_id] - regional_height[cell_id])
		var relative_uplift := smoothstep(6.0, 25.0, relative_height)
		var relief_sum := 0.0
		var relief_weight_sum := 0.0
		var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
		var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
		for neighbor_index in neighbors.size():
			var distance := distances[neighbor_index]
			var weight := 1.0 / distance
			var normalized_delta := absf(
				macro_height[neighbors[neighbor_index]] - macro_height[cell_id]
			) * graph.spacing / distance
			relief_sum += normalized_delta * weight
			relief_weight_sum += weight
		var macro_relief := 0.0 if relief_weight_sum <= 0.0 \
				else relief_sum / relief_weight_sum
		var relief := smoothstep(4.0, 18.0, macro_relief)
		result[cell_id] = clampf(
			1.0 - (1.0 - 0.45 * highland) \
					* (1.0 - 0.80 * relative_uplift) \
					* (1.0 - 0.75 * relief),
			0.0,
			1.0
		)
	return result


static func anchor_weight_field(
		composition: WorldCompositionLayer,
		terrain_structure: PackedFloat32Array
) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(composition.cell_count())
	for cell_id in composition.cell_count():
		var continental_interior := smoothstep(
			4.0, 16.0, absf(float(composition.continental_value[cell_id]) - 20.0)
		)
		result[cell_id] = maxf(
			0.1, 1.0 + 0.35 * continental_interior - 0.35 * terrain_structure[cell_id]
		)
	return result


static func _select_anchor_cells(
		graph: SpatialGraph,
		anchor_weight: PackedFloat32Array,
		world_seed: int,
		settings: TectonicPlateSettings
) -> PackedInt32Array:
	var rng := DeterministicRng.new(
		DeterministicRng.stable_mix(world_seed, PLATE_SEED_SALT)
	)
	var anchors := PackedInt32Array()
	var selected := {}
	var target_spacing := sqrt(
		graph.config.world_width * graph.config.world_height / float(settings.plate_count)
	)
	var minimum_spacing := target_spacing * settings.anchor_min_spacing_factor
	while anchors.size() < settings.plate_count:
		var chosen := -1
		for attempt in settings.anchor_relax_attempts + 1:
			var candidates := _draw_distinct_candidates(
				graph.cell_count(), settings.anchor_candidates_per_plate, selected, rng
			)
			var legal := PackedInt32Array()
			for cell_id in candidates:
				if _meets_anchor_spacing(graph, cell_id, anchors, minimum_spacing):
					legal.append(cell_id)
			if not legal.is_empty():
				chosen = _weighted_candidate(legal, anchor_weight, rng)
				break
			if attempt < settings.anchor_relax_attempts:
				minimum_spacing *= 0.85
		if chosen < 0:
			chosen = _farthest_unselected_cell(graph, anchors, selected)
		if chosen < 0:
			break
		anchors.append(chosen)
		selected[chosen] = true
	return anchors


static func _draw_distinct_candidates(
		cell_count: int, requested: int, excluded: Dictionary, rng: DeterministicRng
) -> PackedInt32Array:
	var available_count := cell_count - excluded.size()
	var target_count := mini(requested, available_count)
	var chosen := {}
	var result := PackedInt32Array()
	while result.size() < target_count:
		var cell_id := mini(floori(rng.next_float() * float(cell_count)), cell_count - 1)
		if excluded.has(cell_id) or chosen.has(cell_id):
			continue
		chosen[cell_id] = true
		result.append(cell_id)
	return result


static func _meets_anchor_spacing(
		graph: SpatialGraph, cell_id: int, anchors: PackedInt32Array, minimum_spacing: float
) -> bool:
	for anchor_id in anchors:
		if graph.cell_centers[cell_id].distance_to(graph.cell_centers[anchor_id]) \
				< minimum_spacing:
			return false
	return true


static func _weighted_candidate(
		candidates: PackedInt32Array,
		anchor_weight: PackedFloat32Array,
		rng: DeterministicRng
) -> int:
	var total_weight := 0.0
	for cell_id in candidates:
		total_weight += anchor_weight[cell_id]
	var target := rng.next_float() * total_weight
	var cumulative := 0.0
	for cell_id in candidates:
		cumulative += anchor_weight[cell_id]
		if target < cumulative:
			return cell_id
	return candidates[-1]


static func _farthest_unselected_cell(
		graph: SpatialGraph, anchors: PackedInt32Array, selected: Dictionary
) -> int:
	var best_cell := -1
	var best_distance := -1.0
	for cell_id in graph.cell_count():
		if selected.has(cell_id):
			continue
		var nearest := INF
		for anchor_id in anchors:
			nearest = minf(
				nearest,
				graph.cell_centers[cell_id].distance_to(graph.cell_centers[anchor_id])
			)
		if nearest > best_distance \
				or (is_equal_approx(nearest, best_distance) and cell_id < best_cell):
			best_distance = nearest
			best_cell = cell_id
	return best_cell


static func _partition_plates(
		graph: SpatialGraph,
		anchors: PackedInt32Array,
		terrain_structure: PackedFloat32Array,
		terrain_weight: float
) -> PackedInt32Array:
	var plate_id := PackedInt32Array()
	plate_id.resize(graph.cell_count())
	plate_id.fill(-1)
	var best_cost := PackedFloat64Array()
	best_cost.resize(graph.cell_count())
	best_cost.fill(INF)
	var heap: Array = []
	var serial := 0
	for id in anchors.size():
		var cell_id := anchors[id]
		plate_id[cell_id] = id
		best_cost[cell_id] = 0.0
		_heap_push(heap, [0.0, id, serial, cell_id])
		serial += 1
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var cost: float = entry[0]
		var id: int = entry[1]
		var cell_id: int = entry[3]
		if cost > best_cost[cell_id] \
				or (cost == best_cost[cell_id] and id != plate_id[cell_id]):
			continue
		var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
		var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
		for neighbor_index in neighbors.size():
			var neighbor_id := neighbors[neighbor_index]
			var structure := 0.5 * (
				terrain_structure[cell_id] + terrain_structure[neighbor_id]
			)
			var next_cost := cost + distances[neighbor_index] \
					* (1.0 + terrain_weight * structure)
			if next_cost < best_cost[neighbor_id] \
					or (next_cost == best_cost[neighbor_id] \
							and (plate_id[neighbor_id] < 0 or id < plate_id[neighbor_id])):
				best_cost[neighbor_id] = next_cost
				plate_id[neighbor_id] = id
				_heap_push(heap, [next_cost, id, serial, neighbor_id])
				serial += 1
	return plate_id


static func _initial_velocities(
		world_seed: int, settings: TectonicPlateSettings
) -> PackedVector2Array:
	var velocities := PackedVector2Array()
	velocities.resize(settings.plate_count)
	for plate_id in settings.plate_count:
		var angle := _random_01(world_seed, plate_id, ANGLE_SALT) * TAU
		var speed := lerpf(
			settings.velocity_min_initial_speed,
			settings.velocity_max_initial_speed,
			_random_01(world_seed, plate_id, SPEED_SALT)
		)
		velocities[plate_id] = Vector2(cos(angle), sin(angle)) * speed
	return velocities


static func _random_01(world_seed: int, plate_id: int, salt: int) -> float:
	var seed := DeterministicRng.stable_mix(
		DeterministicRng.stable_mix(world_seed, salt), plate_id
	)
	return DeterministicRng.new(seed).next_float()


static func _collect_boundary_pairs(
		graph: SpatialGraph,
		plate_id: PackedInt32Array,
		terrain_structure: PackedFloat32Array,
		settings: TectonicPlateSettings
) -> Array:
	var accumulated := {}
	for cell_id in graph.cell_count():
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if neighbor_id <= cell_id or plate_id[cell_id] == plate_id[neighbor_id]:
				continue
			var plate_a := mini(plate_id[cell_id], plate_id[neighbor_id])
			var plate_b := maxi(plate_id[cell_id], plate_id[neighbor_id])
			var cell_a: int = cell_id if plate_id[cell_id] == plate_a else neighbor_id
			var cell_b: int = neighbor_id if cell_a == cell_id else cell_id
			var structure := 0.5 * (
				terrain_structure[cell_a] + terrain_structure[cell_b]
			)
			if structure < settings.velocity_boundary_threshold:
				continue
			var direction := graph.cell_centers[cell_b] - graph.cell_centers[cell_a]
			if direction.length() <= 0.000001:
				continue
			var weight := structure * structure
			var key := plate_a * settings.plate_count + plate_b
			if not accumulated.has(key):
				accumulated[key] = {
					"plate_a": plate_a, "plate_b": plate_b,
					"normal_sum": Vector2.ZERO, "strength_sum": 0.0, "weight_sum": 0.0,
				}
			accumulated[key].normal_sum += direction.normalized() * weight
			accumulated[key].strength_sum += structure * weight
			accumulated[key].weight_sum += weight
	var result: Array = []
	var keys := accumulated.keys()
	keys.sort()
	for key in keys:
		var pair: Dictionary = accumulated[key]
		var normal_sum: Vector2 = pair.normal_sum
		var weight_sum: float = pair.weight_sum
		if weight_sum <= 0.0 or normal_sum.length() <= 0.000001:
			continue
		result.append({
			"plate_a": pair.plate_a,
			"plate_b": pair.plate_b,
			"normal": normal_sum.normalized(),
			"strength": pair.strength_sum / weight_sum,
		})
	return result


static func _relax_velocities(
		velocities: PackedVector2Array,
		boundary_pairs: Array,
		settings: TectonicPlateSettings
) -> void:
	for _iteration in settings.velocity_relaxation_iterations:
		var correction := PackedVector2Array()
		correction.resize(velocities.size())
		for pair in boundary_pairs:
			var plate_a: int = pair.plate_a
			var plate_b: int = pair.plate_b
			var normal: Vector2 = pair.normal
			var strength: float = pair.strength
			var relative_normal_speed := (velocities[plate_b] - velocities[plate_a]).dot(normal)
			var target_relative_normal := -settings.velocity_target_convergence * strength
			if relative_normal_speed <= target_relative_normal:
				continue
			var error := relative_normal_speed - target_relative_normal
			var delta := 0.5 * settings.velocity_correction_factor * strength * error
			correction[plate_a] += normal * delta
			correction[plate_b] -= normal * delta
		for plate_id in velocities.size():
			velocities[plate_id] += correction[plate_id]
			var speed := velocities[plate_id].length()
			if speed > 0.000001:
				velocities[plate_id] = velocities[plate_id] / speed * clampf(
					speed, settings.velocity_min_final_speed, settings.velocity_max_final_speed
				)


static func _inputs_are_valid(
		graph: SpatialGraph,
		composition: WorldCompositionLayer,
		terrain: TerrainHeightLayer,
		settings: TectonicPlateSettings
) -> bool:
	if graph == null or composition == null or terrain == null or graph.config == null:
		push_error("Tectonic Plate generation requires Spatial, Composition, and Terrain")
		return false
	var settings_errors := settings.validate()
	if not settings_errors.is_empty():
		push_error("Invalid TectonicPlateSettings: " + "; ".join(settings_errors))
		return false
	var count := graph.cell_count()
	if count < settings.plate_count or composition.cell_count() != count \
			or terrain.cell_count() != count:
		push_error("Tectonic Plate inputs must align and contain at least one Cell per plate")
		return false
	if not is_finite(graph.spacing) or graph.spacing <= 0.0 \
			or not is_finite(graph.config.world_width) or graph.config.world_width <= 0.0 \
			or not is_finite(graph.config.world_height) or graph.config.world_height <= 0.0:
		push_error("Tectonic Plate generation requires positive finite world dimensions and spacing")
		return false
	if graph.cell_centers.size() != count or graph.cell_neighbors.size() != count \
			or graph.cell_neighbor_distances.size() != count:
		push_error("Tectonic Plate Spatial arrays must contain one entry per Cell")
		return false
	for cell_id in count:
		if not is_finite(graph.cell_centers[cell_id].x) \
				or not is_finite(graph.cell_centers[cell_id].y) \
				or not is_finite(terrain.terrain_height[cell_id]) \
				or composition.continental_value[cell_id] < 0 \
				or composition.continental_value[cell_id] > 100:
			push_error("Tectonic Plate Cell values must be finite and Composition inside [0, 100]")
			return false
		if graph.cell_neighbors[cell_id].size() != graph.cell_neighbor_distances[cell_id].size():
			push_error("Tectonic Plate neighbor distances must align with neighbors")
			return false
		for distance in graph.cell_neighbor_distances[cell_id]:
			if not is_finite(distance) or distance <= 0.0:
				push_error("Tectonic Plate neighbor distances must be finite and positive")
				return false
	return true


static func _heap_push(heap: Array, value: Array) -> void:
	heap.append(value)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) >> 1
		if not _heap_less(value, heap[parent]):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = value


static func _heap_pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var tail: Array = heap.pop_back()
	if heap.is_empty():
		return result
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var child := left
		if right < heap.size() and _heap_less(heap[right], heap[left]):
			child = right
		if not _heap_less(heap[child], tail):
			break
		heap[index] = heap[child]
		index = child
	heap[index] = tail
	return result


static func _heap_less(first: Array, second: Array) -> bool:
	if first[0] != second[0]:
		return first[0] < second[0]
	if first[1] != second[1]:
		return first[1] < second[1]
	return first[2] < second[2]
