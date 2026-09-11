class_name SubsurfaceStrataGenerator
extends RefCounted

const STRATA_SEED_SALT := 0x53545241 # "STRA"
const DEEP_CRUST_CHANNEL_SALT := 0x44435255 # "DCRU"
const THICKNESS_CHANNEL_SALT := 0x5448494b # "THIK"
const THICKNESS_LAYER_OFFSET_SALT := 0x54484f46 # "THOF"


static func generate(
		graph: SpatialGraph,
		composition: WorldCompositionLayer,
		terrain: TerrainHeightLayer,
		geology: GeologyLayer,
		world_seed: int,
		settings: SubsurfaceStrataSettings = null
) -> SubsurfaceStrataLayer:
	var actual_settings := settings if settings != null else SubsurfaceStrataSettings.new()
	if not _inputs_are_valid(graph, composition, terrain, geology, actual_settings):
		return null
	var rules_errors := RockLayerRules.validate_rules()
	if not rules_errors.is_empty():
		push_error("Invalid Rock Layer rules: " + "; ".join(rules_errors))
		return null
	var base_seed := DeterministicRng.stable_mix(world_seed, STRATA_SEED_SALT)
	var deep_crust_noise := make_deep_crust_noise(base_seed, actual_settings)
	var thickness_noise := make_thickness_noise(base_seed, actual_settings)
	var rock_region_seed_cells := RockRegionAssigner.assign_seed_cells(
		graph, geology.province_id, world_seed
	)
	if rock_region_seed_cells.size() != graph.cell_count():
		return null
	var sequence_by_region := {}
	var strata := SubsurfaceStrataLayer.new()
	var count := graph.cell_count()
	strata.cell_offsets.resize(count + 1)
	for cell_id in count:
		strata.cell_offsets[cell_id] = strata.rock_type_ids.size()
		var position := graph.cell_centers[cell_id]
		var province_id := geology.province_id[cell_id]
		var region_seed_cell_id := rock_region_seed_cells[cell_id]
		if not sequence_by_region.has(region_seed_cell_id):
			sequence_by_region[region_seed_cell_id] = RockLayerRules.sequence_for(
				province_id, world_seed, region_seed_cell_id
			)
		var sequence: PackedInt32Array = sequence_by_region[region_seed_cell_id]
		if sequence.is_empty() or sequence[0] != geology.rock_type_id[cell_id]:
			push_error("Surface Rock and Rock Region sequence disagree at Cell %d" % cell_id)
			return null
		var deep_noise := deep_crust_noise.get_noise_2d(position.x, position.y)
		var is_deep_continental := is_continental_deep_substrate(
			composition.continental_value[cell_id], deep_noise, actual_settings
		)
		var basement := RockLayerRules.basement_for(
			is_deep_continental, world_seed, region_seed_cell_id
		)
		var current_top_z := terrain.terrain_height[cell_id]
		var previous_rock := SubsurfaceStrataLayer.NO_ROCK
		for logical_layer_index in sequence.size() + 1:
			var rock_type := sequence[logical_layer_index] \
					if logical_layer_index < sequence.size() else basement
			if rock_type != previous_rock:
				strata.rock_type_ids.append(rock_type)
				strata.top_z.append(current_top_z)
				previous_rock = rock_type
			if logical_layer_index < sequence.size():
				var offset := stable_layer_offset(
					base_seed, logical_layer_index, actual_settings.thickness_feature_scale
				)
				var selector := _unit_value(thickness_noise.get_noise_2d(
					position.x + offset.x, position.y + offset.y
				))
				current_top_z -= thickness_for(
					province_id, logical_layer_index, selector, actual_settings
				)
	strata.cell_offsets[count] = strata.rock_type_ids.size()
	var validation_errors := SubsurfaceStrataValidator.validate(
		graph, composition, terrain, geology, strata, world_seed, actual_settings
	)
	if not validation_errors.is_empty():
		push_error("Subsurface Strata validation failed: " + "; ".join(validation_errors))
		return null
	return strata


static func deep_score_for(
		continental_value: int,
		deep_noise: float,
		settings: SubsurfaceStrataSettings
) -> float:
	return float(continental_value) + deep_noise * settings.deep_crust_noise_amplitude


static func is_continental_deep_substrate(
		continental_value: int,
		deep_noise: float,
		settings: SubsurfaceStrataSettings
) -> bool:
	return deep_score_for(continental_value, deep_noise, settings) \
			>= settings.deep_continental_threshold


static func make_deep_crust_noise(
		base_seed: int, settings: SubsurfaceStrataSettings
) -> FastNoiseLite:
	return _make_noise(
		DeterministicRng.stable_mix(base_seed, DEEP_CRUST_CHANNEL_SALT),
		settings.deep_crust_feature_scale
	)


static func make_thickness_noise(
		base_seed: int, settings: SubsurfaceStrataSettings
) -> FastNoiseLite:
	return _make_noise(
		DeterministicRng.stable_mix(base_seed, THICKNESS_CHANNEL_SALT),
		settings.thickness_feature_scale
	)


static func stable_layer_offset(
		base_seed: int, layer_index: int, feature_scale: float
) -> Vector2:
	var offset_seed := DeterministicRng.stable_mix(
		DeterministicRng.stable_mix(base_seed, THICKNESS_LAYER_OFFSET_SALT),
		layer_index
	)
	var rng := DeterministicRng.new(offset_seed)
	return Vector2(
		rng.range_float(-8.0, 8.0) * feature_scale,
		rng.range_float(-8.0, 8.0) * feature_scale
	)


static func thickness_for(
		province_id: int,
		logical_layer_index: int,
		thickness_selector: float,
		settings: SubsurfaceStrataSettings
) -> float:
	var depth_factor := minf(1.0 + 0.1 * float(logical_layer_index), 1.2)
	return clampf(
		settings.base_thickness_for(province_id)
				* depth_factor
				* lerpf(0.75, 1.25, clampf(thickness_selector, 0.0, 1.0)),
		settings.min_layer_thickness,
		settings.max_layer_thickness
	)


static func _make_noise(seed: int, feature_scale: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.50
	noise.fractal_lacunarity = 2.0
	noise.fractal_weighted_strength = 0.0
	noise.frequency = 1.0 / feature_scale
	noise.domain_warp_enabled = false
	return noise


static func _unit_value(noise_value: float) -> float:
	return clampf(noise_value * 0.5 + 0.5, 0.0, 1.0)


static func _inputs_are_valid(
		graph: SpatialGraph,
		composition: WorldCompositionLayer,
		terrain: TerrainHeightLayer,
		geology: GeologyLayer,
		settings: SubsurfaceStrataSettings
) -> bool:
	if graph == null or composition == null or terrain == null or geology == null:
		push_error(
			"Subsurface Strata requires SpatialGraph, World Composition, Final Terrain, and Geology"
		)
		return false
	var count := graph.cell_count()
	if count <= 0 or graph.cell_centers.size() != count \
			or composition.continental_value.size() != count \
			or terrain.terrain_height.size() != count \
			or geology.province_id.size() != count \
			or geology.rock_type_id.size() != count:
		push_error("Subsurface Strata input arrays must contain one value per Cell")
		return false
	var settings_errors := settings.validate()
	if not settings_errors.is_empty():
		push_error("Invalid Subsurface Strata settings: " + "; ".join(settings_errors))
		return false
	for cell_id in count:
		if not is_finite(graph.cell_centers[cell_id].x) \
				or not is_finite(graph.cell_centers[cell_id].y) \
				or not is_finite(terrain.terrain_height[cell_id]) \
				or geology.province_id[cell_id] < 0 \
				or geology.province_id[cell_id] >= GeologyCatalog.PROVINCE_COUNT \
				or not RockCatalog.is_valid_rock_type(geology.rock_type_id[cell_id]):
			push_error("Subsurface Strata Cell inputs contain invalid values")
			return false
	return true
