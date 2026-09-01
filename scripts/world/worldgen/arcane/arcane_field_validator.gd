class_name ArcaneFieldValidator
extends RefCounted


static func validate(graph: SpatialGraph, arcane_field: ArcaneFieldLayer) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or arcane_field == null:
		errors.append("Arcane Field validation requires a SpatialGraph and ArcaneFieldLayer")
		return errors
	var count := graph.cell_count()
	if arcane_field.background_mana.size() != count:
		errors.append("background_mana must contain one value per Cell")
	if arcane_field.background_stability.size() != count:
		errors.append("background_stability must contain one value per Cell")
	if not errors.is_empty():
		return errors
	for cell_id in count:
		var mana := arcane_field.background_mana[cell_id]
		if not is_finite(mana) or mana < 0.0 or mana > 1.0:
			errors.append("background_mana[%d] must be finite and inside [0, 1]" % cell_id)
		var stability := arcane_field.background_stability[cell_id]
		if not is_finite(stability) or stability < 0.0 or stability > 1.0:
			errors.append(
				"background_stability[%d] must be finite and inside [0, 1]" % cell_id
			)
	return errors
