class_name ArcaneEcologyValidator
extends RefCounted


static func validate_inputs(
		ecology: EcologyLayer, environment: ArcaneEnvironmentLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if ecology == null:
		errors.append("EcologyLayer is null")
	if environment == null:
		errors.append("ArcaneEnvironmentLayer is null")
	if not errors.is_empty():
		return errors
	var count := ecology.cell_count()
	if environment.cell_count() != count:
		errors.append("Ecology and Arcane Environment Cell counts must match")
	_validate_continuous(ecology.ecological_moisture, count, "ecological_moisture", errors)
	_validate_continuous(ecology.vegetation_potential, count, "vegetation_potential", errors)
	_validate_continuous(environment.mana_concentration, count, "mana_concentration", errors)
	_validate_continuous(environment.mana_flowability, count, "mana_flowability", errors)
	_validate_continuous(environment.mana_stability, count, "mana_stability", errors)
	if ecology.biome_id.size() != count:
		errors.append("biome_id size must match Cell count")
	for cell_id in ecology.biome_id.size():
		var biome := ecology.biome_id[cell_id]
		if biome < 0 or biome >= EcologyCatalog.BIOME_COUNT \
				or ArcaneEcologyCatalog.natural_group_for_biome(biome) < 0:
			errors.append("Cell %d has invalid biome_id %d" % [cell_id, biome])
	return errors


static func validate(count: int, layer: ArcaneEcologyLayer) -> PackedStringArray:
	var errors := PackedStringArray()
	if layer == null:
		errors.append("ArcaneEcologyLayer is null")
		return errors
	_validate_continuous(layer.arcane_ecology_potential, count, "arcane_ecology_potential", errors)
	if layer.arcane_ecology_state.size() != count:
		errors.append("arcane_ecology_state size must match Cell count")
	if layer.arcane_response_profile_id.size() != count:
		errors.append("arcane_response_profile_id size must match Cell count")
	if not errors.is_empty():
		return errors
	for cell_id in count:
		var state := layer.arcane_ecology_state[cell_id]
		var profile := layer.arcane_response_profile_id[cell_id]
		var potential := layer.arcane_ecology_potential[cell_id]
		if state < 0 or state >= ArcaneEcologyCatalog.STATE_COUNT:
			errors.append("Cell %d has invalid arcane_ecology_state" % cell_id)
		if profile < ArcaneEcologyCatalog.NO_RESPONSE_PROFILE or profile >= ArcaneEcologyCatalog.PROFILE_COUNT:
			errors.append("Cell %d has invalid arcane_response_profile_id" % cell_id)
		if (profile == ArcaneEcologyCatalog.NO_RESPONSE_PROFILE) != (potential == 0.0):
			errors.append("Cell %d must have NO_RESPONSE_PROFILE exactly when potential is zero" % cell_id)
	return errors


static func _validate_continuous(
		values: PackedFloat32Array, count: int, label: String, errors: PackedStringArray
) -> void:
	if values.size() != count:
		errors.append("%s size must match Cell count" % label)
	for cell_id in values.size():
		var value := values[cell_id]
		if not is_finite(value) or value < 0.0 or value > 1.0:
			errors.append("%s Cell %d must be finite and inside [0, 1]" % [label, cell_id])
