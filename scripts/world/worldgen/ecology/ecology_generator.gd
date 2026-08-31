class_name EcologyGenerator
extends RefCounted


static func generate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		hydrology: WorldHydrologyLayer,
		closed_basin_id: PackedInt32Array,
		geology: GeologyLayer,
		surface_water: SurfaceWaterLayer,
		settings: EcologySettings = null,
		evaporation_settings: SurfaceWaterSettings = null
) -> EcologyLayer:
	var actual_settings := settings if settings != null else EcologySettings.new()
	var actual_evaporation_settings := (
		evaporation_settings if evaporation_settings != null else SurfaceWaterSettings.new()
	)
	if not _inputs_are_valid(
		graph,
		terrain,
		climate,
		hydrology,
		closed_basin_id,
		geology,
		surface_water,
		actual_settings,
		actual_evaporation_settings
	):
		return null
	var layer := EcologyLayer.new()
	var count := graph.cell_count()
	layer.drainage_index.resize(count)
	layer.ecological_moisture.resize(count)
	layer.vegetation_potential.resize(count)
	layer.biome_id.resize(count)
	var lake_shore := _lake_shore_cells(graph, terrain, surface_water)
	for cell_id in count:
		var is_ocean := terrain.terrain_height[cell_id] < 0.0
		var is_lake := surface_water.lake_id[cell_id] >= 0
		var drainage := 0.0
		if not is_ocean and not is_lake:
			var slope := maximum_descending_slope(graph, terrain.terrain_height, cell_id)
			drainage = drainage_index_for(
				geology.permeability[cell_id],
				slope,
				closed_basin_id[cell_id] >= 0,
				actual_settings
			)
		layer.drainage_index[cell_id] = drainage
		var river_strength := river_strength_for(
			hydrology.flow_accumulation[cell_id], hydrology.settings.river_runoff_threshold
		)
		var shore_bonus := actual_settings.lake_shore_bonus if lake_shore[cell_id] != 0 else 0.0
		var moisture := ecological_moisture_for(
			climate.precipitation[cell_id],
			drainage,
			actual_evaporation_settings.evaporation_factor(climate.temperature[cell_id]),
			river_strength,
			shore_bonus,
			actual_settings
		)
		layer.ecological_moisture[cell_id] = moisture
		if is_ocean:
			layer.vegetation_potential[cell_id] = 0.0
			layer.biome_id[cell_id] = EcologyCatalog.Biome.MARINE
			continue
		if is_lake:
			layer.vegetation_potential[cell_id] = 0.0
			layer.biome_id[cell_id] = EcologyCatalog.Biome.LAKE
			continue
		layer.vegetation_potential[cell_id] = vegetation_potential_for(
			moisture, climate.temperature[cell_id], actual_settings
		)
		if climate.temperature[cell_id] <= -10.0:
			layer.biome_id[cell_id] = EcologyCatalog.Biome.GLACIER
			continue
		if is_wetland_candidate(moisture, drainage, actual_settings):
			layer.biome_id[cell_id] = EcologyCatalog.Biome.WETLAND
		else:
			layer.biome_id[cell_id] = EcologyCatalog.matrix_biome(
				climate.temperature[cell_id], moisture
			)
	var validation_errors := EcologyValidator.validate(
		graph, terrain, climate, surface_water, layer
	)
	if not validation_errors.is_empty():
		push_error("Ecology validation failed: " + "; ".join(validation_errors))
		return null
	return layer


static func maximum_descending_slope(
		graph: SpatialGraph, heights: PackedFloat32Array, cell_id: int
) -> float:
	var maximum := 0.0
	var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
	var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
	for neighbor_index in neighbors.size():
		var height_drop := heights[cell_id] - heights[neighbors[neighbor_index]]
		if height_drop > 0.0:
			maximum = maxf(maximum, height_drop / float(distances[neighbor_index]))
	return maximum


static func drainage_index_for(
		permeability: float, slope: float, is_closed_basin: bool, settings: EcologySettings
) -> float:
	var slope_factor := slope / (slope + settings.slope_reference)
	var surface_escape := slope_factor
	if is_closed_basin:
		surface_escape *= settings.closed_basin_surface_escape_multiplier
	return clampf(
		1.0 - (1.0 - clampf(permeability, 0.0, 1.0)) * (1.0 - surface_escape),
		0.0,
		1.0
	)


static func river_strength_for(flow_accumulation: float, river_runoff_threshold: float) -> float:
	if river_runoff_threshold <= 0.0:
		return 1.0 if flow_accumulation > 0.0 else 0.0
	return clampf(
		log(1.0 + maxf(flow_accumulation, 0.0) / river_runoff_threshold) / log(21.0),
		0.0,
		1.0
	)


static func ecological_moisture_for(
		precipitation: float,
		drainage_index: float,
		evaporation_factor: float,
		river_strength: float,
		shore_bonus: float,
		settings: EcologySettings
) -> float:
	var base_moisture := base_ecological_moisture_for(
		precipitation, drainage_index, evaporation_factor, settings
	)
	var river_bonus := clampf(river_strength, 0.0, 1.0) * settings.max_river_bonus
	return clampf(base_moisture + river_bonus + shore_bonus, 0.0, 1.0)


static func base_ecological_moisture_for(
		precipitation: float,
		drainage_index: float,
		evaporation_factor: float,
		settings: EcologySettings
) -> float:
	var retained_supply := maxf(precipitation, 0.0) * (
		1.0 - settings.drainage_moisture_weight * clampf(drainage_index, 0.0, 1.0)
	)
	retained_supply = maxf(retained_supply, 0.0)
	var drying_demand := settings.precip_reference * (
		1.0
		+ settings.evaporation_moisture_weight * clampf(evaporation_factor, 0.0, 1.0)
	)
	var denominator := maxf(retained_supply + drying_demand, 0.000001)
	return clampf(retained_supply / denominator, 0.0, 1.0)


static func temperature_suitability_for(
		temperature: float, settings: EcologySettings
) -> float:
	var cold_factor := smoothstep(
		settings.cold_suitability_minimum, settings.cold_suitability_maximum, temperature
	)
	var heat_factor := 1.0 - smoothstep(
		settings.heat_suitability_minimum, settings.heat_suitability_maximum, temperature
	)
	return clampf(cold_factor * heat_factor, 0.0, 1.0)


static func vegetation_potential_for(
		moisture: float, temperature: float, settings: EcologySettings
) -> float:
	return clampf(
		pow(clampf(moisture, 0.0, 1.0), settings.vegetation_moisture_exponent)
				* temperature_suitability_for(temperature, settings),
		0.0,
		1.0
	)


static func is_wetland_candidate(
		moisture: float, drainage: float, settings: EcologySettings
) -> bool:
	return moisture >= settings.wetland_moisture_threshold \
			and drainage <= settings.wetland_drainage_threshold


static func _lake_shore_cells(
		graph: SpatialGraph, terrain: TerrainHeightLayer, surface_water: SurfaceWaterLayer
) -> PackedByteArray:
	var lake_shore := PackedByteArray()
	lake_shore.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		if surface_water.lake_id[cell_id] < 0:
			continue
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if terrain.terrain_height[neighbor_id] >= 0.0 \
					and surface_water.lake_id[neighbor_id] < 0:
				lake_shore[neighbor_id] = 1
	return lake_shore


static func _inputs_are_valid(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		hydrology: WorldHydrologyLayer,
		closed_basin_id: PackedInt32Array,
		geology: GeologyLayer,
		surface_water: SurfaceWaterLayer,
		settings: EcologySettings,
		evaporation_settings: SurfaceWaterSettings
) -> bool:
	if graph == null or terrain == null or climate == null or hydrology == null \
			or geology == null or surface_water == null:
		push_error(
			"Ecology requires Spatial, Final Terrain, Final Climate, Formal Hydrology, "
			+ "Geology, and Surface Water"
		)
		return false
	var count := graph.cell_count()
	if count == 0 \
			or terrain.cell_count() != count \
			or climate.temperature.size() != count \
			or climate.precipitation.size() != count \
			or hydrology.flow_accumulation.size() != count \
			or closed_basin_id.size() != count \
			or geology.permeability.size() != count \
			or surface_water.lake_id.size() != count \
			or graph.cell_neighbors.size() != count \
			or graph.cell_neighbor_distances.size() != count:
		push_error("Ecology input arrays must contain one value per Cell")
		return false
	if hydrology.settings == null:
		push_error("Ecology requires the Formal Hydrology Settings used by flow accumulation")
		return false
	var setting_errors := settings.validate()
	setting_errors.append_array(evaporation_settings.validate())
	if not setting_errors.is_empty():
		push_error("Invalid Ecology inputs: " + "; ".join(setting_errors))
		return false
	for cell_id in count:
		var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
		var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
		if neighbors.size() != distances.size():
			push_error("Ecology neighbor and distance arrays must have matching lengths")
			return false
		if not is_finite(terrain.terrain_height[cell_id]) \
				or not is_finite(climate.temperature[cell_id]) \
				or not is_finite(climate.precipitation[cell_id]) \
				or climate.precipitation[cell_id] < 0.0 \
				or not is_finite(hydrology.flow_accumulation[cell_id]) \
				or hydrology.flow_accumulation[cell_id] < 0.0 \
				or not is_finite(geology.permeability[cell_id]) \
				or geology.permeability[cell_id] < 0.0 \
				or geology.permeability[cell_id] > 1.0 \
				or closed_basin_id[cell_id] < -1:
			push_error("Ecology Cell inputs contain invalid values")
			return false
		for neighbor_index in neighbors.size():
			if neighbors[neighbor_index] < 0 or neighbors[neighbor_index] >= count \
					or not is_finite(distances[neighbor_index]) \
					or distances[neighbor_index] <= 0.0:
				push_error("Ecology received invalid Spatial neighbor data")
				return false
	return true
