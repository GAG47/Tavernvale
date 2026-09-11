class_name RockLayerRules
extends RefCounted

const ROCK_SEQUENCE_SALT := 0x52534551 # "RSEQ"
const BASEMENT_SALT := 0x42415345 # "BASE"

enum LayerNode {
	BOTTOM,
	FELSIC,
	INTERMEDIATE,
	MAFIC,
	EXTRUSIVE,
	EXTRUSIVE_X2,
	INTRUSIVE,
	MM_HIGH_GRADE,
	MM_LOW_GRADE,
	MM_MARBLE,
	MM_QUARTZITE,
	SEDIMENTARY,
	UPLIFT,
}

const NODE_COUNT := 13


static func root_pool_for(province_id: int) -> PackedInt32Array:
	match province_id:
		GeologyCatalog.Province.OCEANIC_CRUST:
			return PackedInt32Array([LayerNode.EXTRUSIVE])
		GeologyCatalog.Province.CRATON:
			return PackedInt32Array([LayerNode.INTRUSIVE, LayerNode.MM_HIGH_GRADE])
		GeologyCatalog.Province.OROGENIC_BELT:
			return PackedInt32Array([
				LayerNode.UPLIFT, LayerNode.UPLIFT, LayerNode.UPLIFT, LayerNode.SEDIMENTARY,
			])
		GeologyCatalog.Province.SEDIMENTARY_BASIN, GeologyCatalog.Province.PASSIVE_MARGIN:
			return PackedInt32Array([LayerNode.SEDIMENTARY])
		GeologyCatalog.Province.VOLCANIC_PROVINCE:
			return PackedInt32Array([
				LayerNode.EXTRUSIVE, LayerNode.EXTRUSIVE_X2, LayerNode.INTRUSIVE,
			])
	return PackedInt32Array()


## Each Vector2i stores (RockType, next LayerNode).
static func choices_for(node: int) -> Array[Vector2i]:
	match node:
		LayerNode.FELSIC:
			return [Vector2i(RockCatalog.RockType.GRANITE, LayerNode.BOTTOM)]
		LayerNode.INTERMEDIATE:
			return [Vector2i(RockCatalog.RockType.DIORITE, LayerNode.BOTTOM)]
		LayerNode.MAFIC:
			return [Vector2i(RockCatalog.RockType.GABBRO, LayerNode.BOTTOM)]
		LayerNode.EXTRUSIVE:
			return [
				Vector2i(RockCatalog.RockType.RHYOLITE, LayerNode.FELSIC),
				Vector2i(RockCatalog.RockType.ANDESITE, LayerNode.INTERMEDIATE),
				Vector2i(RockCatalog.RockType.DACITE, LayerNode.INTERMEDIATE),
				Vector2i(RockCatalog.RockType.BASALT, LayerNode.MAFIC),
			]
		LayerNode.EXTRUSIVE_X2:
			return [
				Vector2i(RockCatalog.RockType.RHYOLITE, LayerNode.EXTRUSIVE),
				Vector2i(RockCatalog.RockType.ANDESITE, LayerNode.EXTRUSIVE),
				Vector2i(RockCatalog.RockType.DACITE, LayerNode.EXTRUSIVE),
				Vector2i(RockCatalog.RockType.BASALT, LayerNode.EXTRUSIVE),
			]
		LayerNode.INTRUSIVE:
			return [
				Vector2i(RockCatalog.RockType.GRANITE, LayerNode.FELSIC),
				Vector2i(RockCatalog.RockType.DIORITE, LayerNode.INTERMEDIATE),
				Vector2i(RockCatalog.RockType.GABBRO, LayerNode.MAFIC),
			]
		LayerNode.MM_HIGH_GRADE:
			return [
				Vector2i(RockCatalog.RockType.SCHIST, LayerNode.BOTTOM),
				Vector2i(RockCatalog.RockType.GNEISS, LayerNode.BOTTOM),
			]
		LayerNode.MM_LOW_GRADE:
			return [
				Vector2i(RockCatalog.RockType.PHYLLITE, LayerNode.MM_HIGH_GRADE),
				Vector2i(RockCatalog.RockType.SLATE, LayerNode.MM_HIGH_GRADE),
			]
		LayerNode.MM_MARBLE:
			return [Vector2i(RockCatalog.RockType.MARBLE, LayerNode.BOTTOM)]
		LayerNode.MM_QUARTZITE:
			return [Vector2i(RockCatalog.RockType.QUARTZITE, LayerNode.BOTTOM)]
		LayerNode.SEDIMENTARY:
			return [
				Vector2i(RockCatalog.RockType.SHALE, LayerNode.MM_LOW_GRADE),
				Vector2i(RockCatalog.RockType.CLAYSTONE, LayerNode.MM_LOW_GRADE),
				Vector2i(RockCatalog.RockType.CONGLOMERATE, LayerNode.MM_LOW_GRADE),
				Vector2i(RockCatalog.RockType.LIMESTONE, LayerNode.MM_MARBLE),
				Vector2i(RockCatalog.RockType.DOLOMITE, LayerNode.MM_MARBLE),
				Vector2i(RockCatalog.RockType.CHALK, LayerNode.MM_MARBLE),
				Vector2i(RockCatalog.RockType.CHERT, LayerNode.MM_QUARTZITE),
				Vector2i(RockCatalog.RockType.SANDSTONE, LayerNode.MM_QUARTZITE),
			]
		LayerNode.UPLIFT:
			return [
				Vector2i(RockCatalog.RockType.SLATE, LayerNode.MM_HIGH_GRADE),
				Vector2i(RockCatalog.RockType.PHYLLITE, LayerNode.MM_HIGH_GRADE),
				Vector2i(RockCatalog.RockType.SCHIST, LayerNode.MM_HIGH_GRADE),
				Vector2i(RockCatalog.RockType.GNEISS, LayerNode.MM_HIGH_GRADE),
				Vector2i(RockCatalog.RockType.MARBLE, LayerNode.BOTTOM),
				Vector2i(RockCatalog.RockType.QUARTZITE, LayerNode.BOTTOM),
				Vector2i(RockCatalog.RockType.DIORITE, LayerNode.MM_LOW_GRADE),
				Vector2i(RockCatalog.RockType.GRANITE, LayerNode.MM_LOW_GRADE),
				Vector2i(RockCatalog.RockType.GABBRO, LayerNode.MM_LOW_GRADE),
			]
	return []


static func sequence_for(
		province_id: int, world_seed: int, rock_region_seed_cell_id: int
) -> PackedInt32Array:
	var roots := root_pool_for(province_id)
	if roots.is_empty():
		return PackedInt32Array()
	var sequence_seed := DeterministicRng.stable_mix(
		DeterministicRng.stable_mix(world_seed, ROCK_SEQUENCE_SALT),
		rock_region_seed_cell_id
	)
	var rng := DeterministicRng.new(sequence_seed)
	var node := roots[_choice_index(rng.next_float(), roots.size())]
	var sequence := PackedInt32Array()
	while node != LayerNode.BOTTOM:
		var choices := choices_for(node)
		if choices.is_empty():
			return PackedInt32Array()
		var choice := choices[_choice_index(rng.next_float(), choices.size())]
		sequence.append(choice.x)
		node = choice.y
	return sequence


static func surface_rock_for(
		province_id: int, world_seed: int, rock_region_seed_cell_id: int
) -> int:
	var sequence := sequence_for(province_id, world_seed, rock_region_seed_cell_id)
	return sequence[0] if not sequence.is_empty() else -1


static func continental_basement_pool() -> PackedInt32Array:
	return PackedInt32Array([
		RockCatalog.RockType.GNEISS,
		RockCatalog.RockType.SCHIST,
		RockCatalog.RockType.DIORITE,
		RockCatalog.RockType.GRANITE,
		RockCatalog.RockType.GABBRO,
	])


static func basement_for(
		is_deep_continental: bool, world_seed: int, rock_region_seed_cell_id: int
) -> int:
	if not is_deep_continental:
		return RockCatalog.RockType.GABBRO
	var pool := continental_basement_pool()
	var basement_seed := DeterministicRng.stable_mix(
		DeterministicRng.stable_mix(world_seed, ROCK_SEQUENCE_SALT),
		DeterministicRng.stable_mix(rock_region_seed_cell_id, BASEMENT_SALT)
	)
	var rng := DeterministicRng.new(basement_seed)
	return pool[_choice_index(rng.next_float(), pool.size())]


static func transition_is_defined(node: int, rock_type: int, next_node: int) -> bool:
	for choice in choices_for(node):
		if choice.x == rock_type and choice.y == next_node:
			return true
	return false


static func validate_rules() -> PackedStringArray:
	var errors := PackedStringArray()
	for province_id in GeologyCatalog.PROVINCE_COUNT:
		var roots := root_pool_for(province_id)
		if roots.is_empty():
			errors.append("Province %d must have at least one Rock root" % province_id)
		for root in roots:
			if root <= LayerNode.BOTTOM or root >= NODE_COUNT:
				errors.append("Province %d contains an invalid Rock root" % province_id)
	var state := PackedInt32Array()
	state.resize(NODE_COUNT)
	state[LayerNode.BOTTOM] = 2
	for node in range(1, NODE_COUNT):
		_validate_node(node, state, errors)
	for rock_type in continental_basement_pool():
		if not RockCatalog.is_valid_rock_type(rock_type):
			errors.append("Continental basement pool contains an invalid RockType")
	return errors


static func _validate_node(
		node: int, state: PackedInt32Array, errors: PackedStringArray
) -> bool:
	if state[node] == 2:
		return true
	if state[node] == 1:
		errors.append("Rock Layer rules contain a non-BOTTOM cycle at node %d" % node)
		return false
	state[node] = 1
	var choices := choices_for(node)
	if choices.is_empty():
		errors.append("Rock Layer node %d has no choices" % node)
		state[node] = 2
		return false
	var reaches_bottom := true
	for choice in choices:
		if not RockCatalog.is_valid_rock_type(choice.x):
			errors.append("Rock Layer node %d contains an invalid RockType" % node)
			reaches_bottom = false
		if choice.y < LayerNode.BOTTOM or choice.y >= NODE_COUNT:
			errors.append("Rock Layer node %d contains an invalid next node" % node)
			reaches_bottom = false
		elif choice.y != LayerNode.BOTTOM and not _validate_node(choice.y, state, errors):
			reaches_bottom = false
	state[node] = 2
	return reaches_bottom


static func _choice_index(selector: float, count: int) -> int:
	return mini(floori(clampf(selector, 0.0, 0.999999) * float(count)), count - 1)
