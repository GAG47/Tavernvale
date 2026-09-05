class_name ArcaneEcologySettings
extends RefCounted

var woodland_response_floor: float = 0.45
var open_vegetation_response_floor: float = 0.60
var wetland_response_floor: float = 0.55
var barren_extreme_response: float = 0.75
var aquatic_response: float = 0.75
var profile_affinities: Array[PackedFloat64Array] = [
	PackedFloat64Array([1.00, 0.75, 0.45]),
	PackedFloat64Array([0.70, 1.00, 0.75]),
	PackedFloat64Array([0.75, 1.00, 0.85]),
	PackedFloat64Array([0.65, 0.70, 1.00]),
	PackedFloat64Array([0.70, 1.00, 0.70]),
]
# Each row is zero_low, full_low, full_high, zero_high, in Profile enum order.
var stability_anchors: Array[PackedFloat64Array] = [
	PackedFloat64Array([0.35, 0.70, 1.00, 1.00]),
	PackedFloat64Array([0.20, 0.50, 1.00, 1.00]),
	PackedFloat64Array([0.00, 0.15, 0.50, 0.85]),
]
var flowability_anchors: Array[PackedFloat64Array] = [
	PackedFloat64Array([0.00, 0.10, 0.45, 0.80]),
	PackedFloat64Array([0.30, 0.65, 1.00, 1.00]),
	PackedFloat64Array([0.25, 0.55, 1.00, 1.00]),
]
var mana_concentration_medium_threshold: float = 0.40
var mana_concentration_high_threshold: float = 0.70
var arcane_ecology_potential_medium_threshold: float = 0.40
var arcane_ecology_potential_high_threshold: float = 0.70

const _SCALAR_PARAMETERS := [
	"woodland_response_floor", "open_vegetation_response_floor", "wetland_response_floor",
	"barren_extreme_response", "aquatic_response", "mana_concentration_medium_threshold",
	"mana_concentration_high_threshold", "arcane_ecology_potential_medium_threshold",
	"arcane_ecology_potential_high_threshold",
]


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for parameter in _SCALAR_PARAMETERS:
		if not _unit_value(get(parameter)):
			errors.append("%s must be finite and inside [0, 1]" % parameter)
	if mana_concentration_medium_threshold >= mana_concentration_high_threshold:
		errors.append("mana_concentration medium threshold must be below high threshold")
	if arcane_ecology_potential_medium_threshold >= arcane_ecology_potential_high_threshold:
		errors.append("arcane_ecology_potential medium threshold must be below high threshold")
	_validate_table(profile_affinities, ArcaneEcologyCatalog.GROUP_COUNT,
		ArcaneEcologyCatalog.PROFILE_COUNT, "profile_affinities", false, errors)
	_validate_table(stability_anchors, ArcaneEcologyCatalog.PROFILE_COUNT,
		4, "stability_anchors", true, errors)
	_validate_table(flowability_anchors, ArcaneEcologyCatalog.PROFILE_COUNT,
		4, "flowability_anchors", true, errors)
	return errors


func duplicate_settings() -> ArcaneEcologySettings:
	var result := ArcaneEcologySettings.new()
	for parameter in _SCALAR_PARAMETERS:
		result.set(parameter, get(parameter))
	result.profile_affinities = profile_affinities.duplicate(true)
	result.stability_anchors = stability_anchors.duplicate(true)
	result.flowability_anchors = flowability_anchors.duplicate(true)
	return result


static func _unit_value(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0


static func _validate_table(
		table: Array[PackedFloat64Array], rows: int, columns: int,
		label: String, ordered: bool, errors: PackedStringArray
) -> void:
	if table.size() != rows:
		errors.append("%s must have %d rows" % [label, rows])
	for row_id in table.size():
		var row := table[row_id]
		if row.size() != columns:
			errors.append("%s row %d must have %d entries" % [label, row_id, columns])
		for column in row.size():
			if not _unit_value(row[column]):
				errors.append("%s[%d][%d] must be finite and inside [0, 1]" % [label, row_id, column])
			if ordered and column > 0 and row[column] < row[column - 1]:
				errors.append("%s row %d anchors must be non-decreasing" % [label, row_id])
