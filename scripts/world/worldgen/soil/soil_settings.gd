class_name SoilSettings
extends RefCounted

var slope_reference: float = 0.5
var weathering_precip_reference: float = 10.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(slope_reference) or slope_reference <= 0.0:
		errors.append("slope_reference must be finite and positive")
	if not is_finite(weathering_precip_reference) or weathering_precip_reference <= 0.0:
		errors.append("weathering_precip_reference must be finite and positive")
	return errors


func duplicate_settings() -> SoilSettings:
	var result := SoilSettings.new()
	result.slope_reference = slope_reference
	result.weathering_precip_reference = weathering_precip_reference
	return result
