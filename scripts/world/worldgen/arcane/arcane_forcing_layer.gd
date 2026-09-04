class_name ArcaneForcingLayer
extends RefCounted

## Sparse world-space exchange defects plus their Cell-aligned projected rates.
var sites: Array[ArcaneForcingSite] = []
var source_rate := PackedFloat32Array()
var sink_rate := PackedFloat32Array()


func cell_count() -> int:
	return source_rate.size()
