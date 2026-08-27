class_name WorldCompositionLayer
extends RefCounted

## v1.1 macro-composition output. continental_value is an integer tendency
## field, not physical elevation and not formal land/ocean classification.

var config: WorldCompositionConfig
var seed: int = 0
var composition_seed: int = 0
var template_id: StringName
var continental_value := PackedInt32Array()
var operation_metadata: Array[Dictionary] = []


func cell_count() -> int:
	return continental_value.size()
