class_name TerrainHeightProjector
extends RefCounted

const RAW_SEA_LEVEL := 20.0
const MIN_TERRAIN_HEIGHT := -100.0
const MAX_TERRAIN_HEIGHT := 100.0


static func project(raw_composition: PackedInt32Array) -> TerrainHeightLayer:
	var layer := TerrainHeightLayer.new()
	layer.terrain_height.resize(raw_composition.size())
	for cell_id in raw_composition.size():
		layer.terrain_height[cell_id] = project_value(float(raw_composition[cell_id]))
	return layer


static func project_value(raw: float) -> float:
	var result := (raw - RAW_SEA_LEVEL) * 5.0 if raw < RAW_SEA_LEVEL \
		else (raw - RAW_SEA_LEVEL) * 1.25
	return clampf(result, MIN_TERRAIN_HEIGHT, MAX_TERRAIN_HEIGHT)
