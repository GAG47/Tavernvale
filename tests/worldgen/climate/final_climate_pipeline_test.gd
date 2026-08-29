extends SceneTree

var _failures := PackedStringArray()
var _pipeline := {}


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_pipeline = _build_fixed_pipeline()
	if _pipeline.is_empty():
		_expect(false, "fixed Final Climate pipeline should generate")
		_finish()
		return
	_test_final_climate_uses_conditioned_terrain_and_same_generator()
	_test_final_hydrology_uses_final_climate()
	_test_surface_water_uses_final_pipeline_outputs()
	_test_ecology_uses_final_pipeline_outputs()
	_test_terrain_lengths_values_and_validation()
	_test_determinism()
	_finish()


func _build_fixed_pipeline() -> Dictionary:
	var graph := SpatialGenerator.generate(SpatialConfig.new(24680, 300.0, 200.0, 400, 0.9))
	if graph == null:
		return {}
	var composition := WorldCompositionGenerator.generate(
		graph, WorldCompositionConfig.new(24680, CompositionTemplates.CONTINENTS)
	)
	if composition == null:
		return {}
	var projected := TerrainHeightProjector.project(composition.continental_value)
	var geology := GeologyGenerator.generate(graph, projected)
	var settings := WorldClimateSettings.new()
	var hydrology_settings := WorldHydrologySettings.new()
	# Preliminary and Final Climate intentionally call the same generator implementation.
	var preliminary := WorldClimateGenerator.generate(graph, projected, settings)
	var preliminary_flow := PreliminaryFlowGenerator.generate(
		graph, projected, preliminary, hydrology_settings
	) if preliminary != null else null
	var conditioning := HydrologyConditioner.condition(
		graph, projected, preliminary_flow, geology
	) if preliminary_flow != null else null
	if geology == null or preliminary == null or preliminary_flow == null or conditioning == null:
		return {}
	var conditioned := TerrainHeightLayer.new()
	conditioned.terrain_height = conditioning.terrain_height.duplicate()
	var terrain_before_final := conditioned.terrain_height.duplicate()
	var final_climate := WorldClimateGenerator.generate(graph, conditioned, settings)
	if final_climate == null:
		return {}
	var final_hydrology := WorldHydrologyGenerator.generate(
		graph,
		conditioned,
		final_climate,
		conditioning.closed_basin_id,
		hydrology_settings
	)
	if final_hydrology == null:
		return {}
	var final_flow_to_before_surface := final_hydrology.flow_to.duplicate()
	var surface_water_settings := SurfaceWaterSettings.new()
	var surface_water := SurfaceWaterGenerator.generate(
		graph,
		conditioned,
		final_climate,
		final_hydrology,
		conditioning.closed_basin_id,
		geology,
		surface_water_settings
	)
	if surface_water == null:
		return {}
	var ecology := EcologyGenerator.generate(
		graph,
		conditioned,
		final_climate,
		final_hydrology,
		conditioning.closed_basin_id,
		geology,
		surface_water,
		EcologySettings.new(),
		surface_water_settings
	)
	if ecology == null:
		return {}
	return {
		"graph": graph,
		"projected": projected,
		"geology": geology,
		"preliminary": preliminary,
		"preliminary_flow": preliminary_flow,
		"conditioning": conditioning,
		"conditioned": conditioned,
		"terrain_before_final": terrain_before_final,
		"settings": settings,
		"final_climate": final_climate,
		"final_hydrology": final_hydrology,
		"final_flow_to_before_surface": final_flow_to_before_surface,
		"surface_water": surface_water,
		"ecology": ecology,
	}


func _test_final_climate_uses_conditioned_terrain_and_same_generator() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var projected: TerrainHeightLayer = _pipeline.projected
	var conditioned: TerrainHeightLayer = _pipeline.conditioned
	var preliminary: WorldClimateLayer = _pipeline.preliminary
	var final_climate: WorldClimateLayer = _pipeline.final_climate
	var settings: WorldClimateSettings = _pipeline.settings
	var modified_cells := 0
	var modified_land_with_temperature_delta := 0
	for cell_id in graph.cell_count():
		var expected_temperature := WorldClimateGenerator.temperature_at(
			WorldClimateGenerator.latitude_at(cell_id, graph, settings),
			conditioned.terrain_height[cell_id],
			settings
		)
		_expect(
			is_equal_approx(final_climate.temperature[cell_id], expected_temperature),
			"Final temperature[%d] should use conditioned terrain" % cell_id
		)
		if conditioned.terrain_height[cell_id] != projected.terrain_height[cell_id]:
			modified_cells += 1
			if conditioned.terrain_height[cell_id] >= 0.0 \
					and final_climate.temperature[cell_id] != preliminary.temperature[cell_id]:
				modified_land_with_temperature_delta += 1
	_expect(modified_cells > 0, "fixed world should contain conditioning changes")
	_expect(
		modified_land_with_temperature_delta > 0,
		"at least one conditioned Land Cell should change Final temperature"
	)


func _test_final_hydrology_uses_final_climate() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var conditioned: TerrainHeightLayer = _pipeline.conditioned
	var preliminary: WorldClimateLayer = _pipeline.preliminary
	var final_climate: WorldClimateLayer = _pipeline.final_climate
	var conditioning: HydrologyConditioningResult = _pipeline.conditioning
	var final_hydrology: WorldHydrologyLayer = _pipeline.final_hydrology
	var preliminary_hydrology := WorldHydrologyGenerator.generate(
		graph,
		conditioned,
		preliminary,
		conditioning.closed_basin_id,
		WorldHydrologySettings.new()
	)
	_expect(preliminary_hydrology != null, "comparison hydrology should generate")
	if preliminary_hydrology == null:
		return
	var precipitation_changed_cells := 0
	var runoff_changed_cells := 0
	for cell_id in graph.cell_count():
		var expected_runoff := (
			final_climate.precipitation[cell_id]
			* graph.cell_areas[cell_id]
			* final_hydrology.settings.runoff_modifier
		)
		_expect(
			is_equal_approx(final_hydrology.local_runoff[cell_id], expected_runoff),
			"Final Hydrology runoff[%d] should use Final precipitation" % cell_id
		)
		if final_climate.precipitation[cell_id] != preliminary.precipitation[cell_id]:
			precipitation_changed_cells += 1
		if final_hydrology.local_runoff[cell_id] != preliminary_hydrology.local_runoff[cell_id]:
			runoff_changed_cells += 1
	_expect(precipitation_changed_cells > 0, "fixed world should contain precipitation deltas")
	_expect(runoff_changed_cells > 0, "Final precipitation deltas should reach local runoff")
	_expect(
		final_hydrology.flow_to == preliminary_hydrology.flow_to,
		"Flow Direction should remain unchanged when terrain is unchanged"
	)
	for basin in final_hydrology.closed_basin_inflows:
		var temperature_area_sum := 0.0
		var catchment_area := 0.0
		for cell_id in graph.cell_count():
			if conditioned.terrain_height[cell_id] < 0.0:
				continue
			if _terminal_closed_basin_id(
				cell_id, final_hydrology.flow_to, conditioning.closed_basin_id
			) == basin.closed_basin_id:
				temperature_area_sum += final_climate.temperature[cell_id] * graph.cell_areas[cell_id]
				catchment_area += graph.cell_areas[cell_id]
		if catchment_area > 0.0:
			_expect(
				is_equal_approx(basin.mean_temperature, temperature_area_sum / catchment_area),
				"Closed Basin mean temperature should use Final temperature"
			)


func _test_terrain_lengths_values_and_validation() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var conditioned: TerrainHeightLayer = _pipeline.conditioned
	var final_climate: WorldClimateLayer = _pipeline.final_climate
	var final_hydrology: WorldHydrologyLayer = _pipeline.final_hydrology
	var conditioning: HydrologyConditioningResult = _pipeline.conditioning
	_expect(
		conditioned.terrain_height == _pipeline.terrain_before_final,
		"Final Climate and Final Hydrology must not modify terrain_height"
	)
	_expect(final_climate.temperature.size() == graph.cell_count(), "Final temperature length should match")
	_expect(final_climate.precipitation.size() == graph.cell_count(), "Final precipitation length should match")
	for values in [
		final_hydrology.local_runoff,
		final_hydrology.flow_to,
		final_hydrology.flow_accumulation,
		final_hydrology.watershed_id,
		final_hydrology.river_network_id,
		final_hydrology.river_order,
	]:
		_expect(values.size() == graph.cell_count(), "Final Hydrology array length should match")
	for cell_id in graph.cell_count():
		_expect(is_finite(final_climate.temperature[cell_id]), "Final temperature should be finite")
		_expect(is_finite(final_climate.precipitation[cell_id]), "Final precipitation should be finite")
		_expect(final_climate.precipitation[cell_id] >= 0.0, "Final precipitation should be non-negative")
	_expect(
		WorldHydrologyValidator.validate(
			graph, conditioned, final_climate, conditioning.closed_basin_id, final_hydrology
		).is_empty(),
		"Final Hydrology should pass its existing Validator"
	)


func _test_surface_water_uses_final_pipeline_outputs() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var conditioned: TerrainHeightLayer = _pipeline.conditioned
	var final_climate: WorldClimateLayer = _pipeline.final_climate
	var final_hydrology: WorldHydrologyLayer = _pipeline.final_hydrology
	var conditioning: HydrologyConditioningResult = _pipeline.conditioning
	var geology: GeologyLayer = _pipeline.geology
	var surface_water: SurfaceWaterLayer = _pipeline.surface_water
	_expect(
		final_hydrology.flow_to == _pipeline.final_flow_to_before_surface,
		"Surface Water must not modify Formal Hydrology flow_to"
	)
	_expect(surface_water.lake_id.size() == graph.cell_count(), "Surface Water lake_id length should match")
	_expect(
		surface_water.surface_water_depth.size() == graph.cell_count(),
		"Surface Water depth length should match"
	)
	for cell_id in graph.cell_count():
		if conditioned.terrain_height[cell_id] < 0.0:
			_expect(surface_water.lake_id[cell_id] == -1, "Ocean must remain outside all Lakes")
	_expect(
		SurfaceWaterValidator.validate(
			graph,
			conditioned,
			final_climate,
			final_hydrology,
			conditioning.closed_basin_id,
			geology,
			surface_water,
			SurfaceWaterSettings.new()
		).is_empty(),
		"Surface Water should validate after Final Hydrology"
	)


func _test_ecology_uses_final_pipeline_outputs() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var terrain: TerrainHeightLayer = _pipeline.conditioned
	var climate: WorldClimateLayer = _pipeline.final_climate
	var surface_water: SurfaceWaterLayer = _pipeline.surface_water
	var ecology: EcologyLayer = _pipeline.ecology
	_expect(ecology.cell_count() == graph.cell_count(), "Ecology Cell Count should match")
	_expect(
		EcologyValidator.validate(graph, terrain, climate, surface_water, ecology).is_empty(),
		"Ecology should validate after Surface Water"
	)
	for cell_id in graph.cell_count():
		if terrain.terrain_height[cell_id] < 0.0:
			_expect(
				ecology.biome_id[cell_id] == EcologyCatalog.Biome.MARINE,
				"Final ocean Cells should reach Ecology as Marine"
			)
		elif surface_water.lake_id[cell_id] >= 0:
			_expect(
				ecology.biome_id[cell_id] == EcologyCatalog.Biome.LAKE,
				"Surface Water Lakes should reach Ecology as Lake"
			)


func _test_determinism() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var conditioned: TerrainHeightLayer = _pipeline.conditioned
	var settings: WorldClimateSettings = _pipeline.settings
	var conditioning: HydrologyConditioningResult = _pipeline.conditioning
	var first_climate: WorldClimateLayer = _pipeline.final_climate
	var first_hydrology: WorldHydrologyLayer = _pipeline.final_hydrology
	var second_climate := WorldClimateGenerator.generate(graph, conditioned, settings)
	var second_hydrology := WorldHydrologyGenerator.generate(
		graph,
		conditioned,
		second_climate,
		conditioning.closed_basin_id,
		WorldHydrologySettings.new()
	)
	_expect(second_climate != null and second_hydrology != null, "repeat Final pipeline should generate")
	if second_climate == null or second_hydrology == null:
		return
	_expect(first_climate.temperature == second_climate.temperature, "Final temperature should be deterministic")
	_expect(first_climate.precipitation == second_climate.precipitation, "Final precipitation should be deterministic")
	_expect(first_hydrology.local_runoff == second_hydrology.local_runoff, "Final runoff should be deterministic")
	_expect(first_hydrology.flow_to == second_hydrology.flow_to, "Final flow_to should be deterministic")
	_expect(
		first_hydrology.flow_accumulation == second_hydrology.flow_accumulation,
		"Final accumulation should be deterministic"
	)
	_expect(first_hydrology.river_network_id == second_hydrology.river_network_id, "River Networks should be deterministic")
	_expect(first_hydrology.river_order == second_hydrology.river_order, "River Order should be deterministic")
	_expect(first_hydrology.watershed_id == second_hydrology.watershed_id, "Watersheds should be deterministic")


func _terminal_closed_basin_id(
		start_id: int,
		flow_to: PackedInt32Array,
		closed_basin_id: PackedInt32Array
) -> int:
	var cell_id := start_id
	while flow_to[cell_id] >= 0:
		cell_id = flow_to[cell_id]
	if flow_to[cell_id] == WorldHydrologyLayer.FLOW_TO_CLOSED_BASIN:
		return closed_basin_id[cell_id]
	return -1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Final Climate Pipeline: all 6 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Final Climate Pipeline: %d failures" % _failures.size())
		quit(1)
