extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_permeability_increases_drainage()
	_test_slope_increases_drainage()
	_test_closed_basin_reduces_surface_escape()
	_test_precipitation_increases_moisture()
	_test_temperature_evaporation_reduces_moisture()
	_test_river_bonus_is_monotonic_and_capped()
	_test_lake_shore_bonus()
	_test_vegetation_temperature_suitability()
	_test_water_vegetation_is_zero()
	_test_wetland_requires_high_moisture_and_low_drainage()
	_test_biome_matrix()
	_test_determinism()
	_test_array_ranges_and_validator()
	_finish()


func _test_permeability_increases_drainage() -> void:
	var result := _make_case(
		PackedFloat32Array([5.0, 5.0]),
		PackedFloat32Array([12.0, 12.0]),
		PackedFloat32Array([20.0, 20.0]),
		PackedFloat32Array([0.1, 0.9]),
		PackedFloat32Array([0.0, 0.0])
	)
	var layer: EcologyLayer = result.layer
	_expect(layer != null, "permeability comparison should generate")
	if layer != null:
		_expect(
			layer.drainage_index[1] >= layer.drainage_index[0],
			"higher permeability must not reduce Drainage"
		)


func _test_slope_increases_drainage() -> void:
	var graph := _pair_graph()
	var heights := PackedFloat32Array([10.0, 0.0, 10.0, 9.9])
	var steep_slope := EcologyGenerator.maximum_descending_slope(graph, heights, 0)
	var gentle_slope := EcologyGenerator.maximum_descending_slope(graph, heights, 2)
	var settings := EcologySettings.new()
	_expect(steep_slope > gentle_slope, "maximum descending slope must use height drop and distance")
	_expect(
		EcologyGenerator.drainage_index_for(0.2, steep_slope, false, settings)
				> EcologyGenerator.drainage_index_for(0.2, gentle_slope, false, settings),
		"steeper terrain must have higher Drainage at equal permeability"
	)


func _test_closed_basin_reduces_surface_escape() -> void:
	var settings := EcologySettings.new()
	var open_drainage := EcologyGenerator.drainage_index_for(0.2, 0.1, false, settings)
	var closed_drainage := EcologyGenerator.drainage_index_for(0.2, 0.1, true, settings)
	var permeable_closed := EcologyGenerator.drainage_index_for(0.9, 0.1, true, settings)
	_expect(closed_drainage < open_drainage, "Closed Basin must reduce surface drainage")
	_expect(
		permeable_closed >= 0.9,
		"a high-permeability Closed Basin must still allow high final Drainage"
	)


func _test_precipitation_increases_moisture() -> void:
	var result := _make_case(
		PackedFloat32Array([5.0, 5.0]),
		PackedFloat32Array([15.0, 15.0]),
		PackedFloat32Array([2.0, 60.0]),
		PackedFloat32Array([0.3, 0.3]),
		PackedFloat32Array([0.0, 0.0])
	)
	var layer: EcologyLayer = result.layer
	_expect(layer != null, "precipitation comparison should generate")
	if layer != null:
		_expect(
			layer.ecological_moisture[1] >= layer.ecological_moisture[0],
			"higher precipitation must not reduce Ecological Moisture"
		)


func _test_temperature_evaporation_reduces_moisture() -> void:
	var result := _make_case(
		PackedFloat32Array([5.0, 5.0]),
		PackedFloat32Array([-20.0, 35.0]),
		PackedFloat32Array([20.0, 20.0]),
		PackedFloat32Array([0.3, 0.3]),
		PackedFloat32Array([0.0, 0.0])
	)
	var layer: EcologyLayer = result.layer
	_expect(layer != null, "temperature comparison should generate")
	if layer != null:
		_expect(
			layer.ecological_moisture[1] <= layer.ecological_moisture[0],
			"higher evaporation temperature must not increase Ecological Moisture"
		)
	var evaporation := SurfaceWaterSettings.new()
	_expect(evaporation.evaporation_factor(-20.0) == 0.0, "cold evaporation factor should be zero")
	_expect(evaporation.evaporation_factor(35.0) == 1.0, "hot evaporation factor should be one")
	_expect(
		is_equal_approx(evaporation.evaporation_rate(-20.0), 4.0)
				and is_equal_approx(evaporation.evaporation_rate(35.0), 24.0),
		"shared factor extraction must preserve v1.8 evaporation rate endpoints"
	)


func _test_river_bonus_is_monotonic_and_capped() -> void:
	var settings := EcologySettings.new()
	var dry_channel := EcologyGenerator.ecological_moisture_for(
		0.0, 0.5, 0.5, EcologyGenerator.river_strength_for(0.0, 5000.0), 0.0, settings
	)
	var full_channel := EcologyGenerator.ecological_moisture_for(
		0.0,
		0.5,
		0.5,
		EcologyGenerator.river_strength_for(100000.0, 5000.0),
		0.0,
		settings
	)
	_expect(full_channel > dry_channel, "greater flow accumulation must increase river moisture support")
	_expect(
		full_channel - dry_channel <= settings.max_river_bonus + 0.000001,
		"River Bonus must never exceed 0.20"
	)
	_expect(
		is_equal_approx(EcologyGenerator.river_strength_for(100000.0, 5000.0), 1.0),
		"twenty thresholds of accumulation should saturate the specified log curve"
	)


func _test_lake_shore_bonus() -> void:
	var result := _make_case(
		PackedFloat32Array([5.0, 5.0, 5.0, 5.0]),
		PackedFloat32Array([15.0, 15.0, 15.0, 15.0]),
		PackedFloat32Array([10.0, 10.0, 10.0, 10.0]),
		PackedFloat32Array([0.3, 0.3, 0.3, 0.3]),
		PackedFloat32Array([0.0, 0.0, 0.0, 0.0]),
		PackedInt32Array([-1, -1, -1, -1]),
		PackedInt32Array([-1, -1, 0, -1])
	)
	var layer: EcologyLayer = result.layer
	_expect(layer != null, "Lake Shore comparison should generate")
	if layer != null:
		_expect(
			layer.ecological_moisture[3] > layer.ecological_moisture[0],
			"a one-ring Lake Shore Cell should be wetter than an equivalent inland Cell"
		)


func _test_vegetation_temperature_suitability() -> void:
	var settings := EcologySettings.new()
	var temperate := EcologyGenerator.vegetation_potential_for(0.8, 20.0, settings)
	var frozen := EcologyGenerator.vegetation_potential_for(0.8, -20.0, settings)
	_expect(temperate > 0.7, "warm wet conditions should support high Vegetation Potential")
	_expect(frozen < temperate * 0.2, "extreme cold must strongly reduce Vegetation Potential")


func _test_water_vegetation_is_zero() -> void:
	var result := _make_case(
		PackedFloat32Array([-5.0, 5.0]),
		PackedFloat32Array([20.0, 20.0]),
		PackedFloat32Array([100.0, 100.0]),
		PackedFloat32Array([0.0, 0.0]),
		PackedFloat32Array([100000.0, 100000.0]),
		PackedInt32Array([-1, -1]),
		PackedInt32Array([-1, 0])
	)
	var layer: EcologyLayer = result.layer
	_expect(layer != null, "water override case should generate")
	if layer != null:
		_expect(layer.vegetation_potential[0] == 0.0, "Marine vegetation must be zero")
		_expect(layer.vegetation_potential[1] == 0.0, "Lake vegetation must be zero")
		_expect(layer.biome_id[0] == EcologyCatalog.Biome.MARINE, "Ocean must classify as Marine")
		_expect(layer.biome_id[1] == EcologyCatalog.Biome.LAKE, "Lake must classify as Lake")


func _test_wetland_requires_high_moisture_and_low_drainage() -> void:
	var result := _make_case(
		PackedFloat32Array([5.0, 5.0]),
		PackedFloat32Array([0.0, 0.0]),
		PackedFloat32Array([100.0, 100.0]),
		PackedFloat32Array([0.0, 1.0]),
		PackedFloat32Array([0.0, 0.0])
	)
	var layer: EcologyLayer = result.layer
	_expect(layer != null, "Wetland comparison should generate")
	if layer != null:
		_expect(
			layer.ecological_moisture[0] >= 0.53
					and layer.biome_id[0] == EcologyCatalog.Biome.WETLAND,
			"high-Moisture low-Drainage land should be Wetland without Hydrology support"
		)
		_expect(
			layer.biome_id[1] != EcologyCatalog.Biome.WETLAND,
			"high Drainage must prevent Wetland even when moisture is high"
		)
	var settings := EcologySettings.new()
	_expect(
		not EcologyGenerator.is_wetland_candidate(0.529, 0.0, settings),
		"Moisture below 0.53 must prevent Wetland"
	)
	_expect(
		not EcologyGenerator.is_wetland_candidate(0.8, 0.301, settings),
		"Drainage above 0.30 must prevent Wetland"
	)


func _test_biome_matrix() -> void:
	var cases := [
		[30.0, 0.10, EcologyCatalog.Biome.HOT_DESERT],
		[12.0, 0.20, EcologyCatalog.Biome.GRASSLAND],
		[30.0, 0.40, EcologyCatalog.Biome.SAVANNA],
		[5.0, 0.55, EcologyCatalog.Biome.TAIGA],
		[15.0, 0.45, EcologyCatalog.Biome.TEMPERATE_FOREST],
		[30.0, 0.75, EcologyCatalog.Biome.TROPICAL_RAINFOREST],
		[0.0, 0.40, EcologyCatalog.Biome.TUNDRA],
	]
	for entry in cases:
		_expect(
			EcologyCatalog.matrix_biome(entry[0], entry[1]) == entry[2],
			"fixed Biome Matrix case should classify as %s" % EcologyCatalog.biome_name(entry[2])
		)


func _test_determinism() -> void:
	var first: EcologyLayer = _mixed_case().layer
	var second: EcologyLayer = _mixed_case().layer
	_expect(first != null and second != null, "determinism cases should generate")
	if first == null or second == null:
		return
	_expect(first.drainage_index == second.drainage_index, "Drainage must be deterministic")
	_expect(first.ecological_moisture == second.ecological_moisture, "Moisture must be deterministic")
	_expect(first.vegetation_potential == second.vegetation_potential, "Vegetation must be deterministic")
	_expect(first.biome_id == second.biome_id, "Biome must be deterministic")


func _test_array_ranges_and_validator() -> void:
	var result := _mixed_case()
	var layer: EcologyLayer = result.layer
	_expect(layer != null, "range validation case should generate")
	if layer == null:
		return
	for values in [layer.drainage_index, layer.ecological_moisture, layer.vegetation_potential]:
		_expect(values.size() == result.graph.cell_count(), "each continuous Ecology array must match Cell Count")
		for value in values:
			_expect(is_finite(value) and value >= 0.0 and value <= 1.0, "continuous Ecology values must be finite in [0, 1]")
	_expect(layer.biome_id.size() == result.graph.cell_count(), "biome_id must match Cell Count")
	_expect(
		result.terrain.terrain_height == result.terrain_before,
		"Ecology must not modify Final Terrain"
	)
	_expect(
		result.climate.temperature == result.temperature_before \
				and result.climate.precipitation == result.precipitation_before,
		"Ecology must not modify Final Climate"
	)
	_expect(
		result.hydrology.flow_accumulation == result.accumulation_before,
		"Ecology must not modify Formal Hydrology"
	)
	_expect(
		result.geology.permeability == result.permeability_before,
		"Ecology must not modify Geology"
	)
	_expect(
		result.surface_water.lake_id == result.lake_id_before,
		"Ecology must not modify Surface Water"
	)
	_expect(
		EcologyValidator.validate(
			result.graph, result.terrain, result.climate, result.surface_water, layer
		).is_empty(),
		"generated Ecology should pass its Validator"
	)


func _mixed_case() -> Dictionary:
	return _make_case(
		PackedFloat32Array([-5.0, 0.0, 2.0, 8.0, 8.0, 5.0]),
		PackedFloat32Array([20.0, -15.0, 5.0, 15.0, 30.0, 12.0]),
		PackedFloat32Array([20.0, 5.0, 20.0, 45.0, 2.0, 100.0]),
		PackedFloat32Array([0.2, 0.1, 0.5, 0.2, 0.8, 0.0]),
		PackedFloat32Array([0.0, 100.0, 5000.0, 25000.0, 0.0, 100000.0]),
		PackedInt32Array([-1, -1, -1, -1, -1, 0]),
		PackedInt32Array([-1, -1, -1, -1, 0, -1])
	)


func _make_case(
		heights: PackedFloat32Array,
		temperatures: PackedFloat32Array,
		precipitation: PackedFloat32Array,
		permeability: PackedFloat32Array,
		flow_accumulation: PackedFloat32Array,
		closed_basin_id: PackedInt32Array = PackedInt32Array(),
		lake_id: PackedInt32Array = PackedInt32Array()
) -> Dictionary:
	var graph := _line_graph(heights.size())
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = heights
	var climate := WorldClimateLayer.new()
	climate.temperature = temperatures
	climate.precipitation = precipitation
	var geology := GeologyLayer.new()
	geology.permeability = permeability
	var hydrology := WorldHydrologyLayer.new()
	hydrology.settings = WorldHydrologySettings.new()
	hydrology.flow_accumulation = flow_accumulation
	if closed_basin_id.is_empty():
		closed_basin_id.resize(heights.size())
		closed_basin_id.fill(-1)
	var surface_water := SurfaceWaterLayer.new()
	if lake_id.is_empty():
		lake_id.resize(heights.size())
		lake_id.fill(-1)
	surface_water.lake_id = lake_id
	surface_water.surface_water_depth.resize(heights.size())
	var terrain_before := terrain.terrain_height.duplicate()
	var temperature_before := climate.temperature.duplicate()
	var precipitation_before := climate.precipitation.duplicate()
	var accumulation_before := hydrology.flow_accumulation.duplicate()
	var permeability_before := geology.permeability.duplicate()
	var lake_id_before := surface_water.lake_id.duplicate()
	var layer := EcologyGenerator.generate(
		graph,
		terrain,
		climate,
		hydrology,
		closed_basin_id,
		geology,
		surface_water,
		EcologySettings.new(),
		SurfaceWaterSettings.new()
	)
	return {
		"graph": graph,
		"terrain": terrain,
		"climate": climate,
		"hydrology": hydrology,
		"closed_basin_id": closed_basin_id,
		"geology": geology,
		"surface_water": surface_water,
		"terrain_before": terrain_before,
		"temperature_before": temperature_before,
		"precipitation_before": precipitation_before,
		"accumulation_before": accumulation_before,
		"permeability_before": permeability_before,
		"lake_id_before": lake_id_before,
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
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(1, 4.0, 1.0, 4, 0.9)
	graph.cell_centers = PackedVector2Array([
		Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(2.0, 0.5), Vector2(3.0, 0.5)
	])
	graph.cell_neighbors = [
		PackedInt32Array([1]),
		PackedInt32Array([0]),
		PackedInt32Array([3]),
		PackedInt32Array([2]),
	]
	graph.cell_neighbor_distances = [
		PackedFloat64Array([1.0]),
		PackedFloat64Array([1.0]),
		PackedFloat64Array([1.0]),
		PackedFloat64Array([1.0]),
	]
	return graph


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Ecology / Surface Environment: all 13 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Ecology / Surface Environment: %d failures" % _failures.size())
		quit(1)
