class_name RockRegionAssigner
extends RefCounted

const ROCK_REGION_TARGET_CELLS_PER_SEED := 180
const MAX_ROCK_REGION_SEEDS_PER_COMPONENT := 96
const ROCK_REGION_SALT := 0x5245474e # "REGN"


static func assign_seed_cells(
		graph: SpatialGraph, province_id: PackedInt32Array, world_seed: int
) -> PackedInt32Array:
	if graph == null or graph.cell_count() <= 0 \
			or graph.cell_centers.size() != graph.cell_count() \
			or graph.cell_neighbors.size() != graph.cell_count() \
			or graph.cell_neighbor_distances.size() != graph.cell_count() \
			or province_id.size() != graph.cell_count():
		push_error("RockRegionAssigner requires complete SpatialGraph and Province inputs")
		return PackedInt32Array()
	var result := PackedInt32Array()
	result.resize(graph.cell_count())
	result.fill(-1)
	var components := _components_by_province(graph, province_id)
	var seed := DeterministicRng.stable_mix(world_seed, ROCK_REGION_SALT)
	for component_id in components.components.size():
		var cells: PackedInt32Array = components.components[component_id]
		var region_count := clampi(
			ceili(float(cells.size()) / float(ROCK_REGION_TARGET_CELLS_PER_SEED)),
			1,
			mini(MAX_ROCK_REGION_SEEDS_PER_COMPONENT, cells.size())
		)
		var seeds: Array = []
		var nearest_distance_squared := {}
		for region_index in region_count:
			var seed_cell_id := _choose_rock_region_seed(
				graph,
				cells,
				nearest_distance_squared,
				region_index == 0,
				seed,
				component_id * 137 + region_index
			)
			seeds.append(seed_cell_id)
			for candidate_id in cells:
				var distance_squared := graph.cell_centers[candidate_id].distance_squared_to(
					graph.cell_centers[seed_cell_id]
				)
				nearest_distance_squared[candidate_id] = minf(
					distance_squared,
					float(nearest_distance_squared.get(candidate_id, INF))
				)
		_expand_component(
			graph,
			seeds,
			component_id,
			components.component_by_cell,
			seed,
			result
		)
	return result


static func _components_by_province(
		graph: SpatialGraph, province_id: PackedInt32Array
) -> Dictionary:
	var component_by_cell := PackedInt32Array()
	component_by_cell.resize(graph.cell_count())
	component_by_cell.fill(-1)
	var components: Array = []
	for seed_id in graph.cell_count():
		if component_by_cell[seed_id] >= 0:
			continue
		var component_id := components.size()
		var cells := PackedInt32Array([seed_id])
		component_by_cell[seed_id] = component_id
		var queue_index := 0
		while queue_index < cells.size():
			var cell_id := cells[queue_index]
			queue_index += 1
			for neighbor_id in graph.cell_neighbors[cell_id]:
				if component_by_cell[neighbor_id] < 0 \
						and province_id[neighbor_id] == province_id[seed_id]:
					component_by_cell[neighbor_id] = component_id
					cells.append(neighbor_id)
		components.append(cells)
	return {"components": components, "component_by_cell": component_by_cell}


static func _choose_rock_region_seed(
		graph: SpatialGraph,
		cells: PackedInt32Array,
		nearest_distance_squared: Dictionary,
		first_seed: bool,
		seed: int,
		salt: int
) -> int:
	var best_cell := cells[0]
	var best_score := -INF
	for cell_id in cells:
		var minimum_distance := float(nearest_distance_squared.get(cell_id, INF))
		if minimum_distance <= 0.0:
			continue
		var random_factor := _unit_value(seed, cell_id, salt)
		var score: float = random_factor if first_seed \
				else minimum_distance * (0.92 + random_factor * 0.16)
		if score > best_score or (is_equal_approx(score, best_score) and cell_id < best_cell):
			best_score = score
			best_cell = cell_id
	return best_cell


static func _expand_component(
		graph: SpatialGraph,
		seeds: Array,
		component_id: int,
		component_by_cell: PackedInt32Array,
		seed: int,
		output: PackedInt32Array
) -> void:
	var best_cost := {}
	var heap: Array = []
	var serial := 0
	for seed_cell_id in seeds:
		best_cost[seed_cell_id] = 0.0
		output[seed_cell_id] = seed_cell_id
		_heap_push(heap, [0.0, serial, seed_cell_id, seed_cell_id])
		serial += 1
	var distance_scale := _distance_scale(graph)
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var cost: float = entry[0]
		var cell_id: int = entry[2]
		var seed_cell_id: int = entry[3]
		if cost > float(best_cost[cell_id]) or output[cell_id] != seed_cell_id:
			continue
		var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
		var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
		for neighbor_index in neighbors.size():
			var neighbor_id := neighbors[neighbor_index]
			if component_by_cell[neighbor_id] != component_id:
				continue
			var variation := lerpf(
				0.90,
				1.10,
				_unit_value(
					seed,
					mini(cell_id, neighbor_id),
					maxi(cell_id, neighbor_id) + seed_cell_id * 193
				)
			)
			var next_cost := cost + distances[neighbor_index] / distance_scale * variation
			if next_cost < float(best_cost.get(neighbor_id, INF)):
				best_cost[neighbor_id] = next_cost
				output[neighbor_id] = seed_cell_id
				_heap_push(heap, [next_cost, serial, neighbor_id, seed_cell_id])
				serial += 1


static func _distance_scale(graph: SpatialGraph) -> float:
	if graph.spacing > 0.0:
		return graph.spacing
	return maxf(
		sqrt(graph.config.world_width * graph.config.world_height / float(graph.cell_count())),
		0.000001
	)


static func _unit_value(seed: int, first: int, second: int) -> float:
	var mixed := DeterministicRng.stable_mix(seed, first + 0x1f123bb5)
	mixed = DeterministicRng.stable_mix(mixed, second + 0x5f356495)
	return float(mixed) / 2147483648.0


static func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) >> 1
		if not _heap_less(entry, heap[parent]):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = entry


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
	if float(first[0]) != float(second[0]):
		return float(first[0]) < float(second[0])
	return int(first[1]) < int(second[1])
