class_name SoilGenerator
extends RefCounted

const _LOCAL_RELIEF_EPSILON := 0.000001


static func generate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		hydrology: WorldHydrologyLayer,
		geology: GeologyLayer,
		surface_water: SurfaceWaterLayer,
		ecology: EcologyLayer,
		settings: SoilSettings = null
) -> SoilLayer:
	var actual_settings := settings if settings != null else SoilSettings.new()
	if not _inputs_are_valid(
		graph, terrain, climate, hydrology, geology, surface_water, ecology, actual_settings
	):
		return null
	var soil := SoilLayer.new()
	var count := graph.cell_count()
	soil.soil_depth.resize(count)
	soil.soil_texture_id.resize(count)
	soil.organic_matter.resize(count)
	soil.soil_fertility.resize(count)
	for cell_id in count:
		if _has_no_surface_soil(ecology.biome_id[cell_id]):
			soil.soil_texture_id[cell_id] = SoilCatalog.TextureType.NONE
			continue
		var material_id := geology.material_id[cell_id]
		var slope_factor := slope_factor_for(
			graph, terrain.terrain_height, cell_id, actual_settings.slope_reference
		)
		var valley_position := valley_position_for(graph, terrain.terrain_height, cell_id)
		var climate_weathering := climate_weathering_for(
			climate.temperature[cell_id],
			climate.precipitation[cell_id],
			actual_settings.weathering_precip_reference
		)
		var formation_potential := formation_potential_for(
			SoilCatalog.weatherability_for(material_id), climate_weathering
		)
		var erosion_pressure := erosion_pressure_for(
			slope_factor, geology.erodibility[cell_id]
		)
		var flow_strength := EcologyGenerator.river_strength_for(
			hydrology.flow_accumulation[cell_id], hydrology.settings.river_runoff_threshold
		)
		var deposition_tendency := deposition_tendency_for(
			slope_factor, valley_position, flow_strength
		)
		soil.soil_depth[cell_id] = soil_depth_for(
			formation_potential, deposition_tendency, erosion_pressure
		)
		var texture_fineness := texture_fineness_for(
			SoilCatalog.parent_fineness_for(material_id),
			climate_weathering,
			deposition_tendency
		)
		soil.soil_texture_id[cell_id] = texture_for_fineness(texture_fineness)
		soil.organic_matter[cell_id] = organic_matter_for(
			ecology.vegetation_potential[cell_id],
			climate.temperature[cell_id],
			ecology.drainage_index[cell_id]
		)
		var leaching := leaching_for(
			climate.temperature[cell_id],
			ecology.ecological_moisture[cell_id],
			ecology.drainage_index[cell_id]
		)
		soil.soil_fertility[cell_id] = soil_fertility_for(
			SoilCatalog.parent_nutrient_for(material_id),
			soil.organic_matter[cell_id],
			deposition_tendency,
			leaching
		)
	var validation_errors := SoilValidator.validate(
		graph, terrain, surface_water, ecology, soil
	)
	if not validation_errors.is_empty():
		push_error("Soil generation failed validation: " + "; ".join(validation_errors))
		return null
	return soil


static func slope_factor_for(
		graph: SpatialGraph,
		heights: PackedFloat32Array,
		cell_id: int,
		slope_reference: float
) -> float:
	var slope := EcologyGenerator.maximum_descending_slope(graph, heights, cell_id)
	return slope / (slope + slope_reference)


static func valley_position_for(
		graph: SpatialGraph, heights: PackedFloat32Array, cell_id: int
) -> float:
	var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
	if neighbors.is_empty():
		return 0.0
	var current_height := heights[cell_id]
	var neighbor_height_sum := 0.0
	var absolute_relief_sum := 0.0
	for neighbor_id in neighbors:
		var neighbor_height := heights[neighbor_id]
		neighbor_height_sum += neighbor_height
		absolute_relief_sum += absf(neighbor_height - current_height)
	var mean_neighbor_height := neighbor_height_sum / float(neighbors.size())
	var mean_absolute_relief := absolute_relief_sum / float(neighbors.size())
	return clampf(
		(mean_neighbor_height - current_height) / (mean_absolute_relief + _LOCAL_RELIEF_EPSILON),
		0.0,
		1.0
	)


static func climate_weathering_for(
		temperature: float, precipitation: float, precipitation_reference: float
) -> float:
	var temperature_weathering := smoothstep(-10.0, 20.0, temperature)
	var precipitation_supply := precipitation / (precipitation + precipitation_reference)
	return temperature_weathering * precipitation_supply


static func formation_potential_for(weatherability: float, climate_weathering: float) -> float:
	return weatherability * (0.35 + 0.65 * climate_weathering)


static func erosion_pressure_for(slope_factor: float, erodibility: float) -> float:
	return slope_factor * lerpf(0.40, 1.00, erodibility)


static func deposition_tendency_for(
		slope_factor: float, valley_position: float, flow_strength: float
) -> float:
	return (1.0 - slope_factor) * clampf(
		0.80 * valley_position + 0.20 * flow_strength, 0.0, 1.0
	)


static func soil_depth_for(
		formation_potential: float, deposition_tendency: float, erosion_pressure: float
) -> float:
	return clampf(
		0.15 + 0.70 * formation_potential + 0.35 * deposition_tendency \
				- 0.55 * erosion_pressure,
		0.0,
		1.0
	)


static func texture_fineness_for(
		parent_fineness: float, climate_weathering: float, deposition_tendency: float
) -> float:
	return clampf(
		parent_fineness + 0.10 * climate_weathering + 0.15 * deposition_tendency,
		0.0,
		1.0
	)


static func texture_for_fineness(texture_fineness: float) -> int:
	if texture_fineness < 0.30:
		return SoilCatalog.TextureType.SANDY
	if texture_fineness < 0.60:
		return SoilCatalog.TextureType.LOAMY
	if texture_fineness < 0.78:
		return SoilCatalog.TextureType.SILTY
	return SoilCatalog.TextureType.CLAYEY


static func organic_matter_for(
		vegetation_potential: float, temperature: float, drainage_index: float
) -> float:
	var cold_retention := 1.0 - smoothstep(5.0, 30.0, temperature)
	var water_retention := 1.0 - drainage_index
	var organic_retention := clampf(
		0.30 + 0.35 * cold_retention + 0.35 * water_retention, 0.0, 1.0
	)
	return clampf(vegetation_potential * organic_retention, 0.0, 1.0)


static func leaching_for(
		temperature: float, ecological_moisture: float, drainage_index: float
) -> float:
	var leaching_temperature := smoothstep(15.0, 30.0, temperature)
	var leaching_moisture := smoothstep(0.45, 0.75, ecological_moisture)
	return clampf(
		leaching_temperature * leaching_moisture * drainage_index, 0.0, 1.0
	)


static func soil_fertility_for(
		parent_nutrient: float,
		organic_matter: float,
		deposition_tendency: float,
		leaching: float
) -> float:
	return clampf(
		0.55 * parent_nutrient + 0.30 * organic_matter \
				+ 0.20 * deposition_tendency - 0.25 * leaching,
		0.0,
		1.0
	)


static func _has_no_surface_soil(biome_id: int) -> bool:
	return biome_id == EcologyCatalog.Biome.MARINE \
			or biome_id == EcologyCatalog.Biome.LAKE \
			or biome_id == EcologyCatalog.Biome.GLACIER


static func _inputs_are_valid(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		hydrology: WorldHydrologyLayer,
		geology: GeologyLayer,
		surface_water: SurfaceWaterLayer,
		ecology: EcologyLayer,
		settings: SoilSettings
) -> bool:
	if graph == null or terrain == null or climate == null or hydrology == null \
			or geology == null or surface_water == null or ecology == null:
		push_error(
			"Soil requires Spatial, Final Terrain, Final Climate, Formal Hydrology, "
			+ "Geology, Surface Water, and Ecology"
		)
		return false
	var count := graph.cell_count()
	if count == 0 \
			or terrain.terrain_height.size() != count \
			or climate.temperature.size() != count \
			or climate.precipitation.size() != count \
			or hydrology.flow_accumulation.size() != count \
			or geology.material_id.size() != count \
			or geology.erodibility.size() != count \
			or surface_water.lake_id.size() != count \
			or ecology.drainage_index.size() != count \
			or ecology.ecological_moisture.size() != count \
			or ecology.vegetation_potential.size() != count \
			or ecology.biome_id.size() != count \
			or graph.cell_neighbors.size() != count \
			or graph.cell_neighbor_distances.size() != count:
		push_error("Soil input arrays must contain one value per Cell")
		return false
	if hydrology.settings == null:
		push_error("Soil requires the Formal Hydrology Settings used by flow accumulation")
		return false
	var setting_errors := settings.validate()
	if not setting_errors.is_empty():
		push_error("Invalid Soil settings: " + "; ".join(setting_errors))
		return false
	if not is_finite(hydrology.settings.river_runoff_threshold) \
			or hydrology.settings.river_runoff_threshold < 0.0:
		push_error("Soil requires a finite non-negative river runoff threshold")
		return false
	for cell_id in count:
		var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
		var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
		if neighbors.size() != distances.size():
			push_error("Soil neighbor and distance arrays must have matching lengths")
			return false
		if not is_finite(terrain.terrain_height[cell_id]) \
				or not is_finite(climate.temperature[cell_id]) \
				or not is_finite(climate.precipitation[cell_id]) \
				or climate.precipitation[cell_id] < 0.0 \
				or not is_finite(hydrology.flow_accumulation[cell_id]) \
				or hydrology.flow_accumulation[cell_id] < 0.0 \
				or geology.material_id[cell_id] < 0 \
				or geology.material_id[cell_id] >= GeologyCatalog.MATERIAL_COUNT \
				or not is_finite(geology.erodibility[cell_id]) \
				or geology.erodibility[cell_id] < 0.0 \
				or geology.erodibility[cell_id] > 1.0 \
				or not is_finite(ecology.drainage_index[cell_id]) \
				or ecology.drainage_index[cell_id] < 0.0 \
				or ecology.drainage_index[cell_id] > 1.0 \
				or not is_finite(ecology.ecological_moisture[cell_id]) \
				or ecology.ecological_moisture[cell_id] < 0.0 \
				or ecology.ecological_moisture[cell_id] > 1.0 \
				or not is_finite(ecology.vegetation_potential[cell_id]) \
				or ecology.vegetation_potential[cell_id] < 0.0 \
				or ecology.vegetation_potential[cell_id] > 1.0 \
				or ecology.biome_id[cell_id] < 0 \
				or ecology.biome_id[cell_id] >= EcologyCatalog.BIOME_COUNT:
			push_error("Soil Cell inputs contain invalid values")
			return false
		for neighbor_index in neighbors.size():
			if neighbors[neighbor_index] < 0 or neighbors[neighbor_index] >= count \
					or not is_finite(distances[neighbor_index]) \
					or distances[neighbor_index] <= 0.0:
				push_error("Soil received invalid Spatial neighbor data")
				return false
	return true
