class_name ResourcePotentialLayer
extends RefCounted

## World-scale environmental suitability / geological prospectivity in [0, 1].
## Potential is not a realized Deposit, reserve quantity, or production rate.
var agriculture_potential := PackedFloat32Array()
var timber_potential := PackedFloat32Array()
var forage_potential := PackedFloat32Array()
var construction_stone_potential := PackedFloat32Array()
var base_metal_potential := PackedFloat32Array()
var precious_mineral_potential := PackedFloat32Array()
var freshwater_aquatic_potential := PackedFloat32Array()
var coastal_aquatic_potential := PackedFloat32Array()


func cell_count() -> int:
	return agriculture_potential.size()
