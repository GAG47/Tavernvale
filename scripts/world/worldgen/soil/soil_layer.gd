class_name SoilLayer
extends RefCounted

## Formal v1.10 Soil Foundation outputs. Soil depth uses a fixed relative [0, 1] scale.
var soil_depth := PackedFloat32Array()
var soil_texture_id := PackedInt32Array()
var organic_matter := PackedFloat32Array()
var soil_fertility := PackedFloat32Array()


func cell_count() -> int:
	return soil_depth.size()
