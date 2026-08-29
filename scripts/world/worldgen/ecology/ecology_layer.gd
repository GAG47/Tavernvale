class_name EcologyLayer
extends RefCounted

## Formal v1.9 Ecology / Surface Environment outputs.
var drainage_index := PackedFloat32Array()
var ecological_moisture := PackedFloat32Array()
var vegetation_potential := PackedFloat32Array()
var biome_id := PackedInt32Array()


func cell_count() -> int:
	return drainage_index.size()
