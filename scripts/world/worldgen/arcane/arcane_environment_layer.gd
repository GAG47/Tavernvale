class_name ArcaneEnvironmentLayer
extends RefCounted

## Public standardized Arcane state after steady transport, drift, and restoration.
## All three formal arrays are strictly aligned with SpatialGraph Cell IDs.
## mana_concentration maps the internal raw solution onto [0, 1]; raw overload remains
## internal diagnostics and is used to synthesize long-term Mana Stability.
var mana_concentration := PackedFloat32Array()
var mana_flowability := PackedFloat32Array()
var mana_stability := PackedFloat32Array()


func cell_count() -> int:
	return mana_concentration.size()
