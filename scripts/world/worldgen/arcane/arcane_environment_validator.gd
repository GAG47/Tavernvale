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
	for field_name in ["converged", "hit_iteration_cap", "finite", "within_expected_range"]:
		if not report.has(field_name):
			errors.append("transport Solver must report %s" % field_name)
	if not errors.is_empty():
		return errors
	if not bool(report.get("finite", false)):
		errors.append("transport Solver produced a non-finite concentration")
	if not bool(report.converged) and not bool(report.hit_iteration_cap):
		errors.append("non-converged transport Solver must report its iteration cap")
	if bool(report.converged) and bool(report.hit_iteration_cap):
		errors.append("converged transport Solver cannot also report its iteration cap")
	for field_name in ["dt", "final_max_delta"]:
		if not report.has(field_name) or not is_finite(float(report.get(field_name, NAN))):
			errors.append("transport Solver report %s must be finite" % field_name)
	if int(report.get("iterations", 0)) <= 0:
		errors.append("transport Solver must report at least one iteration")
	return errors
