class_name ArcaneEnvironmentLayer
extends RefCounted

## Current Arcane state after transport, drift, and background restoration.
## All three formal arrays are strictly aligned with SpatialGraph Cell IDs.
var mana_concentration := PackedFloat32Array()
var mana_flowability := PackedFloat32Array()
var mana_stability := PackedFloat32Array()


func cell_count() -> int:
	return mana_concentration.size()
