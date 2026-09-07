class_name ArcaneHazardPotentialLayer
extends RefCounted

## World-scale environmental hazard potential, not an event or realized damage.
var arcane_hazard_activity_potential := PackedFloat32Array()
var arcane_hazard_severity_potential := PackedFloat32Array()
var arcane_hazard_propagation_potential := PackedFloat32Array()


func cell_count() -> int:
	return arcane_hazard_activity_potential.size()
