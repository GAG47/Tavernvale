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
	var rules_errors := RockLayerRules.validate_rules()
	if not rules_errors.is_empty():
		errors.append_array(rules_errors)
		return errors
	var count := graph.cell_count()
	if strata.cell_offsets.size() != count + 1:
		errors.append("cell_offsets size must equal Cell Count + 1")
		return errors
	if strata.cell_offsets[0] != 0:
		errors.append("cell_offsets[0] must equal zero")
	if strata.rock_type_ids.size() != strata.top_z.size():
		errors.append("rock_type_ids and top_z must have equal sizes")
		return errors
	var record_count := strata.rock_type_ids.size()
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
			or geology.rock_type_id.size() != count:
		errors.append("Spatial, World Composition, Final Terrain, and Geology arrays must match Cell Count")
		return errors
	var rock_region_seed_cells := RockRegionAssigner.assign_seed_cells(
		graph, geology.province_id, world_seed
	)
	if rock_region_seed_cells.size() != count:
		errors.append("Rock Region assignment failed")
		return errors
	var base_seed := DeterministicRng.stable_mix(
		world_seed, SubsurfaceStrataGenerator.STRATA_SEED_SALT
	)
	var deep_crust_noise := SubsurfaceStrataGenerator.make_deep_crust_noise(
		base_seed, actual_settings
	)
	var expected_by_region_and_substrate := {}
	for cell_id in count:
		var begin := strata.cell_offsets[cell_id]
		var end := strata.cell_offsets[cell_id + 1]
		if end <= begin:
			errors.append("Cell %d must contain at least one Rock layer" % cell_id)
			continue
		if strata.rock_type_ids[begin] != geology.rock_type_id[cell_id]:
			errors.append("Cell %d first RockType must match Geology" % cell_id)
		if not is_equal_approx(strata.top_z[begin], terrain.terrain_height[cell_id]):
			errors.append("Cell %d first top_z must match Final Terrain" % cell_id)
		for record_index in range(begin, end):
			var rock_type := strata.rock_type_ids[record_index]
			var layer_top_z := strata.top_z[record_index]
			if not RockCatalog.is_valid_rock_type(rock_type):
				errors.append("rock_type_ids[%d] is invalid" % record_index)
			if not is_finite(layer_top_z):
				errors.append("top_z[%d] must be finite" % record_index)
			if record_index + 1 < end:
				if strata.top_z[record_index + 1] >= layer_top_z:
					errors.append("Cell %d top_z must strictly descend" % cell_id)
				if strata.rock_type_ids[record_index + 1] == rock_type:
					errors.append("Cell %d adjacent RockTypes must differ" % cell_id)
		var position := graph.cell_centers[cell_id]
		var is_deep_continental := SubsurfaceStrataGenerator.is_continental_deep_substrate(
			composition.continental_value[cell_id],
			deep_crust_noise.get_noise_2d(position.x, position.y),
			actual_settings
		)
		var region_seed_cell_id := rock_region_seed_cells[cell_id]
		var expected_key := "%d:%d" % [region_seed_cell_id, int(is_deep_continental)]
		if not expected_by_region_and_substrate.has(expected_key):
			var expected := RockLayerRules.sequence_for(
				geology.province_id[cell_id], world_seed, region_seed_cell_id
			)
			expected.append(RockLayerRules.basement_for(
				is_deep_continental, world_seed, region_seed_cell_id
			))
			expected_by_region_and_substrate[expected_key] = _normalized_sequence(expected)
		var expected_sequence: PackedInt32Array = expected_by_region_and_substrate[expected_key]
		if end - begin != expected_sequence.size():
			errors.append("Cell %d stored Rock sequence has the wrong length" % cell_id)
			continue
		for local_index in expected_sequence.size():
			if strata.rock_type_ids[begin + local_index] != expected_sequence[local_index]:
				errors.append("Cell %d stored Rock sequence does not match its Rock Region" % cell_id)
				break
	return errors


static func _normalized_sequence(sequence: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for rock_type in sequence:
		if result.is_empty() or result[-1] != rock_type:
			result.append(rock_type)
	return result
