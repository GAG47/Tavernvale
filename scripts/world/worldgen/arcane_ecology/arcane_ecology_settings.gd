class_name ArcaneEcologySettings
extends RefCounted

var mana_medium_threshold: float = 0.60
var mana_high_threshold: float = 0.75
var potential_medium_threshold: float = 0.55
var potential_high_threshold: float = 0.65


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	_validate_threshold_pair(
		"mana", mana_medium_threshold, mana_high_threshold, errors
	)
	_validate_threshold_pair(
		"potential", potential_medium_threshold, potential_high_threshold, errors
	)
	return errors


func duplicate_settings() -> ArcaneEcologySettings:
	var result := ArcaneEcologySettings.new()
	result.mana_medium_threshold = mana_medium_threshold
	result.mana_high_threshold = mana_high_threshold
	result.potential_medium_threshold = potential_medium_threshold
	result.potential_high_threshold = potential_high_threshold
	return result


func _validate_threshold_pair(
		label: String,
		medium_threshold: float,
		high_threshold: float,
		errors: PackedStringArray
) -> void:
	if not is_finite(medium_threshold) or not is_finite(high_threshold):
		errors.append("%s thresholds must be finite" % label)
	elif medium_threshold < 0.0 or medium_threshold >= high_threshold \
			or high_threshold > 1.0:
		errors.append("%s thresholds must satisfy 0 <= medium < high <= 1" % label)
