class_name EcologySettings
extends RefCounted

var slope_reference: float = 0.5
var closed_basin_surface_escape_multiplier: float = 0.35

var precip_reference: float = 10.0
var drainage_moisture_weight: float = 0.30
var evaporation_moisture_weight: float = 0.25
var max_river_bonus: float = 0.20
var lake_shore_bonus: float = 0.15

var wetland_moisture_threshold: float = 0.53
var wetland_drainage_threshold: float = 0.30

var cold_suitability_minimum: float = -12.0
var cold_suitability_maximum: float = 8.0
var heat_suitability_minimum: float = 35.0
var heat_suitability_maximum: float = 48.0
var vegetation_moisture_exponent: float = 0.8


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(slope_reference) or slope_reference <= 0.0:
		errors.append("slope_reference must be finite and positive")
	if not _is_unit_interval(closed_basin_surface_escape_multiplier):
		errors.append("closed_basin_surface_escape_multiplier must be inside [0, 1]")
	if not is_finite(precip_reference) or precip_reference <= 0.0:
		errors.append("precip_reference must be finite and positive")
	for entry in [
		["drainage_moisture_weight", drainage_moisture_weight],
		["evaporation_moisture_weight", evaporation_moisture_weight],
		["max_river_bonus", max_river_bonus],
		["lake_shore_bonus", lake_shore_bonus],
		["wetland_moisture_threshold", wetland_moisture_threshold],
		["wetland_drainage_threshold", wetland_drainage_threshold],
	]:
		if not _is_unit_interval(entry[1]):
			errors.append("%s must be inside [0, 1]" % entry[0])
	if not is_finite(cold_suitability_minimum) \
			or not is_finite(cold_suitability_maximum) \
			or cold_suitability_maximum <= cold_suitability_minimum:
		errors.append("cold suitability anchors must be finite and strictly increasing")
	if not is_finite(heat_suitability_minimum) \
			or not is_finite(heat_suitability_maximum) \
			or heat_suitability_maximum <= heat_suitability_minimum:
		errors.append("heat suitability anchors must be finite and strictly increasing")
	if not is_finite(vegetation_moisture_exponent) or vegetation_moisture_exponent <= 0.0:
		errors.append("vegetation_moisture_exponent must be finite and positive")
	return errors


func duplicate_settings() -> EcologySettings:
	var result := EcologySettings.new()
	result.slope_reference = slope_reference
	result.closed_basin_surface_escape_multiplier = closed_basin_surface_escape_multiplier
	result.precip_reference = precip_reference
	result.drainage_moisture_weight = drainage_moisture_weight
	result.evaporation_moisture_weight = evaporation_moisture_weight
	result.max_river_bonus = max_river_bonus
	result.lake_shore_bonus = lake_shore_bonus
	result.wetland_moisture_threshold = wetland_moisture_threshold
	result.wetland_drainage_threshold = wetland_drainage_threshold
	result.cold_suitability_minimum = cold_suitability_minimum
	result.cold_suitability_maximum = cold_suitability_maximum
	result.heat_suitability_minimum = heat_suitability_minimum
	result.heat_suitability_maximum = heat_suitability_maximum
	result.vegetation_moisture_exponent = vegetation_moisture_exponent
	return result


func _is_unit_interval(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0
