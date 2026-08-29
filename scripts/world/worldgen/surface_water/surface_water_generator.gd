class_name SurfaceWaterGenerator
extends RefCounted

const WATER_LEVEL_EPSILON := 0.001


static func generate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		hydrology: WorldHydrologyLayer,
		closed_basin_id: PackedInt32Array,
		geology: GeologyLayer,
		settings: SurfaceWaterSettings = null
) -> SurfaceWaterLayer:
	var actual_settings := settings if settings != null else SurfaceWaterSettings.new()
	if not _inputs_are_valid(
		graph, terrain, climate, hydrology, closed_basin_id, geology, actual_settings
	):
		return null
	var layer := SurfaceWaterLayer.new()
	layer.lake_id.resize(graph.cell_count())
	layer.lake_id.fill(-1)
	layer.surface_water_depth.resize(graph.cell_count())
	var basin_cells := _basin_cells_by_id(closed_basin_id)
	var inflow_by_basin := _inflow_by_basin_id(hydrology.closed_basin_inflows)
	var basin_ids := PackedInt32Array()
	for basin_id in basin_cells:
		basin_ids.append(basin_id)
	basin_ids.sort()
	for basin_id in basin_ids:
		var cells: PackedInt32Array = basin_cells[basin_id]
		var geometry := reconstruct_basin_geometry(
			graph, terrain.terrain_height, closed_basin_id, basin_id, cells
		)
		if geometry.is_empty():
			push_error("Surface Water could not reconstruct Closed Basin %d geometry" % basin_id)
			return null
		var climate_and_geology := _area_weighted_basin_conditions(
			graph, cells, climate.temperature, geology.permeability
		)
		var evaporation := actual_settings.evaporation_rate(
			climate_and_geology.mean_temperature
		)
		var infiltration := actual_settings.infiltration_rate(
			climate_and_geology.mean_permeability
		)
		var loss_per_area := maxf(
			evaporation + infiltration, actual_settings.minimum_loss_per_area
		)
		var inflow: ClosedBasinInflow = inflow_by_basin[basin_id]
		var target_lake_area := inflow.total_inflow / loss_per_area
		if target_lake_area < actual_settings.minimum_lake_area:
			if target_lake_area > 0.0:
				layer.rejected_small_lake_count += 1
			continue
		var flooded := _flood_to_target_area(
			graph,
			terrain.terrain_height,
			closed_basin_id,
			basin_id,
			geometry.lowest_cell,
			geometry.spill_height,
			target_lake_area
		)
		if flooded.cells.is_empty() or flooded.area < actual_settings.minimum_lake_area:
			if flooded.area > 0.0:
				layer.rejected_small_lake_count += 1
			continue
		var lake := SurfaceWaterLake.new()
		lake.id = layer.lakes.size()
		lake.basin_id = basin_id
		lake.water_level = flooded.water_level
		lake.area = flooded.area
		layer.lakes.append(lake)
		for cell_id in flooded.cells:
			layer.lake_id[cell_id] = lake.id
			layer.surface_water_depth[cell_id] = lake.water_level - terrain.terrain_height[cell_id]
	layer.no_lake_basin_count = basin_ids.size() - layer.lakes.size()
	var validation_errors := SurfaceWaterValidator.validate(
		graph,
		terrain,
		climate,
		hydrology,
		closed_basin_id,
		geology,
		layer,
		actual_settings
	)
	if not validation_errors.is_empty():
		push_error("Surface Water validation failed: " + "; ".join(validation_errors))
		return null
	return layer


static func target_lake_area(
		water_supply: float,
		temperature: float,
		permeability: float,
		settings: SurfaceWaterSettings
) -> float:
	var loss_per_area := maxf(
		settings.evaporation_rate(temperature) + settings.infiltration_rate(permeability),
		settings.minimum_loss_per_area
	)
	return water_supply / loss_per_area


static func reconstruct_basin_geometry(
		graph: SpatialGraph,
		heights: PackedFloat32Array,
		closed_basin_id: PackedInt32Array,
		basin_id: int,
		cells: PackedInt32Array
) -> Dictionary:
	if cells.is_empty():
		return {}
	var lowest_cell := cells[0]
	var spill_height := INF
	for cell_id in cells:
		if heights[cell_id] < heights[lowest_cell] \
				or (heights[cell_id] == heights[lowest_cell] and cell_id < lowest_cell):
			lowest_cell = cell_id
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if closed_basin_id[neighbor_id] == basin_id:
				continue
			spill_height = minf(spill_height, maxf(heights[cell_id], heights[neighbor_id]))
	if not is_finite(spill_height) or spill_height <= heights[lowest_cell]:
		return {}
	return {
		"cells": cells,
		"lowest_cell": lowest_cell,
		"spill_height": spill_height,
	}


static func _flood_to_target_area(
		graph: SpatialGraph,
		heights: PackedFloat32Array,
		closed_basin_id: PackedInt32Array,
		basin_id: int,
		lowest_cell: int,
		spill_height: float,
		target_area: float
) -> Dictionary:
	var queued := PackedByteArray()
	queued.resize(graph.cell_count())
	queued[lowest_cell] = 1
	var heap: Array = []
	_heap_push(heap, [heights[lowest_cell], lowest_cell])
	var accumulated_area := 0.0
	var highest_included := heights[lowest_cell]
	while not heap.is_empty() and accumulated_area < target_area:
		var entry: Array = _heap_pop(heap)
		var cell_id: int = entry[1]
		if heights[cell_id] >= spill_height:
			continue
		accumulated_area += graph.cell_areas[cell_id]
		highest_included = maxf(highest_included, heights[cell_id])
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if closed_basin_id[neighbor_id] != basin_id or queued[neighbor_id] != 0:
				continue
			queued[neighbor_id] = 1
			_heap_push(heap, [heights[neighbor_id], neighbor_id])
	if accumulated_area <= 0.0:
		return {"cells": PackedInt32Array(), "area": 0.0, "water_level": 0.0}
	var water_level := minf(spill_height, highest_included + WATER_LEVEL_EPSILON)
	if accumulated_area < target_area:
		water_level = spill_height
	var cells := _connected_cells_below_level(
		graph, heights, closed_basin_id, basin_id, lowest_cell, water_level
	)
	var actual_area := 0.0
	for cell_id in cells:
		actual_area += graph.cell_areas[cell_id]
	return {"cells": cells, "area": actual_area, "water_level": water_level}


static func _connected_cells_below_level(
		graph: SpatialGraph,
		heights: PackedFloat32Array,
		closed_basin_id: PackedInt32Array,
		basin_id: int,
		lowest_cell: int,
		water_level: float
) -> PackedInt32Array:
	var cells := PackedInt32Array()
	if heights[lowest_cell] >= water_level:
		return cells
	var visited := PackedByteArray()
	visited.resize(graph.cell_count())
	visited[lowest_cell] = 1
	var queue := PackedInt32Array([lowest_cell])
	var queue_index := 0
	while queue_index < queue.size():
		var cell_id := queue[queue_index]
		queue_index += 1
		cells.append(cell_id)
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if visited[neighbor_id] != 0 \
					or closed_basin_id[neighbor_id] != basin_id \
					or heights[neighbor_id] >= water_level:
				continue
			visited[neighbor_id] = 1
			queue.append(neighbor_id)
	return cells


static func _basin_cells_by_id(closed_basin_id: PackedInt32Array) -> Dictionary:
	var basin_cells := {}
	for cell_id in closed_basin_id.size():
		var basin_id := closed_basin_id[cell_id]
		if basin_id < 0:
			continue
		if not basin_cells.has(basin_id):
			basin_cells[basin_id] = PackedInt32Array()
		var cells: PackedInt32Array = basin_cells[basin_id]
		cells.append(cell_id)
		basin_cells[basin_id] = cells
	return basin_cells


static func _inflow_by_basin_id(inflows: Array) -> Dictionary:
	var by_id := {}
	for inflow in inflows:
		by_id[inflow.closed_basin_id] = inflow
	return by_id


static func _area_weighted_basin_conditions(
		graph: SpatialGraph,
		cells: PackedInt32Array,
		temperature: PackedFloat32Array,
		permeability: PackedFloat32Array
) -> Dictionary:
	var area_sum := 0.0
	var temperature_sum := 0.0
	var permeability_sum := 0.0
	for cell_id in cells:
		var area := graph.cell_areas[cell_id]
		area_sum += area
		temperature_sum += temperature[cell_id] * area
		permeability_sum += permeability[cell_id] * area
	return {
		"mean_temperature": temperature_sum / area_sum,
		"mean_permeability": permeability_sum / area_sum,
	}


static func _inputs_are_valid(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		hydrology: WorldHydrologyLayer,
		closed_basin_id: PackedInt32Array,
		geology: GeologyLayer,
		settings: SurfaceWaterSettings
) -> bool:
	if graph == null or terrain == null or climate == null or hydrology == null or geology == null:
		push_error("Surface Water requires Spatial, Final Terrain, Final Climate, Formal Hydrology, and Geology")
		return false
	var count := graph.cell_count()
	if count == 0 \
			or terrain.cell_count() != count \
			or climate.temperature.size() != count \
			or hydrology.cell_count() != count \
			or closed_basin_id.size() != count \
			or geology.permeability.size() != count \
			or graph.cell_areas.size() != count \
			or graph.cell_neighbors.size() != count:
		push_error("Surface Water input arrays must contain one value per Cell")
		return false
	var setting_errors := settings.validate()
	if not setting_errors.is_empty():
		push_error("Invalid SurfaceWaterSettings: " + "; ".join(setting_errors))
		return false
	var basin_ids := {}
	for cell_id in count:
		if not is_finite(graph.cell_areas[cell_id]) or graph.cell_areas[cell_id] <= 0.0:
			push_error("Surface Water Cell areas must be finite and positive")
			return false
		if not is_finite(terrain.terrain_height[cell_id]) \
				or not is_finite(climate.temperature[cell_id]) \
				or not is_finite(geology.permeability[cell_id]) \
				or geology.permeability[cell_id] < 0.0 \
				or geology.permeability[cell_id] > 1.0 \
				or closed_basin_id[cell_id] < -1:
			push_error("Surface Water Cell inputs contain invalid values")
			return false
		if closed_basin_id[cell_id] >= 0:
			if terrain.terrain_height[cell_id] < 0.0:
				push_error("Ocean Cells cannot be Closed Basin candidates")
				return false
			basin_ids[closed_basin_id[cell_id]] = true
	var inflow_ids := {}
	for inflow in hydrology.closed_basin_inflows:
		if inflow == null \
				or inflow.closed_basin_id < 0 \
				or not basin_ids.has(inflow.closed_basin_id) \
				or inflow_ids.has(inflow.closed_basin_id) \
				or not is_finite(inflow.total_inflow) \
				or inflow.total_inflow < 0.0:
			push_error("Surface Water received invalid final Closed Basin inflow metadata")
			return false
		inflow_ids[inflow.closed_basin_id] = true
	if inflow_ids.size() != basin_ids.size():
		push_error("Surface Water requires one final inflow record per Closed Basin")
		return false
	return true


static func _heap_less(first: Array, second: Array) -> bool:
	return first[0] < second[0] or (first[0] == second[0] and first[1] < second[1])


static func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if not _heap_less(heap[index], heap[parent]):
			break
		var temporary = heap[parent]
		heap[parent] = heap[index]
		heap[index] = temporary
		index = parent


static func _heap_pop(heap: Array) -> Array:
	var root: Array = heap[0]
	var last = heap.pop_back()
	if heap.is_empty():
		return root
	heap[0] = last
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var smallest := left
		if right < heap.size() and _heap_less(heap[right], heap[left]):
			smallest = right
		if not _heap_less(heap[smallest], heap[index]):
			break
		var temporary = heap[index]
		heap[index] = heap[smallest]
		heap[smallest] = temporary
		index = smallest
	return root
