class_name HydrologyFlowResult
extends RefCounted

const FLOW_TO_SINK := -4

## Intermediate basic Flow data. It is not a Natural World snapshot layer.
var local_runoff := PackedFloat32Array()
var flow_to := PackedInt32Array()
var flow_accumulation := PackedFloat32Array()


func cell_count() -> int:
	return local_runoff.size()
