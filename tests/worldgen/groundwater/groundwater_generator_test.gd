extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_settings_and_pure_formulas()
	_test_recharge_distance_and_maximum()
	_test_ocean_blocks_recharge()
	_test_marine_distance_and_salinity()
	_test_special_cases_and_water_table()
	_test_active_groundwater_and_aquifer()
	_test_surface_relative_aquifer_query()
	_test_validator_rejections()
	_test_determinism_and_mutation()
	var standard := _standard_world_fixture()
	_test_standard_world(standard)
	_finish()


func _test_settings_and_pure_formulas() -> void:
	var settings := GroundwaterSettings.new()
	_expect(settings.validate().is_empty(), "default Groundwater settings must be valid")
	_expect(settings.precipitation_reference == 20.0, "precipitation reference must default to 20")
	_expect(settings.river_recharge_radius == 40.0, "River radius must default to 40")
	_expect(settings.lake_recharge_radius == 60.0, "Lake radius must default to 60")
	_expect(settings.active_groundwater_half_depth == 50.0, "active half-depth must default to 50")
	_expect(GroundwaterGenerator.climate_supply_for(0.0, 20.0) == 0.0, "zero precipitation must give zero Climate Supply")
	_expect(is_equal_approx(GroundwaterGenerator.climate_supply_for(20.0, 20.0), 0.5), "precipitation at reference must give 0.5 Climate Supply")
	_expect(is_equal_approx(GroundwaterGenerator.water_table_depth_for(1.0, 20.0, settings), 6.0), "full supply lowland Water Table depth must be 6")
	_expect(is_equal_approx(GroundwaterGenerator.water_table_depth_for(0.0, 20.0, settings), 50.0), "zero supply lowland Water Table depth must be 50")
	_expect(GroundwaterGenerator.water_table_depth_for(0.5, 80.0, settings) > GroundwaterGenerator.water_table_depth_for(0.5, 20.0, settings), "Highland must deepen Water Table at equal supply")
	var invalid := settings.duplicate_settings()
	invalid.heavy_aquifer_threshold = invalid.light_aquifer_threshold
	_expect(not invalid.validate().is_empty(), "invalid Aquifer threshold ordering must be rejected")


func _test_recharge_distance_and_maximum() -> void:
	var graph := _line_graph(9, 10.0)
	var terrain := _terrain(PackedFloat32Array([10, 10, 10, 10, 10, 10, 10, 10, 10]))
	var hydrology := _hydrology(9, PackedInt32Array([0, -1, 1, -1, -1, -1, -1, -1, -1]))
	var surface_water := _surface_water(PackedInt32Array([-1, -1, -1, -1, -1, 0, -1, 1, -1]))
	var settings := GroundwaterSettings.new()
	var fields := GroundwaterGenerator.recharge_influence_fields(
		graph, terrain, hydrology, surface_water, settings
	)
	var source_strength := EcologyGenerator.river_strength_for(
		hydrology.flow_accumulation[0], hydrology.settings.river_runoff_threshold
	)
	_expect(is_equal_approx(fields.river[0], source_strength), "River source must reuse Ecology River Strength")
	_expect(is_equal_approx(fields.river[1], source_strength * GroundwaterGenerator.distance_influence_for(10.0, 40.0)), "River influence must use graph distance falloff")
	_expect(fields.river[6] == 0.0, "River influence must be zero at radius")
	var expected_river_max := maxf(
		EcologyGenerator.river_strength_for(hydrology.flow_accumulation[0], 5000.0) \
				* GroundwaterGenerator.distance_influence_for(10.0, 40.0),
		EcologyGenerator.river_strength_for(hydrology.flow_accumulation[2], 5000.0) \
				* GroundwaterGenerator.distance_influence_for(10.0, 40.0)
	)
	_expect(is_equal_approx(fields.river[1], expected_river_max), "multiple River sources must use max, not sum")
	var expected_lake_max := maxf(
		GroundwaterGenerator.distance_influence_for(10.0, 60.0),
		GroundwaterGenerator.distance_influence_for(10.0, 60.0)
	)
	_expect(is_equal_approx(fields.lake[6], expected_lake_max), "multiple Lake sources must use max, not sum")
	_expect(fields.lake[5] == 1.0, "Lake source influence must be one")
	var lake_radius_fields := GroundwaterGenerator.recharge_influence_fields(
		_line_graph(7, 10.0),
		_terrain(PackedFloat32Array([10, 10, 10, 10, 10, 10, 10])),
		_hydrology(7, PackedInt32Array([-1, -1, -1, -1, -1, -1, -1])),
		_surface_water(PackedInt32Array([0, -1, -1, -1, -1, -1, -1])),
		settings
	)
	_expect(is_equal_approx(lake_radius_fields.lake[1], GroundwaterGenerator.distance_influence_for(10.0, 60.0)), "Lake influence must use graph distance falloff")
	_expect(lake_radius_fields.lake[6] == 0.0, "Lake influence must be zero at radius")


func _test_ocean_blocks_recharge() -> void:
	var graph := _line_graph(3, 10.0)
	var terrain := _terrain(PackedFloat32Array([10.0, -5.0, 10.0]))
	var hydrology := _hydrology(3, PackedInt32Array([0, -1, -1]))
	var surface_water := _surface_water(PackedInt32Array([-1, -1, -1]))
	var fields := GroundwaterGenerator.recharge_influence_fields(
		graph, terrain, hydrology, surface_water, GroundwaterSettings.new()
	)
	_expect(fields.river[2] == 0.0, "Ocean must not carry River recharge to disconnected Land")
	_expect(fields.river[1] == 0.0, "Ocean must not receive River recharge propagation")


func _test_marine_distance_and_salinity() -> void:
	var graph := _line_graph(7, 10.0)
	var terrain := _terrain(PackedFloat32Array([-5.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0]))
	var settings := GroundwaterSettings.new()
	var influence := GroundwaterGenerator.marine_influence_field(graph, terrain, settings)
	_expect(influence[0] == 1.0, "Ocean debug Marine Influence must be one")
	_expect(is_equal_approx(influence[1], GroundwaterGenerator.distance_influence_for(10.0, 50.0)), "Marine influence must use graph distance")
	_expect(influence[5] == 0.0 and influence[6] == 0.0, "Land at or beyond Marine radius must have zero influence")
	_expect(GroundwaterGenerator.salinity_class_for_pressure(0.1999, settings) == GroundwaterLayer.SalinityClass.FRESH, "pressure below 0.20 must be Fresh")
	_expect(GroundwaterGenerator.salinity_class_for_pressure(0.20, settings) == GroundwaterLayer.SalinityClass.BRACKISH, "pressure 0.20 must be Brackish")
	_expect(GroundwaterGenerator.salinity_class_for_pressure(0.60, settings) == GroundwaterLayer.SalinityClass.SALINE, "pressure 0.60 must be Saline")
	_expect(GroundwaterGenerator.salinity_pressure_for(0.8, 0.8) < GroundwaterGenerator.salinity_pressure_for(0.8, 0.2), "higher supply must lower pressure at equal Marine Influence")


func _test_special_cases_and_water_table() -> void:
	var fixture := _small_generation_fixture()
	var groundwater: GroundwaterLayer = fixture.groundwater
	_expect(groundwater != null, "small Groundwater fixture must generate")
	if groundwater == null:
		return
	_expect(groundwater.groundwater_supply[0] == 1.0, "Ocean supply must be one")
	_expect(groundwater.water_table_z[0] == fixture.terrain.terrain_height[0], "Ocean Water Table must equal Terrain z")
	_expect(groundwater.groundwater_salinity_class[0] == GroundwaterLayer.SalinityClass.SALINE, "Ocean must be Saline")
	_expect(groundwater.groundwater_supply[1] == 1.0, "Lake supply must be one")
	_expect(groundwater.water_table_z[1] == fixture.terrain.terrain_height[1], "Lake Water Table must equal Terrain z")
	_expect(groundwater.groundwater_salinity_class[1] == GroundwaterLayer.SalinityClass.FRESH, "Lake must be Fresh")
	var expected_depth := GroundwaterGenerator.water_table_depth_for(
		groundwater.groundwater_supply[2], fixture.terrain.terrain_height[2], groundwater.settings
	)
	_expect(is_equal_approx(groundwater.water_table_z[2], fixture.terrain.terrain_height[2] - expected_depth), "Land Water Table must be stored as absolute z")
	_expect(is_equal_approx(groundwater.water_table_depth(2, fixture.terrain), expected_depth), "Water Table depth query must be relative to Terrain")
	_expect(GroundwaterValidator.validate(fixture.graph, fixture.terrain, fixture.surface_water, groundwater).is_empty(), "generated Groundwater must pass Validator")


func _test_active_groundwater_and_aquifer() -> void:
	var groundwater := GroundwaterLayer.new()
	groundwater.settings = GroundwaterSettings.new()
	groundwater.groundwater_supply = PackedFloat32Array([0.8])
	groundwater.water_table_z = PackedFloat32Array([20.0])
	groundwater.groundwater_salinity_class = PackedInt32Array([GroundwaterLayer.SalinityClass.FRESH])
	_expect(is_equal_approx(groundwater.active_groundwater_at_z(0, 20.0), 0.8), "active Groundwater at Water Table must equal supply")
	_expect(is_equal_approx(groundwater.active_groundwater_at_z(0, -30.0), 0.4), "active Groundwater at one half-depth must halve")
	_expect(is_equal_approx(groundwater.active_groundwater_at_z(0, -80.0), 0.2), "active Groundwater at two half-depths must quarter")
	_expect(groundwater.active_groundwater_at_z(0, 21.0) == 0.0, "active Groundwater above Water Table must be zero")
	_expect(groundwater.is_below_water_table_at_z(0, 20.0), "Water Table boundary must count as below Water Table")
	_expect(not groundwater.is_below_water_table_at_z(0, 20.001), "z above Water Table must not count as below")

	var strata := _single_rock_strata(RockCatalog.RockType.SANDSTONE, 60.0)
	groundwater.groundwater_supply[0] = 0.80
	groundwater.water_table_z[0] = 21.0
	_expect(is_equal_approx(groundwater.aquifer_yield_at_z(0, 21.0, strata), 0.48), "Sandstone Aquifer Yield must use RockCatalog permeability")
	_expect(groundwater.aquifer_class_at_z(0, 21.0, strata) == GroundwaterLayer.AquiferClass.HEAVY, "0.48 Sandstone yield must be Heavy")
	strata.rock_type_ids[0] = RockCatalog.RockType.SHALE
	_expect(is_equal_approx(groundwater.aquifer_yield_at_z(0, 21.0, strata), 0.032), "Shale yield must use fixed 0.04 permeability")
	_expect(groundwater.aquifer_class_at_z(0, 21.0, strata) == GroundwaterLayer.AquiferClass.NONE, "Shale example must not form an Aquifer")

	strata.rock_type_ids[0] = RockCatalog.RockType.SANDSTONE
	groundwater.groundwater_supply[0] = 1.0
	groundwater.water_table_z[0] = 0.0
	_expect(groundwater.aquifer_class_at_z(0, 0.0, strata) == GroundwaterLayer.AquiferClass.HEAVY, "Sandstone at Water Table must be Heavy at full supply")
	_expect(groundwater.aquifer_class_at_z(0, -50.0, strata) == GroundwaterLayer.AquiferClass.LIGHT, "depth attenuation must naturally reduce Heavy to Light")
	_expect(groundwater.aquifer_class_at_z(0, -100.0, strata) == GroundwaterLayer.AquiferClass.NONE, "depth attenuation must naturally reduce Light to None")
	groundwater.water_table_z[0] = 100.0
	_expect(groundwater.aquifer_yield_at_z(0, 61.0, strata) == 0.0, "NO_ROCK above Terrain must give zero Aquifer Yield")

	_expect(GroundwaterLayer.aquifer_class_for_yield(0.18, groundwater.settings) == GroundwaterLayer.AquiferClass.LIGHT, "Aquifer yield 0.18 must be Light")
	_expect(GroundwaterLayer.aquifer_class_for_yield(0.45, groundwater.settings) == GroundwaterLayer.AquiferClass.HEAVY, "Aquifer yield 0.45 must be Heavy")


func _test_validator_rejections() -> void:
	var fixture := _small_generation_fixture()
	var groundwater: GroundwaterLayer = fixture.groundwater
	groundwater.groundwater_supply[0] = 0.9
	_expect(not GroundwaterValidator.validate(
		fixture.graph, fixture.terrain, fixture.surface_water, groundwater
	).is_empty(), "Validator must reject an Ocean Cell without supply one")
	groundwater.groundwater_supply[0] = 1.0
	groundwater.groundwater_salinity_class[2] = GroundwaterLayer.SALINITY_CLASS_COUNT
	_expect(not GroundwaterValidator.validate(
		fixture.graph, fixture.terrain, fixture.surface_water, groundwater
	).is_empty(), "Validator must reject an invalid Salinity enum")


func _test_determinism_and_mutation() -> void:
	var fixture := _small_generation_fixture(false)
	var graph: SpatialGraph = fixture.graph
	var terrain: TerrainHeightLayer = fixture.terrain
	var climate: WorldClimateLayer = fixture.climate
	var hydrology: WorldHydrologyLayer = fixture.hydrology
	var surface_water: SurfaceWaterLayer = fixture.surface_water
	var centers_before := graph.cell_centers.duplicate()
	var neighbors_before := graph.cell_neighbors.duplicate(true)
	var distances_before := graph.cell_neighbor_distances.duplicate(true)
	var heights_before := terrain.terrain_height.duplicate()
	var precipitation_before := climate.precipitation.duplicate()
	var accumulation_before := hydrology.flow_accumulation.duplicate()
	var river_ids_before := hydrology.river_network_id.duplicate()
	var lake_before := surface_water.lake_id.duplicate()
	var surface_depth_before := surface_water.surface_water_depth.duplicate()
	var strata := _single_rock_strata(RockCatalog.RockType.SANDSTONE, 100.0)
	var strata_rocks_before := strata.rock_type_ids.duplicate()
	var first := GroundwaterGenerator.generate(graph, terrain, climate, hydrology, surface_water)
	var second := GroundwaterGenerator.generate(graph, terrain, climate, hydrology, surface_water)
	_expect(first.groundwater_supply == second.groundwater_supply, "Groundwater Supply must be deterministic")
	_expect(first.water_table_z == second.water_table_z, "Water Table z must be deterministic")
	_expect(first.groundwater_salinity_class == second.groundwater_salinity_class, "Groundwater Salinity must be deterministic")
	first.aquifer_yield_at_z(0, 0.0, strata)
	_expect(graph.cell_centers == centers_before, "Groundwater must not modify SpatialGraph")
	_expect(graph.cell_neighbors == neighbors_before, "Groundwater must not modify graph neighbors")
	_expect(graph.cell_neighbor_distances == distances_before, "Groundwater must not modify graph edge distances")
	_expect(terrain.terrain_height == heights_before, "Groundwater must not modify Final Terrain")
	_expect(climate.precipitation == precipitation_before, "Groundwater must not modify Final Climate")
	_expect(hydrology.flow_accumulation == accumulation_before, "Groundwater must not modify Formal Hydrology")
	_expect(hydrology.river_network_id == river_ids_before, "Groundwater must not modify River facts")
	_expect(surface_water.lake_id == lake_before, "Groundwater must not modify Surface Water")
	_expect(surface_water.surface_water_depth == surface_depth_before, "Groundwater must not modify Surface Water depth")
	_expect(strata.rock_type_ids == strata_rocks_before, "Aquifer query must not modify Strata")


func _test_standard_world(fixture: Dictionary) -> void:
	_expect(not fixture.is_empty(), "standard Groundwater fixture must generate")
	if fixture.is_empty():
		return
	var groundwater: GroundwaterLayer = fixture.groundwater
	_expect(groundwater != null, "standard Groundwater must not be null")
	if groundwater == null:
		return
	_expect(GroundwaterValidator.validate(fixture.graph, fixture.terrain, fixture.surface_water, groundwater).is_empty(), "standard Groundwater must pass Validator")
	var statistics := _standard_statistics(fixture)
	print("Groundwater standard 20k statistics:")
	print("  Land / Ocean / Lake: %d / %d / %d" % [statistics.land_count, statistics.ocean_count, statistics.lake_count])
	_print_distribution("Land Supply", statistics.land_supply)
	_print_distribution("Land Water Table Depth", statistics.land_depth)
	print("  World Salinity Fresh / Brackish / Saline: %s" % str(statistics.world_salinity))
	print("  Land Salinity Fresh / Brackish / Saline: %s" % str(statistics.land_salinity))
	print("  Aquifer @ Surface -25 None / Light / Heavy: %s" % str(statistics.aquifer_surface_25))
	print("  Aquifer @ z=-25 None / Light / Heavy: %s" % str(statistics.aquifer_25))
	print("  Aquifer @ z=-75 None / Light / Heavy: %s" % str(statistics.aquifer_75))
	print("  Aquifer Material @ Surface -25: %s" % str(statistics.material_aquifer_surface_25))
	print("  Aquifer Material @ z=-25: %s" % str(statistics.material_aquifer_25))
	print("  Aquifer Material @ z=-75: %s" % str(statistics.material_aquifer_75))
	_expect(statistics.ocean_non_saline == 0, "all Ocean Cells must be Saline")
	_expect(statistics.lake_non_fresh == 0, "all Lake Cells must be Fresh")


func _small_generation_fixture(generate_groundwater: bool = true) -> Dictionary:
	var graph := _line_graph(4, 10.0)
	var terrain := _terrain(PackedFloat32Array([-5.0, 10.0, 20.0, 80.0]))
	var climate := WorldClimateLayer.new()
	climate.temperature = PackedFloat32Array([15.0, 15.0, 15.0, 15.0])
	climate.precipitation = PackedFloat32Array([0.0, 0.0, 20.0, 20.0])
	var hydrology := _hydrology(4, PackedInt32Array([-1, -1, 0, -1]))
	var surface_water := _surface_water(PackedInt32Array([-1, 0, -1, -1]))
	return {
		"graph": graph,
		"terrain": terrain,
		"climate": climate,
		"hydrology": hydrology,
		"surface_water": surface_water,
		"groundwater": GroundwaterGenerator.generate(
			graph, terrain, climate, hydrology, surface_water
		) if generate_groundwater else null,
	}


func _test_surface_relative_aquifer_query() -> void:
	var terrain := _terrain(PackedFloat32Array([20.0, 80.0]))
	var groundwater := GroundwaterLayer.new()
	groundwater.settings = GroundwaterSettings.new()
	groundwater.groundwater_supply = PackedFloat32Array([1.0, 1.0])
	groundwater.water_table_z = PackedFloat32Array([20.0, 80.0])
	groundwater.groundwater_salinity_class = PackedInt32Array([
		GroundwaterLayer.SalinityClass.FRESH,
		GroundwaterLayer.SalinityClass.FRESH,
	])
	var strata := SubsurfaceStrataLayer.new()
	strata.cell_offsets = PackedInt32Array([0, 1, 2])
	strata.rock_type_ids = PackedInt32Array([
		RockCatalog.RockType.SANDSTONE,
		RockCatalog.RockType.SANDSTONE,
	])
	strata.top_z = PackedFloat32Array([20.0, 80.0])
	var low_query_z := _surface_depth_query_z(terrain, 0)
	var high_query_z := _surface_depth_query_z(terrain, 1)
	_expect(low_query_z == -5.0, "Surface -25 at Terrain z=20 must query absolute z=-5")
	_expect(high_query_z == 55.0, "Surface -25 at Terrain z=80 must query absolute z=55")
	_expect(low_query_z != high_query_z, "Surface -25 must not use one fixed absolute z")
	_expect(groundwater.aquifer_class_at_z(0, low_query_z, strata) == GroundwaterLayer.AquiferClass.LIGHT, "Surface -25 must use the existing Aquifer class query for the low Cell")
	_expect(groundwater.aquifer_class_at_z(1, high_query_z, strata) == GroundwaterLayer.AquiferClass.LIGHT, "Surface -25 must use the existing Aquifer class query for the high Cell")


func _standard_world_fixture() -> Dictionary:
	var graph := SpatialGenerator.generate(SpatialConfig.new(1, 2000.0, 1000.0, 20000, 0.9))
	if graph == null:
		return {}
	var composition := WorldCompositionGenerator.generate(graph, WorldCompositionConfig.new(1, &"continents"))
	var projected := TerrainHeightProjector.project(composition.continental_value)
	var geology := GeologyGenerator.generate(graph, projected)
	var climate_settings := WorldClimateSettings.new(70.0, -20.0)
	var preliminary_climate := WorldClimateGenerator.generate(graph, projected, climate_settings)
	var hydrology_settings := WorldHydrologySettings.new()
	var preliminary_flow := PreliminaryFlowGenerator.generate(graph, projected, preliminary_climate, hydrology_settings)
	var conditioning := HydrologyConditioner.condition(graph, projected, preliminary_flow, geology, HydrologyConditioningSettings.new())
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = conditioning.terrain_height.duplicate()
	var climate := WorldClimateGenerator.generate(graph, terrain, climate_settings)
	var hydrology := WorldHydrologyGenerator.generate(
		graph, terrain, climate, conditioning.closed_basin_id, hydrology_settings
	)
	var surface_water := SurfaceWaterGenerator.generate(
		graph, terrain, climate, hydrology, conditioning.closed_basin_id,
		geology, SurfaceWaterSettings.new()
	)
	var strata := SubsurfaceStrataGenerator.generate(
		graph, composition, terrain, geology, 1, SubsurfaceStrataSettings.new()
	)
	return {
		"graph": graph,
		"terrain": terrain,
		"climate": climate,
		"hydrology": hydrology,
		"surface_water": surface_water,
		"strata": strata,
		"groundwater": GroundwaterGenerator.generate(
			graph, terrain, climate, hydrology, surface_water
		),
	}


func _standard_statistics(fixture: Dictionary) -> Dictionary:
	var graph: SpatialGraph = fixture.graph
	var terrain: TerrainHeightLayer = fixture.terrain
	var surface_water: SurfaceWaterLayer = fixture.surface_water
	var groundwater: GroundwaterLayer = fixture.groundwater
	var strata: SubsurfaceStrataLayer = fixture.strata
	var land_supply := PackedFloat32Array()
	var land_depth := PackedFloat32Array()
	var world_salinity := PackedInt32Array([0, 0, 0])
	var land_salinity := PackedInt32Array([0, 0, 0])
	var aquifer_surface_25 := PackedInt32Array([0, 0, 0])
	var aquifer_25 := PackedInt32Array([0, 0, 0])
	var aquifer_75 := PackedInt32Array([0, 0, 0])
	var material_aquifer_surface_25 := {}
	var material_aquifer_25 := {}
	var material_aquifer_75 := {}
	var land_count := 0
	var ocean_count := 0
	var lake_count := 0
	var ocean_non_saline := 0
	var lake_non_fresh := 0
	for cell_id in graph.cell_count():
		var salinity := groundwater.groundwater_salinity_class[cell_id]
		world_salinity[salinity] += 1
		if terrain.terrain_height[cell_id] < 0.0:
			ocean_count += 1
			if salinity != GroundwaterLayer.SalinityClass.SALINE:
				ocean_non_saline += 1
		elif surface_water.lake_id[cell_id] >= 0:
			lake_count += 1
			if salinity != GroundwaterLayer.SalinityClass.FRESH:
				lake_non_fresh += 1
		else:
			land_count += 1
			land_supply.append(groundwater.groundwater_supply[cell_id])
			land_depth.append(groundwater.water_table_depth(cell_id, terrain))
			land_salinity[salinity] += 1
		var surface_query_z := _surface_depth_query_z(terrain, cell_id)
		_accumulate_aquifer_statistics(cell_id, surface_query_z, groundwater, strata, aquifer_surface_25, material_aquifer_surface_25)
		_accumulate_aquifer_statistics(cell_id, -25.0, groundwater, strata, aquifer_25, material_aquifer_25)
		_accumulate_aquifer_statistics(cell_id, -75.0, groundwater, strata, aquifer_75, material_aquifer_75)
	return {
		"land_count": land_count,
		"ocean_count": ocean_count,
		"lake_count": lake_count,
		"land_supply": _distribution(land_supply),
		"land_depth": _distribution(land_depth),
		"world_salinity": world_salinity,
		"land_salinity": land_salinity,
		"aquifer_surface_25": aquifer_surface_25,
		"aquifer_25": aquifer_25,
		"aquifer_75": aquifer_75,
		"material_aquifer_surface_25": material_aquifer_surface_25,
		"material_aquifer_25": material_aquifer_25,
		"material_aquifer_75": material_aquifer_75,
		"ocean_non_saline": ocean_non_saline,
		"lake_non_fresh": lake_non_fresh,
	}


func _surface_depth_query_z(terrain: TerrainHeightLayer, cell_id: int) -> float:
	return terrain.terrain_height[cell_id] - 25.0


func _accumulate_aquifer_statistics(
		cell_id: int,
		z: float,
		groundwater: GroundwaterLayer,
		strata: SubsurfaceStrataLayer,
		class_counts: PackedInt32Array,
		material_counts: Dictionary
) -> void:
	var rock_type := strata.rock_type_at_z(cell_id, z)
	var aquifer_class := groundwater.aquifer_class_at_z(cell_id, z, strata)
	class_counts[aquifer_class] += 1
	if rock_type != SubsurfaceStrataLayer.NO_ROCK \
			and aquifer_class != GroundwaterLayer.AquiferClass.NONE:
		if not material_counts.has(rock_type):
			material_counts[rock_type] = PackedInt32Array([0, 0, 0])
		var counts: PackedInt32Array = material_counts[rock_type]
		counts[aquifer_class] += 1
		material_counts[rock_type] = counts


func _line_graph(count: int, spacing: float) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.cell_centers.resize(count)
	graph.cell_neighbors.resize(count)
	graph.cell_neighbor_distances.resize(count)
	for cell_id in count:
		graph.cell_centers[cell_id] = Vector2(cell_id * spacing, 0.0)
		var neighbors := PackedInt32Array()
		if cell_id > 0:
			neighbors.append(cell_id - 1)
		if cell_id + 1 < count:
			neighbors.append(cell_id + 1)
		graph.cell_neighbors[cell_id] = neighbors
		var distances := PackedFloat64Array()
		distances.resize(neighbors.size())
		distances.fill(spacing)
		graph.cell_neighbor_distances[cell_id] = distances
	return graph


func _terrain(heights: PackedFloat32Array) -> TerrainHeightLayer:
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = heights
	return terrain


func _hydrology(count: int, river_ids: PackedInt32Array) -> WorldHydrologyLayer:
	var hydrology := WorldHydrologyLayer.new()
	hydrology.settings = WorldHydrologySettings.new()
	hydrology.local_runoff.resize(count)
	hydrology.flow_accumulation.resize(count)
	hydrology.river_network_id = river_ids
	hydrology.flow_accumulation.fill(0.0)
	for cell_id in count:
		if river_ids[cell_id] >= 0:
			hydrology.flow_accumulation[cell_id] = hydrology.settings.river_runoff_threshold * 20.0
	return hydrology


func _surface_water(lake_ids: PackedInt32Array) -> SurfaceWaterLayer:
	var surface_water := SurfaceWaterLayer.new()
	surface_water.lake_id = lake_ids
	surface_water.surface_water_depth.resize(lake_ids.size())
	return surface_water


func _single_rock_strata(rock_type: int, top_z: float) -> SubsurfaceStrataLayer:
	var strata := SubsurfaceStrataLayer.new()
	strata.cell_offsets = PackedInt32Array([0, 1])
	strata.rock_type_ids = PackedInt32Array([rock_type])
	strata.top_z = PackedFloat32Array([top_z])
	return strata


func _distribution(values: PackedFloat32Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values:
		total += value
	return {
		"min": sorted[0] if not sorted.is_empty() else 0.0,
		"mean": total / maxf(float(values.size()), 1.0),
		"p25": _percentile(sorted, 0.25),
		"p50": _percentile(sorted, 0.50),
		"p75": _percentile(sorted, 0.75),
		"p90": _percentile(sorted, 0.90),
		"max": sorted[-1] if not sorted.is_empty() else 0.0,
	}


func _percentile(sorted: PackedFloat32Array, percentile: float) -> float:
	if sorted.is_empty():
		return 0.0
	var position := float(sorted.size() - 1) * percentile
	var lower := floori(position)
	var upper := ceili(position)
	return sorted[lower] if lower == upper else lerpf(sorted[lower], sorted[upper], position - lower)


func _print_distribution(label: String, distribution: Dictionary) -> void:
	print("  %s min/mean/P25/P50/P75/P90/max: %.4f / %.4f / %.4f / %.4f / %.4f / %.4f / %.4f" % [
		label, distribution.min, distribution.mean, distribution.p25, distribution.p50,
		distribution.p75, distribution.p90, distribution.max,
	])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Groundwater / Aquifer: all dedicated test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Groundwater / Aquifer: %d failures" % _failures.size())
		quit(1)
