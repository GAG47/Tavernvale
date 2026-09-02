class_name ArcaneWebNode
extends RefCounted

enum Kind {
	JUNCTION,
	BOUNDARY_EXIT,
}

var id: int = -1
var world_position := Vector2.ZERO
var kind: Kind = Kind.JUNCTION


func _init(
		id_value: int = -1,
		position_value: Vector2 = Vector2.ZERO,
		kind_value: Kind = Kind.JUNCTION
) -> void:
	id = id_value
	world_position = position_value
	kind = kind_value


func kind_name() -> String:
	return "Boundary Exit" if kind == Kind.BOUNDARY_EXIT else "Junction"
