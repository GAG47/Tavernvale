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
	_test_soil_uses_final_pipeline_outputs()
	_test_resource_potential_uses_final_pipeline_outputs()
	_test_arcane_field_follows_v1_and_preserves_it()
	_test_arcane_web_follows_arcane_field_and_preserves_prior_layers()
	_test_arcane_circulation_follows_web_and_preserves_prior_layers()
	_test_arcane_environment_follows_circulation_and_preserves_prior_layers()
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
	var soil_settings := SoilSettings.new()
	var soil := SoilGenerator.generate(
		graph,
		conditioned,
		final_climate,
		final_hydrology,
		geology,
		surface_water,
		ecology,
		soil_settings
	)
	if soil == null:
		return {}
	var resource_settings := ResourcePotentialSettings.new()
	var resources := ResourcePotentialGenerator.generate(
		graph,
		conditioned,
		final_climate,
		final_hydrology,
		geology,
		surface_water,
		ecology,
		soil,
		resource_settings,
		soil_settings
	)
	if resources == null:
		return {}
	var v1_hash_before_arcane := _v1_pipeline_hash({
		"composition": composition,
		"projected": projected,
		"geology": geology,
		"preliminary": preliminary,
		"preliminary_flow": preliminary_flow,
		"conditioning": conditioning,
		"conditioned": conditioned,
		"final_climate": final_climate,
		"final_hydrology": final_hydrology,
		"surface_water": surface_water,
		"ecology": ecology,
		"soil": soil,
		"resources": resources,
	})
	var arcane_field := ArcaneFieldGenerator.generate(graph, graph.config.seed)
	if arcane_field == null:
		return {}
	var v2_hash_before_web := hash([
		v1_hash_before_arcane,
		arcane_field.background_mana,
		arcane_field.background_stability,
	])
	var arcane_web := ArcaneWebGenerator.generate(
		graph.config.seed, graph.config.world_width, graph.config.world_height
	)
	if arcane_web == null:
		return {}
	var v21_hash_before_circulation := _v21_pipeline_hash(
		v2_hash_before_web, arcane_field, arcane_web
	)
	var arcane_circulation := ArcaneCirculationGenerator.generate(
		arcane_web
	)
	if arcane_circulation == null:
		return {}
	var arcane_forcing := ArcaneForcingGenerator.generate(graph, graph.config.seed)
	if arcane_forcing == null:
		return {}
	var arcane_forcing_diagnostics := ArcaneForcingGenerator.last_generation_diagnostics()
	var v22_hash_before_environment := _v22_pipeline_hash(
		v2_hash_before_web, arcane_field, arcane_web, arcane_circulation
	)
	var arcane_environment := ArcaneEnvironmentGenerator.generate(
		graph, arcane_field, arcane_web, arcane_circulation, arcane_forcing
	)
	if arcane_environment == null:
		return {}
	var arcane_environment_diagnostics := (
		ArcaneEnvironmentGenerator.last_generation_diagnostics()
	)
	return {
		"graph": graph,
		"composition": composition,
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
		"soil": soil,
		"soil_settings": soil_settings,
		"resource_settings": resource_settings,
		"resources": resources,
		"arcane_field": arcane_field,
		"arcane_web": arcane_web,
		"arcane_circulation": arcane_circulation,
		"arcane_forcing": arcane_forcing,
		"arcane_forcing_diagnostics": arcane_forcing_diagnostics,
		"arcane_environment": arcane_environment,
		"arcane_environment_diagnostics": arcane_environment_diagnostics,
		"v1_hash_before_arcane": v1_hash_before_arcane,
		"v2_hash_before_web": v2_hash_before_web,
		"v21_hash_before_circulation": v21_hash_before_circulation,
		"v22_hash_before_environment": v22_hash_before_environment,
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


func _test_soil_uses_final_pipeline_outputs() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var terrain: TerrainHeightLayer = _pipeline.conditioned
	var surface_water: SurfaceWaterLayer = _pipeline.surface_water
	var ecology: EcologyLayer = _pipeline.ecology
	var soil: SoilLayer = _pipeline.soil
	_expect(soil.cell_count() == graph.cell_count(), "Soil Cell Count should match")
	_expect(
		SoilValidator.validate(graph, terrain, surface_water, ecology, soil).is_empty(),
		"Soil should validate after Ecology"
	)
	for cell_id in graph.cell_count():
		var biome_id := ecology.biome_id[cell_id]
		if biome_id == EcologyCatalog.Biome.MARINE \
				or biome_id == EcologyCatalog.Biome.LAKE \
				or biome_id == EcologyCatalog.Biome.GLACIER:
			_expect(
				soil.soil_texture_id[cell_id] == SoilCatalog.TextureType.NONE,
				"Marine, Lake, and Glacier Cells should reach Soil as None"
			)


func _test_resource_potential_uses_final_pipeline_outputs() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var terrain: TerrainHeightLayer = _pipeline.conditioned
	var surface_water: SurfaceWaterLayer = _pipeline.surface_water
	var resources: ResourcePotentialLayer = _pipeline.resources
	_expect(resources.cell_count() == graph.cell_count(), "Resource Potential Cell Count should match")
	_expect(
		ResourcePotentialValidator.validate(graph, terrain, surface_water, resources).is_empty(),
		"Resource Potential should validate after Soil"
	)
	for cell_id in graph.cell_count():
		if terrain.terrain_height[cell_id] < 0.0 or surface_water.lake_id[cell_id] >= 0:
			_expect(resources.agriculture_potential[cell_id] == 0.0, "Water must have no Agriculture Potential")
			_expect(resources.base_metal_potential[cell_id] == 0.0, "Water must have no Base Metal Potential")
		if terrain.terrain_height[cell_id] < 0.0:
			_expect(resources.freshwater_aquatic_potential[cell_id] == 0.0, "Ocean must have no Freshwater Potential")


func _test_arcane_field_follows_v1_and_preserves_it() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var arcane_field: ArcaneFieldLayer = _pipeline.arcane_field
	_expect(arcane_field.cell_count() == graph.cell_count(),
		"Arcane Field should be stored after Resource Potential with one value per Cell")
	_expect(ArcaneFieldValidator.validate(graph, arcane_field).is_empty(),
		"Arcane Field should validate in the complete composition pipeline")
	_expect(_pipeline.v1_hash_before_arcane == _v1_pipeline_hash(_pipeline),
		"Arcane Field generation must leave every existing v1 Layer unchanged")


func _test_arcane_web_follows_arcane_field_and_preserves_prior_layers() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var arcane_web: ArcaneWebLayer = _pipeline.arcane_web
	_expect(arcane_web != null and ArcaneWebValidator.validate(arcane_web).is_empty(),
		"Arcane Web should validate after Arcane Field in the complete pipeline")
	_expect(
		arcane_web.world_seed == graph.config.seed
				and arcane_web.world_width == graph.config.world_width
				and arcane_web.world_height == graph.config.world_height,
		"Arcane Web formal inputs should be World Seed and World Extent"
	)
	_expect(_pipeline.v2_hash_before_web == hash([
		_v1_pipeline_hash(_pipeline),
		_pipeline.arcane_field.background_mana,
		_pipeline.arcane_field.background_stability,
	]), "Arcane Web generation must preserve v2.0 Arcane Field and every v1 Layer")


func _test_arcane_circulation_follows_web_and_preserves_prior_layers() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var arcane_web: ArcaneWebLayer = _pipeline.arcane_web
	var circulation: ArcaneCirculationLayer = _pipeline.arcane_circulation
	_expect(
		circulation != null
				and ArcaneCirculationValidator.validate(
					arcane_web, circulation
				).is_empty(),
		"Arcane Circulation should validate after Arcane Web in the complete pipeline"
	)
	_expect(
		circulation != null and circulation.edge_flow.size() == arcane_web.edges.size(),
		"Arcane Circulation edge_flow should be index-aligned with Arcane Web edges"
	)
	_expect(
		_pipeline.v21_hash_before_circulation == _v21_pipeline_hash(
			_pipeline.v2_hash_before_web, _pipeline.arcane_field, arcane_web
		),
		"Arcane Circulation generation must preserve v2.1 Web, v2.0 Field, and every v1 Layer"
	)


func _test_arcane_environment_follows_circulation_and_preserves_prior_layers() -> void:
	var graph: SpatialGraph = _pipeline.graph
	var environment: ArcaneEnvironmentLayer = _pipeline.arcane_environment
	var forcing: ArcaneForcingLayer = _pipeline.arcane_forcing
	var diagnostics: Dictionary = _pipeline.arcane_environment_diagnostics
	_expect(
		forcing != null and ArcaneForcingValidator.validate(graph, forcing).is_empty(),
		"Natural Arcane Forcing should validate as an independent formal pipeline input"
	)
	_expect(
		environment != null
				and ArcaneEnvironmentValidator.validate(graph, environment).is_empty(),
		"Arcane Environment should validate after Arcane Circulation in the complete pipeline"
	)
	_expect(
		environment != null
				and environment.mana_concentration.size() == graph.cell_count()
				and environment.mana_flowability.size() == graph.cell_count()
				and environment.mana_stability.size() == graph.cell_count(),
		"Arcane Environment formal arrays should remain strictly Cell-aligned"
	)
	_expect(
		ArcaneEnvironmentValidator.validate_solver_report(
			diagnostics.get("solver", {})
		).is_empty(),
		"complete-pipeline Arcane Transport Solver must provide finite diagnostics"
	)
	_expect(
		_pipeline.v22_hash_before_environment == _v22_pipeline_hash(
			_pipeline.v2_hash_before_web,
			_pipeline.arcane_field,
			_pipeline.arcane_web,
			_pipeline.arcane_circulation
		),
		"Arcane Environment generation must preserve v2.2 Circulation, v2.1 Web, v2.0 Field, and v1"
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
	var repeated_environment := ArcaneEnvironmentGenerator.generate(
		graph,
		_pipeline.arcane_field,
		_pipeline.arcane_web,
		_pipeline.arcane_circulation,
		_pipeline.arcane_forcing
	)
	_expect(repeated_environment != null, "repeat Arcane Environment pipeline should generate")
	if repeated_environment != null:
		_expect(_pipeline.arcane_environment.mana_concentration
				== repeated_environment.mana_concentration,
			"Final Mana Concentration should be deterministic")
		_expect(_pipeline.arcane_environment.mana_flowability
				== repeated_environment.mana_flowability,
			"Final Mana Flowability should be deterministic")
		_expect(_pipeline.arcane_environment.mana_stability
				== repeated_environment.mana_stability,
			"Final Mana Stability should be deterministic")
	var repeated_forcing := ArcaneForcingGenerator.generate(graph, graph.config.seed)
	_expect(repeated_forcing != null, "repeat Arcane Forcing pipeline should generate")
	if repeated_forcing != null:
		_expect(_forcing_signature(_pipeline.arcane_forcing)
				== _forcing_signature(repeated_forcing),
			"Natural Arcane Forcing Sites should be deterministic")
		_expect(_pipeline.arcane_forcing.source_rate == repeated_forcing.source_rate
				and _pipeline.arcane_forcing.sink_rate == repeated_forcing.sink_rate,
			"Natural Arcane Forcing projected rates should be deterministic")
	var repeated_resources := ResourcePotentialGenerator.generate(
		graph,
		conditioned,
		first_climate,
		first_hydrology,
		_pipeline.geology,
		_pipeline.surface_water,
		_pipeline.ecology,
		_pipeline.soil,
		_pipeline.resource_settings,
		_pipeline.soil_settings
	)
	_expect(repeated_resources != null, "repeat Resource Potential should generate")
	if repeated_resources != null:
		_expect(
			_pipeline.resources.base_metal_potential == repeated_resources.base_metal_potential,
			"Base Metal Potential should be deterministic"
		)
		_expect(
			_pipeline.resources.precious_mineral_potential == repeated_resources.precious_mineral_potential,
			"Precious Mineral Potential should be deterministic"
		)


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


func _v1_pipeline_hash(pipeline: Dictionary) -> int:
	return hash([
		pipeline.composition.continental_value,
		pipeline.projected.terrain_height,
		pipeline.geology.province_id,
		pipeline.geology.material_id,
		pipeline.geology.permeability,
		pipeline.geology.erodibility,
		pipeline.preliminary.temperature,
		pipeline.preliminary.precipitation,
		pipeline.preliminary_flow.flow_to,
		pipeline.preliminary_flow.flow_accumulation,
		pipeline.conditioning.terrain_height,
		pipeline.conditioning.height_delta,
		pipeline.conditioned.terrain_height,
		pipeline.final_climate.temperature,
		pipeline.final_climate.precipitation,
		pipeline.final_hydrology.local_runoff,
		pipeline.final_hydrology.flow_to,
		pipeline.final_hydrology.flow_accumulation,
		pipeline.final_hydrology.watershed_id,
		pipeline.final_hydrology.river_network_id,
		pipeline.final_hydrology.river_order,
		pipeline.surface_water.lake_id,
		pipeline.surface_water.surface_water_depth,
		pipeline.ecology.drainage_index,
		pipeline.ecology.ecological_moisture,
		pipeline.ecology.vegetation_potential,
		pipeline.ecology.biome_id,
		pipeline.soil.soil_depth,
		pipeline.soil.soil_texture_id,
		pipeline.soil.organic_matter,
		pipeline.soil.soil_fertility,
		pipeline.resources.agriculture_potential,
		pipeline.resources.timber_potential,
		pipeline.resources.forage_potential,
		pipeline.resources.construction_stone_potential,
		pipeline.resources.base_metal_potential,
		pipeline.resources.precious_mineral_potential,
		pipeline.resources.freshwater_aquatic_potential,
		pipeline.resources.coastal_aquatic_potential,
	])


func _v21_pipeline_hash(
		v2_hash_before_web: int,
		arcane_field: ArcaneFieldLayer,
		arcane_web: ArcaneWebLayer
) -> int:
	var signature: Array = [
		v2_hash_before_web,
		arcane_field.background_mana,
		arcane_field.background_stability,
		arcane_web.world_seed,
		arcane_web.world_width,
		arcane_web.world_height,
		arcane_web.generated_nucleus_count,
		arcane_web.settings.web_generation_margin,
		arcane_web.settings.web_nucleus_min_separation,
	]
	for domain in arcane_web.domains:
		signature.append([
			domain.id, domain.nucleus_position, domain.power_weight, domain.polygon
		])
	for node in arcane_web.nodes:
		signature.append([node.id, node.world_position, node.kind])
	for edge in arcane_web.edges:
		signature.append([edge.id, edge.node_a_id, edge.node_b_id, edge.length])
	return hash(signature)


func _v22_pipeline_hash(
		v2_hash_before_web: int,
		arcane_field: ArcaneFieldLayer,
		arcane_web: ArcaneWebLayer,
		arcane_circulation: ArcaneCirculationLayer
) -> int:
	return hash([
		_v21_pipeline_hash(v2_hash_before_web, arcane_field, arcane_web),
		arcane_circulation.edge_flow,
	])


func _forcing_signature(forcing: ArcaneForcingLayer) -> Array:
	var signature := []
	for site in forcing.sites:
		signature.append([
			site.id, site.world_position, site.kind, site.core_radius, site.total_power,
		])
	return signature


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Final Climate Pipeline: all 12 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Final Climate Pipeline: %d failures" % _failures.size())
		quit(1)
