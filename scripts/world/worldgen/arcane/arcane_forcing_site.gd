class_name ArcaneForcingSite
extends RefCounted

enum Kind {
	SOURCE,
	SINK,
}

var id: int = -1
var world_position := Vector2.ZERO
var kind: Kind = Kind.SOURCE
var core_radius: float = 0.0
var total_power: float = 0.0


func _init(
		id_value: int = -1,
		position_value: Vector2 = Vector2.ZERO,
		kind_value: Kind = Kind.SOURCE,
		core_radius_value: float = 0.0,
		total_power_value: float = 0.0
) -> void:
	id = id_value
	world_position = position_value
	kind = kind_value
	core_radius = core_radius_value
	total_power = total_power_value


func kind_name() -> String:
	return "Source" if kind == Kind.SOURCE else "Sink"
