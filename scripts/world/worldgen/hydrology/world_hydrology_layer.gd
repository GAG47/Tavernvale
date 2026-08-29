class_name WorldHydrologyLayer
extends RefCounted

const FLOW_TO_WATER := -1
const FLOW_TO_BOUNDARY := -2
const FLOW_TO_CLOSED_BASIN := -3

var settings: WorldHydrologySettings
var local_runoff := PackedFloat32Array()
var flow_to := PackedInt32Array()
var flow_accumulation := PackedFloat32Array()
var watershed_id := PackedInt32Array()
var river_network_id := PackedInt32Array()
var river_order := PackedInt32Array()
var river_networks: Array = [] # HydrologyRiverNetwork entries.
var closed_basin_inflows: Array = [] # ClosedBasinInflow entries.
var watershed_count: int = 0


func cell_count() -> int:
	return local_runoff.size()


func is_river(cell_id: int) -> bool:
	return river_network_id[cell_id] >= 0
