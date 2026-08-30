extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_determinism()
	_test_steep_land_has_thinner_soil_than_flat_land()
	_test_valley_has_deeper_soil_than_ridge()
	_test_parent_material_texture_semantics()
	_test_low_drainage_retains_more_organic_matter()
	_test_warm_wet_well_drained_land_leaches_more()
	_test_leaching_reduces_fertility()
	_test_special_surfaces_have_no_soil_and_wetland_does()
	_test_arrays_ranges_validation_and_input_preservation()
	_finish()


func _test_determinism() -> void:
	var first: SoilLayer = _mixed_case().layer
	var second: SoilLayer = _mixed_case().layer
	_expect(first != null and second != null, "determinism cases should generate")
	if first == null or second == null:
		return
	_expect(first.soil_depth == second.soil_depth, "Soil Depth must be deterministic")
	_expect(first.soil_texture_id == second.soil_texture_id, "Soil Texture must be deterministic")
	_expect(first.organic_matter == second.organic_matter, "Organic Matter must be deterministic")
	_expect(first.soil_fertility == second.soil_fertility, "Soil Fertility must be deterministic")


func _test_steep_land_has_thinner_soil_than_flat_land() -> void:
	var result := _make_case(
		PackedFloat32Array([10.0, 0.0, 10.0, 9.9]),
		PackedInt32Array([
			GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
			GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
			GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
			GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
		]),
		PackedFloat32Array([0.5, 0.5, 0.5, 0.5]),
		PackedFloat32Array([15.0, 15.0, 15.0, 15.0]),
		PackedFloat32Array([10.0, 10.0, 10.0, 10.0]),
		PackedFloat32Array([0.0, 0.0, 0.0, 0.0]),
		PackedFloat32Array([0.5, 0.5, 0.5, 0.5]),
		PackedFloat32Array([0.5, 0.5, 0.5, 0.5]),
		PackedFloat32Array([0.5, 0.5, 0.5, 0.5]),
		PackedInt32Array([
			EcologyCatalog.Biome.GRASSLAND,
			EcologyCatalog.Biome.GRASSLAND,
			EcologyCatalog.Biome.GRASSLAND,
			EcologyCatalog.Biome.GRASSLAND,
		]),
		true
	)
	var layer: SoilLayer = result.layer
	_expect(layer != null, "slope comparison should generate")
	if layer != null:
		_expect(layer.soil_depth[0] < layer.soil_depth[2], "steep Land should have thinner Soil than flat Land")


func _test_valley_has_deeper_soil_than_ridge() -> void:
	var result := _make_uniform_case(PackedFloat32Array([10.0, 0.0, 10.0]))
	var layer: SoilLayer = result.layer
	_expect(layer != null, "valley comparison should generate")
	if layer != null:
		_expect(layer.soil_depth[1] > layer.soil_depth[0], "valley Soil should be deeper than ridge Soil")


func _test_parent_material_texture_semantics() -> void:
	var sandstone_fineness := SoilGenerator.texture_fineness_for(
		SoilCatalog.parent_fineness_for(GeologyCatalog.MaterialType.SANDSTONE), 0.0, 0.0
	)
	var shale_fineness := SoilGenerator.texture_fineness_for(
		SoilCatalog.parent_fineness_for(GeologyCatalog.MaterialType.SHALE_MUDSTONE), 0.0, 0.0
	)
	_expect(
		SoilGenerator.texture_for_fineness(sandstone_fineness) == SoilCatalog.TextureType.SANDY,
		"unweathered Sandstone should begin as Sandy Soil"
	)
	_expect(
		SoilGenerator.texture_for_fineness(shale_fineness) == SoilCatalog.TextureType.CLAYEY,
		"unweathered Shale / Mudstone should begin as Clayey Soil"
	)
	_expect(SoilCatalog.TEXTURE_COUNT == 5, "formal Soil Texture must not add a Rocky class")


func _test_low_drainage_retains_more_organic_matter() -> void:
	var low_drainage := SoilGenerator.organic_matter_for(0.8, 15.0, 0.1)
	var high_drainage := SoilGenerator.organic_matter_for(0.8, 15.0, 0.9)
	_expect(low_drainage > high_drainage, "low Drainage should retain more Organic Matter")


func _test_warm_wet_well_drained_land_leaches_more() -> void:
	var warm_wet := SoilGenerator.leaching_for(30.0, 0.75, 1.0)
	var cold_dry := SoilGenerator.leaching_for(0.0, 0.30, 1.0)
	var poorly_drained := SoilGenerator.leaching_for(30.0, 0.75, 0.1)
	_expect(warm_wet > cold_dry, "warm wet Soil should leach more than cold dry Soil")
	_expect(warm_wet > poorly_drained, "well-drained Soil should leach more than poorly drained Soil")


func _test_leaching_reduces_fertility() -> void:
	var low_leaching := SoilGenerator.soil_fertility_for(0.6, 0.5, 0.3, 0.1)
	var high_leaching := SoilGenerator.soil_fertility_for(0.6, 0.5, 0.3, 0.9)
	_expect(high_leaching < low_leaching, "higher leaching must lower Soil Fertility")


func _test_special_surfaces_have_no_soil_and_wetland_does() -> void:
	var biomes := PackedInt32Array([
		EcologyCatalog.Biome.MARINE,
		EcologyCatalog.Biome.LAKE,
		EcologyCatalog.Biome.GLACIER,
		EcologyCatalog.Biome.WETLAND,
	])
	var result := _make_case(
		PackedFloat32Array([-5.0, 5.0, 50.0, 5.0]),
		PackedInt32Array([
			GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK,
			GeologyCatalog.MaterialType.SHALE_MUDSTONE,
			GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
			GeologyCatalog.MaterialType.SHALE_MUDSTONE,
		]),
		PackedFloat32Array([0.6, 0.75, 0.15, 0.75]),
		PackedFloat32Array([20.0, 20.0, -20.0, 18.0]),
		PackedFloat32Array([20.0, 30.0, 10.0, 50.0]),
		PackedFloat32Array([0.0, 0.0, 0.0, 5000.0]),
		PackedFloat32Array([0.5, 0.0, 0.2, 0.2]),
		PackedFloat32Array([0.5, 1.0, 0.2, 0.7]),
		PackedFloat32Array([0.0, 0.0, 0.0, 0.8]),
		biomes,
		false,
		PackedInt32Array([-1, 0, -1, -1])
	)
	var layer: SoilLayer = result.layer
	_expect(layer != null, "special Surface case should generate")
	if layer == null:
		return
	for cell_id in 3:
		_expect(layer.soil_depth[cell_id] == 0.0, "special Surface Soil Depth must be zero")
		_expect(layer.organic_matter[cell_id] == 0.0, "special Surface Organic Matter must be zero")
		_expect(layer.soil_fertility[cell_id] == 0.0, "special Surface Fertility must be zero")
		_expect(layer.soil_texture_id[cell_id] == SoilCatalog.TextureType.NONE, "special Surface Texture must be None")
	_expect(layer.soil_texture_id[3] != SoilCatalog.TextureType.NONE, "Wetland should generate ordinary Surface Soil")


func _test_arrays_ranges_validation_and_input_preservation() -> void:
	var result := _mixed_case()
	var layer: SoilLayer = result.layer
	_expect(layer != null, "range validation case should generate")
	if layer == null:
		return
	for values in [layer.soil_depth, layer.organic_matter, layer.soil_fertility]:
		_expect(values.size() == result.graph.cell_count(), "each continuous Soil array must match Cell Count")
		for value in values:
			_expect(is_finite(value) and value >= 0.0 and value <= 1.0, "continuous Soil values must be finite in [0, 1]")
	_expect(layer.soil_texture_id.size() == result.graph.cell_count(), "Soil Texture length must match")
	_expect(
		SoilValidator.validate(result.graph, result.terrain, result.surface_water, result.ecology, layer).is_empty(),
		"generated Soil should pass its Validator"
	)
	_expect(result.terrain.terrain_height == result.terrain_before, "Soil must not modify Final Terrain")
	_expect(result.climate.temperature == result.temperature_before, "Soil must not modify Final Climate")
	_expect(result.hydrology.flow_accumulation == result.accumulation_before, "Soil must not modify Formal Hydrology")
	_expect(result.geology.material_id == result.material_before, "Soil must not modify Geology")
	_expect(result.surface_water.lake_id == result.lake_before, "Soil must not modify Surface Water")
	_expect(result.ecology.biome_id == result.biome_before, "Soil must not modify Ecology")


func _mixed_case() -> Dictionary:
	return _make_case(
		PackedFloat32Array([-5.0, 0.0, 2.0, 8.0, 20.0, 5.0]),
		PackedInt32Array([
			GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK,
			GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
			GeologyCatalog.MaterialType.SANDSTONE,
			GeologyCatalog.MaterialType.SHALE_MUDSTONE,
			GeologyCatalog.MaterialType.VOLCANIC_ROCK,
			GeologyCatalog.MaterialType.CARBONATE_ROCK,
		]),
		PackedFloat32Array([0.6, 0.15, 0.55, 0.75, 0.3, 0.45]),
		PackedFloat32Array([20.0, -10.0, 5.0, 15.0, 30.0, 12.0]),
		PackedFloat32Array([20.0, 5.0, 20.0, 45.0, 2.0, 100.0]),
		PackedFloat32Array([0.0, 100.0, 5000.0, 25000.0, 0.0, 100000.0]),
		PackedFloat32Array([0.2, 0.1, 0.5, 0.2, 0.8, 0.0]),
		PackedFloat32Array([0.3, 0.2, 0.5, 0.7, 0.1, 0.8]),
		PackedFloat32Array([0.0, 0.1, 0.5, 0.8, 0.2, 0.9]),
		PackedInt32Array([
			EcologyCatalog.Biome.MARINE,
			EcologyCatalog.Biome.TUNDRA,
			EcologyCatalog.Biome.GRASSLAND,
			EcologyCatalog.Biome.TEMPERATE_FOREST,
			EcologyCatalog.Biome.HOT_DESERT,
			EcologyCatalog.Biome.WETLAND,
		])
	)


func _make_uniform_case(heights: PackedFloat32Array) -> Dictionary:
	var count := heights.size()
	var materials := PackedInt32Array()
	materials.resize(count)
	materials.fill(GeologyCatalog.MaterialType.CRYSTALLINE_ROCK)
	var erodibility := PackedFloat32Array()
	erodibility.resize(count)
	erodibility.fill(0.5)
	var temperature := PackedFloat32Array()
	temperature.resize(count)
	temperature.fill(15.0)
	var precipitation := PackedFloat32Array()
	precipitation.resize(count)
	precipitation.fill(10.0)
	var flow := PackedFloat32Array()
	flow.resize(count)
	var drainage := PackedFloat32Array()
	drainage.resize(count)
	drainage.fill(0.5)
	var moisture := PackedFloat32Array()
	moisture.resize(count)
	moisture.fill(0.5)
	var vegetation := PackedFloat32Array()
	vegetation.resize(count)
	vegetation.fill(0.5)
	var biomes := PackedInt32Array()
	biomes.resize(count)
	biomes.fill(EcologyCatalog.Biome.GRASSLAND)
	return _make_case(
		heights, materials, erodibility, temperature, precipitation, flow,
		drainage, moisture, vegetation, biomes
	)


func _make_case(
		heights: PackedFloat32Array,
		materials: PackedInt32Array,
		erodibility: PackedFloat32Array,
		temperature: PackedFloat32Array,
		precipitation: PackedFloat32Array,
		flow_accumulation: PackedFloat32Array,
		drainage: PackedFloat32Array,
		moisture: PackedFloat32Array,
		vegetation: PackedFloat32Array,
		biomes: PackedInt32Array,
		pair_graph: bool = false,
		lake_id: PackedInt32Array = PackedInt32Array()
) -> Dictionary:
	var graph := _pair_graph() if pair_graph else _line_graph(heights.size())
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = heights
	var climate := WorldClimateLayer.new()
	climate.temperature = temperature
	climate.precipitation = precipitation
	var hydrology := WorldHydrologyLayer.new()
	hydrology.settings = WorldHydrologySettings.new()
	hydrology.flow_accumulation = flow_accumulation
	var geology := GeologyLayer.new()
	geology.material_id = materials
	geology.erodibility = erodibility
	var surface_water := SurfaceWaterLayer.new()
	if lake_id.is_empty():
		lake_id.resize(heights.size())
		lake_id.fill(-1)
	surface_water.lake_id = lake_id
	surface_water.surface_water_depth.resize(heights.size())
	var ecology := EcologyLayer.new()
	ecology.drainage_index = drainage
	ecology.ecological_moisture = moisture
	ecology.vegetation_potential = vegetation
	ecology.biome_id = biomes
	var terrain_before := heights.duplicate()
	var temperature_before := temperature.duplicate()
	var accumulation_before := flow_accumulation.duplicate()
	var material_before := materials.duplicate()
	var lake_before := lake_id.duplicate()
	var biome_before := biomes.duplicate()
	var layer := SoilGenerator.generate(
		graph, terrain, climate, hydrology, geology, surface_water, ecology, SoilSettings.new()
	)
	return {
		"graph": graph,
		"terrain": terrain,
		"climate": climate,
		"hydrology": hydrology,
		"geology": geology,
		"surface_water": surface_water,
		"ecology": ecology,
		"terrain_before": terrain_before,
		"temperature_before": temperature_before,
		"accumulation_before": accumulation_before,
		"material_before": material_before,
		"lake_before": lake_before,
		"biome_before": biome_before,
		"layer": layer,
	}


func _line_graph(cell_count: int) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(1, float(cell_count), 1.0, cell_count, 0.9)
	graph.cell_centers.resize(cell_count)
	graph.cell_neighbors.resize(cell_count)
	graph.cell_neighbor_distances.resize(cell_count)
	for cell_id in cell_count:
		graph.cell_centers[cell_id] = Vector2(float(cell_id), 0.5)
		var neighbors := PackedInt32Array()
		var distances := PackedFloat64Array()
		if cell_id > 0:
			neighbors.append(cell_id - 1)
			distances.append(1.0)
		if cell_id + 1 < cell_count:
			neighbors.append(cell_id + 1)
			distances.append(1.0)
		graph.cell_neighbors[cell_id] = neighbors
		graph.cell_neighbor_distances[cell_id] = distances
	return graph


func _pair_graph() -> SpatialGraph:
	var graph := _line_graph(4)
	graph.cell_neighbors = [
		PackedInt32Array([1]), PackedInt32Array([0]),
		PackedInt32Array([3]), PackedInt32Array([2]),
	]
	graph.cell_neighbor_distances = [
		PackedFloat64Array([1.0]), PackedFloat64Array([1.0]),
		PackedFloat64Array([1.0]), PackedFloat64Array([1.0]),
	]
	return graph


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Soil Foundation: all 9 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Soil Foundation: %d failures" % _failures.size())
		quit(1)
