class_name CompositionRng
extends RefCounted

## Isolated deterministic RNG for World Composition. It never reads or writes
## Godot's global random state and uses a salt distinct from Spatial generation.

const _MODULUS := 2147483648
const _MASK := 0x7fffffff
const _MULTIPLIER := 1103515245
const _INCREMENT := 12345
const _COMPOSITION_SALT := 0x434f4d50 # "COMP"

var _state: int


func _init(seed_value: int) -> void:
	_state = seed_value & _MASK
	if _state == 0:
		_state = 1


static func composition_seed(config: WorldCompositionConfig) -> int:
	var value := (config.seed & _MASK) ^ _COMPOSITION_SALT
	for character in String(config.template_id).to_utf8_buffer():
		value = ((value ^ int(character)) * 16777619) & _MASK
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & _MASK
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & _MASK
	value = (value ^ (value >> 16)) & _MASK
	return value if value != 0 else 1


func next_float() -> float:
	_state = (_state * _MULTIPLIER + _INCREMENT) & _MASK
	return float(_state) / float(_MODULUS)


func range_float(minimum: float, maximum: float) -> float:
	return minimum + (maximum - minimum) * next_float()


func range_int(minimum: int, maximum: int) -> int:
	if maximum <= minimum:
		return minimum
	return floori(next_float() * float(maximum - minimum + 1)) + minimum


func chance(probability: float) -> bool:
	if probability >= 1.0:
		return true
	if probability <= 0.0:
		return false
	return next_float() < probability
