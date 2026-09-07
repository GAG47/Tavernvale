class_name ArcaneResourcePotentialValidator
extends RefCounted


static func validate(
		graph: SpatialGraph, resources: ArcaneResourcePotentialLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or resources == null:
		errors.append("Arcane Resource Potential validation requires graph and result layer")
		return errors
	var count := graph.cell_count()
	if count <= 0:
		errors.append("Arcane Resource Potential requires at least one Cell")
		return errors
	var arrays := _named_arrays(resources)
	for entry in arrays:
		if entry[1].size() != count:
			errors.append("%s must contain one value per Cell" % entry[0])
	if not errors.is_empty():
		return errors
	for cell_id in count:
		for entry in arrays:
			var value: float = entry[1][cell_id]
			if not is_finite(value) or value < 0.0 or value > 1.0:
				errors.append(
					"%s[%d] must be finite and inside [0, 1]" % [entry[0], cell_id]
				)
	return errors


static func statistics(resources: ArcaneResourcePotentialLayer) -> Dictionary:
	if resources == null:
		return {}
	var count := resources.cell_count()
	for entry in _named_arrays(resources):
		if entry[1].size() != count:
			return {}
	var result := {}
	for entry in _named_arrays(resources):
		result[entry[0]] = _continuous_statistics(entry[1])
	return result


static func _continuous_statistics(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var minimum := INF
	var maximum := -INF
	var sum := 0.0
	var zero_count := 0
	var threshold_counts := PackedInt32Array([0, 0, 0])
	for value in values:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
		sum += value
		if value == 0.0:
			zero_count += 1
		for threshold_index in 3:
			if value >= [0.25, 0.50, 0.75][threshold_index]:
				threshold_counts[threshold_index] += 1
	return {
		"count": values.size(),
		"min": minimum,
		"mean": sum / float(values.size()),
		"p10": _percentile(sorted, 0.10),
		"p25": _percentile(sorted, 0.25),
		"p50": _percentile(sorted, 0.50),
		"p75": _percentile(sorted, 0.75),
		"p90": _percentile(sorted, 0.90),
		"p95": _percentile(sorted, 0.95),
		"max": maximum,
		"zero_count": zero_count,
		"threshold_counts": threshold_counts,
	}


static func _percentile(sorted_values: PackedFloat32Array, percentile: float) -> float:
	var position := float(sorted_values.size() - 1) * percentile
	var lower_index := floori(position)
	var upper_index := ceili(position)
	if lower_index == upper_index:
		return sorted_values[lower_index]
	return lerpf(
		sorted_values[lower_index],
		sorted_values[upper_index],
		position - lower_index
	)


static func _named_arrays(resources: ArcaneResourcePotentialLayer) -> Array:
	return [
		["arcane_energy_potential", resources.arcane_energy_potential],
		["arcane_material_potential", resources.arcane_material_potential],
		["arcane_bioresource_potential", resources.arcane_bioresource_potential],
		["rare_arcane_resource_potential", resources.rare_arcane_resource_potential],
	]
