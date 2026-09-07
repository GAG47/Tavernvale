class_name ArcaneHazardPotentialGenerator
extends RefCounted


static func generate(
		arcane_field: ArcaneFieldLayer,
		arcane_environment: ArcaneEnvironmentLayer
) -> ArcaneHazardPotentialLayer:
	if not _inputs_are_valid(arcane_field, arcane_environment):
		return null
	var result := ArcaneHazardPotentialLayer.new()
	var count := arcane_environment.mana_concentration.size()
	result.arcane_hazard_activity_potential.resize(count)
	result.arcane_hazard_severity_potential.resize(count)
	result.arcane_hazard_propagation_potential.resize(count)
	for cell_id in count:
		result.arcane_hazard_activity_potential[cell_id] = activity_potential_for(
			arcane_environment.mana_stability[cell_id],
			arcane_environment.mana_flowability[cell_id]
		)
		result.arcane_hazard_severity_potential[cell_id] = severity_potential_for(
			arcane_environment.mana_concentration[cell_id],
			arcane_field.background_arcane_potential[cell_id]
		)
		result.arcane_hazard_propagation_potential[cell_id] = propagation_potential_for(
			arcane_environment.mana_flowability[cell_id],
			arcane_environment.mana_concentration[cell_id]
		)
	var errors := ArcaneHazardPotentialValidator.validate(result)
	if not errors.is_empty():
		push_error("Arcane Hazard Potential validation failed: " + "; ".join(errors))
		return null
	return result


static func activity_potential_for(stability: float, flowability: float) -> float:
	var instability := 1.0 - clampf(stability, 0.0, 1.0)
	return clampf(
		instability * (0.70 + 0.30 * clampf(flowability, 0.0, 1.0)), 0.0, 1.0
	)


static func severity_potential_for(concentration: float, potential: float) -> float:
	return clampf(
		clampf(concentration, 0.0, 1.0)
		* (0.70 + 0.30 * clampf(potential, 0.0, 1.0)),
		0.0,
		1.0
	)


static func propagation_potential_for(flowability: float, concentration: float) -> float:
	return clampf(
		clampf(flowability, 0.0, 1.0)
		* (0.60 + 0.40 * clampf(concentration, 0.0, 1.0)),
		0.0,
		1.0
	)


static func _inputs_are_valid(
		arcane_field: ArcaneFieldLayer,
		arcane_environment: ArcaneEnvironmentLayer
) -> bool:
	if arcane_field == null or arcane_environment == null:
		push_error("Arcane Hazard Potential requires Arcane Field and Arcane Environment")
		return false
	var count := arcane_environment.mana_concentration.size()
	if count <= 0:
		push_error("Arcane Hazard Potential formal input arrays must be non-empty")
		return false
	if arcane_environment.mana_flowability.size() != count \
			or arcane_environment.mana_stability.size() != count \
			or arcane_field.background_arcane_potential.size() != count:
		push_error("Arcane Hazard Potential formal input arrays must be Cell-aligned")
		return false
	for cell_id in count:
		var named_values := [
			["mana_concentration", arcane_environment.mana_concentration[cell_id]],
			["mana_flowability", arcane_environment.mana_flowability[cell_id]],
			["mana_stability", arcane_environment.mana_stability[cell_id]],
			["background_arcane_potential", arcane_field.background_arcane_potential[cell_id]],
		]
		for entry in named_values:
			var value: float = entry[1]
			if not is_finite(value) or value < 0.0 or value > 1.0:
				push_error("%s[%d] must be finite and inside [0, 1]" % [entry[0], cell_id])
				return false
	return true
