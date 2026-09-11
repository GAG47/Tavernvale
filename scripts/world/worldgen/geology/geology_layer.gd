class_name GeologyLayer
extends RefCounted

## Formal surface Geology facts. RockType is the single source of lithology identity.
var province_id := PackedInt32Array()
var rock_type_id := PackedInt32Array()
var permeability := PackedFloat32Array()
var erodibility := PackedFloat32Array()


func cell_count() -> int:
	return province_id.size()
