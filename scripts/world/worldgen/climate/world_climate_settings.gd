class_name WorldClimateSettings
extends RefCounted

var latitude_north: float = 70.0
var latitude_south: float = -20.0
var equator_temperature: float = 27.0
var north_pole_temperature: float = -30.0
var south_pole_temperature: float = -15.0
var precipitation_modifier: float = 1.0
var wind_bands := PackedFloat32Array([225.0, 45.0, 225.0, 315.0, 135.0, 315.0])
var height_exponent: float = 2.0


func _init(
		north: float = 70.0,
		south: float = -20.0,
		equator_temp: float = 27.0,
		north_pole_temp: float = -30.0,
		south_pole_temp: float = -15.0,
		precipitation_scale: float = 1.0,
		winds: PackedFloat32Array = PackedFloat32Array(
			[225.0, 45.0, 225.0, 315.0, 135.0, 315.0]
		),
		altitude_exponent: float = 2.0
) -> void:
	latitude_north = north
	latitude_south = south
	equator_temperature = equator_temp
	north_pole_temperature = north_pole_temp
	south_pole_temperature = south_pole_temp
	precipitation_modifier = precipitation_scale
	wind_bands = winds.duplicate()
	height_exponent = altitude_exponent


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(latitude_north) or latitude_north < -90.0 or latitude_north > 90.0:
		errors.append("latitude_north must be finite and inside [-90, 90]")
	if not is_finite(latitude_south) or latitude_south < -90.0 or latitude_south > 90.0:
		errors.append("latitude_south must be finite and inside [-90, 90]")
	if latitude_north <= latitude_south:
		errors.append("latitude_north must be greater than latitude_south")
	if not is_finite(equator_temperature):
		errors.append("equator_temperature must be finite")
	if not is_finite(north_pole_temperature):
		errors.append("north_pole_temperature must be finite")
	if not is_finite(south_pole_temperature):
		errors.append("south_pole_temperature must be finite")
	if not is_finite(precipitation_modifier) or precipitation_modifier < 0.0:
		errors.append("precipitation_modifier must be finite and non-negative")
	if wind_bands.size() != 6:
		errors.append("wind_bands must contain six 30-degree latitude tiers")
	else:
		for angle in wind_bands:
			if not is_finite(angle):
				errors.append("wind_bands must contain only finite angles")
				break
	if not is_finite(height_exponent) or height_exponent <= 0.0:
		errors.append("height_exponent must be finite and greater than zero")
	return errors


func duplicate_settings() -> WorldClimateSettings:
	return WorldClimateSettings.new(
		latitude_north,
		latitude_south,
		equator_temperature,
		north_pole_temperature,
		south_pole_temperature,
		precipitation_modifier,
		wind_bands,
		height_exponent
	)
