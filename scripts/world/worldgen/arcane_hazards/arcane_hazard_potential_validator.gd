class_name ArcaneHazardPotentialValidator
extends RefCounted

const THRESHOLDS := [0.10, 0.25, 0.50, 0.75]


static func validate(hazards: ArcaneHazardPotentialLayer) -> PackedStringArray:
	var errors := PackedStringArray()
	if hazards == null:
		errors.append("Arcane Hazard Potential validation requires a result layer")
		return errors
	var arrays := _named_arrays(hazards)
	var count: int = arrays[0][1].size()
	if count <= 0:
		errors.append("Arcane Hazard Potential arrays must be non-empty")
		return errors
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


static func statistics(hazards: ArcaneHazardPotentialLayer) -> Dictionary:
	if not validate(hazards).is_empty():
		return {}
	var result := {}
	for entry in _named_arrays(hazards):
		result[entry[0]] = continuous_statistics(entry[1])
	return result


static func continuous_statistics(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var minimum := INF
	var maximum := -INF
	var sum := 0.0
	var zero_count := 0
	var threshold_counts := PackedInt32Array()
	threshold_counts.resize(THRESHOLDS.size())
	for value in values:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
		sum += value
		if value == 0.0:
			zero_count += 1
		for threshold_index in THRESHOLDS.size():
			if value >= THRESHOLDS[threshold_index]:
				threshold_counts[threshold_index] += 1
	return {
		"count": values.size(),
		"min": minimum,
		"mean": sum / float(values.size()),
		"p10": _percentile(sorted_values, 0.10),
		"p25": _percentile(sorted_values, 0.25),
		"p50": _percentile(sorted_values, 0.50),
		"p75": _percentile(sorted_values, 0.75),
		"p90": _percentile(sorted_values, 0.90),
		"p95": _percentile(sorted_values, 0.95),
		"max": maximum,
		"zero_count": zero_count,
		"threshold_counts": threshold_counts,
	}


static func pearson(first: PackedFloat32Array, second: PackedFloat32Array) -> float:
	if first.is_empty() or first.size() != second.size():
		return 0.0
	var sum_first := 0.0
	var sum_second := 0.0
	var sum_first_squared := 0.0
	var sum_second_squared := 0.0
	var sum_product := 0.0
	for index in first.size():
		var first_value := float(first[index])
		var second_value := float(second[index])
		sum_first += first_value
		sum_second += second_value
		sum_first_squared += first_value * first_value
		sum_second_squared += second_value * second_value
		sum_product += first_value * second_value
	var count := float(first.size())
	var numerator := count * sum_product - sum_first * sum_second
	var variance_first := count * sum_first_squared - sum_first * sum_first
	var variance_second := count * sum_second_squared - sum_second * sum_second
	var denominator := sqrt(maxf(variance_first * variance_second, 0.0))
	return numerator / denominator if denominator > 0.0 else 0.0


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


static func _named_arrays(hazards: ArcaneHazardPotentialLayer) -> Array:
	return [
		["arcane_hazard_activity_potential", hazards.arcane_hazard_activity_potential],
		["arcane_hazard_severity_potential", hazards.arcane_hazard_severity_potential],
		["arcane_hazard_propagation_potential", hazards.arcane_hazard_propagation_potential],
	]
