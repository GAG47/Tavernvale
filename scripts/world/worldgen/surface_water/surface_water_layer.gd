class_name SurfaceWaterLayer
extends RefCounted

## Formal v1.8 outputs. Ocean is intentionally excluded from both arrays.
var lake_id := PackedInt32Array()
var surface_water_depth := PackedFloat32Array()
var lakes: Array = [] # SurfaceWaterLake entries.

## Debug generation counters; these are not required in a persisted world snapshot.
var rejected_small_lake_count: int = 0
var zero_capacity_basin_count: int = 0
var no_lake_basin_count: int = 0


func cell_count() -> int:
	return lake_id.size()
