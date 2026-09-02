class_name ArcaneWebEdge
extends RefCounted

var id: int = -1
var node_a_id: int = -1
var node_b_id: int = -1
var length: float = 0.0
var structural_importance: float = 0.0


func _init(
		id_value: int = -1,
		node_a_value: int = -1,
		node_b_value: int = -1,
		length_value: float = 0.0
) -> void:
	id = id_value
	node_a_id = mini(node_a_value, node_b_value)
	node_b_id = maxi(node_a_value, node_b_value)
	length = length_value
