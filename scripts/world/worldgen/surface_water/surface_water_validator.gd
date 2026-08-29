class_name SurfaceWaterValidator
extends RefCounted


static func validate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		hydrology: WorldHydrologyLayer,
		closed_basin_id: PackedInt32Array,
		geology: GeologyLayer,
		layer: SurfaceWaterLayer,
		settings: SurfaceWaterSettings
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null \
			or terrain == null \
			or climate == null \
			or hydrology == null \
			or geology == null \
			or layer == null \
			or settings == null:
		errors.append("Surface Water validation inputs must not be null")
		return errors
	var count := graph.cell_count()
	if terrain.cell_count() != count \
			or climate.temperature.size() != count \
			or closed_basin_id.size() != count \
			or geology.permeability.size() != count \
			or graph.cell_areas.size() != count \
			or graph.cell_neighbors.size() != count \
			or layer.lake_id.size() != count \
			or layer.surface_water_depth.size() != count:
		errors.append("Surface Water arrays must contain one value per Cell")
		return errors
	var lake_area_sum := PackedFloat64Array()
	lake_area_sum.resize(layer.lakes.size())
	var lake_cell_count := PackedInt32Array()
	lake_cell_count.resize(layer.lakes.size())
	var basin_has_lake := {}
	for cell_id in count:
		var lake_id := layer.lake_id[cell_id]
		var depth := layer.surface_water_depth[cell_id]
		if not is_finite(depth) or depth < 0.0:
			errors.append("surface_water_depth[%d] must be finite and non-negative" % cell_id)
			continue
		if terrain.terrain_height[cell_id] < 0.0:
			if lake_id != -1 or depth != 0.0:
				errors.append("Ocean Cell %d must not contain inland Surface Water" % cell_id)
			continue
		if lake_id < 0:
			if lake_id != -1 or depth != 0.0:
				errors.append("non-Lake Cell %d must use lake_id -1 and zero depth" % cell_id)
			continue
		if lake_id >= layer.lakes.size():
			errors.append("lake_id[%d] references an invalid Lake" % cell_id)
			continue
		var lake: SurfaceWaterLake = layer.lakes[lake_id]
		if closed_basin_id[cell_id] != lake.basin_id:
			errors.append("Lake Cell %d must remain inside its Closed Basin" % cell_id)
		if terrain.terrain_height[cell_id] >= lake.water_level:
			errors.append("Lake Cell %d must be strictly below its water level" % cell_id)
		if not is_equal_approx(depth, lake.water_level - terrain.terrain_height[cell_id]):
			errors.append("surface_water_depth[%d] must equal water level minus terrain" % cell_id)
		lake_area_sum[lake_id] += graph.cell_areas[cell_id]
		lake_cell_count[lake_id] += 1
	for lake_index in layer.lakes.size():
		var lake: SurfaceWaterLake = layer.lakes[lake_index]
		if lake == null \
				or lake.id != lake_index \
				or lake.basin_id < 0 \
				or not is_finite(lake.water_level) \
				or not is_finite(lake.area) \
				or lake.area < settings.minimum_lake_area \
				or lake_cell_count[lake_index] == 0:
			errors.append("Lake %d metadata is invalid" % lake_index)
			continue
		if basin_has_lake.has(lake.basin_id):
			errors.append("Closed Basin %d produced more than one Lake" % lake.basin_id)
		basin_has_lake[lake.basin_id] = true
		if not is_equal_approx(lake.area, lake_area_sum[lake_index]):
			errors.append("Lake %d area must equal its actual Voronoi Cell area" % lake_index)
		var cells := PackedInt32Array()
		for cell_id in count:
			if closed_basin_id[cell_id] == lake.basin_id:
				cells.append(cell_id)
		var geometry := SurfaceWaterGenerator.reconstruct_basin_geometry(
			graph, terrain.terrain_height, closed_basin_id, lake.basin_id, cells
		)
		if geometry.is_empty() \
				or geometry.zero_capacity \
				or lake.water_level > geometry.spill_height:
			errors.append("Lake %d has invalid or non-floodable Closed Basin geometry" % lake_index)
	var basin_cells := {}
	for cell_id in count:
		var basin_id := closed_basin_id[cell_id]
		if basin_id < 0:
			continue
		if not basin_cells.has(basin_id):
			basin_cells[basin_id] = PackedInt32Array()
		var cells: PackedInt32Array = basin_cells[basin_id]
		cells.append(cell_id)
		basin_cells[basin_id] = cells
	var zero_capacity_count := 0
	for basin_id in basin_cells:
		var cells: PackedInt32Array = basin_cells[basin_id]
		var geometry := SurfaceWaterGenerator.reconstruct_basin_geometry(
			graph, terrain.terrain_height, closed_basin_id, basin_id, cells
		)
		if geometry.is_empty():
			errors.append("Closed Basin %d geometry is invalid" % basin_id)
		elif geometry.zero_capacity:
			zero_capacity_count += 1
			if basin_has_lake.has(basin_id):
				errors.append("Zero-Capacity Basin %d must not produce a Lake" % basin_id)
	if layer.rejected_small_lake_count < 0 \
			or layer.zero_capacity_basin_count != zero_capacity_count \
			or layer.no_lake_basin_count < 0 \
			or layer.no_lake_basin_count + layer.lakes.size() \
					!= hydrology.closed_basin_inflows.size():
		errors.append("Surface Water Debug basin counters are inconsistent")
	return errors
