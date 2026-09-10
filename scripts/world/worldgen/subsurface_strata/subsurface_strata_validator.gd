class_name SubsurfaceStrataValidator
extends RefCounted


static func validate(
		graph: SpatialGraph,
		composition: WorldCompositionLayer,
		terrain: TerrainHeightLayer,
		geology: GeologyLayer,
		strata: SubsurfaceStrataLayer,
		world_seed: int,
		settings: SubsurfaceStrataSettings = null
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or composition == null or terrain == null \
			or geology == null or strata == null:
		errors.append(
			"Spatial, World Composition, Final Terrain, Geology, and SubsurfaceStrataLayer must not be null"
		)
		return errors
	var actual_settings := settings if settings != null else SubsurfaceStrataSettings.new()
	var settings_errors := actual_settings.validate()
	if not settings_errors.is_empty():
		errors.append_array(settings_errors)
		return errors
	var count := graph.cell_count()
	var maximum_layers := actual_settings.max_layers
	if strata.cell_offsets.size() != count + 1:
		errors.append("cell_offsets size must equal Cell Count + 1")
		return errors
	if strata.cell_offsets[0] != 0:
		errors.append("cell_offsets[0] must equal zero")
	if strata.material_ids.size() != strata.top_z.size():
		errors.append("material_ids and top_z must have equal sizes")
		return errors
	var record_count := strata.material_ids.size()
	var previous_offset := 0
	for offset_index in strata.cell_offsets.size():
		var offset := strata.cell_offsets[offset_index]
		if offset < previous_offset:
			errors.append("cell_offsets must be monotonically non-decreasing")
			return errors
		if offset < 0 or offset > record_count:
			errors.append("cell_offsets[%d] is outside the record arrays" % offset_index)
			return errors
		previous_offset = offset
	if strata.cell_offsets[-1] != record_count:
		errors.append("final cell offset must equal record count")
		return errors
	if graph.cell_centers.size() != count \
			or composition.continental_value.size() != count \
			or terrain.terrain_height.size() != count \
			or geology.province_id.size() != count \
			or geology.material_id.size() != count:
		errors.append("Spatial, World Composition, Final Terrain, and Geology arrays must match Cell Count")
		return errors
	var base_seed := DeterministicRng.stable_mix(
		world_seed, SubsurfaceStrataGenerator.STRATA_SEED_SALT
	)
	var deep_crust_noise := SubsurfaceStrataGenerator.make_deep_crust_noise(
		base_seed, actual_settings
	)

	for cell_id in count:
		var begin := strata.cell_offsets[cell_id]
		var end := strata.cell_offsets[cell_id + 1]
		var layer_count := end - begin
		if layer_count < 1 or layer_count > 4 or layer_count > maximum_layers:
			errors.append("Cell %d layer count must be inside [1, max_layers]" % cell_id)
			continue
		if strata.material_ids[begin] != geology.material_id[cell_id]:
			errors.append("Cell %d first Material must match Geology" % cell_id)
		if not is_equal_approx(strata.top_z[begin], terrain.terrain_height[cell_id]):
			errors.append("Cell %d first top_z must match Final Terrain" % cell_id)
		var position := graph.cell_centers[cell_id]
		var is_deep_continental := SubsurfaceStrataGenerator.is_continental_deep_substrate(
			composition.continental_value[cell_id],
			deep_crust_noise.get_noise_2d(position.x, position.y),
			actual_settings
		)
		for record_index in range(begin, end):
			var material_id := strata.material_ids[record_index]
			var layer_top_z := strata.top_z[record_index]
			if material_id < 0 or material_id >= GeologyCatalog.MATERIAL_COUNT:
				errors.append("material_ids[%d] is invalid" % record_index)
			if not is_finite(layer_top_z):
				errors.append("top_z[%d] must be finite" % record_index)
			if record_index + 1 < end:
				if strata.top_z[record_index + 1] >= layer_top_z:
					errors.append("Cell %d top_z must strictly descend" % cell_id)
				if strata.material_ids[record_index + 1] == material_id:
					errors.append("Cell %d adjacent Materials must differ" % cell_id)
				if not SubsurfaceStrataGenerator.transition_is_allowed(
					geology.province_id[cell_id],
					material_id,
					strata.material_ids[record_index + 1],
					record_index - begin,
					is_deep_continental
				):
					errors.append(
					"Cell %d layer %d transition is not allowed for its Province"
					% [cell_id, record_index - begin]
				)
		var expected_terminal := GeologyCatalog.MaterialType.CRYSTALLINE_ROCK
		if geology.province_id[cell_id] == GeologyCatalog.Province.OCEANIC_CRUST \
				and not is_deep_continental:
			expected_terminal = GeologyCatalog.MaterialType.VOLCANIC_ROCK
		if strata.material_ids[end - 1] != expected_terminal:
			errors.append("Cell %d has the wrong terminal Material" % cell_id)
	return errors
