class_name TectonicPlateSettings
extends RefCounted

var plate_count: int = 5
var macro_radius: float = 80.0
var regional_radius: float = 200.0
var anchor_candidates_per_plate: int = 96
var anchor_min_spacing_factor: float = 0.45
var anchor_relax_attempts: int = 4
var partition_terrain_weight: float = 2.5
var velocity_min_initial_speed: float = 0.8
var velocity_max_initial_speed: float = 1.2
var velocity_relaxation_iterations: int = 6
var velocity_boundary_threshold: float = 0.35
var velocity_target_convergence: float = 0.50
var velocity_correction_factor: float = 0.25
var velocity_min_final_speed: float = 0.75
var velocity_max_final_speed: float = 1.25


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if plate_count <= 0:
		errors.append("plate_count must be positive")
	if not is_finite(macro_radius) or macro_radius <= 0.0:
		errors.append("macro_radius must be finite and positive")
	if not is_finite(regional_radius) or regional_radius <= 0.0:
		errors.append("regional_radius must be finite and positive")
	if anchor_candidates_per_plate <= 0:
		errors.append("anchor_candidates_per_plate must be positive")
	if not is_finite(anchor_min_spacing_factor) or anchor_min_spacing_factor <= 0.0:
		errors.append("anchor_min_spacing_factor must be finite and positive")
	if anchor_relax_attempts < 0:
		errors.append("anchor_relax_attempts must be non-negative")
	if not is_finite(partition_terrain_weight) or partition_terrain_weight < 0.0:
		errors.append("partition_terrain_weight must be finite and non-negative")
	if not _valid_speed_range(velocity_min_initial_speed, velocity_max_initial_speed):
		errors.append("initial velocity speeds must be finite, positive, and ordered")
	if velocity_relaxation_iterations < 0:
		errors.append("velocity_relaxation_iterations must be non-negative")
	if not is_finite(velocity_boundary_threshold) \
			or velocity_boundary_threshold < 0.0 \
			or velocity_boundary_threshold > 1.0:
		errors.append("velocity_boundary_threshold must be finite and inside [0, 1]")
	if not is_finite(velocity_target_convergence) or velocity_target_convergence < 0.0:
		errors.append("velocity_target_convergence must be finite and non-negative")
	if not is_finite(velocity_correction_factor) or velocity_correction_factor < 0.0:
		errors.append("velocity_correction_factor must be finite and non-negative")
	if not _valid_speed_range(velocity_min_final_speed, velocity_max_final_speed):
		errors.append("final velocity speeds must be finite, positive, and ordered")
	return errors


func duplicate_settings() -> TectonicPlateSettings:
	var result := TectonicPlateSettings.new()
	result.plate_count = plate_count
	result.macro_radius = macro_radius
	result.regional_radius = regional_radius
	result.anchor_candidates_per_plate = anchor_candidates_per_plate
	result.anchor_min_spacing_factor = anchor_min_spacing_factor
	result.anchor_relax_attempts = anchor_relax_attempts
	result.partition_terrain_weight = partition_terrain_weight
	result.velocity_min_initial_speed = velocity_min_initial_speed
	result.velocity_max_initial_speed = velocity_max_initial_speed
	result.velocity_relaxation_iterations = velocity_relaxation_iterations
	result.velocity_boundary_threshold = velocity_boundary_threshold
	result.velocity_target_convergence = velocity_target_convergence
	result.velocity_correction_factor = velocity_correction_factor
	result.velocity_min_final_speed = velocity_min_final_speed
	result.velocity_max_final_speed = velocity_max_final_speed
	return result


func _valid_speed_range(minimum: float, maximum: float) -> bool:
	return is_finite(minimum) and is_finite(maximum) and minimum > 0.0 and maximum >= minimum
