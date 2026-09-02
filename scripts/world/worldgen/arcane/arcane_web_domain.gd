class_name ArcaneWebDomain
extends RefCounted

## A weighted Power Diagram cell retained for Arcane Web geometry generation
## and world-space queries. It does not define an area with distinct magical
## properties.

var id: int = -1
var nucleus_position := Vector2.ZERO
var power_weight: float = 0.0
var polygon := PackedVector2Array()


func _init(
		id_value: int = -1,
		position_value: Vector2 = Vector2.ZERO,
		weight_value: float = 0.0,
		polygon_value: PackedVector2Array = PackedVector2Array()
) -> void:
	id = id_value
	nucleus_position = position_value
	power_weight = weight_value
	polygon = polygon_value
