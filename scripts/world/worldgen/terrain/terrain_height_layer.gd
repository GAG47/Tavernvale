class_name TerrainHeightLayer
extends RefCounted

## v1.2 formal normalized surface height. Values are normalized units, not meters.

var terrain_height := PackedFloat32Array()


func cell_count() -> int:
	return terrain_height.size()


func is_land(cell_id: int) -> bool:
	return terrain_height[cell_id] >= 0.0
