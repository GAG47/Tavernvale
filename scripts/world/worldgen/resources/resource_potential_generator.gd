class_name ResourcePotentialGenerator
extends RefCounted


static func generate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		hydrology: WorldHydrologyLayer,
		geology: GeologyLayer,
		surface_water: SurfaceWaterLayer,
		ecology: EcologyLayer,
		soil: SoilLayer,
		settings: ResourcePotentialSettings = null,
		soil_settings: SoilSettings = null
) -> ResourcePotentialLayer:
	var actual_settings := settings if settings != null else ResourcePotentialSettings.new()
	var actual_soil_settings := soil_settings if soil_settings != null else SoilSettings.new()
	if not _inputs_are_valid(
		graph, terrain, climate, hydrology, geology, surface_water, ecology, soil,
		actual_settings, actual_soil_settings
	):
		return null
	var resources := ResourcePotentialLayer.new()
	var count := graph.cell_count()
	for values in _resource_arrays(resources):
		values.resize(count)
	var base_metal_noise := _make_noise(_channel_seed(
		graph.config.seed, actual_settings.base_metal_noise_seed_salt
	))
	var precious_noise := _make_noise(_channel_seed(
		graph.config.seed, actual_settings.precious_mineral_noise_seed_salt
	))
	for cell_id in count:
		var is_ocean := terrain.terrain_height[cell_id] < 0.0
		var is_lake := surface_water.lake_id[cell_id] >= 0
		var is_land_surface := not is_ocean and not is_lake
		var temperature := climate.temperature[cell_id]
		var river_strength := 0.0
		if hydrology.is_river(cell_id):
			river_strength = EcologyGenerator.river_strength_for(
				hydrology.flow_accumulation[cell_id], hydrology.settings.river_runoff_threshold
			)
		if is_land_surface:
			var slope_factor := SoilGenerator.slope_factor_for(
				graph, terrain.terrain_height, cell_id, actual_soil_settings.slope_reference
			)
			resources.agriculture_potential[cell_id] = agriculture_potential_for(
				soil.soil_fertility[cell_id], soil.soil_depth[cell_id],
				soil.soil_texture_id[cell_id], temperature,
				ecology.ecological_moisture[cell_id], ecology.drainage_index[cell_id], slope_factor
			)
			resources.timber_potential[cell_id] = timber_potential_for(
				ecology.vegetation_potential[cell_id], ecology.biome_id[cell_id],
				soil.soil_depth[cell_id], soil.soil_fertility[cell_id]
			)
			resources.forage_potential[cell_id] = forage_potential_for(
				ecology.vegetation_potential[cell_id], ecology.biome_id[cell_id],
				soil.soil_fertility[cell_id], actual_settings
			)
			resources.construction_stone_potential[cell_id] = construction_stone_potential_for(
				geology.material_id[cell_id], soil.soil_depth[cell_id]
			)
			var base_host := base_metal_host_for(
				geology.province_id[cell_id], geology.material_id[cell_id]
			)
			var precious_host := precious_mineral_host_for(
				geology.province_id[cell_id], geology.material_id[cell_id]
			)
			var position: Vector2 = graph.cell_centers[cell_id]
			var normalized_x := position.x / graph.config.world_width
			var normalized_y := position.y / graph.config.world_height
			var base_raw := base_metal_noise.get_noise_2d(
				normalized_x * actual_settings.base_metal_concentration_scale,
				normalized_y * actual_settings.base_metal_concentration_scale
			)
			var precious_raw := precious_noise.get_noise_2d(
				normalized_x * actual_settings.precious_mineral_concentration_scale,
				normalized_y * actual_settings.precious_mineral_concentration_scale
			)
			resources.base_metal_potential[cell_id] = base_metal_potential_for(base_host, base_raw)
			resources.precious_mineral_potential[cell_id] = precious_mineral_potential_for(
				precious_host, precious_raw
			)
		resources.freshwater_aquatic_potential[cell_id] = freshwater_aquatic_potential_for(
			is_ocean, is_lake, river_strength, temperature
		)
		if is_ocean and is_coastal_ocean_cell(graph, terrain, cell_id):
			resources.coastal_aquatic_potential[cell_id] = coastal_aquatic_potential_for(
				temperature,
				shelf_suitability_for(terrain.terrain_height[cell_id], actual_settings),
				estuary_strength_for(graph, terrain, hydrology, cell_id)
			)
	var errors := ResourcePotentialValidator.validate(
		graph, terrain, surface_water, resources, actual_settings
	)
	if not errors.is_empty():
		push_error("Resource Potential validation failed: " + "; ".join(errors))
		return null
	return resources


static func agriculture_potential_for(
		fertility: float,
		depth: float,
		texture_id: int,
		temperature: float,
		ecological_moisture: float,
		drainage_index: float,
		slope_factor: float
) -> float:
	var soil_quality := 0.50 * fertility + 0.30 * depth + 0.20 * texture_factor_for(texture_id)
	var temperature_suitability := smoothstep(0.0, 10.0, temperature) * (
		1.0 - smoothstep(30.0, 40.0, temperature)
	)
	var water_suitability := smoothstep(0.15, 0.40, ecological_moisture)
	var drainage_suitability := smoothstep(0.05, 0.25, drainage_index)
	var terrain_suitability := 1.0 - smoothstep(0.35, 0.75, slope_factor)
	var climate_suitability := sqrt(maxf(temperature_suitability * water_suitability, 0.0))
	var terrain_support := terrain_suitability * drainage_suitability
	return clampf(
		pow(clampf(soil_quality, 0.0, 1.0), 0.50)
				* pow(clampf(climate_suitability, 0.0, 1.0), 0.35)
				* pow(clampf(terrain_support, 0.0, 1.0), 0.15),
		0.0,
		1.0
	)


static func timber_potential_for(
		vegetation: float, biome_id: int, depth: float, fertility: float
) -> float:
	var soil_support := 0.70 + 0.15 * depth + 0.15 * fertility
	return clampf(
		timber_vegetation_support_for(vegetation)
				* woody_biome_factor_for(biome_id) * soil_support,
		0.0,
		1.0
	)


static func timber_vegetation_support_for(vegetation: float) -> float:
	return sqrt(clampf(vegetation, 0.0, 1.0))


static func forage_potential_for(
		vegetation: float,
		biome_id: int,
		fertility: float,
		settings: ResourcePotentialSettings = null
) -> float:
	var actual_settings := settings if settings != null else ResourcePotentialSettings.new()
	var soil_support := 0.75 + 0.25 * fertility
	return clampf(
		forage_growth_support_for(vegetation, actual_settings)
				* forage_biome_factor_for(biome_id) * soil_support,
		0.0,
		1.0
	)


static func forage_growth_support_for(
		vegetation: float, settings: ResourcePotentialSettings
) -> float:
	return smoothstep(
		settings.forage_vegetation_low, settings.forage_vegetation_full, vegetation
	)


static func construction_stone_potential_for(material_id: int, soil_depth: float) -> float:
	var exposure := 1.0 - 0.25 * clampf(soil_depth, 0.0, 1.0)
	return clampf(construction_material_factor_for(material_id) * exposure, 0.0, 1.0)


static func base_metal_host_for(province_id: int, material_id: int) -> float:
	return sqrt(
		base_metal_province_factor_for(province_id) * base_metal_material_factor_for(material_id)
	)


static func precious_mineral_host_for(province_id: int, material_id: int) -> float:
	return sqrt(
		precious_province_factor_for(province_id) * precious_material_factor_for(material_id)
	)


static func base_metal_potential_for(host: float, raw_noise: float) -> float:
	return clampf(host * (0.25 + 0.75 * base_metal_concentration_for(raw_noise)), 0.0, 1.0)


static func precious_mineral_potential_for(host: float, raw_noise: float) -> float:
	return clampf(host * precious_mineral_concentration_for(raw_noise), 0.0, 1.0)


static func base_metal_concentration_for(raw_noise: float) -> float:
	return smoothstep(0.30, 0.85, clampf((raw_noise + 1.0) * 0.5, 0.0, 1.0))


static func precious_mineral_concentration_for(raw_noise: float) -> float:
	return smoothstep(0.60, 0.92, clampf((raw_noise + 1.0) * 0.5, 0.0, 1.0))


static func base_metal_raw_concentration_at(
		graph: SpatialGraph, cell_id: int, settings: ResourcePotentialSettings
) -> float:
	return _raw_concentration_at(
		graph, cell_id, settings.base_metal_noise_seed_salt,
		settings.base_metal_concentration_scale
	)


static func precious_mineral_raw_concentration_at(
		graph: SpatialGraph, cell_id: int, settings: ResourcePotentialSettings
) -> float:
	return _raw_concentration_at(
		graph, cell_id, settings.precious_mineral_noise_seed_salt,
		settings.precious_mineral_concentration_scale
	)


static func freshwater_aquatic_potential_for(
		is_ocean: bool, is_lake: bool, formal_river_strength: float, temperature: float
) -> float:
	if is_ocean:
		return 0.0
	var water_habitat := maxf(1.0 if is_lake else 0.0, clampf(formal_river_strength, 0.0, 1.0))
	return clampf(water_habitat * freshwater_temperature_suitability_for(temperature), 0.0, 1.0)


static func coastal_aquatic_potential_for(
		temperature: float, shelf_suitability: float, estuary_strength: float
) -> float:
	return clampf(
		coastal_temperature_suitability_for(temperature)
				* (0.45 + 0.35 * clampf(shelf_suitability, 0.0, 1.0)
						+ 0.20 * clampf(estuary_strength, 0.0, 1.0)),
		0.0,
		1.0
	)


static func ocean_depth_for(terrain_height: float) -> float:
	return maxf(-terrain_height, 0.0)


static func shelf_suitability_for(
		terrain_height: float, settings: ResourcePotentialSettings
) -> float:
	return 1.0 - smoothstep(
		settings.coastal_shallow_shelf_depth,
		settings.coastal_deep_shelf_depth,
		ocean_depth_for(terrain_height)
	)


static func freshwater_temperature_suitability_for(temperature: float) -> float:
	return smoothstep(-2.0, 8.0, temperature) * (1.0 - smoothstep(30.0, 38.0, temperature))


static func coastal_temperature_suitability_for(temperature: float) -> float:
	return smoothstep(-5.0, 5.0, temperature) * (1.0 - smoothstep(32.0, 40.0, temperature))


static func is_coastal_ocean_cell(
		graph: SpatialGraph, terrain: TerrainHeightLayer, cell_id: int
) -> bool:
	if cell_id < 0 or cell_id >= graph.cell_count() or terrain.terrain_height[cell_id] >= 0.0:
		return false
	for neighbor_id in graph.cell_neighbors[cell_id]:
		if terrain.terrain_height[neighbor_id] >= 0.0:
			return true
	return false


static func estuary_strength_for(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		hydrology: WorldHydrologyLayer,
		ocean_cell_id: int
) -> float:
	if not is_coastal_ocean_cell(graph, terrain, ocean_cell_id):
		return 0.0
	var maximum_strength := 0.0
	for neighbor_id in graph.cell_neighbors[ocean_cell_id]:
		if terrain.terrain_height[neighbor_id] < 0.0 \
				or not hydrology.is_river(neighbor_id) \
				or hydrology.flow_to[neighbor_id] != ocean_cell_id:
			continue
		maximum_strength = maxf(
			maximum_strength,
			EcologyGenerator.river_strength_for(
				hydrology.flow_accumulation[neighbor_id], hydrology.settings.river_runoff_threshold
			)
		)
	return maximum_strength


static func texture_factor_for(texture_id: int) -> float:
	match texture_id:
		SoilCatalog.TextureType.SANDY:
			return 0.45
		SoilCatalog.TextureType.LOAMY:
			return 1.00
		SoilCatalog.TextureType.SILTY:
			return 0.85
		SoilCatalog.TextureType.CLAYEY:
			return 0.65
		_:
			return 0.0


static func woody_biome_factor_for(biome_id: int) -> float:
	match biome_id:
		EcologyCatalog.Biome.TROPICAL_RAINFOREST, EcologyCatalog.Biome.TEMPERATE_RAINFOREST:
			return 1.0
		EcologyCatalog.Biome.TEMPERATE_FOREST:
			return 0.90
		EcologyCatalog.Biome.TAIGA:
			return 0.85
		EcologyCatalog.Biome.TROPICAL_SEASONAL_FOREST:
			return 0.80
		EcologyCatalog.Biome.WETLAND:
			return 0.35
		EcologyCatalog.Biome.SAVANNA:
			return 0.30
		EcologyCatalog.Biome.GRASSLAND:
			return 0.10
		EcologyCatalog.Biome.TUNDRA:
			return 0.05
		_:
			return 0.0


static func forage_biome_factor_for(biome_id: int) -> float:
	match biome_id:
		EcologyCatalog.Biome.GRASSLAND, EcologyCatalog.Biome.SAVANNA:
			return 1.0
		EcologyCatalog.Biome.TUNDRA:
			return 0.55
		EcologyCatalog.Biome.TROPICAL_SEASONAL_FOREST:
			return 0.40
		EcologyCatalog.Biome.TEMPERATE_FOREST:
			return 0.35
		EcologyCatalog.Biome.TAIGA, EcologyCatalog.Biome.WETLAND:
			return 0.25
		EcologyCatalog.Biome.TEMPERATE_RAINFOREST, EcologyCatalog.Biome.TROPICAL_RAINFOREST:
			return 0.15
		EcologyCatalog.Biome.COLD_DESERT, EcologyCatalog.Biome.HOT_DESERT:
			return 0.05
		_:
			return 0.0


static func construction_material_factor_for(material_id: int) -> float:
	match material_id:
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK:
			return 1.00
		GeologyCatalog.MaterialType.METAMORPHIC_ROCK:
			return 0.95
		GeologyCatalog.MaterialType.CARBONATE_ROCK:
			return 0.90
		GeologyCatalog.MaterialType.VOLCANIC_ROCK:
			return 0.85
		GeologyCatalog.MaterialType.SANDSTONE:
			return 0.80
		GeologyCatalog.MaterialType.SHALE_MUDSTONE:
			return 0.35
		GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK:
			return 0.25
		_:
			return 0.0


static func base_metal_province_factor_for(province_id: int) -> float:
	match province_id:
		GeologyCatalog.Province.OROGENIC_BELT:
			return 1.00
		GeologyCatalog.Province.VOLCANIC_PROVINCE:
			return 0.90
		GeologyCatalog.Province.CRATON:
			return 0.65
		GeologyCatalog.Province.SEDIMENTARY_BASIN:
			return 0.45
		GeologyCatalog.Province.PASSIVE_MARGIN:
			return 0.25
		GeologyCatalog.Province.OCEANIC_CRUST:
			return 0.20
		_:
			return 0.0


static func base_metal_material_factor_for(material_id: int) -> float:
	match material_id:
		GeologyCatalog.MaterialType.VOLCANIC_ROCK:
			return 0.90
		GeologyCatalog.MaterialType.METAMORPHIC_ROCK:
			return 0.85
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK:
			return 0.75
		GeologyCatalog.MaterialType.SHALE_MUDSTONE:
			return 0.45
		GeologyCatalog.MaterialType.CARBONATE_ROCK:
			return 0.35
		GeologyCatalog.MaterialType.SANDSTONE:
			return 0.25
		GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK:
			return 0.20
		_:
			return 0.0


static func precious_province_factor_for(province_id: int) -> float:
	match province_id:
		GeologyCatalog.Province.OROGENIC_BELT:
			return 1.00
		GeologyCatalog.Province.VOLCANIC_PROVINCE:
			return 0.90
		GeologyCatalog.Province.CRATON:
			return 0.55
		GeologyCatalog.Province.SEDIMENTARY_BASIN:
			return 0.30
		GeologyCatalog.Province.PASSIVE_MARGIN:
			return 0.20
		GeologyCatalog.Province.OCEANIC_CRUST:
			return 0.15
		_:
			return 0.0


static func precious_material_factor_for(material_id: int) -> float:
	match material_id:
		GeologyCatalog.MaterialType.METAMORPHIC_ROCK:
			return 1.00
		GeologyCatalog.MaterialType.VOLCANIC_ROCK:
			return 0.90
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK:
			return 0.80
		GeologyCatalog.MaterialType.CARBONATE_ROCK:
			return 0.35
		GeologyCatalog.MaterialType.SHALE_MUDSTONE:
			return 0.30
		GeologyCatalog.MaterialType.SANDSTONE:
			return 0.20
		GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK:
			return 0.15
		_:
			return 0.0


static func _make_noise(seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.50
	noise.fractal_lacunarity = 2.0
	noise.frequency = 1.0
	return noise


static func _channel_seed(world_seed: int, salt: int) -> int:
	return DeterministicRng.stable_mix(world_seed, salt)


static func _raw_concentration_at(
		graph: SpatialGraph, cell_id: int, salt: int, scale: float
) -> float:
	var position: Vector2 = graph.cell_centers[cell_id]
	return _make_noise(_channel_seed(graph.config.seed, salt)).get_noise_2d(
		position.x / graph.config.world_width * scale,
		position.y / graph.config.world_height * scale
	)


static func _resource_arrays(resources: ResourcePotentialLayer) -> Array:
	return [
		resources.agriculture_potential,
		resources.timber_potential,
		resources.forage_potential,
		resources.construction_stone_potential,
		resources.base_metal_potential,
		resources.precious_mineral_potential,
		resources.freshwater_aquatic_potential,
		resources.coastal_aquatic_potential,
	]


static func _inputs_are_valid(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		hydrology: WorldHydrologyLayer,
		geology: GeologyLayer,
		surface_water: SurfaceWaterLayer,
		ecology: EcologyLayer,
		soil: SoilLayer,
		settings: ResourcePotentialSettings,
		soil_settings: SoilSettings
) -> bool:
	if graph == null or terrain == null or climate == null or hydrology == null \
			or geology == null or surface_water == null or ecology == null or soil == null:
		push_error(
			"Resource Potential requires Spatial, Final Terrain, Final Climate, Formal Hydrology, "
			+ "Geology, Surface Water, Ecology, and Soil"
		)
		return false
	var count := graph.cell_count()
	if count == 0 or graph.config == null \
			or graph.config.world_width <= 0.0 or graph.config.world_height <= 0.0 \
			or graph.cell_centers.size() != count or graph.cell_neighbors.size() != count \
			or graph.cell_neighbor_distances.size() != count \
			or terrain.terrain_height.size() != count \
			or climate.temperature.size() != count or climate.precipitation.size() != count \
			or hydrology.flow_accumulation.size() != count or hydrology.flow_to.size() != count \
			or hydrology.river_network_id.size() != count or hydrology.settings == null \
			or geology.province_id.size() != count or geology.material_id.size() != count \
			or surface_water.lake_id.size() != count \
			or ecology.drainage_index.size() != count \
			or ecology.ecological_moisture.size() != count \
			or ecology.vegetation_potential.size() != count or ecology.biome_id.size() != count \
			or soil.soil_depth.size() != count or soil.soil_texture_id.size() != count \
			or soil.soil_fertility.size() != count:
		push_error("Resource Potential input arrays must contain one value per Cell")
		return false
	var errors := settings.validate()
	errors.append_array(soil_settings.validate())
	if not errors.is_empty():
		push_error("Invalid Resource Potential inputs: " + "; ".join(errors))
		return false
	return true
