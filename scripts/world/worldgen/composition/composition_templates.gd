class_name CompositionTemplates
extends RefCounted

const CONTINENTS := &"continents"
const PANGEA := &"pangea"
const ARCHIPELAGO := &"archipelago"
const MEDITERRANEAN := &"mediterranean"
const OLD_WORLD := &"old_world"
const SHATTERED := &"shattered"

const _CONTINENTS_OPERATIONS: Array[Dictionary] = [
	{"type": &"Hill", "count": "1", "strength": "80-85", "range_x": "60-80", "range_y": "40-60"},
	{"type": &"Hill", "count": "1", "strength": "80-85", "range_x": "20-30", "range_y": "40-60"},
	{"type": &"Hill", "count": "6-7", "strength": "15-30", "range_x": "25-75", "range_y": "15-85"},
	{"type": &"Multiply", "factor": 0.6, "target": &"land"},
	{"type": &"Hill", "count": "8-10", "strength": "5-10", "range_x": "15-85", "range_y": "20-80"},
	{"type": &"Range", "count": "1-2", "strength": "30-60", "range_x": "5-15", "range_y": "25-75"},
	{"type": &"Range", "count": "1-2", "strength": "30-60", "range_x": "80-95", "range_y": "25-75"},
	{"type": &"Range", "count": "0-3", "strength": "30-60", "range_x": "80-90", "range_y": "20-80"},
	{"type": &"Strait", "width": "2", "direction": &"vertical"},
	{"type": &"Strait", "width": "1", "direction": &"vertical"},
	{"type": &"Smooth", "factor": 3},
	{"type": &"Trough", "count": "3-4", "strength": "15-20", "range_x": "15-85", "range_y": "20-80"},
	{"type": &"Trough", "count": "3-4", "strength": "5-10", "range_x": "45-55", "range_y": "45-55"},
	{"type": &"Pit", "count": "3-4", "strength": "10-20", "range_x": "15-85", "range_y": "20-80"},
	{"type": &"Mask", "power": 4.0},
]

const _PANGEA_OPERATIONS: Array[Dictionary] = [
	{"type": &"Hill", "count": "1-2", "strength": "25-40", "range_x": "15-50", "range_y": "0-10"},
	{"type": &"Hill", "count": "1-2", "strength": "5-40", "range_x": "50-85", "range_y": "0-10"},
	{"type": &"Hill", "count": "1-2", "strength": "25-40", "range_x": "50-85", "range_y": "90-100"},
	{"type": &"Hill", "count": "1-2", "strength": "5-40", "range_x": "15-50", "range_y": "90-100"},
	{"type": &"Hill", "count": "8-12", "strength": "20-40", "range_x": "20-80", "range_y": "48-52"},
	{"type": &"Smooth", "factor": 2},
	{"type": &"Multiply", "factor": 0.7, "target": &"land"},
	{"type": &"Trough", "count": "3-4", "strength": "25-35", "range_x": "5-95", "range_y": "10-20"},
	{"type": &"Trough", "count": "3-4", "strength": "25-35", "range_x": "5-95", "range_y": "80-90"},
	{"type": &"Range", "count": "5-6", "strength": "30-40", "range_x": "10-90", "range_y": "35-65"},
]

const _ARCHIPELAGO_OPERATIONS: Array[Dictionary] = [
	{"type": &"Add", "value": 11, "target": &"all"},
	{"type": &"Range", "count": "2-3", "strength": "40-60", "range_x": "20-80", "range_y": "20-80"},
	{"type": &"Hill", "count": "5", "strength": "15-20", "range_x": "10-90", "range_y": "30-70"},
	{"type": &"Hill", "count": "2", "strength": "10-15", "range_x": "10-30", "range_y": "20-80"},
	{"type": &"Hill", "count": "2", "strength": "10-15", "range_x": "60-90", "range_y": "20-80"},
	{"type": &"Smooth", "factor": 3},
	{"type": &"Trough", "count": "10", "strength": "20-30", "range_x": "5-95", "range_y": "5-95"},
	{"type": &"Strait", "width": "2", "direction": &"vertical"},
	{"type": &"Strait", "width": "2", "direction": &"horizontal"},
]

const _MEDITERRANEAN_OPERATIONS: Array[Dictionary] = [
	{"type": &"Range", "count": "4-6", "strength": "30-80", "range_x": "0-100", "range_y": "0-10"},
	{"type": &"Range", "count": "4-6", "strength": "30-80", "range_x": "0-100", "range_y": "90-100"},
	{"type": &"Hill", "count": "6-8", "strength": "30-50", "range_x": "10-90", "range_y": "0-5"},
	{"type": &"Hill", "count": "6-8", "strength": "30-50", "range_x": "10-90", "range_y": "95-100"},
	{"type": &"Multiply", "factor": 0.9, "target": &"land"},
	{"type": &"Mask", "power": -2.0},
	{"type": &"Smooth", "factor": 1},
	{"type": &"Hill", "count": "2-3", "strength": "30-70", "range_x": "0-5", "range_y": "20-80"},
	{"type": &"Hill", "count": "2-3", "strength": "30-70", "range_x": "95-100", "range_y": "20-80"},
	{"type": &"Trough", "count": "3-6", "strength": "40-50", "range_x": "0-100", "range_y": "0-10"},
	{"type": &"Trough", "count": "3-6", "strength": "40-50", "range_x": "0-100", "range_y": "90-100"},
]

const _OLD_WORLD_OPERATIONS: Array[Dictionary] = [
	{"type": &"Range", "count": "3", "strength": "70", "range_x": "15-85", "range_y": "20-80"},
	{"type": &"Hill", "count": "2-3", "strength": "50-70", "range_x": "15-45", "range_y": "20-80"},
	{"type": &"Hill", "count": "2-3", "strength": "50-70", "range_x": "65-85", "range_y": "20-80"},
	{"type": &"Hill", "count": "4-6", "strength": "20-25", "range_x": "15-85", "range_y": "20-80"},
	{"type": &"Multiply", "factor": 0.5, "target": &"land"},
	{"type": &"Smooth", "factor": 2},
	{"type": &"Range", "count": "3-4", "strength": "20-50", "range_x": "15-35", "range_y": "20-45"},
	{"type": &"Range", "count": "2-4", "strength": "20-50", "range_x": "65-85", "range_y": "45-80"},
	{"type": &"Strait", "width": "3-7", "direction": &"vertical"},
	{"type": &"Trough", "count": "6-8", "strength": "20-50", "range_x": "15-85", "range_y": "45-65"},
	{"type": &"Pit", "count": "5-6", "strength": "20-30", "range_x": "10-90", "range_y": "10-90"},
]

const _SHATTERED_OPERATIONS: Array[Dictionary] = [
	{"type": &"Hill", "count": "8", "strength": "35-40", "range_x": "15-85", "range_y": "30-70"},
	{"type": &"Trough", "count": "10-20", "strength": "40-50", "range_x": "5-95", "range_y": "5-95"},
	{"type": &"Range", "count": "5-7", "strength": "30-40", "range_x": "10-90", "range_y": "20-80"},
	{"type": &"Pit", "count": "12-20", "strength": "30-40", "range_x": "15-85", "range_y": "20-80"},
]


static func template_ids() -> PackedStringArray:
	return PackedStringArray([
		String(CONTINENTS),
		String(PANGEA),
		String(ARCHIPELAGO),
		String(MEDITERRANEAN),
		String(OLD_WORLD),
		String(SHATTERED),
	])


static func has_template(template_id: StringName) -> bool:
	return template_ids().has(String(template_id))


static func display_name(template_id: StringName) -> String:
	match template_id:
		CONTINENTS:
			return "Continents"
		PANGEA:
			return "Pangea"
		ARCHIPELAGO:
			return "Archipelago"
		MEDITERRANEAN:
			return "Mediterranean"
		OLD_WORLD:
			return "Old World"
		SHATTERED:
			return "Shattered"
		_:
			return String(template_id)


static func operations_for(template_id: StringName) -> Array[Dictionary]:
	match template_id:
		CONTINENTS:
			return _duplicate_operations(_CONTINENTS_OPERATIONS)
		PANGEA:
			return _duplicate_operations(_PANGEA_OPERATIONS)
		ARCHIPELAGO:
			return _duplicate_operations(_ARCHIPELAGO_OPERATIONS)
		MEDITERRANEAN:
			return _duplicate_operations(_MEDITERRANEAN_OPERATIONS)
		OLD_WORLD:
			return _duplicate_operations(_OLD_WORLD_OPERATIONS)
		SHATTERED:
			return _duplicate_operations(_SHATTERED_OPERATIONS)
		_:
			return []


static func _duplicate_operations(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for operation in source:
		result.append(operation.duplicate(true))
	return result
