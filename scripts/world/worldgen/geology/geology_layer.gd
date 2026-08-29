class_name GeologyLayer
extends RefCounted

## Formal v1.7 Geology / Subsurface Foundation data.
var province_id := PackedInt32Array()
var material_id := PackedInt32Array()
var permeability := PackedFloat32Array()
var erodibility := PackedFloat32Array()


func cell_count() -> int:
	return province_id.size()
