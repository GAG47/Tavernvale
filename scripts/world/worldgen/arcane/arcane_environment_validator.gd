class_name ArcaneEnvironmentValidator
extends RefCounted


static func validate(
		graph: SpatialGraph, environment: ArcaneEnvironmentLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or environment == null:
		errors.append(
			"Arcane Environment validation requires a SpatialGraph and ArcaneEnvironmentLayer"
		)
		return errors
	var count := graph.cell_count()
	var named_arrays := {
		"mana_concentration": environment.mana_concentration,
		"mana_flowability": environment.mana_flowability,
		"mana_stability": environment.mana_stability,
	}
	for field_name in named_arrays:
		var values: PackedFloat32Array = named_arrays[field_name]
		if values.size() != count:
			errors.append("%s must contain one value per Cell" % field_name)
			continue
		for cell_id in count:
			var value := values[cell_id]
			if not is_finite(value) or value < 0.0 or value > 1.0:
				errors.append(
					"%s[%d] must be finite and inside [0, 1]" % [field_name, cell_id]
				)
	return errors


static func validate_solver_report(report: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for field_name in [
		"converged", "breakdown", "finite", "iterations", "relative_residual",
		"absolute_residual", "l_inf_residual", "raw_min", "raw_max",
		"raw_negative_count", "raw_significantly_negative_count",
	]:
		if not report.has(field_name):
			errors.append("sparse steady-state Solver must report %s" % field_name)
	if not errors.is_empty():
		return errors
	if not bool(report.get("finite", false)):
		errors.append("sparse steady-state Solver produced a non-finite result")
	if bool(report.get("breakdown", false)):
		errors.append("sparse steady-state Solver reported breakdown: %s" % [
		str(report.get("breakdown_reason", "unspecified")),
	])
	if not bool(report.get("converged", false)):
		errors.append("sparse steady-state Solver did not converge")
	for field_name in [
		"relative_residual", "absolute_residual", "l_inf_residual", "raw_min", "raw_max",
	]:
		if not report.has(field_name) or not is_finite(float(report.get(field_name, NAN))):
			errors.append("sparse steady-state Solver report %s must be finite" % field_name)
	if int(report.get("iterations", -1)) < 0:
		errors.append("sparse steady-state Solver iterations must be non-negative")
	if int(report.get("raw_significantly_negative_count", 0)) > 0:
		errors.append("raw concentration contains values below -1e-6")
	return errors
