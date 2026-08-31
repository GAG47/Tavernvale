extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_agriculture_factors()
	_test_biome_resources()
	_test_geology_resources()
	_test_mineral_channels()
	_test_aquatic_semantics()
	_test_generator_structure_determinism_and_preservation()
	_test_validator_rejects_invalid_outputs()
	_finish()


func _test_agriculture_factors() -> void:
	_expect(ResourcePotentialGenerator.texture_factor_for(SoilCatalog.TextureType.LOAMY) == 1.0,
		"Loamy texture should be the strongest Agriculture texture")
	_expect(ResourcePotentialGenerator.texture_factor_for(SoilCatalog.TextureType.NONE) == 0.0,
		"None texture should provide no Agriculture support")
	var suitable := ResourcePotentialGenerator.agriculture_potential_for(
		0.8, 0.8, SoilCatalog.TextureType.LOAMY, 20.0, 0.6, 0.5, 0.1
	)
	var cold := ResourcePotentialGenerator.agriculture_potential_for(
		0.8, 0.8, SoilCatalog.TextureType.LOAMY, -5.0, 0.6, 0.5, 0.1
	)
	var steep := ResourcePotentialGenerator.agriculture_potential_for(
		0.8, 0.8, SoilCatalog.TextureType.LOAMY, 20.0, 0.6, 0.5, 0.9
	)
	var poor_soil := ResourcePotentialGenerator.agriculture_potential_for(
		0.2, 0.2, SoilCatalog.TextureType.LOAMY, 20.0, 0.6, 0.5, 0.1
	)
	var dry := ResourcePotentialGenerator.agriculture_potential_for(
		0.8, 0.8, SoilCatalog.TextureType.LOAMY, 20.0, 0.05, 0.5, 0.1
	)
	var lower_fertility := ResourcePotentialGenerator.agriculture_potential_for(
		0.3, 0.8, SoilCatalog.TextureType.LOAMY, 20.0, 0.6, 0.5, 0.1
	)
	var shallower_soil := ResourcePotentialGenerator.agriculture_potential_for(
		0.8, 0.3, SoilCatalog.TextureType.LOAMY, 20.0, 0.6, 0.5, 0.1
	)
	_expect(suitable > cold, "Suitable temperature should raise Agriculture Potential")
	_expect(suitable > steep, "Gentle terrain should raise Agriculture Potential")
	_expect(suitable > poor_soil, "Fertility and Soil Depth should raise Agriculture Potential")
	_expect(suitable > dry, "Very low moisture should lower Agriculture Potential")
	_expect(suitable >= lower_fertility, "Fertility should not lower Agriculture Potential")
	_expect(suitable >= shallower_soil, "Soil Depth should not lower Agriculture Potential")


func _test_biome_resources() -> void:
	_expect(
		ResourcePotentialGenerator.woody_biome_factor_for(EcologyCatalog.Biome.TROPICAL_RAINFOREST)
				> ResourcePotentialGenerator.woody_biome_factor_for(EcologyCatalog.Biome.GRASSLAND),
		"Rainforest should provide stronger Timber suitability than Grassland"
	)
	_expect(
		ResourcePotentialGenerator.forage_biome_factor_for(EcologyCatalog.Biome.GRASSLAND)
				> ResourcePotentialGenerator.forage_biome_factor_for(EcologyCatalog.Biome.TEMPERATE_RAINFOREST),
		"Grassland should provide stronger Forage suitability than Rainforest"
	)
	_expect(ResourcePotentialGenerator.timber_potential_for(
		0.8, EcologyCatalog.Biome.TEMPERATE_FOREST, 0.5, 0.5
	) > ResourcePotentialGenerator.timber_potential_for(
		0.8, EcologyCatalog.Biome.GRASSLAND, 0.5, 0.5
	), "Forest biome should produce more Timber than Grassland at equal vegetation")
	_expect(ResourcePotentialGenerator.timber_potential_for(
		0.8, EcologyCatalog.Biome.TEMPERATE_FOREST, 0.5, 0.5
	) > ResourcePotentialGenerator.timber_potential_for(
		0.3, EcologyCatalog.Biome.TEMPERATE_FOREST, 0.5, 0.5
	), "Vegetation should raise Timber Potential")
	_expect(is_equal_approx(
		ResourcePotentialGenerator.timber_vegetation_support_for(0.25), 0.5
	), "Timber Vegetation Support should use the square-root mapping")
	_expect(ResourcePotentialGenerator.timber_vegetation_support_for(-1.0) == 0.0,
		"Timber Vegetation Support should clamp negative values")
	_expect(ResourcePotentialGenerator.timber_vegetation_support_for(2.0) == 1.0,
		"Timber Vegetation Support should clamp values above one")
	_expect(ResourcePotentialGenerator.forage_potential_for(
		0.8, EcologyCatalog.Biome.GRASSLAND, 0.5
	) > ResourcePotentialGenerator.forage_potential_for(
		0.3, EcologyCatalog.Biome.GRASSLAND, 0.5
	), "Vegetation should raise Forage Potential")
	var grass_high := ResourcePotentialGenerator.forage_potential_for(
		0.50, EcologyCatalog.Biome.GRASSLAND, 0.5
	)
	var grass_medium := ResourcePotentialGenerator.forage_potential_for(
		0.20, EcologyCatalog.Biome.GRASSLAND, 0.5
	)
	var grass_low := ResourcePotentialGenerator.forage_potential_for(
		0.05, EcologyCatalog.Biome.GRASSLAND, 0.5
	)
	var rainforest_high := ResourcePotentialGenerator.forage_potential_for(
		0.50, EcologyCatalog.Biome.TROPICAL_RAINFOREST, 0.5
	)
	_expect(grass_high > grass_medium and grass_medium > grass_low,
		"Forage Growth Support should rise from very low through medium vegetation")
	_expect(grass_high > 0.75, "Grassland at vegetation 0.50 should have high Forage Potential")
	_expect(grass_high > rainforest_high,
		"Grassland should exceed Rainforest Forage at equal vegetation")
	_expect(grass_low < 0.05,
		"Very low vegetation must not gain anomalous Forage from its Biome factor")


func _test_geology_resources() -> void:
	var crystalline := ResourcePotentialGenerator.construction_stone_potential_for(
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK, 0.1
	)
	var shale := ResourcePotentialGenerator.construction_stone_potential_for(
		GeologyCatalog.MaterialType.SHALE_MUDSTONE, 0.1
	)
	_expect(crystalline > shale, "Crystalline Rock should outrank Shale for Construction Stone")
	var deep_crystalline := ResourcePotentialGenerator.construction_stone_potential_for(
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK, 1.0
	)
	_expect(deep_crystalline > 0.0 and deep_crystalline < crystalline,
		"Soil Depth should only mildly reduce Construction Stone Potential")
	var high_host := ResourcePotentialGenerator.base_metal_host_for(
		GeologyCatalog.Province.OROGENIC_BELT, GeologyCatalog.MaterialType.VOLCANIC_ROCK
	)
	var low_host := ResourcePotentialGenerator.base_metal_host_for(
		GeologyCatalog.Province.PASSIVE_MARGIN, GeologyCatalog.MaterialType.SANDSTONE
	)
	_expect(high_host > low_host, "Favorable province/material should raise Base Metal host suitability")


func _test_mineral_channels() -> void:
	var base_nonzero := 0
	var precious_nonzero := 0
	for index in 101:
		var normalized := float(index) / 100.0
		var raw := normalized * 2.0 - 1.0
		if ResourcePotentialGenerator.base_metal_potential_for(1.0, raw) > 0.25:
			base_nonzero += 1
		if ResourcePotentialGenerator.precious_mineral_potential_for(1.0, raw) > 0.0:
			precious_nonzero += 1
	_expect(precious_nonzero < base_nonzero,
		"Precious Mineral concentration should be sparser than Base Metal concentration")
	_expect(
		ResourcePotentialGenerator.base_metal_potential_for(0.9, 0.4)
				> ResourcePotentialGenerator.base_metal_potential_for(0.2, 0.4),
		"Mineral host suitability should affect potential at equal concentration"
	)
	_expect(ResourcePotentialGenerator.base_metal_potential_for(0.8, 0.7)
			> ResourcePotentialGenerator.base_metal_potential_for(0.8, -0.7),
		"Base Metal concentration should raise potential")
	_expect(ResourcePotentialGenerator.precious_mineral_potential_for(0.8, 0.7)
			> ResourcePotentialGenerator.precious_mineral_potential_for(0.8, -0.7),
		"Precious Mineral concentration should raise potential")


func _test_aquatic_semantics() -> void:
	_expect(ResourcePotentialGenerator.freshwater_aquatic_potential_for(true, false, 1.0, 18.0) == 0.0,
		"Ocean must have no Freshwater Aquatic Potential")
	_expect(
		ResourcePotentialGenerator.freshwater_aquatic_potential_for(false, true, 0.0, 18.0)
				> ResourcePotentialGenerator.freshwater_aquatic_potential_for(false, false, 0.0, 18.0),
		"Lake habitat should exceed ordinary non-river Land habitat")
	_expect(ResourcePotentialGenerator.coastal_aquatic_potential_for(18.0, 0.5, 0.8)
			>= ResourcePotentialGenerator.coastal_aquatic_potential_for(18.0, 0.5, 0.0),
		"Estuary strength should raise Coastal Aquatic Potential")
	_expect(ResourcePotentialGenerator.coastal_aquatic_potential_for(18.0, 1.0, 0.0)
			> ResourcePotentialGenerator.coastal_aquatic_potential_for(18.0, 0.0, 0.0),
		"Shallow shelf should exceed deep coastal ocean at equal temperature")
	var resource_settings := ResourcePotentialSettings.new()
	_expect(ResourcePotentialGenerator.shelf_suitability_for(-10.0, resource_settings)
			> ResourcePotentialGenerator.shelf_suitability_for(-80.0, resource_settings),
		"Formal shallow Ocean height should have greater shelf suitability than deep Ocean")
	_expect(ResourcePotentialGenerator.freshwater_aquatic_potential_for(false, false, 0.8, 18.0)
			> ResourcePotentialGenerator.freshwater_aquatic_potential_for(false, false, 0.0, 18.0),
		"Strong formal River habitat should exceed dry Land")
	_expect(ResourcePotentialGenerator.freshwater_aquatic_potential_for(false, true, 0.0, 18.0)
			> ResourcePotentialGenerator.freshwater_aquatic_potential_for(false, true, 0.0, -10.0),
		"Extreme cold should reduce Freshwater Aquatic Potential")


func _test_generator_structure_determinism_and_preservation() -> void:
	var fixture := _fixture()
	var terrain_before: PackedFloat32Array = fixture.terrain.terrain_height.duplicate()
	var flow_before: PackedInt32Array = fixture.hydrology.flow_to.duplicate()
	var soil_before: PackedFloat32Array = fixture.soil.soil_depth.duplicate()
	var first := ResourcePotentialGenerator.generate(
		fixture.graph, fixture.terrain, fixture.climate, fixture.hydrology, fixture.geology,
		fixture.surface_water, fixture.ecology, fixture.soil
	)
	var second := ResourcePotentialGenerator.generate(
		fixture.graph, fixture.terrain, fixture.climate, fixture.hydrology, fixture.geology,
		fixture.surface_water, fixture.ecology, fixture.soil
	)
	_expect(first != null and second != null, "Resource Potential fixture should generate")
	if first == null or second == null:
		return
	_expect(first.agriculture_potential.size() == fixture.graph.cell_count(),
		"Resource Potential arrays should match Cell Count")
	for entry in [
		["Agriculture", first.agriculture_potential, second.agriculture_potential],
		["Timber", first.timber_potential, second.timber_potential],
		["Forage", first.forage_potential, second.forage_potential],
		["Construction Stone", first.construction_stone_potential, second.construction_stone_potential],
		["Base Metal", first.base_metal_potential, second.base_metal_potential],
		["Precious Mineral", first.precious_mineral_potential, second.precious_mineral_potential],
		["Freshwater Aquatic", first.freshwater_aquatic_potential, second.freshwater_aquatic_potential],
		["Coastal Aquatic", first.coastal_aquatic_potential, second.coastal_aquatic_potential],
	]:
		_expect(entry[1] == entry[2], "%s Potential should be deterministic" % entry[0])
	_expect(first.base_metal_potential != first.precious_mineral_potential,
		"Base Metal and Precious Mineral must use independent channels")
	var noise_settings := ResourcePotentialSettings.new()
	var base_raw_a := ResourcePotentialGenerator.base_metal_raw_concentration_at(
		fixture.graph, 1, noise_settings
	)
	var base_raw_repeat := ResourcePotentialGenerator.base_metal_raw_concentration_at(
		fixture.graph, 1, noise_settings
	)
	var base_raw_neighbor := ResourcePotentialGenerator.base_metal_raw_concentration_at(
		fixture.graph, 2, noise_settings
	)
	var precious_raw := ResourcePotentialGenerator.precious_mineral_raw_concentration_at(
		fixture.graph, 1, noise_settings
	)
	_expect(base_raw_a == base_raw_repeat, "Coherent mineral noise should be deterministic")
	_expect(absf(base_raw_a - base_raw_neighbor) < 1.0,
		"Neighboring Cells should sample a coherent Base Metal field")
	_expect(base_raw_a != precious_raw, "Mineral noise channels should be independent")
	_expect(first.agriculture_potential[0] == 0.0 and first.agriculture_potential[3] == 0.0,
		"Ocean and Lake should have zero terrestrial potential")
	_expect(first.freshwater_aquatic_potential[0] == 0.0,
		"Ocean should have zero Freshwater Aquatic Potential")
	_expect(first.coastal_aquatic_potential[0] > 0.0,
		"Coastal Ocean next to a river mouth should have Coastal Aquatic Potential")
	_expect(first.coastal_aquatic_potential[4] == 0.0,
		"Inland Land should have zero Coastal Aquatic Potential")
	_expect(first.coastal_aquatic_potential[5] == 0.0,
		"Non-coastal Ocean should have zero Coastal Aquatic Potential")
	_expect(ResourcePotentialGenerator.estuary_strength_for(
		fixture.graph, fixture.terrain, fixture.hydrology, 0
	) > 0.0, "Formal River mouth should contribute estuary strength")
	_expect(fixture.terrain.terrain_height == terrain_before, "Resource generation must preserve Terrain")
	_expect(fixture.hydrology.flow_to == flow_before, "Resource generation must preserve Hydrology")
	_expect(fixture.soil.soil_depth == soil_before, "Resource generation must preserve Soil")


func _test_validator_rejects_invalid_outputs() -> void:
	var fixture := _fixture()
	var resources := ResourcePotentialGenerator.generate(
		fixture.graph, fixture.terrain, fixture.climate, fixture.hydrology, fixture.geology,
		fixture.surface_water, fixture.ecology, fixture.soil
	)
	_expect(ResourcePotentialValidator.validate(
		fixture.graph, fixture.terrain, fixture.surface_water, resources
	).is_empty(), "valid Resource Potential should pass validation")
	resources.agriculture_potential[0] = 0.2
	_expect(not ResourcePotentialValidator.validate(
		fixture.graph, fixture.terrain, fixture.surface_water, resources
	).is_empty(), "Validator should reject terrestrial potential on Ocean")


func _fixture() -> Dictionary:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(123, 50.0, 10.0, 6, 0.9)
	graph.cell_centers = PackedVector2Array([
		Vector2(5, 5), Vector2(15, 5), Vector2(25, 5), Vector2(35, 5), Vector2(45, 5),
		Vector2(5, 9)
	])
	graph.cell_neighbors = [
		PackedInt32Array([1]), PackedInt32Array([0, 2]), PackedInt32Array([1, 3]),
		PackedInt32Array([2, 4]), PackedInt32Array([3]), PackedInt32Array(),
	]
	graph.cell_neighbor_distances = [
		PackedFloat64Array([10.0]), PackedFloat64Array([10.0, 10.0]),
		PackedFloat64Array([10.0, 10.0]), PackedFloat64Array([10.0, 10.0]),
		PackedFloat64Array([10.0]), PackedFloat64Array(),
	]
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = PackedFloat32Array([-5.0, 3.0, 4.0, 2.0, 5.0, -80.0])
	var climate := WorldClimateLayer.new()
	climate.temperature = PackedFloat32Array([18.0, 18.0, 20.0, 16.0, 22.0, 18.0])
	climate.precipitation = PackedFloat32Array([20.0, 18.0, 15.0, 20.0, 12.0, 20.0])
	var hydrology := WorldHydrologyLayer.new()
	hydrology.settings = WorldHydrologySettings.new()
	hydrology.flow_accumulation = PackedFloat32Array([0.0, 25000.0, 1000.0, 0.0, 500.0, 0.0])
	hydrology.flow_to = PackedInt32Array([WorldHydrologyLayer.FLOW_TO_WATER, 0, 1,
		WorldHydrologyLayer.FLOW_TO_CLOSED_BASIN, 3, WorldHydrologyLayer.FLOW_TO_WATER])
	hydrology.river_network_id = PackedInt32Array([-1, 0, -1, -1, -1, -1])
	var geology := GeologyLayer.new()
	geology.province_id = PackedInt32Array([
		GeologyCatalog.Province.OCEANIC_CRUST, GeologyCatalog.Province.OROGENIC_BELT,
		GeologyCatalog.Province.CRATON, GeologyCatalog.Province.SEDIMENTARY_BASIN,
		GeologyCatalog.Province.PASSIVE_MARGIN, GeologyCatalog.Province.OCEANIC_CRUST,
	])
	geology.material_id = PackedInt32Array([
		GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK,
		GeologyCatalog.MaterialType.VOLCANIC_ROCK,
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
		GeologyCatalog.MaterialType.SHALE_MUDSTONE,
		GeologyCatalog.MaterialType.SANDSTONE,
		GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK,
	])
	var surface_water := SurfaceWaterLayer.new()
	surface_water.lake_id = PackedInt32Array([-1, -1, -1, 0, -1, -1])
	var ecology := EcologyLayer.new()
	ecology.drainage_index = PackedFloat32Array([0.0, 0.4, 0.5, 0.0, 0.3, 0.0])
	ecology.ecological_moisture = PackedFloat32Array([0.0, 0.6, 0.45, 1.0, 0.35, 0.0])
	ecology.vegetation_potential = PackedFloat32Array([0.0, 0.8, 0.7, 0.0, 0.5, 0.0])
	ecology.biome_id = PackedInt32Array([
		EcologyCatalog.Biome.MARINE, EcologyCatalog.Biome.TROPICAL_SEASONAL_FOREST,
		EcologyCatalog.Biome.TEMPERATE_FOREST, EcologyCatalog.Biome.LAKE,
		EcologyCatalog.Biome.GRASSLAND, EcologyCatalog.Biome.MARINE,
	])
	var soil := SoilLayer.new()
	soil.soil_depth = PackedFloat32Array([0.0, 0.6, 0.7, 0.0, 0.5, 0.0])
	soil.soil_texture_id = PackedInt32Array([
		SoilCatalog.TextureType.NONE, SoilCatalog.TextureType.LOAMY,
		SoilCatalog.TextureType.SILTY, SoilCatalog.TextureType.NONE,
		SoilCatalog.TextureType.SANDY, SoilCatalog.TextureType.NONE,
	])
	soil.soil_fertility = PackedFloat32Array([0.0, 0.7, 0.6, 0.0, 0.5, 0.0])
	return {
		"graph": graph, "terrain": terrain, "climate": climate, "hydrology": hydrology,
		"geology": geology, "surface_water": surface_water, "ecology": ecology, "soil": soil,
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Resource Potential: all 7 test groups passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	printerr("Resource Potential: %d failures" % _failures.size())
	quit(1)
