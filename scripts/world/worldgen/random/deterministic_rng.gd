class_name DeterministicRng
extends RefCounted

## A small, isolated 31-bit LCG. Its arithmetic and output mapping are explicit so
## spatial generation does not depend on Godot's global RNG or another world layer.

const _MODULUS := 2147483648
const _MASK := 0x7fffffff
const _MULTIPLIER := 1103515245
const _INCREMENT := 12345
const _SPATIAL_SALT := 0x53504154 # "SPAT"

var _state: int


func _init(seed_value: int) -> void:
	_state = seed_value & _MASK
	if _state == 0:
		_state = 1


static func spatial_seed(world_seed: int) -> int:
	var value := (world_seed & _MASK) ^ _SPATIAL_SALT
	# Stable integer avalanche; all intermediates remain within signed 64-bit range.
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & _MASK
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & _MASK
	value = (value ^ (value >> 16)) & _MASK
	return value if value != 0 else 1


func next_float() -> float:
	_state = (_state * _MULTIPLIER + _INCREMENT) & _MASK
	return float(_state) / float(_MODULUS)


func range_float(minimum: float, maximum: float) -> float:
	return lerpf(minimum, maximum, next_float())
