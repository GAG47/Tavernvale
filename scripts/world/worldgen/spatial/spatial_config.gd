class_name SpatialConfig
extends RefCounted

var seed: int = 1
var world_width: float = 1000.0
var world_height: float = 1000.0
var target_cell_count: int = 10000
var jitter: float = 0.9


func _init(
		seed_value: int = 1,
		width: float = 1000.0,
		height: float = 1000.0,
		cell_count: int = 10000,
		jitter_amount: float = 0.9
) -> void:
	seed = seed_value
	world_width = width
	world_height = height
	target_cell_count = cell_count
	jitter = jitter_amount


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if world_width <= 0.0:
		errors.append("world_width must be greater than zero")
	if world_height <= 0.0:
		errors.append("world_height must be greater than zero")
	if target_cell_count <= 0:
		errors.append("target_cell_count must be greater than zero")
	if jitter < 0.0 or jitter > 1.0:
		errors.append("jitter must be in the inclusive range [0, 1]")
	return errors


func to_dict() -> Dictionary:
	return {
		"seed": seed,
		"world_width": world_width,
		"world_height": world_height,
		"target_cell_count": target_cell_count,
		"jitter": jitter,
	}


static func from_dict(data: Dictionary) -> SpatialConfig:
	return SpatialConfig.new(
		int(data.get("seed", 1)),
		float(data.get("world_width", 1000.0)),
		float(data.get("world_height", 1000.0)),
		int(data.get("target_cell_count", 10000)),
		float(data.get("jitter", 0.9))
	)


func duplicate_config() -> SpatialConfig:
	return SpatialConfig.from_dict(to_dict())
