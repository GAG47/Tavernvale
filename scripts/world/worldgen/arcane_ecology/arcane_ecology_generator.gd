class_name ArcaneEcologyGenerator
extends RefCounted

const _STATE_TABLE := [[0, 0, 0], [0, 1, 1], [0, 1, 2]]


static func generate(
		ecology: EcologyLayer, arcane_environment: ArcaneEnvironmentLayer,
		settings: ArcaneEcologySettings = null
) -> ArcaneEcologyLayer:
	var actual_settings := settings if settings != null else ArcaneEcologySettings.new()
	var errors := ArcaneEcologyValidator.validate_inputs(ecology, arcane_environment)
	errors.append_array(actual_settings.validate())
	if not errors.is_empty():
		push_error("Arcane Ecology input validation failed: " + "; ".join(errors))
		return null
	var result := ArcaneEcologyLayer.new()
	var count := ecology.cell_count()
	result.arcane_ecology_potential.resize(count)
	result.arcane_ecology_state.resize(count)
	result.arcane_response_profile_id.resize(count)
	for cell_id in count:
		var group := ArcaneEcologyCatalog.natural_group_for_biome(ecology.biome_id[cell_id])
		var natural_base := natural_base_for(group, ecology.ecological_moisture[cell_id],
			ecology.vegetation_potential[cell_id], actual_settings)
		var best := 0.0
		var winner := ArcaneEcologyCatalog.NO_RESPONSE_PROFILE
		for profile in ArcaneEcologyCatalog.PROFILE_COUNT:
			var natural_response := clampf(
				natural_base * actual_settings.profile_affinities[group][profile], 0.0, 1.0)
			var stability := _suitability(arcane_environment.mana_stability[cell_id],
				actual_settings.stability_anchors[profile])
			var flowability := _suitability(arcane_environment.mana_flowability[cell_id],
				actual_settings.flowability_anchors[profile])
			var environment_match := sqrt(stability * flowability)
			var profile_potential := clampf(natural_response * environment_match, 0.0, 1.0)
			# Strict comparison preserves enum order for equal non-zero maxima.
			if profile_potential > best:
				best = profile_potential
				winner = profile
		result.arcane_ecology_potential[cell_id] = best
		result.arcane_response_profile_id[cell_id] = winner
		# Concentration is only the independent classification axis, never a potential input.
		result.arcane_ecology_state[cell_id] = state_for(
			arcane_environment.mana_concentration[cell_id],
			result.arcane_ecology_potential[cell_id], actual_settings)
	errors = ArcaneEcologyValidator.validate(count, result)
	if not errors.is_empty():
		push_error("Arcane Ecology output validation failed: " + "; ".join(errors))
		return null
	return result


static func natural_base_for(
		group: int, moisture: float, vegetation: float, settings: ArcaneEcologySettings
) -> float:
	var result := 0.0
	match group:
		ArcaneEcologyCatalog.NaturalEcologyGroup.WOODLAND:
			result = lerpf(settings.woodland_response_floor, 1.0, vegetation)
		ArcaneEcologyCatalog.NaturalEcologyGroup.OPEN_VEGETATION:
			result = lerpf(settings.open_vegetation_response_floor, 1.0, vegetation)
		ArcaneEcologyCatalog.NaturalEcologyGroup.WETLAND:
			result = lerpf(settings.wetland_response_floor, 1.0, maxf(moisture, vegetation))
		ArcaneEcologyCatalog.NaturalEcologyGroup.BARREN_EXTREME:
			result = settings.barren_extreme_response
		ArcaneEcologyCatalog.NaturalEcologyGroup.AQUATIC:
			result = settings.aquatic_response
	return clampf(result, 0.0, 1.0)


static func trapezoid_suitability(
		value: float, zero_low: float, full_low: float, full_high: float, zero_high: float
) -> float:
	if value < zero_low or value > zero_high:
		return 0.0
	if value >= full_low and value <= full_high:
		return 1.0
	if value < full_low:
		return (value - zero_low) / (full_low - zero_low)
	return (zero_high - value) / (zero_high - full_high)


static func _suitability(value: float, anchors: PackedFloat64Array) -> float:
	return trapezoid_suitability(value, anchors[0], anchors[1], anchors[2], anchors[3])


static func band_for(value: float, medium: float, high: float) -> int:
	if value < medium:
		return ArcaneEcologyCatalog.Band.LOW
	if value < high:
		return ArcaneEcologyCatalog.Band.MEDIUM
	return ArcaneEcologyCatalog.Band.HIGH


static func state_for(mana: float, potential: float, settings: ArcaneEcologySettings) -> int:
	return _STATE_TABLE[
		band_for(mana, settings.mana_concentration_medium_threshold,
			settings.mana_concentration_high_threshold)
	][
		band_for(potential, settings.arcane_ecology_potential_medium_threshold,
			settings.arcane_ecology_potential_high_threshold)
	]


## Read-only diagnostics of formal outputs; no additional persistent layer fields.
static func statistics(
		ecology: EcologyLayer, environment: ArcaneEnvironmentLayer,
		layer: ArcaneEcologyLayer, settings: ArcaneEcologySettings = null
) -> Dictionary:
	var actual_settings := settings if settings != null else ArcaneEcologySettings.new()
	var errors := ArcaneEcologyValidator.validate_inputs(ecology, environment)
	if ecology != null:
		errors.append_array(ArcaneEcologyValidator.validate(ecology.cell_count(), layer))
	errors.append_array(actual_settings.validate())
	if not errors.is_empty():
		push_error("Arcane Ecology statistics validation failed: " + "; ".join(errors))
		return {}
	var mana_counts := [0, 0, 0]
	var potential_counts := [0, 0, 0]
	var state_counts := [0, 0, 0]
	# The final entry is NO_RESPONSE_PROFILE.
	var profile_counts := [0, 0, 0, 0]
	var mana_potential := [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
	var group_state := [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]]
	var minimum := INF
	var maximum := 0.0
	var total := 0.0
	var count := layer.cell_count()
	for cell_id in count:
		var potential := layer.arcane_ecology_potential[cell_id]
		minimum = minf(minimum, potential)
		maximum = maxf(maximum, potential)
		total += potential
		var mana_band := band_for(environment.mana_concentration[cell_id],
			actual_settings.mana_concentration_medium_threshold,
			actual_settings.mana_concentration_high_threshold)
		var potential_band := band_for(potential,
			actual_settings.arcane_ecology_potential_medium_threshold,
			actual_settings.arcane_ecology_potential_high_threshold)
		var state := layer.arcane_ecology_state[cell_id]
		var profile := layer.arcane_response_profile_id[cell_id]
		var group := ArcaneEcologyCatalog.natural_group_for_biome(ecology.biome_id[cell_id])
		mana_counts[mana_band] += 1
		potential_counts[potential_band] += 1
		state_counts[state] += 1
		profile_counts[profile if profile >= 0 else 3] += 1
		mana_potential[mana_band][potential_band] += 1
		group_state[group][state] += 1
	return {
		"cell_count": count,
		"potential": {"min": minimum if count > 0 else 0.0,
			"mean": total / count if count > 0 else 0.0, "max": maximum},
		"mana_bands": _count_statistics(mana_counts, count),
		"potential_bands": _count_statistics(potential_counts, count),
		"states": _count_statistics(state_counts, count),
		"profiles": _count_statistics(profile_counts, count),
		"mana_by_potential": mana_potential,
		"group_by_state": group_state,
	}


static func _count_statistics(counts: Array, total: int) -> Array:
	var result := []
	for count in counts:
		result.append({"count": count,
			"percentage": 100.0 * count / total if total > 0 else 0.0})
	return result
