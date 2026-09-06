class_name ArcaneEcologyValidator
extends RefCounted


static func validate(
		arcane_field: ArcaneFieldLayer,
		arcane_environment: ArcaneEnvironmentLayer,
		arcane_ecology: ArcaneEcologyLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if arcane_field == null or arcane_environment == null or arcane_ecology == null:
		errors.append(
			"Arcane Ecology validation requires Field, Environment, and Ecology layers"
		)
		return errors
	var count := arcane_environment.mana_concentration.size()
	if arcane_field.background_arcane_potential.size() != count:
		errors.append("Arcane Ecology formal input arrays must have the same Cell count")
	if arcane_ecology.arcane_ecology_state.size() != count:
		errors.append("arcane_ecology_state must contain one value per input Cell")
	if arcane_ecology.arcane_manifestation_type.size() != count:
		errors.append("arcane_manifestation_type must contain one value per input Cell")
	if not errors.is_empty():
		return errors

	for cell_id in count:
		var state := arcane_ecology.arcane_ecology_state[cell_id]
		var manifestation := arcane_ecology.arcane_manifestation_type[cell_id]
		if state not in [
			ArcaneEcologyLayer.EcologyState.NORMAL,
			ArcaneEcologyLayer.EcologyState.INFLUENCED,
			ArcaneEcologyLayer.EcologyState.DOMINANT,
		]:
			errors.append("arcane_ecology_state[%d] is invalid" % cell_id)
			continue
		if manifestation not in [
			ArcaneEcologyLayer.ManifestationType.NONE,
			ArcaneEcologyLayer.ManifestationType.MANA_DOMINANT,
			ArcaneEcologyLayer.ManifestationType.ECOLOGY_DOMINANT,
			ArcaneEcologyLayer.ManifestationType.MIXED,
		]:
			errors.append("arcane_manifestation_type[%d] is invalid" % cell_id)
			continue
		if manifestation == ArcaneEcologyLayer.ManifestationType.NONE \
				and state != ArcaneEcologyLayer.EcologyState.NORMAL:
			errors.append("NONE manifestation requires NORMAL Ecology State at Cell %d" % cell_id)
		if state == ArcaneEcologyLayer.EcologyState.DOMINANT \
				and manifestation != ArcaneEcologyLayer.ManifestationType.MIXED:
			errors.append("DOMINANT Ecology State requires MIXED manifestation at Cell %d" % cell_id)
	return errors


static func statistics(
		arcane_field: ArcaneFieldLayer,
		arcane_environment: ArcaneEnvironmentLayer,
		arcane_ecology: ArcaneEcologyLayer,
		settings: ArcaneEcologySettings = null
) -> Dictionary:
	if arcane_field == null or arcane_environment == null or arcane_ecology == null:
		return {}
	var actual_settings := settings if settings != null else ArcaneEcologySettings.new()
	if not actual_settings.validate().is_empty():
		return {}
	var count := arcane_environment.mana_concentration.size()
	if count <= 0 or arcane_field.background_arcane_potential.size() != count \
			or arcane_ecology.arcane_ecology_state.size() != count \
			or arcane_ecology.arcane_manifestation_type.size() != count:
		return {}

	var mana_band_counts := PackedInt32Array([0, 0, 0])
	var potential_band_counts := PackedInt32Array([0, 0, 0])
	var ecology_state_counts := PackedInt32Array([0, 0, 0])
	var manifestation_type_counts := PackedInt32Array([0, 0, 0, 0])
	var matrix: Array[PackedInt32Array] = [
		PackedInt32Array([0, 0, 0]),
		PackedInt32Array([0, 0, 0]),
		PackedInt32Array([0, 0, 0]),
	]
	var sum_mana := 0.0
	var sum_potential := 0.0
	var sum_mana_squared := 0.0
	var sum_potential_squared := 0.0
	var sum_product := 0.0
	var mana_medium_threshold := _stored_threshold(actual_settings.mana_medium_threshold)
	var mana_high_threshold := _stored_threshold(actual_settings.mana_high_threshold)
	var potential_medium_threshold := _stored_threshold(
		actual_settings.potential_medium_threshold
	)
	var potential_high_threshold := _stored_threshold(actual_settings.potential_high_threshold)
	for cell_id in count:
		var mana := float(arcane_environment.mana_concentration[cell_id])
		var potential := float(arcane_field.background_arcane_potential[cell_id])
		var mana_band := _classify(
			mana, mana_medium_threshold, mana_high_threshold
		)
		var potential_band := _classify(
			potential, potential_medium_threshold, potential_high_threshold
		)
		mana_band_counts[mana_band] += 1
		potential_band_counts[potential_band] += 1
		matrix[mana_band][potential_band] += 1
		ecology_state_counts[arcane_ecology.arcane_ecology_state[cell_id]] += 1
		manifestation_type_counts[arcane_ecology.arcane_manifestation_type[cell_id]] += 1
		sum_mana += mana
		sum_potential += potential
		sum_mana_squared += mana * mana
		sum_potential_squared += potential * potential
		sum_product += mana * potential
	return {
		"cell_count": count,
		"mana_band_counts": mana_band_counts,
		"potential_band_counts": potential_band_counts,
		"matrix": matrix,
		"ecology_state_counts": ecology_state_counts,
		"manifestation_type_counts": manifestation_type_counts,
		"mana_potential_pearson": _pearson(
			count,
			sum_mana,
			sum_potential,
			sum_mana_squared,
			sum_potential_squared,
			sum_product
		),
	}


static func _classify(value: float, medium_threshold: float, high_threshold: float) -> int:
	if value < medium_threshold:
		return ArcaneEcologyGenerator.Band.LOW
	if value < high_threshold:
		return ArcaneEcologyGenerator.Band.MEDIUM
	return ArcaneEcologyGenerator.Band.HIGH


static func _stored_threshold(value: float) -> float:
	return PackedFloat32Array([value])[0]


static func _pearson(
		count: int,
		sum_x: float,
		sum_y: float,
		sum_x_squared: float,
		sum_y_squared: float,
		sum_product: float
) -> float:
	var numerator := float(count) * sum_product - sum_x * sum_y
	var variance_x := float(count) * sum_x_squared - sum_x * sum_x
	var variance_y := float(count) * sum_y_squared - sum_y * sum_y
	var denominator := sqrt(maxf(variance_x * variance_y, 0.0))
	return numerator / denominator if denominator > 0.0 else 0.0
