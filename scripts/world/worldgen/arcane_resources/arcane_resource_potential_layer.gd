class_name ArcaneResourcePotentialLayer
extends RefCounted

## World-scale potential only: not a realized Deposit, reserve, or production rate.
var arcane_energy_potential := PackedFloat32Array()
var arcane_material_potential := PackedFloat32Array()
var arcane_bioresource_potential := PackedFloat32Array()
var rare_arcane_resource_potential := PackedFloat32Array()


func cell_count() -> int:
	return arcane_energy_potential.size()
