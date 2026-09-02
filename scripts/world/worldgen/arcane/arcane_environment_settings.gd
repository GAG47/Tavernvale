class_name ArcaneEnvironmentSettings
extends RefCounted

var leyline_influence_radius: float = 55.0
var ambient_flowability: float = 0.15
var diffusion_rate: float = 1.0
# Seed 1 at 0.60 converged cleanly but never reached a +/-0.05 visible
# enrichment/depletion. The single v2.3 calibration raises only the physical
# Drift strength; all transport, restoration, and stability equations stay fixed.
var arcane_drift_speed: float = 0.75
var background_restoration_min_rate: float = 0.03
var background_restoration_max_rate: float = 0.15
var solver_cfl_safety: float = 0.40
var solver_max_dt: float = 1.0
var solver_max_iterations: int = 400
var solver_convergence_epsilon: float = 0.00001
var stability_min_resistance: float = 0.15
var stability_stress_response: float = 2.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(leyline_influence_radius) or leyline_influence_radius <= 0.0:
		errors.append("leyline_influence_radius must be finite and positive")
	if not is_finite(ambient_flowability) \
			or ambient_flowability < 0.0 or ambient_flowability > 1.0:
		errors.append("ambient_flowability must be finite and inside [0, 1]")
	if not is_finite(diffusion_rate) or diffusion_rate < 0.0:
		errors.append("diffusion_rate must be finite and non-negative")
	if not is_finite(arcane_drift_speed) or arcane_drift_speed < 0.0:
		errors.append("arcane_drift_speed must be finite and non-negative")
	if not is_finite(background_restoration_min_rate) \
			or background_restoration_min_rate < 0.0:
		errors.append("background_restoration_min_rate must be finite and non-negative")
	if not is_finite(background_restoration_max_rate) \
			or background_restoration_max_rate < background_restoration_min_rate:
		errors.append(
			"background_restoration_max_rate must be finite and at least the minimum rate"
		)
	if not is_finite(solver_cfl_safety) \
			or solver_cfl_safety <= 0.0 or solver_cfl_safety > 1.0:
		errors.append("solver_cfl_safety must be finite and inside (0, 1]")
	if not is_finite(solver_max_dt) or solver_max_dt <= 0.0:
		errors.append("solver_max_dt must be finite and positive")
	if solver_max_iterations <= 0:
		errors.append("solver_max_iterations must be positive")
	if not is_finite(solver_convergence_epsilon) \
			or solver_convergence_epsilon <= 0.0:
		errors.append("solver_convergence_epsilon must be finite and positive")
	if not is_finite(stability_min_resistance) \
			or stability_min_resistance <= 0.0 or stability_min_resistance > 1.0:
		errors.append("stability_min_resistance must be finite and inside (0, 1]")
	if not is_finite(stability_stress_response) or stability_stress_response < 0.0:
		errors.append("stability_stress_response must be finite and non-negative")
	return errors


func duplicate_settings() -> ArcaneEnvironmentSettings:
	var result := ArcaneEnvironmentSettings.new()
	result.leyline_influence_radius = leyline_influence_radius
	result.ambient_flowability = ambient_flowability
	result.diffusion_rate = diffusion_rate
	result.arcane_drift_speed = arcane_drift_speed
	result.background_restoration_min_rate = background_restoration_min_rate
	result.background_restoration_max_rate = background_restoration_max_rate
	result.solver_cfl_safety = solver_cfl_safety
	result.solver_max_dt = solver_max_dt
	result.solver_max_iterations = solver_max_iterations
	result.solver_convergence_epsilon = solver_convergence_epsilon
	result.stability_min_resistance = stability_min_resistance
	result.stability_stress_response = stability_stress_response
	return result
