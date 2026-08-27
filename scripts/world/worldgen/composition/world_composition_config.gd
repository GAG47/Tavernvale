class_name WorldCompositionConfig
extends RefCounted

var seed: int = 1
var template_id: StringName = &"continents"


func _init(seed_value: int = 1, template: StringName = &"continents") -> void:
	seed = seed_value
	template_id = template


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not CompositionTemplates.has_template(template_id):
		errors.append("template_id must be one of: " + ", ".join(CompositionTemplates.template_ids()))
	return errors


func to_dict() -> Dictionary:
	return {
		"seed": seed,
		"template_id": String(template_id),
	}


static func from_dict(data: Dictionary) -> WorldCompositionConfig:
	return WorldCompositionConfig.new(
		int(data.get("seed", 1)),
		StringName(data.get("template_id", "continents"))
	)


func duplicate_config() -> WorldCompositionConfig:
	return WorldCompositionConfig.from_dict(to_dict())
