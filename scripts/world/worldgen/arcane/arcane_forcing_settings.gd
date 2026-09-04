class_name ArcaneForcingSettings
extends RefCounted

var forcing_min_separation: float = 420.0
var forcing_poisson_k: int = 30
var forcing_generation_margin: float = 420.0
var forcing_core_radius: float = 30.0
var forcing_total_power: float = 70.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(forcing_min_separation) or forcing_min_separation <= 0.0:
		errors.append("forcing_min_separation must be finite and positive")
	if forcing_poisson_k <= 0:
		errors.append("forcing_poisson_k must be positive")
	if not is_finite(forcing_generation_margin) or forcing_generation_margin < 0.0:
		errors.append("forcing_generation_margin must be finite and non-negative")
	if not is_finite(forcing_core_radius) or forcing_core_radius <= 0.0:
		errors.append("forcing_core_radius must be finite and positive")
	if not is_finite(forcing_total_power) or forcing_total_power <= 0.0:
		errors.append("forcing_total_power must be finite and positive")
	return errors


func duplicate_settings() -> ArcaneForcingSettings:
	var result := ArcaneForcingSettings.new()
	result.forcing_min_separation = forcing_min_separation
	result.forcing_poisson_k = forcing_poisson_k
	result.forcing_generation_margin = forcing_generation_margin
	result.forcing_core_radius = forcing_core_radius
	result.forcing_total_power = forcing_total_power
	return result
