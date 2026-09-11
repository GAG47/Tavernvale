class_name TectonicPlateLayer
extends RefCounted

var plate_id := PackedInt32Array()
var plate_velocity := PackedVector2Array()


func cell_count() -> int:
	return plate_id.size()


func plate_count() -> int:
	return plate_velocity.size()


func get_plate_id(cell_id: int) -> int:
	return plate_id[cell_id] if cell_id >= 0 and cell_id < cell_count() else -1


func get_plate_velocity(id: int) -> Vector2:
	return plate_velocity[id] if id >= 0 and id < plate_count() else Vector2.ZERO
