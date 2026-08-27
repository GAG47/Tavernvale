class_name CompositionTemplates
extends RefCounted

const CONTINENTS := &"continents"
const PANGEA := &"pangea"

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


static func template_ids() -> PackedStringArray:
	return PackedStringArray([String(CONTINENTS), String(PANGEA)])


static func has_template(template_id: StringName) -> bool:
	return template_id == CONTINENTS or template_id == PANGEA


static func operations_for(template_id: StringName) -> Array[Dictionary]:
	match template_id:
		CONTINENTS:
			return _duplicate_operations(_CONTINENTS_OPERATIONS)
		PANGEA:
			return _duplicate_operations(_PANGEA_OPERATIONS)
		_:
			return []


static func _duplicate_operations(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for operation in source:
		result.append(operation.duplicate(true))
	return result
