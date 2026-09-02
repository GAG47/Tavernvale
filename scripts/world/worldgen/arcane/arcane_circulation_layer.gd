class_name ArcaneCirculationLayer
extends RefCounted

## Long-term signed mana circulation aligned one-to-one with ArcaneWebLayer.edges.
## Positive flow follows the canonical node_a_id -> node_b_id direction.
var edge_flow := PackedFloat32Array()


func edge_count() -> int:
	return edge_flow.size()


func flow_for_edge_index(index: int) -> float:
	return edge_flow[index] if index >= 0 and index < edge_flow.size() else 0.0
