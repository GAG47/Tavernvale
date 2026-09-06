class_name ArcaneEcologyGenerator
extends RefCounted

enum Band {
	LOW = 0,
	MEDIUM = 1,
	HIGH = 2,
}


static func generate(
		arcane_field: ArcaneFieldLayer,
		arcane_environment: ArcaneEnvironmentLayer,
		settings: ArcaneEcologySettings = null
) -> ArcaneEcologyLayer:
	var actual_settings := settings if settings != null else ArcaneEcologySettings.new()
	if arcane_field == null or arcane_environment == null:
		push_error(
			"ArcaneEcologyGenerator requires ArcaneFieldLayer and ArcaneEnvironmentLayer"
		)
		return null
	var settings_errors := actual_settings.validate()
	if not settings_errors.is_empty():
		push_error("ArcaneEcologyGenerator: invalid settings: " + "; ".join(settings_errors))
		return null

	var count := arcane_environment.mana_concentration.size()
	if count <= 0 or arcane_field.background_arcane_potential.size() != count:
		push_error("ArcaneEcologyGenerator: formal input arrays must be non-empty and Cell-aligned")
		return null

	var result := ArcaneEcologyLayer.new()
	result.arcane_ecology_state.resize(count)
	result.arcane_manifestation_type.resize(count)
	var mana_medium_threshold := _stored_threshold(actual_settings.mana_medium_threshold)
	var mana_high_threshold := _stored_threshold(actual_settings.mana_high_threshold)
	var potential_medium_threshold := _stored_threshold(
		actual_settings.potential_medium_threshold
	)
	var potential_high_threshold := _stored_threshold(actual_settings.potential_high_threshold)
	for cell_id in count:
		var mana := arcane_environment.mana_concentration[cell_id]
		var potential := arcane_field.background_arcane_potential[cell_id]
		if not is_finite(mana) or mana < 0.0 or mana > 1.0 \
				or not is_finite(potential) or potential < 0.0 or potential > 1.0:
			push_error(
				"ArcaneEcologyGenerator: formal inputs must be finite and inside [0, 1]"
			)
			return null
		var classification := _classification_for(
			_classify(mana, mana_medium_threshold, mana_high_threshold),
			_classify(potential, potential_medium_threshold, potential_high_threshold)
		)
		result.arcane_ecology_state[cell_id] = classification.x
		result.arcane_manifestation_type[cell_id] = classification.y

	var validation_errors := ArcaneEcologyValidator.validate(
		arcane_field, arcane_environment, result
	)
	if not validation_errors.is_empty():
		push_error("Arcane Ecology validation failed: " + "; ".join(validation_errors))
		return null
	return result


static func classify_mana(value: float, settings: ArcaneEcologySettings) -> int:
	return _classify(
		value,
		_stored_threshold(settings.mana_medium_threshold),
		_stored_threshold(settings.mana_high_threshold)
	)


static func classify_potential(value: float, settings: ArcaneEcologySettings) -> int:
	return _classify(
		value,
		_stored_threshold(settings.potential_medium_threshold),
		_stored_threshold(settings.potential_high_threshold)
	)


static func band_name(band: int) -> String:
	match band:
		Band.LOW:
			return "LOW"
		Band.MEDIUM:
			return "MEDIUM"
		Band.HIGH:
			return "HIGH"
		_:
			return "UNKNOWN"


static func _classify(value: float, medium_threshold: float, high_threshold: float) -> int:
	if value < medium_threshold:
		return Band.LOW
	if value < high_threshold:
		return Band.MEDIUM
	return Band.HIGH


static func _stored_threshold(value: float) -> float:
	return PackedFloat32Array([value])[0]


static func _classification_for(mana_band: int, potential_band: int) -> Vector2i:
	if mana_band == Band.LOW:
		return Vector2i(
			ArcaneEcologyLayer.EcologyState.NORMAL,
			ArcaneEcologyLayer.ManifestationType.NONE
		)
	if potential_band == Band.LOW:
		return Vector2i(
			ArcaneEcologyLayer.EcologyState.NORMAL,
			ArcaneEcologyLayer.ManifestationType.CRYSTALLINE
		)
	if potential_band == Band.MEDIUM:
		return Vector2i(
			ArcaneEcologyLayer.EcologyState.INFLUENCED,
			ArcaneEcologyLayer.ManifestationType.MIXED
		)
	if mana_band == Band.MEDIUM:
		return Vector2i(
			ArcaneEcologyLayer.EcologyState.INFLUENCED,
			ArcaneEcologyLayer.ManifestationType.ECOLOGICAL
		)
	return Vector2i(
		ArcaneEcologyLayer.EcologyState.DOMINANT,
		ArcaneEcologyLayer.ManifestationType.MIXED
	)
