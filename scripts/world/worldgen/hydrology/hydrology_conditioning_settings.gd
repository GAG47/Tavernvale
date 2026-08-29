class_name HydrologyConditioningSettings
extends RefCounted

## Conservative v1.4 terrain-conditioning thresholds in normalized terrain units.

var flow_epsilon: float = 0.001
var small_fill_max_cells: int = 4
var small_fill_max_depth: float = 1.0
var max_breach_distance: int = 12
var max_breach_cost: float = 12.0
var fallback_fill_max_cells: int = 16
var fallback_fill_max_depth: float = 2.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(flow_epsilon) or flow_epsilon <= 0.0:
		errors.append("flow_epsilon must be finite and greater than zero")
	if small_fill_max_cells < 1:
		errors.append("small_fill_max_cells must be at least one")
	if not is_finite(small_fill_max_depth) or small_fill_max_depth < 0.0:
		errors.append("small_fill_max_depth must be finite and non-negative")
	if max_breach_distance < 1:
		errors.append("max_breach_distance must be at least one")
	if not is_finite(max_breach_cost) or max_breach_cost < 0.0:
		errors.append("max_breach_cost must be finite and non-negative")
	if fallback_fill_max_cells < 1:
		errors.append("fallback_fill_max_cells must be at least one")
	if not is_finite(fallback_fill_max_depth) or fallback_fill_max_depth < 0.0:
		errors.append("fallback_fill_max_depth must be finite and non-negative")
	return errors
