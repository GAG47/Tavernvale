class_name HydrologyConditioningResult
extends RefCounted

enum Action {
	NONE,
	FILL,
	CARVE,
	CLOSED_BASIN,
}

## Formal v1.4 outputs.
var terrain_height := PackedFloat32Array()
var closed_basin_id := PackedInt32Array()

## Debug and validation data; callers do not need to persist these in a world snapshot.
var original_height := PackedFloat32Array()
var height_delta := PackedFloat32Array()
var conditioning_action := PackedByteArray()
var initial_sink_count: int = 0
var filled_depression_count: int = 0
var breached_depression_count: int = 0
var closed_basin_count: int = 0
var modified_cell_ratio: float = 0.0
var max_raise: float = 0.0
var max_cut: float = 0.0


func cell_count() -> int:
	return terrain_height.size()


func action_name(cell_id: int) -> String:
	match conditioning_action[cell_id]:
		Action.FILL:
			return "Fill"
		Action.CARVE:
			return "Carve"
		Action.CLOSED_BASIN:
			return "Closed Basin"
		_:
			return "None"
