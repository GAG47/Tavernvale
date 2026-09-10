class_name GroundwaterSettings
extends RefCounted

var precipitation_reference: float = 20.0
var river_recharge_radius: float = 40.0
var lake_recharge_radius: float = 60.0
var surface_water_recharge_weight: float = 0.30
var min_water_table_depth: float = 6.0
var max_water_table_depth: float = 50.0
var highland_start_z: float = 40.0
var highland_full_z: float = 80.0
var highland_max_extra_depth: float = 20.0
var active_groundwater_half_depth: float = 50.0
var light_aquifer_threshold: float = 0.18
var heavy_aquifer_threshold: float = 0.45
var marine_influence_radius: float = 50.0
var brackish_salinity_threshold: float = 0.20
var saline_salinity_threshold: float = 0.60


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(precipitation_reference) or precipitation_reference <= 0.0:
		errors.append("precipitation_reference must be finite and positive")
	if not is_finite(river_recharge_radius) or river_recharge_radius <= 0.0:
		errors.append("river_recharge_radius must be finite and positive")
	if not is_finite(lake_recharge_radius) or lake_recharge_radius <= 0.0:
		errors.append("lake_recharge_radius must be finite and positive")
	if not is_finite(surface_water_recharge_weight) \
			or surface_water_recharge_weight < 0.0 \
			or surface_water_recharge_weight > 1.0:
		errors.append("surface_water_recharge_weight must be finite and inside [0, 1]")
	if not is_finite(min_water_table_depth) or min_water_table_depth < 0.0:
		errors.append("min_water_table_depth must be finite and non-negative")
	if not is_finite(max_water_table_depth) \
			or max_water_table_depth < min_water_table_depth:
		errors.append("max_water_table_depth must be finite and at least the minimum")
	if not is_finite(highland_start_z) or not is_finite(highland_full_z) \
			or highland_full_z <= highland_start_z:
		errors.append("highland_full_z must be finite and greater than highland_start_z")
	if not is_finite(highland_max_extra_depth) or highland_max_extra_depth < 0.0:
		errors.append("highland_max_extra_depth must be finite and non-negative")
	if not is_finite(active_groundwater_half_depth) or active_groundwater_half_depth <= 0.0:
		errors.append("active_groundwater_half_depth must be finite and positive")
	if not is_finite(light_aquifer_threshold) \
			or not is_finite(heavy_aquifer_threshold) \
			or light_aquifer_threshold < 0.0 \
			or heavy_aquifer_threshold <= light_aquifer_threshold \
			or heavy_aquifer_threshold > 1.0:
		errors.append("Aquifer thresholds must satisfy 0 <= light < heavy <= 1")
	if not is_finite(marine_influence_radius) or marine_influence_radius <= 0.0:
		errors.append("marine_influence_radius must be finite and positive")
	if not is_finite(brackish_salinity_threshold) \
			or not is_finite(saline_salinity_threshold) \
			or brackish_salinity_threshold < 0.0 \
			or saline_salinity_threshold <= brackish_salinity_threshold \
			or saline_salinity_threshold > 1.0:
		errors.append("Salinity thresholds must satisfy 0 <= brackish < saline <= 1")
	return errors


func duplicate_settings() -> GroundwaterSettings:
	var result := GroundwaterSettings.new()
	result.precipitation_reference = precipitation_reference
	result.river_recharge_radius = river_recharge_radius
	result.lake_recharge_radius = lake_recharge_radius
	result.surface_water_recharge_weight = surface_water_recharge_weight
	result.min_water_table_depth = min_water_table_depth
	result.max_water_table_depth = max_water_table_depth
	result.highland_start_z = highland_start_z
	result.highland_full_z = highland_full_z
	result.highland_max_extra_depth = highland_max_extra_depth
	result.active_groundwater_half_depth = active_groundwater_half_depth
	result.light_aquifer_threshold = light_aquifer_threshold
	result.heavy_aquifer_threshold = heavy_aquifer_threshold
	result.marine_influence_radius = marine_influence_radius
	result.brackish_salinity_threshold = brackish_salinity_threshold
	result.saline_salinity_threshold = saline_salinity_threshold
	return result
