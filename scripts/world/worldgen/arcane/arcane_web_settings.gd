class_name ArcaneWebSettings
extends RefCounted

var web_generation_margin: float = 300.0
var web_nucleus_min_separation: float = 210.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(web_generation_margin) or web_generation_margin <= 0.0:
		errors.append("web_generation_margin must be finite and positive")
	if not is_finite(web_nucleus_min_separation) or web_nucleus_min_separation <= 0.0:
		errors.append("web_nucleus_min_separation must be finite and positive")
	return errors


func duplicate_settings() -> ArcaneWebSettings:
	var result := ArcaneWebSettings.new()
	result.web_generation_margin = web_generation_margin
	result.web_nucleus_min_separation = web_nucleus_min_separation
	return result
