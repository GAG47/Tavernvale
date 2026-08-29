class_name WorldClimateLayer
extends RefCounted

## Preliminary or final climate output, depending on the terrain_height input supplied.

var settings: WorldClimateSettings
var temperature := PackedFloat32Array() # Mean annual temperature in degrees Celsius.
var precipitation := PackedFloat32Array() # Non-negative relative precipitation.


func cell_count() -> int:
	return temperature.size()
