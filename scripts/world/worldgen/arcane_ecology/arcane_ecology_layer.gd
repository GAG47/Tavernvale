class_name ArcaneEcologyLayer
extends RefCounted

var arcane_ecology_potential := PackedFloat32Array()
var arcane_ecology_state := PackedInt32Array()
var arcane_response_profile_id := PackedInt32Array()


func cell_count() -> int:
	return arcane_ecology_potential.size()
