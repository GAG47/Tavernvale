class_name GeologyGenerator
extends RefCounted

const PROVINCE_TARGET_CELLS_PER_SEED := 800
const MAX_PROVINCE_SEEDS_PER_COMPONENT := 32
const CONTINENTAL_PROVINCE_SUPPORT_THRESHOLD := 14
const PROVINCE_BASE_PRIOR := [0.0, 0.30, 0.25, 0.25, 0.15, 0.05]

const _MASK := 0x7fffffff
const _GEOLOGY_SALT := 0x47454f4c # "GEOL"


static func generate(
		graph: SpatialGraph,
		composition: WorldCompositionLayer,
		terrain: TerrainHeightLayer
) -> GeologyLayer:
	if not _inputs_are_valid(graph, composition, terrain):
		return null
	var rules_errors := RockLayerRules.validate_rules()
	if not rules_errors.is_empty():
		push_error("Invalid Rock Layer rules: " + "; ".join(rules_errors))
		return null
	var geology := GeologyLayer.new()
	var count := graph.cell_count()
	geology.province_id.resize(count)
	geology.province_id.fill(GeologyCatalog.Province.OCEANIC_CRUST)
	geology.rock_type_id.resize(count)
	geology.rock_type_id.fill(-1)
	geology.permeability.resize(count)
	geology.erodibility.resize(count)
	var seed := _geology_seed(graph.config.seed)
	var suitability := _province_suitability(graph, terrain)
	var coast_steps := _coast_steps(graph, terrain)
	var support_components := _components_by_continental_support(graph, composition)
	for component_id in support_components.components.size():
		var support_cells: PackedInt32Array = support_components.components[component_id]
		var land_cells := PackedInt32Array()
		for cell_id in support_cells:
			if terrain.terrain_height[cell_id] >= 0.0:
				land_cells.append(cell_id)
		if land_cells.is_empty():
			continue
		_assign_province_component(
			graph,
			terrain,
			land_cells,
			component_id,
			support_components.component_by_cell,
			suitability,
			coast_steps,
			seed,
			geology.province_id
		)

	var rock_region_seed_cells := RockRegionAssigner.assign_seed_cells(
		graph, geology.province_id, graph.config.seed
	)
	if rock_region_seed_cells.size() != count:
		return null
	var surface_rock_by_region := {}
	for cell_id in count:
		var region_seed_cell_id := rock_region_seed_cells[cell_id]
		if not surface_rock_by_region.has(region_seed_cell_id):
			surface_rock_by_region[region_seed_cell_id] = RockLayerRules.surface_rock_for(
				geology.province_id[cell_id], graph.config.seed, region_seed_cell_id
			)
		geology.rock_type_id[cell_id] = surface_rock_by_region[region_seed_cell_id]
		geology.permeability[cell_id] = RockCatalog.permeability_for(
			geology.rock_type_id[cell_id]
		)
		geology.erodibility[cell_id] = RockCatalog.erodibility_for(
			geology.rock_type_id[cell_id]
		)
	var validation_errors := GeologyValidator.validate(graph, composition, terrain, geology)
	if not validation_errors.is_empty():
		push_error("Geology generation failed validation: " + "; ".join(validation_errors))
		return null
	return geology


static func _inputs_are_valid(
		graph: SpatialGraph,
		composition: WorldCompositionLayer,
		terrain: TerrainHeightLayer
) -> bool:
	if graph == null or composition == null or terrain == null or graph.config == null:
		push_error("GeologyGenerator requires Spatial, Composition, and projected terrain inputs")
		return false
	var count := graph.cell_count()
	if count == 0 or composition.cell_count() != count or terrain.cell_count() != count:
		push_error("GeologyGenerator inputs must contain the same non-zero Cell Count")
		return false
	if graph.cell_neighbors.size() != count \
			or graph.cell_neighbor_distances.size() != count \
			or graph.cell_centers.size() != count:
		push_error("GeologyGenerator requires neighbors, distances, and centers for every Cell")
		return false
	for cell_id in count:
		if graph.cell_neighbor_distances[cell_id].size() != graph.cell_neighbors[cell_id].size():
			push_error("GeologyGenerator neighbor distances must align with Cell neighbors")
			return false
		if not is_finite(terrain.terrain_height[cell_id]) \
				or terrain.terrain_height[cell_id] < -100.0 \
				or terrain.terrain_height[cell_id] > 100.0:
			push_error("GeologyGenerator terrain_height must be finite and inside [-100, 100]")
			return false
		if composition.continental_value[cell_id] < 0 \
				or composition.continental_value[cell_id] > 100:
			push_error("GeologyGenerator continental_value must be inside [0, 100]")
			return false
	return true


static func _province_suitability(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer
) -> Array:
	var fields: Array = []
	fields.resize(GeologyCatalog.PROVINCE_COUNT)
	for province_id in GeologyCatalog.PROVINCE_COUNT:
		var values := PackedFloat32Array()
		values.resize(graph.cell_count())
		fields[province_id] = values
	var coast_steps := _coast_steps(graph, terrain)
	for cell_id in graph.cell_count():
		var height := terrain.terrain_height[cell_id]
		if height < 0.0:
			continue
		var minimum_neighbor_height := height
		var maximum_neighbor_height := height
		var neighbor_height_sum := 0.0
		var land_neighbor_count := 0
		for neighbor_id in graph.cell_neighbors[cell_id]:
			var neighbor_height := terrain.terrain_height[neighbor_id]
			if neighbor_height < 0.0:
				continue
			minimum_neighbor_height = minf(minimum_neighbor_height, neighbor_height)
			maximum_neighbor_height = maxf(maximum_neighbor_height, neighbor_height)
			neighbor_height_sum += neighbor_height
			land_neighbor_count += 1
		var neighbor_mean := height if land_neighbor_count == 0 \
				else neighbor_height_sum / float(land_neighbor_count)
		var relief := clampf((maximum_neighbor_height - minimum_neighbor_height) / 30.0, 0.0, 1.0)
		var smoothness := 1.0 - relief
		var normalized_height := clampf(height / 100.0, 0.0, 1.0)
		var relative_low := clampf(0.5 + (neighbor_mean - height) / 30.0, 0.0, 1.0)
		var interior := 1.0 if coast_steps[cell_id] < 0 \
				else clampf(float(coast_steps[cell_id]) / 8.0, 0.0, 1.0)
		var coast_proximity := 1.0 - interior
		fields[GeologyCatalog.Province.CRATON][cell_id] = clampf(
			0.25 + 0.35 * interior + 0.25 * smoothness + 0.15 * (1.0 - normalized_height),
			0.0,
			1.0
		)
		fields[GeologyCatalog.Province.OROGENIC_BELT][cell_id] = clampf(
			0.05 + 0.45 * normalized_height + 0.40 * relief + 0.10 * interior,
			0.0,
			1.0
		)
		fields[GeologyCatalog.Province.SEDIMENTARY_BASIN][cell_id] = clampf(
			0.10 + 0.25 * interior + 0.30 * smoothness \
			+ 0.20 * (1.0 - normalized_height) + 0.15 * relative_low,
			0.0,
			1.0
		)
		fields[GeologyCatalog.Province.PASSIVE_MARGIN][cell_id] = clampf(
			0.05 + 0.55 * coast_proximity + 0.25 * smoothness \
			+ 0.15 * (1.0 - normalized_height),
			0.0,
			1.0
		)
		var orogenic_suitability: float = fields[
			GeologyCatalog.Province.OROGENIC_BELT
		][cell_id]
		fields[GeologyCatalog.Province.VOLCANIC_PROVINCE][cell_id] = clampf(
			0.05 + 0.55 * orogenic_suitability + 0.25 * coast_proximity \
			+ 0.15 * normalized_height,
			0.0,
			1.0
		)
	return fields


static func _coast_steps(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer
) -> PackedInt32Array:
	var steps := PackedInt32Array()
	steps.resize(graph.cell_count())
	steps.fill(-1)
	var queue := PackedInt32Array()
	for cell_id in graph.cell_count():
		if terrain.terrain_height[cell_id] < 0.0:
			continue
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if terrain.terrain_height[neighbor_id] < 0.0:
				steps[cell_id] = 0
				queue.append(cell_id)
				break
	var queue_index := 0
	while queue_index < queue.size():
		var cell_id := queue[queue_index]
		queue_index += 1
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if terrain.terrain_height[neighbor_id] >= 0.0 and steps[neighbor_id] < 0:
				steps[neighbor_id] = steps[cell_id] + 1
				queue.append(neighbor_id)
	return steps


static func _components_by_continental_support(
		graph: SpatialGraph,
		composition: WorldCompositionLayer
) -> Dictionary:
	var component_by_cell := PackedInt32Array()
	component_by_cell.resize(graph.cell_count())
	component_by_cell.fill(-1)
	var components: Array = []
	for seed_id in graph.cell_count():
		if composition.continental_value[seed_id] < CONTINENTAL_PROVINCE_SUPPORT_THRESHOLD \
				or component_by_cell[seed_id] >= 0:
			continue
		var component_id := components.size()
		var cells := PackedInt32Array([seed_id])
		component_by_cell[seed_id] = component_id
		var queue_index := 0
		while queue_index < cells.size():
			var cell_id := cells[queue_index]
			queue_index += 1
			for neighbor_id in graph.cell_neighbors[cell_id]:
				if composition.continental_value[neighbor_id] \
						>= CONTINENTAL_PROVINCE_SUPPORT_THRESHOLD \
						and component_by_cell[neighbor_id] < 0:
					component_by_cell[neighbor_id] = component_id
					cells.append(neighbor_id)
		components.append(cells)
	return {"components": components, "component_by_cell": component_by_cell}


static func _assign_province_component(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		land_cells: PackedInt32Array,
		component_id: int,
		component_by_cell: PackedInt32Array,
		suitability: Array,
		coast_steps: PackedInt32Array,
		seed: int,
		province_id: PackedInt32Array
) -> void:
	var seed_count := clampi(
		ceili(float(land_cells.size()) / float(PROVINCE_TARGET_CELLS_PER_SEED)),
		1,
		mini(MAX_PROVINCE_SEEDS_PER_COMPONENT, land_cells.size())
	)
	var seeds: Array = []
	var landmass_suitability := _landmass_suitability(land_cells, suitability)
	for seed_index in seed_count:
		var cell_id := _choose_region_seed(
			graph, land_cells, seeds, seed, component_id * 101 + seed_index
		)
		var local_suitability := _local_province_suitability(
			graph, terrain, cell_id, coast_steps
		)
		var province := select_province_type(
			local_suitability,
			_unit_noise(seed, component_id * 1009 + seed_index, 0x50524f56),
			landmass_suitability
		)
		seeds.append({"cell_id": cell_id, "value": province})
	_expand_regions(
		graph,
		terrain,
		seeds,
		component_id,
		component_by_cell,
		suitability,
		seed,
		province_id
	)


static func _landmass_suitability(
		cells: PackedInt32Array,
		suitability: Array
) -> PackedFloat32Array:
	var representative := PackedFloat32Array()
	representative.resize(GeologyCatalog.PROVINCE_COUNT)
	var top_count := clampi(ceili(float(cells.size()) * 0.10), 1, 64)
	for province in range(
			GeologyCatalog.Province.CRATON,
			GeologyCatalog.Province.VOLCANIC_PROVINCE + 1
	):
		var candidates := PackedFloat32Array()
		candidates.resize(cells.size())
		for cell_index in cells.size():
			candidates[cell_index] = suitability[province][cells[cell_index]]
		candidates.sort()
		var sum := 0.0
		for candidate_index in range(candidates.size() - top_count, candidates.size()):
			sum += candidates[candidate_index]
		representative[province] = sum / float(top_count)
	return representative


static func _local_province_suitability(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		seed_cell_id: int,
		coast_steps: PackedInt32Array
) -> PackedFloat32Array:
	var features := _local_terrain_features(graph, terrain, seed_cell_id, coast_steps)
	var normalized_height: float = features.local_mean_height
	var relief: float = features.local_relief
	var smoothness := 1.0 - relief
	var relative_lowland: float = features.relative_lowland
	var coast_proximity: float = features.coast_proximity
	var interior := 1.0 - coast_proximity
	var values := PackedFloat32Array()
	values.resize(GeologyCatalog.PROVINCE_COUNT)
	values[GeologyCatalog.Province.CRATON] = clampf(
		0.15 + 0.35 * interior + 0.30 * smoothness + 0.20 * (1.0 - normalized_height),
		0.0,
		1.0
	)
	values[GeologyCatalog.Province.OROGENIC_BELT] = clampf(
		0.02 + 0.45 * normalized_height + 0.50 * relief + 0.03 * interior,
		0.0,
		1.0
	)
	values[GeologyCatalog.Province.SEDIMENTARY_BASIN] = clampf(
		0.05 + 0.25 * interior + 0.25 * smoothness \
		+ 0.35 * relative_lowland + 0.10 * (1.0 - normalized_height),
		0.0,
		1.0
	)
	values[GeologyCatalog.Province.PASSIVE_MARGIN] = clampf(
		0.03 + 0.55 * coast_proximity + 0.25 * smoothness \
		+ 0.17 * (1.0 - normalized_height),
		0.0,
		1.0
	)
	values[GeologyCatalog.Province.VOLCANIC_PROVINCE] = clampf(
		0.02 + 0.55 * values[GeologyCatalog.Province.OROGENIC_BELT] \
		+ 0.20 * coast_proximity + 0.18 * normalized_height + 0.05 * relief,
		0.0,
		1.0
	)
	return values


static func _local_terrain_features(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		seed_cell_id: int,
		coast_steps: PackedInt32Array
) -> Dictionary:
	var queue := PackedInt32Array([seed_cell_id])
	var ring_by_cell := {seed_cell_id: 0}
	var local_minimum := terrain.terrain_height[seed_cell_id]
	var local_maximum := local_minimum
	var local_sum := 0.0
	var local_count := 0
	var context_sum := 0.0
	var context_count := 0
	var queue_index := 0
	while queue_index < queue.size():
		var cell_id := queue[queue_index]
		queue_index += 1
		var ring: int = ring_by_cell[cell_id]
		var height := terrain.terrain_height[cell_id]
		context_sum += height
		context_count += 1
		if ring <= 2:
			local_minimum = minf(local_minimum, height)
			local_maximum = maxf(local_maximum, height)
			local_sum += height
			local_count += 1
		if ring >= 4:
			continue
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if terrain.terrain_height[neighbor_id] < 0.0 or ring_by_cell.has(neighbor_id):
				continue
			ring_by_cell[neighbor_id] = ring + 1
			queue.append(neighbor_id)
	var local_mean := local_sum / float(local_count)
	var context_mean := context_sum / float(context_count)
	var coast_step := coast_steps[seed_cell_id]
	var interior := 1.0 if coast_step < 0 else clampf(float(coast_step) / 8.0, 0.0, 1.0)
	return {
		"local_mean_height": clampf(local_mean / 100.0, 0.0, 1.0),
		"local_relief": clampf((local_maximum - local_minimum) / 30.0, 0.0, 1.0),
		"relative_lowland": clampf(0.5 + (context_mean - local_mean) / 30.0, 0.0, 1.0),
		"coast_proximity": 1.0 - interior,
	}


static func select_province_type(
		local_suitability: PackedFloat32Array,
		deterministic_value: float,
		landmass_context: PackedFloat32Array = PackedFloat32Array()
) -> int:
	var weights := province_type_weights(local_suitability, landmass_context)
	var total_weight := 0.0
	for province in range(
		GeologyCatalog.Province.CRATON,
		GeologyCatalog.Province.VOLCANIC_PROVINCE + 1
	):
		total_weight += weights[province]
	if total_weight <= 0.0:
		return GeologyCatalog.Province.CRATON
	var target := clampf(deterministic_value, 0.0, 0.999999) * total_weight
	var cumulative := 0.0
	for province in range(
		GeologyCatalog.Province.CRATON,
		GeologyCatalog.Province.VOLCANIC_PROVINCE + 1
	):
		cumulative += weights[province]
		if target < cumulative:
			return province
	return GeologyCatalog.Province.VOLCANIC_PROVINCE


static func province_type_weights(
		local_suitability: PackedFloat32Array,
		landmass_context: PackedFloat32Array = PackedFloat32Array()
) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	weights.resize(GeologyCatalog.PROVINCE_COUNT)
	var has_context := landmass_context.size() == GeologyCatalog.PROVINCE_COUNT
	for province in range(
		GeologyCatalog.Province.CRATON,
		GeologyCatalog.Province.VOLCANIC_PROVINCE + 1
	):
		var context_modifier := 1.0
		if has_context:
			context_modifier = lerpf(0.90, 1.10, clampf(landmass_context[province], 0.0, 1.0))
		weights[province] = PROVINCE_BASE_PRIOR[province] \
				* local_suitability[province] * context_modifier
	return weights


static func _choose_region_seed(
		graph: SpatialGraph,
		cells: PackedInt32Array,
		existing_seeds: Array,
		seed: int,
		salt: int
) -> int:
	var diagonal := maxf(
		Vector2(graph.config.world_width, graph.config.world_height).length(), 1.0
	)
	var best_cell := cells[0]
	var best_score := -INF
	for cell_id in cells:
		var used := false
		var minimum_distance := diagonal
		for existing in existing_seeds:
			if existing.cell_id == cell_id:
				used = true
				break
			minimum_distance = minf(
				minimum_distance,
				graph.cell_centers[cell_id].distance_to(graph.cell_centers[existing.cell_id])
			)
		if used:
			continue
		var separation := 0.0 if existing_seeds.is_empty() \
				else clampf(minimum_distance * sqrt(float(existing_seeds.size() + 1)) / diagonal, 0.0, 1.0)
		var score := separation * 0.65 + _unit_noise(seed, cell_id, salt) * 0.08
		if score > best_score or (is_equal_approx(score, best_score) and cell_id < best_cell):
			best_score = score
			best_cell = cell_id
	return best_cell


static func _expand_regions(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		seeds: Array,
		component_id: int,
		component_by_cell: PackedInt32Array,
		suitability: Array,
		seed: int,
		output: PackedInt32Array
) -> void:
	var best_cost := {}
	var heap: Array = []
	var serial := 0
	for region_seed in seeds:
		var cell_id: int = region_seed.cell_id
		best_cost[cell_id] = 0.0
		output[cell_id] = region_seed.value
		_heap_push(heap, [0.0, serial, cell_id, region_seed.value])
		serial += 1
	var distance_scale := _distance_scale(graph)
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var cost: float = entry[0]
		var cell_id: int = entry[2]
		var value: int = entry[3]
		if cost > float(best_cost[cell_id]) or output[cell_id] != value:
			continue
		var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
		var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
		for neighbor_index in neighbors.size():
			var neighbor_id := neighbors[neighbor_index]
			if component_by_cell[neighbor_id] != component_id:
				continue
			var suitability_cost := 1.0
			if terrain.terrain_height[neighbor_id] >= 0.0:
				suitability_cost = lerpf(1.75, 0.75, suitability[value][neighbor_id])
				if value == GeologyCatalog.Province.VOLCANIC_PROVINCE:
					suitability_cost *= 1.60
			var variation := lerpf(
				0.92,
				1.08,
				_unit_noise(seed, mini(cell_id, neighbor_id), maxi(cell_id, neighbor_id) + value * 131)
			)
			var next_cost := cost + distances[neighbor_index] / distance_scale \
					* suitability_cost * variation
			if next_cost < float(best_cost.get(neighbor_id, INF)):
				best_cost[neighbor_id] = next_cost
				output[neighbor_id] = value
				_heap_push(heap, [next_cost, serial, neighbor_id, value])
				serial += 1


static func _distance_scale(graph: SpatialGraph) -> float:
	if graph.spacing > 0.0:
		return graph.spacing
	return maxf(
		sqrt(graph.config.world_width * graph.config.world_height / float(graph.cell_count())),
		0.000001
	)


static func _geology_seed(world_seed: int) -> int:
	var value := (world_seed & _MASK) ^ _GEOLOGY_SALT
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & _MASK
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & _MASK
	value = (value ^ (value >> 16)) & _MASK
	return value if value != 0 else 1


static func _unit_noise(seed: int, first: int, second: int) -> float:
	var value := seed & _MASK
	value = (value ^ ((first + 1) * 0x1f123bb5)) & _MASK
	value = (value ^ ((second + 1) * 0x5f356495)) & _MASK
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & _MASK
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & _MASK
	value = (value ^ (value >> 16)) & _MASK
	return float(value) / 2147483648.0


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
