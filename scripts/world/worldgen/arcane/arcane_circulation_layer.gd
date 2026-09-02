class_name ArcaneCirculationLayer
extends RefCounted

## Long-term relative Arcane Current in the Arcane Medium, aligned one-to-one
## with ArcaneWebLayer.edges. Magnitude is relative circulation strength with no
## absolute mana unit; positive flow follows canonical node_a_id -> node_b_id.
var edge_flow := PackedFloat32Array()


func edge_count() -> int:
	return edge_flow.size()


func flow_for_edge_index(index: int) -> float:
	return edge_flow[index] if index >= 0 and index < edge_flow.size() else 0.0
