class_name SubsurfaceStrataGenerator
extends RefCounted

const STRATA_SEED_SALT := 0x53545241 # "STRA"
const SEQUENCE_CHANNEL_SALTS := [0x53513030, 0x53513031, 0x53513032] # SQ00..SQ02
const THICKNESS_CHANNEL_SALTS := [0x54483030, 0x54483031, 0x54483032] # TH00..TH02
const _DEPTH_FACTORS := [1.0, 1.1, 1.2]


static func generate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		geology: GeologyLayer,
		world_seed: int,
		settings: SubsurfaceStrataSettings = null
) -> SubsurfaceStrataLayer:
	var actual_settings := settings if settings != null else SubsurfaceStrataSettings.new()
	if not _inputs_are_valid(graph, terrain, geology, actual_settings):
		return null
	var base_seed := DeterministicRng.stable_mix(world_seed, STRATA_SEED_SALT)
	var sequence_noises: Array[FastNoiseLite] = []
	var thickness_noises: Array[FastNoiseLite] = []
	for channel_index in 3:
		sequence_noises.append(_make_noise(
			DeterministicRng.stable_mix(base_seed, SEQUENCE_CHANNEL_SALTS[channel_index]),
			actual_settings.sequence_feature_scale
		))
		thickness_noises.append(_make_noise(
			DeterministicRng.stable_mix(base_seed, THICKNESS_CHANNEL_SALTS[channel_index]),
			actual_settings.thickness_feature_scale
		))

	var strata := SubsurfaceStrataLayer.new()
	var count := graph.cell_count()
	strata.cell_offsets.resize(count + 1)
	for cell_id in count:
		strata.cell_offsets[cell_id] = strata.material_ids.size()
		var position := graph.cell_centers[cell_id]
		var province_id := geology.province_id[cell_id]
		var current_material := geology.material_id[cell_id]
		var current_top_z := terrain.terrain_height[cell_id]
		var terminated := false
		for local_layer_index in actual_settings.max_layers:
			strata.material_ids.append(current_material)
			strata.top_z.append(current_top_z)
			var selector := 0.0
			if local_layer_index < sequence_noises.size():
				selector = _unit_value(sequence_noises[local_layer_index].get_noise_2d(
					position.x, position.y
				))
			var next_material := next_material_for(
				province_id, current_material, local_layer_index, selector
			)
			if next_material == SubsurfaceStrataLayer.NO_MATERIAL:
				terminated = true
				break
			if next_material == current_material:
				push_error("Subsurface Strata transition repeated Material at Cell %d" % cell_id)
				return null
			if local_layer_index >= thickness_noises.size():
				break
			var thickness_selector := _unit_value(
				thickness_noises[local_layer_index].get_noise_2d(position.x, position.y)
			)
			current_top_z -= thickness_for(
				province_id, local_layer_index, thickness_selector, actual_settings
			)
			current_material = next_material
		if not terminated:
			push_error("Subsurface Strata did not terminate within max_layers at Cell %d" % cell_id)
			return null
	strata.cell_offsets[count] = strata.material_ids.size()
	var validation_errors := SubsurfaceStrataValidator.validate(
		graph, terrain, geology, strata, actual_settings
	)
	if not validation_errors.is_empty():
		push_error("Subsurface Strata validation failed: " + "; ".join(validation_errors))
		return null
	return strata


static func next_material_for(
		province_id: int, current_material: int, local_layer_index: int, selector: float
) -> int:
	if province_id == GeologyCatalog.Province.OCEANIC_CRUST:
		if current_material == GeologyCatalog.MaterialType.VOLCANIC_ROCK:
			return SubsurfaceStrataLayer.NO_MATERIAL
		return GeologyCatalog.MaterialType.VOLCANIC_ROCK
	if current_material == GeologyCatalog.MaterialType.CRYSTALLINE_ROCK:
		return SubsurfaceStrataLayer.NO_MATERIAL
	if current_material == GeologyCatalog.MaterialType.METAMORPHIC_ROCK:
		return GeologyCatalog.MaterialType.CRYSTALLINE_ROCK

	match province_id:
		GeologyCatalog.Province.CRATON:
			return GeologyCatalog.MaterialType.METAMORPHIC_ROCK \
					if selector < 0.35 else GeologyCatalog.MaterialType.CRYSTALLINE_ROCK
		GeologyCatalog.Province.OROGENIC_BELT:
			return GeologyCatalog.MaterialType.METAMORPHIC_ROCK \
					if selector < 0.80 else GeologyCatalog.MaterialType.CRYSTALLINE_ROCK
		GeologyCatalog.Province.SEDIMENTARY_BASIN:
			return _basin_next_material(current_material, local_layer_index, selector)
		GeologyCatalog.Province.PASSIVE_MARGIN:
			return _passive_margin_next_material(current_material, local_layer_index, selector)
		GeologyCatalog.Province.VOLCANIC_PROVINCE:
			return _volcanic_province_next_material(current_material, selector)
	return SubsurfaceStrataLayer.NO_MATERIAL


static func thickness_for(
		province_id: int,
		local_layer_index: int,
		thickness_selector: float,
		settings: SubsurfaceStrataSettings
) -> float:
	var depth_factor: float = _DEPTH_FACTORS[mini(local_layer_index, _DEPTH_FACTORS.size() - 1)]
	return clampf(
		settings.base_thickness_for(province_id)
				* depth_factor
				* lerpf(0.75, 1.25, clampf(thickness_selector, 0.0, 1.0)),
		settings.min_layer_thickness,
		settings.max_layer_thickness
	)


static func _basin_next_material(current_material: int, layer_index: int, selector: float) -> int:
	if layer_index == 0 and _is_land_sedimentary(current_material):
		match current_material:
			GeologyCatalog.MaterialType.SANDSTONE:
				return GeologyCatalog.MaterialType.SHALE_MUDSTONE \
						if selector < 0.60 else GeologyCatalog.MaterialType.CARBONATE_ROCK
			GeologyCatalog.MaterialType.SHALE_MUDSTONE:
				return GeologyCatalog.MaterialType.SANDSTONE \
						if selector < 0.55 else GeologyCatalog.MaterialType.CARBONATE_ROCK
			GeologyCatalog.MaterialType.CARBONATE_ROCK:
				return GeologyCatalog.MaterialType.SHALE_MUDSTONE \
						if selector < 0.60 else GeologyCatalog.MaterialType.SANDSTONE
	if _is_land_sedimentary(current_material):
		return GeologyCatalog.MaterialType.METAMORPHIC_ROCK \
				if selector < 0.65 else GeologyCatalog.MaterialType.CRYSTALLINE_ROCK
	if current_material == GeologyCatalog.MaterialType.VOLCANIC_ROCK:
		return GeologyCatalog.MaterialType.METAMORPHIC_ROCK \
				if selector < 0.50 else GeologyCatalog.MaterialType.CRYSTALLINE_ROCK
	if current_material == GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK:
		return GeologyCatalog.MaterialType.SHALE_MUDSTONE \
				if selector < 0.65 else GeologyCatalog.MaterialType.METAMORPHIC_ROCK
	return GeologyCatalog.MaterialType.CRYSTALLINE_ROCK


static func _passive_margin_next_material(
		current_material: int, layer_index: int, selector: float
) -> int:
	if layer_index == 0 and _is_land_sedimentary(current_material):
		if selector < 0.30:
			if current_material == GeologyCatalog.MaterialType.SHALE_MUDSTONE:
				return GeologyCatalog.MaterialType.SANDSTONE
			return GeologyCatalog.MaterialType.SHALE_MUDSTONE
		if selector < 0.55:
			if current_material == GeologyCatalog.MaterialType.CARBONATE_ROCK:
				return GeologyCatalog.MaterialType.SANDSTONE
			return GeologyCatalog.MaterialType.CARBONATE_ROCK
		if selector < 0.75:
			return GeologyCatalog.MaterialType.METAMORPHIC_ROCK
		return GeologyCatalog.MaterialType.CRYSTALLINE_ROCK
	if _is_land_sedimentary(current_material):
		return GeologyCatalog.MaterialType.METAMORPHIC_ROCK \
				if selector < 0.45 else GeologyCatalog.MaterialType.CRYSTALLINE_ROCK
	if current_material == GeologyCatalog.MaterialType.VOLCANIC_ROCK:
		return GeologyCatalog.MaterialType.METAMORPHIC_ROCK \
				if selector < 0.35 else GeologyCatalog.MaterialType.CRYSTALLINE_ROCK
	if current_material == GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK:
		return GeologyCatalog.MaterialType.SHALE_MUDSTONE \
				if selector < 0.55 else GeologyCatalog.MaterialType.CRYSTALLINE_ROCK
	return GeologyCatalog.MaterialType.CRYSTALLINE_ROCK


static func _volcanic_province_next_material(current_material: int, selector: float) -> int:
	if current_material == GeologyCatalog.MaterialType.VOLCANIC_ROCK:
		return GeologyCatalog.MaterialType.METAMORPHIC_ROCK \
				if selector < 0.30 else GeologyCatalog.MaterialType.CRYSTALLINE_ROCK
	if _is_land_sedimentary(current_material) \
			or current_material == GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK:
		if selector < 0.60:
			return GeologyCatalog.MaterialType.VOLCANIC_ROCK
		if selector < 0.80:
			return GeologyCatalog.MaterialType.METAMORPHIC_ROCK
	return GeologyCatalog.MaterialType.CRYSTALLINE_ROCK


static func _is_land_sedimentary(material_id: int) -> bool:
	return material_id == GeologyCatalog.MaterialType.SANDSTONE \
			or material_id == GeologyCatalog.MaterialType.SHALE_MUDSTONE \
			or material_id == GeologyCatalog.MaterialType.CARBONATE_ROCK


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
		terrain: TerrainHeightLayer,
		geology: GeologyLayer,
		settings: SubsurfaceStrataSettings
) -> bool:
	if graph == null or terrain == null or geology == null:
		push_error("Subsurface Strata requires SpatialGraph, Final Terrain, and Geology")
		return false
	var count := graph.cell_count()
	if count <= 0 or graph.cell_centers.size() != count \
			or terrain.terrain_height.size() != count \
			or geology.province_id.size() != count \
			or geology.material_id.size() != count:
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
				or geology.material_id[cell_id] < 0 \
				or geology.material_id[cell_id] >= GeologyCatalog.MATERIAL_COUNT:
			push_error("Subsurface Strata Cell inputs contain invalid values")
			return false
	return true
