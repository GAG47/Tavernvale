class_name GroundwaterGenerator
extends RefCounted


static func generate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		hydrology: WorldHydrologyLayer,
		surface_water: SurfaceWaterLayer,
		settings: GroundwaterSettings = null
) -> GroundwaterLayer:
	var actual_settings := settings if settings != null else GroundwaterSettings.new()
	if not _inputs_are_valid(
		graph, terrain, climate, hydrology, surface_water, actual_settings
	):
		return null
	var recharge := recharge_influence_fields(
		graph, terrain, hydrology, surface_water, actual_settings
	)
	var marine_influence := marine_influence_field(graph, terrain, actual_settings)
	var groundwater := GroundwaterLayer.new()
	var count := graph.cell_count()
	groundwater.settings = actual_settings.duplicate_settings()
	groundwater.groundwater_supply.resize(count)
	groundwater.water_table_z.resize(count)
	groundwater.groundwater_salinity_class.resize(count)
	for cell_id in count:
		var terrain_z := terrain.terrain_height[cell_id]
		var is_ocean := terrain_z < 0.0
		var is_lake := surface_water.lake_id[cell_id] >= 0
		if is_ocean:
			groundwater.groundwater_supply[cell_id] = 1.0
			groundwater.water_table_z[cell_id] = terrain_z
			groundwater.groundwater_salinity_class[cell_id] = (
				GroundwaterLayer.SalinityClass.SALINE
			)
			continue
		if is_lake:
			groundwater.groundwater_supply[cell_id] = 1.0
			groundwater.water_table_z[cell_id] = terrain_z
			groundwater.groundwater_salinity_class[cell_id] = (
				GroundwaterLayer.SalinityClass.FRESH
			)
			continue
		var climate_supply := climate_supply_for(
			climate.precipitation[cell_id], actual_settings.precipitation_reference
		)
		var surface_water_influence := maxf(
			recharge.river[cell_id], recharge.lake[cell_id]
		)
		var supply := groundwater_supply_for(
			climate_supply,
			surface_water_influence,
			actual_settings.surface_water_recharge_weight
		)
		groundwater.groundwater_supply[cell_id] = supply
		groundwater.water_table_z[cell_id] = terrain_z - water_table_depth_for(
			supply, terrain_z, actual_settings
		)
		groundwater.groundwater_salinity_class[cell_id] = salinity_class_for_pressure(
			salinity_pressure_for(marine_influence[cell_id], supply), actual_settings
		)
	var validation_errors := GroundwaterValidator.validate(
		graph, terrain, surface_water, groundwater
	)
	if not validation_errors.is_empty():
		push_error("Groundwater validation failed: " + "; ".join(validation_errors))
		return null
	return groundwater


static func climate_supply_for(precipitation: float, precipitation_reference: float) -> float:
	return precipitation / (precipitation + precipitation_reference)


static func distance_influence_for(distance: float, radius: float) -> float:
	if distance >= radius:
		return 0.0
	return 1.0 - smoothstep(0.0, radius, distance)


static func groundwater_supply_for(
		climate_supply: float, surface_water_influence: float, recharge_weight: float
) -> float:
	return clampf(climate_supply + recharge_weight * surface_water_influence, 0.0, 1.0)


static func water_table_depth_for(
		groundwater_supply: float, terrain_z: float, settings: GroundwaterSettings
) -> float:
	var base_depth := lerpf(
		settings.max_water_table_depth,
		settings.min_water_table_depth,
		sqrt(groundwater_supply)
	)
	var highland_factor := smoothstep(
		settings.highland_start_z, settings.highland_full_z, terrain_z
	)
	return base_depth + settings.highland_max_extra_depth * highland_factor


static func salinity_pressure_for(marine_influence: float, groundwater_supply: float) -> float:
	return marine_influence * (1.0 - groundwater_supply)


static func salinity_class_for_pressure(
		salinity_pressure: float, settings: GroundwaterSettings
) -> int:
	if salinity_pressure < settings.brackish_salinity_threshold:
		return GroundwaterLayer.SalinityClass.FRESH
	if salinity_pressure < settings.saline_salinity_threshold:
		return GroundwaterLayer.SalinityClass.BRACKISH
	return GroundwaterLayer.SalinityClass.SALINE


static func recharge_influence_fields(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		hydrology: WorldHydrologyLayer,
		surface_water: SurfaceWaterLayer,
		settings: GroundwaterSettings
) -> Dictionary:
	var count := graph.cell_count()
	var river_influence := PackedFloat32Array()
	var lake_influence := PackedFloat32Array()
	river_influence.resize(count)
	lake_influence.resize(count)
	for cell_id in count:
		if terrain.terrain_height[cell_id] < 0.0:
			continue
		if hydrology.is_river(cell_id):
			var source_strength := EcologyGenerator.river_strength_for(
				hydrology.flow_accumulation[cell_id],
				hydrology.settings.river_runoff_threshold
			)
			_propagate_source_max(
				graph, terrain, cell_id, source_strength,
				settings.river_recharge_radius, river_influence
			)
		if surface_water.lake_id[cell_id] >= 0:
			_propagate_source_max(
				graph, terrain, cell_id, 1.0,
				settings.lake_recharge_radius, lake_influence
			)
	return {"river": river_influence, "lake": lake_influence}


static func marine_influence_field(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		settings: GroundwaterSettings
) -> PackedFloat32Array:
	var count := graph.cell_count()
	var distances := PackedFloat64Array()
	distances.resize(count)
	distances.fill(INF)
	var heap: Array = []
	for cell_id in count:
		if terrain.terrain_height[cell_id] < 0.0:
			distances[cell_id] = 0.0
			_heap_push(heap, [0.0, cell_id])
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var distance: float = entry[0]
		var cell_id: int = entry[1]
		if distance > distances[cell_id] or distance >= settings.marine_influence_radius:
			continue
		var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
		var edge_distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
		for neighbor_index in neighbors.size():
			var neighbor_id := neighbors[neighbor_index]
			var candidate := distance + edge_distances[neighbor_index]
			if candidate < settings.marine_influence_radius \
					and candidate < distances[neighbor_id]:
				distances[neighbor_id] = candidate
				_heap_push(heap, [candidate, neighbor_id])
	var influence := PackedFloat32Array()
	influence.resize(count)
	for cell_id in count:
		if terrain.terrain_height[cell_id] < 0.0:
			influence[cell_id] = 1.0
		elif distances[cell_id] < settings.marine_influence_radius:
			influence[cell_id] = distance_influence_for(
				distances[cell_id], settings.marine_influence_radius
			)
	return influence


static func _propagate_source_max(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		source_id: int,
		source_strength: float,
		radius: float,
		result: PackedFloat32Array
) -> void:
	var distances := {source_id: 0.0}
	var heap: Array = []
	_heap_push(heap, [0.0, source_id])
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var distance: float = entry[0]
		var cell_id: int = entry[1]
		if distance > float(distances.get(cell_id, INF)) or distance >= radius:
			continue
		result[cell_id] = maxf(
			result[cell_id], source_strength * distance_influence_for(distance, radius)
		)
		var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
		var edge_distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
		for neighbor_index in neighbors.size():
			var neighbor_id := neighbors[neighbor_index]
			if terrain.terrain_height[neighbor_id] < 0.0:
				continue
			var candidate := distance + edge_distances[neighbor_index]
			if candidate < radius and candidate < float(distances.get(neighbor_id, INF)):
				distances[neighbor_id] = candidate
				_heap_push(heap, [candidate, neighbor_id])


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
	if first[0] != second[0]:
		return float(first[0]) < float(second[0])
	return int(first[1]) < int(second[1])


static func _inputs_are_valid(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		hydrology: WorldHydrologyLayer,
		surface_water: SurfaceWaterLayer,
		settings: GroundwaterSettings
) -> bool:
	if graph == null or terrain == null or climate == null \
			or hydrology == null or surface_water == null:
		push_error(
			"Groundwater requires Spatial, Final Terrain, Final Climate, Formal Hydrology, and Surface Water"
		)
		return false
	var count := graph.cell_count()
	if count <= 0 or terrain.terrain_height.size() != count \
			or climate.precipitation.size() != count \
			or hydrology.flow_accumulation.size() != count \
			or hydrology.river_network_id.size() != count \
			or surface_water.lake_id.size() != count \
			or graph.cell_neighbors.size() != count \
			or graph.cell_neighbor_distances.size() != count:
		push_error("Groundwater input arrays must contain one value per Cell")
		return false
	if hydrology.settings == null:
		push_error("Groundwater requires Formal Hydrology settings")
		return false
	var settings_errors := settings.validate()
	if not settings_errors.is_empty():
		push_error("Invalid Groundwater settings: " + "; ".join(settings_errors))
		return false
	for cell_id in count:
		if not is_finite(terrain.terrain_height[cell_id]) \
				or not is_finite(climate.precipitation[cell_id]) \
				or climate.precipitation[cell_id] < 0.0 \
				or not is_finite(hydrology.flow_accumulation[cell_id]) \
				or hydrology.flow_accumulation[cell_id] < 0.0:
			push_error("Groundwater Cell inputs contain invalid values")
			return false
		var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
		var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
		if neighbors.size() != distances.size():
			push_error("Groundwater neighbor and edge-distance arrays must match")
			return false
		for neighbor_index in neighbors.size():
			var neighbor_id := neighbors[neighbor_index]
			var edge_distance := distances[neighbor_index]
			if neighbor_id < 0 or neighbor_id >= count \
					or not is_finite(edge_distance) or edge_distance <= 0.0:
				push_error("Groundwater graph edges must have valid Cells and positive distances")
				return false
	return true
