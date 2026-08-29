class_name WorldHydrologySettings
extends RefCounted

## Relative v1.5 water units. No real-world unit is assigned yet.

var runoff_modifier: float = 1.0
var river_runoff_threshold: float = 50000.0


func _init(runoff_scale: float = 1.0, river_threshold: float = 50000.0) -> void:
	runoff_modifier = runoff_scale
	river_runoff_threshold = river_threshold


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(runoff_modifier) or runoff_modifier < 0.0:
		errors.append("runoff_modifier must be finite and non-negative")
	if not is_finite(river_runoff_threshold) or river_runoff_threshold < 0.0:
		errors.append("river_runoff_threshold must be finite and non-negative")
	return errors


func duplicate_settings() -> WorldHydrologySettings:
	return WorldHydrologySettings.new(runoff_modifier, river_runoff_threshold)
