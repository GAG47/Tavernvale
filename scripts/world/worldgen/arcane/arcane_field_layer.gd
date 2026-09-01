class_name ArcaneFieldLayer
extends RefCounted

## Natural arcane background fields before ley networks or other magical influences.
var background_mana := PackedFloat32Array()
var background_stability := PackedFloat32Array()


func cell_count() -> int:
	return background_mana.size()
