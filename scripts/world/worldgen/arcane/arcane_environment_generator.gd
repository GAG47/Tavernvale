class_name ArcaneEnvironmentGenerator
extends RefCounted

const NUMERICAL_EPSILON := 0.000000001
const OPERATOR_DIAGONAL_THRESHOLD := 1.0e-18
const RAW_NEGATIVE_TOLERANCE := 1.0e-6

static var _last_generation_diagnostics := {}


static func generate(
		spatial_graph: SpatialGraph,
		arcane_field: ArcaneFieldLayer,
		arcane_web: ArcaneWebLayer,
		arcane_circulation: ArcaneCirculationLayer,
		arcane_forcing: ArcaneForcingLayer,
		settings: ArcaneEnvironmentSettings = null
) -> ArcaneEnvironmentLayer:
	_last_generation_diagnostics = {}
	var actual_settings := settings if settings != null else ArcaneEnvironmentSettings.new()
	var input_errors := _validate_inputs(
		spatial_graph, arcane_field, arcane_web, arcane_circulation,
		arcane_forcing, actual_settings
	)
	if not input_errors.is_empty():
		push_error("ArcaneEnvironmentGenerator: invalid inputs:\n" + "\n".join(input_errors))
		return null

	var total_started := Time.get_ticks_usec()
	var stage_started := Time.get_ticks_usec()
	var transport_projection := project_leyline_transport(
		spatial_graph, arcane_web, arcane_circulation, actual_settings
	)
	var leyline_transport_projection_ms := _elapsed_ms(stage_started)
	stage_started = Time.get_ticks_usec()
	var transport_faces := build_transport_faces(
		spatial_graph,
		transport_projection.transport_tensor,
		transport_projection.drift_field,
		actual_settings,
		true
	)
	var face_transport_precompute_ms := _elapsed_ms(stage_started)
	stage_started = Time.get_ticks_usec()
	var operator_result := build_steady_state_operator(
		spatial_graph,
		arcane_field.background_mana,
		arcane_field.background_stability,
		arcane_forcing.source_rate,
		arcane_forcing.sink_rate,
		actual_settings,
		transport_faces
	)
	var operator_build_ms := _elapsed_ms(stage_started)
	if not operator_result.errors.is_empty():
		_last_generation_diagnostics = {
			"operator_errors": operator_result.errors,
			"performance": {
				"leyline_transport_projection_ms": leyline_transport_projection_ms,
				"face_transport_precompute_ms": face_transport_precompute_ms,
				"linear_operator_build_ms": operator_build_ms,
				"bicgstab_solve_ms": 0.0,
				"concentration_finalization_ms": 0.0,
				"stability_synthesis_ms": 0.0,
				"total_ms": _elapsed_ms(total_started),
			},
		}
		push_error(
			"ArcaneEnvironmentGenerator: invalid steady-state operator:\n"
			+ "\n".join(operator_result.errors)
		)
		return null

	var initial_guess := PackedFloat64Array()
	initial_guess.resize(spatial_graph.cell_count())
	for cell_id in spatial_graph.cell_count():
		initial_guess[cell_id] = arcane_field.background_mana[cell_id]
	stage_started = Time.get_ticks_usec()
	var solver_result := ArcaneBiCGSTABSolver.solve(operator_result.operator, initial_guess)
	var solver_ms := _elapsed_ms(stage_started)
	var solver_report: Dictionary = solver_result.report
	solver_report.merge(_raw_concentration_report(solver_result.concentration), true)
	solver_report["operator_cell_count"] = operator_result.operator.cell_count()
	solver_report["operator_internal_face_count"] = (
		operator_result.operator.internal_face_count()
	)
	solver_report["operator_boundary_face_count"] = (
		operator_result.operator.boundary_face_count
	)
	solver_report["operator_diagonal"] = _statistics(operator_result.operator.diagonal)
	var solver_errors := ArcaneEnvironmentValidator.validate_solver_report(solver_report)
	if not solver_errors.is_empty():
		_last_generation_diagnostics = {
			"solver": solver_report,
			"performance": {
				"leyline_transport_projection_ms": leyline_transport_projection_ms,
				"face_transport_precompute_ms": face_transport_precompute_ms,
				"linear_operator_build_ms": operator_build_ms,
				"bicgstab_solve_ms": solver_ms,
				"concentration_finalization_ms": 0.0,
				"stability_synthesis_ms": 0.0,
				"total_ms": _elapsed_ms(total_started),
			},
		}
		push_error("ArcaneEnvironmentGenerator: Solver failed:\n" + "\n".join(solver_errors))
		return null

	stage_started = Time.get_ticks_usec()
	var environment := ArcaneEnvironmentLayer.new()
	environment.mana_concentration = public_concentration_from_raw(
		solver_result.concentration
	)
	environment.mana_flowability = _clamped_float32(transport_projection.flowability)
	var concentration_finalization_ms := _elapsed_ms(stage_started)
	stage_started = Time.get_ticks_usec()
	var stability_result := synthesize_stability(
		spatial_graph,
		arcane_field.background_mana,
		arcane_field.background_stability,
		arcane_forcing,
		solver_result.concentration,
		transport_faces,
		actual_settings
	)
	environment.mana_stability = stability_result.stability
	var stability_ms := _elapsed_ms(stage_started)
	var total_ms := _elapsed_ms(total_started)
	_last_generation_diagnostics = _build_diagnostics(
		spatial_graph,
		arcane_field,
		environment,
		arcane_forcing,
		transport_projection,
		transport_faces,
		solver_result.concentration,
		stability_result,
		solver_report,
		actual_settings,
		{
			"leyline_transport_projection_ms": leyline_transport_projection_ms,
			"face_transport_precompute_ms": face_transport_precompute_ms,
			"linear_operator_build_ms": operator_build_ms,
			"bicgstab_solve_ms": solver_ms,
			"concentration_finalization_ms": concentration_finalization_ms,
			"stability_synthesis_ms": stability_ms,
			"total_ms": total_ms,
		}
	)
	var output_errors := ArcaneEnvironmentValidator.validate(spatial_graph, environment)
	if not output_errors.is_empty():
		push_error("ArcaneEnvironmentGenerator: invalid output:\n" + "\n".join(output_errors))
		return null
	return environment


static func last_generation_diagnostics() -> Dictionary:
	return _last_generation_diagnostics.duplicate(true)


static func project_leyline_transport(
		graph: SpatialGraph,
		web: ArcaneWebLayer,
		circulation: ArcaneCirculationLayer,
		settings: ArcaneEnvironmentSettings
) -> Dictionary:
	var web_influence := PackedFloat64Array()
	web_influence.resize(graph.cell_count())
	var transport_tensor := PackedVector3Array()
	transport_tensor.resize(graph.cell_count())
	var drift_field := PackedVector2Array()
	drift_field.resize(graph.cell_count())
	for edge in web.edges:
		var segment_start := web.nodes[edge.node_a_id].world_position
		var segment_end := web.nodes[edge.node_b_id].world_position
		var tangent := (segment_end - segment_start).normalized()
		var tensor_contribution := Vector3(
			tangent.x * tangent.x, tangent.x * tangent.y, tangent.y * tangent.y
		)
		var signed_velocity := float(circulation.edge_flow[edge.id]) \
				* settings.arcane_drift_speed_per_flow
		for cell_id in graph.cell_count():
			var distance := point_segment_distance(
				graph.cell_centers[cell_id], segment_start, segment_end
			)
			var influence := leyline_influence(distance, settings.leyline_influence_radius)
			if influence > web_influence[cell_id]:
				web_influence[cell_id] = influence
			if influence > 0.0:
				transport_tensor[cell_id] += influence * tensor_contribution
				drift_field[cell_id] += influence * signed_velocity * tangent
	var flowability := PackedFloat64Array()
	flowability.resize(graph.cell_count())
	var maximum_eigenvalues := PackedFloat64Array()
	maximum_eigenvalues.resize(graph.cell_count())
	var drift_magnitudes := PackedFloat64Array()
	drift_magnitudes.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		transport_tensor[cell_id] = normalize_transport_tensor(transport_tensor[cell_id])
		maximum_eigenvalues[cell_id] = tensor_max_eigenvalue(transport_tensor[cell_id])
		drift_magnitudes[cell_id] = drift_field[cell_id].length()
		flowability[cell_id] = clampf(
			settings.ambient_flowability
					+ (1.0 - settings.ambient_flowability) * web_influence[cell_id],
			0.0,
			1.0
		)
	var maximum_abs_edge_flow := 0.0
	for edge_flow in circulation.edge_flow:
		maximum_abs_edge_flow = maxf(maximum_abs_edge_flow, absf(float(edge_flow)))
	return {
		"web_influence": web_influence,
		"flowability": flowability,
		"transport_tensor": transport_tensor,
		"drift_field": drift_field,
		"tensor_max_eigenvalue": _statistics(maximum_eigenvalues),
		"drift_velocity_magnitude": _statistics(drift_magnitudes, [0.90]),
		"maximum_abs_edge_flow": maximum_abs_edge_flow,
	}


static func synthesize_stability(
		graph: SpatialGraph,
		background_mana: PackedFloat32Array,
		background_stability: PackedFloat32Array,
		forcing: ArcaneForcingLayer,
		raw_concentration,
		transport_faces: Dictionary,
		settings: ArcaneEnvironmentSettings
) -> Dictionary:
	## Long-term Stability compares persistent forcing/transport imbalance with
	## Background restoration ability. Concentration and Flowability are not direct
	## Stability inputs; Raw C is used only to evaluate the existing physical fluxes.
	var count := graph.cell_count()
	var transport_net_amount := compute_transport_net_amount(
		graph, background_mana, raw_concentration, transport_faces
	)
	var stability := PackedFloat32Array()
	stability.resize(count)
	var forcing_disturbance := PackedFloat64Array()
	forcing_disturbance.resize(count)
	var transport_imbalance := PackedFloat64Array()
	transport_imbalance.resize(count)
	var persistent_disturbance := PackedFloat64Array()
	persistent_disturbance.resize(count)
	var restoration_rate := PackedFloat64Array()
	restoration_rate.resize(count)
	for cell_id in count:
		forcing_disturbance[cell_id] = (
			float(forcing.source_rate[cell_id]) + float(forcing.sink_rate[cell_id])
		)
		transport_imbalance[cell_id] = (
			absf(transport_net_amount[cell_id]) / graph.cell_areas[cell_id]
		)
		persistent_disturbance[cell_id] = (
			forcing_disturbance[cell_id] + transport_imbalance[cell_id]
		)
		restoration_rate[cell_id] = lerpf(
			settings.background_restoration_min_rate,
			settings.background_restoration_max_rate,
			background_stability[cell_id]
		)
		var competition := restoration_rate[cell_id] + persistent_disturbance[cell_id]
		stability[cell_id] = (
			clampf(restoration_rate[cell_id] / competition, 0.0, 1.0)
			if competition > NUMERICAL_EPSILON else 1.0
		)
	return {
		"stability": stability,
		"forcing_disturbance": forcing_disturbance,
		"transport_net_amount": transport_net_amount,
		"transport_imbalance": transport_imbalance,
		"persistent_disturbance": persistent_disturbance,
		"restoration_rate": restoration_rate,
	}


static func compute_transport_net_amount(
		graph: SpatialGraph,
		background_mana: PackedFloat32Array,
		raw_concentration,
		faces: Dictionary
) -> PackedFloat64Array:
	var transport_net_amount := PackedFloat64Array()
	transport_net_amount.resize(graph.cell_count())
	for face_index in faces.internal_a.size():
		var cell_a: int = faces.internal_a[face_index]
		var cell_b: int = faces.internal_b[face_index]
		var anomaly_a := float(raw_concentration[cell_a]) - float(background_mana[cell_a])
		var anomaly_b := float(raw_concentration[cell_b]) - float(background_mana[cell_b])
		var diffusion_flux: float = faces.internal_diffusion[face_index] * (
			anomaly_a - anomaly_b
		)
		var velocity_length: float = faces.internal_velocity_length[face_index]
		var upwind_concentration := (
			float(raw_concentration[cell_a])
			if velocity_length >= 0.0 else float(raw_concentration[cell_b])
		)
		var total_face_flux := diffusion_flux + velocity_length * upwind_concentration
		transport_net_amount[cell_a] -= total_face_flux
		transport_net_amount[cell_b] += total_face_flux
	for face_index in faces.boundary_cell.size():
		var cell_id: int = faces.boundary_cell[face_index]
		var background := float(background_mana[cell_id])
		var anomaly := float(raw_concentration[cell_id]) - background
		var diffusion_flux: float = faces.boundary_diffusion[face_index] * anomaly
		var velocity_length: float = faces.boundary_velocity_length[face_index]
		var upwind_concentration := (
			float(raw_concentration[cell_id]) if velocity_length > 0.0 else background
		)
		transport_net_amount[cell_id] -= (
			diffusion_flux + velocity_length * upwind_concentration
		)
	return transport_net_amount


static func leyline_influence(distance: float, radius: float) -> float:
	if distance >= radius:
		return 0.0
	var u := clampf(1.0 - distance / radius, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


static func point_segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= NUMERICAL_EPSILON:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)


static func tensor_max_eigenvalue(tensor: Vector3) -> float:
	var trace := tensor.x + tensor.z
	var discriminant := sqrt(maxf(
		0.0, (tensor.x - tensor.z) * (tensor.x - tensor.z) + 4.0 * tensor.y * tensor.y
	))
	return 0.5 * (trace + discriminant)


static func normalize_transport_tensor(tensor: Vector3) -> Vector3:
	var maximum_eigenvalue := tensor_max_eigenvalue(tensor)
	return tensor / maximum_eigenvalue if maximum_eigenvalue > 1.0 else tensor


static func tensor_alignment(tensor: Vector3, direction: Vector2) -> float:
	var normalized_direction := direction.normalized()
	var transformed := Vector2(
		tensor.x * normalized_direction.x + tensor.y * normalized_direction.y,
		tensor.y * normalized_direction.x + tensor.z * normalized_direction.y
	)
	return clampf(normalized_direction.dot(transformed), 0.0, 1.0)


static func directional_diffusivity(
		tensor: Vector3, direction: Vector2, settings: ArcaneEnvironmentSettings
) -> float:
	var alignment := tensor_alignment(tensor, direction)
	return settings.ambient_mana_diffusivity * (
		1.0 + (settings.leyline_parallel_diffusivity_multiplier - 1.0) * alignment
	)


static func build_transport_faces(
		graph: SpatialGraph,
		transport_tensor: PackedVector3Array,
		drift_field: PackedVector2Array,
		settings: ArcaneEnvironmentSettings,
		include_boundary: bool
) -> Dictionary:
	var internal_a := PackedInt32Array()
	var internal_b := PackedInt32Array()
	var internal_diffusion := PackedFloat64Array()
	var internal_velocity_length := PackedFloat64Array()
	var boundary_cell := PackedInt32Array()
	var boundary_diffusion := PackedFloat64Array()
	var boundary_velocity_length := PackedFloat64Array()
	var face_diffusivity := PackedFloat64Array()
	for edge_id in graph.edge_count():
		var cells: PackedInt32Array = graph.edge_cells[edge_id]
		var vertices: Vector2i = graph.edge_vertex_ids[edge_id]
		var first_vertex := graph.vertex_positions[vertices.x]
		var second_vertex := graph.vertex_positions[vertices.y]
		var face_length := first_vertex.distance_to(second_vertex)
		if face_length <= NUMERICAL_EPSILON:
			continue
		if cells.size() == 2:
			var cell_a := cells[0]
			var cell_b := cells[1]
			var center_delta := graph.cell_centers[cell_b] - graph.cell_centers[cell_a]
			var center_distance := center_delta.length()
			if center_distance <= NUMERICAL_EPSILON:
				continue
			var normal := center_delta / center_distance
			var face_tensor := 0.5 * (
				transport_tensor[cell_a] + transport_tensor[cell_b]
			)
			var diffusivity := directional_diffusivity(face_tensor, normal, settings)
			var normal_velocity := 0.5 * (
				drift_field[cell_a] + drift_field[cell_b]
			).dot(normal)
			internal_a.append(cell_a)
			internal_b.append(cell_b)
			internal_diffusion.append(
				diffusivity * face_length / center_distance
			)
			internal_velocity_length.append(normal_velocity * face_length)
			face_diffusivity.append(diffusivity)
		elif include_boundary and cells.size() == 1:
			var cell_id := cells[0]
			var midpoint := (first_vertex + second_vertex) * 0.5
			var outward_delta := midpoint - graph.cell_centers[cell_id]
			var boundary_distance := outward_delta.length()
			if boundary_distance <= NUMERICAL_EPSILON:
				continue
			var outward_normal := outward_delta / boundary_distance
			var diffusivity := directional_diffusivity(
				transport_tensor[cell_id], outward_normal, settings
			)
			boundary_cell.append(cell_id)
			boundary_diffusion.append(
				diffusivity * face_length / boundary_distance
			)
			boundary_velocity_length.append(
				drift_field[cell_id].dot(outward_normal) * face_length
			)
			face_diffusivity.append(diffusivity)
	return {
		"internal_a": internal_a,
		"internal_b": internal_b,
		"internal_diffusion": internal_diffusion,
		"internal_velocity_length": internal_velocity_length,
		"boundary_cell": boundary_cell,
		"boundary_diffusion": boundary_diffusion,
		"boundary_velocity_length": boundary_velocity_length,
		"face_diffusivity": face_diffusivity,
		"face_diffusivity_statistics": _statistics(face_diffusivity, [0.90]),
	}


static func build_steady_state_operator(
		graph: SpatialGraph,
		background_mana: PackedFloat32Array,
		background_stability: PackedFloat32Array,
		source_rate,
		sink_rate,
		settings: ArcaneEnvironmentSettings,
		faces: Dictionary
) -> Dictionary:
	var operator := ArcaneSteadyStateOperator.new()
	var count := graph.cell_count()
	operator.diagonal.resize(count)
	operator.rhs.resize(count)
	operator.internal_a = faces.internal_a
	operator.internal_b = faces.internal_b
	operator.internal_diffusion = faces.internal_diffusion
	operator.internal_velocity_length = faces.internal_velocity_length
	operator.boundary_face_count = faces.boundary_cell.size()

	for cell_id in count:
		var area := graph.cell_areas[cell_id]
		var background := float(background_mana[cell_id])
		var restoration_rate := lerpf(
			settings.background_restoration_min_rate,
			settings.background_restoration_max_rate,
			background_stability[cell_id]
		)
		var source := float(source_rate[cell_id])
		var sink := float(sink_rate[cell_id])
		operator.diagonal[cell_id] = area * (restoration_rate + source + sink)
		operator.rhs[cell_id] = area * (restoration_rate * background + source)

	for face_index in operator.internal_a.size():
		var cell_a := operator.internal_a[face_index]
		var cell_b := operator.internal_b[face_index]
		var diffusion := operator.internal_diffusion[face_index]
		var velocity_length := operator.internal_velocity_length[face_index]
		operator.diagonal[cell_a] += diffusion
		operator.diagonal[cell_b] += diffusion
		operator.rhs[cell_a] += diffusion * (
			float(background_mana[cell_a]) - float(background_mana[cell_b])
		)
		operator.rhs[cell_b] += diffusion * (
			float(background_mana[cell_b]) - float(background_mana[cell_a])
		)
		if velocity_length >= 0.0:
			operator.diagonal[cell_a] += velocity_length
		else:
			operator.diagonal[cell_b] -= velocity_length

	for face_index in faces.boundary_cell.size():
		var cell_id: int = faces.boundary_cell[face_index]
		var background := float(background_mana[cell_id])
		var diffusion: float = faces.boundary_diffusion[face_index]
		var velocity_length: float = faces.boundary_velocity_length[face_index]
		operator.diagonal[cell_id] += diffusion
		operator.rhs[cell_id] += diffusion * background
		if velocity_length > 0.0:
			operator.diagonal[cell_id] += velocity_length
		else:
			operator.rhs[cell_id] -= velocity_length * background

	var errors := PackedStringArray()
	for cell_id in count:
		var diagonal := operator.diagonal[cell_id]
		var rhs_value := operator.rhs[cell_id]
		if not is_finite(diagonal) or not is_finite(rhs_value):
			errors.append("steady-state operator Cell %d has a non-finite diagonal/RHS" % cell_id)
		elif absf(diagonal) <= OPERATOR_DIAGONAL_THRESHOLD:
			errors.append(
				"steady-state operator Cell %d has a zero/near-zero diagonal (%s)" % [
					cell_id, str(diagonal),
				]
			)
	return {"operator": operator, "errors": errors}


static func _validate_inputs(
		graph: SpatialGraph,
		field: ArcaneFieldLayer,
		web: ArcaneWebLayer,
		circulation: ArcaneCirculationLayer,
		forcing: ArcaneForcingLayer,
		settings: ArcaneEnvironmentSettings
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null:
		errors.append("SpatialGraph is null")
	else:
		errors.append_array(SpatialValidator.validate(graph))
	if graph != null:
		errors.append_array(ArcaneFieldValidator.validate(graph, field))
	elif field == null:
		errors.append("Arcane Field is null")
	if web == null:
		errors.append("Arcane Web is null")
	else:
		errors.append_array(ArcaneWebValidator.validate(web))
	if web != null:
		errors.append_array(ArcaneCirculationValidator.validate(web, circulation))
	elif circulation == null:
		errors.append("Arcane Circulation is null")
	if graph != null:
		errors.append_array(ArcaneForcingValidator.validate(graph, forcing))
	elif forcing == null:
		errors.append("Arcane Forcing is null")
	if settings == null:
		errors.append("Arcane Environment settings are null")
	else:
		errors.append_array(settings.validate())
	if graph != null and web != null and graph.config != null:
		if graph.config.world_width != web.world_width \
				or graph.config.world_height != web.world_height:
			errors.append("SpatialGraph and Arcane Web World Extents must match")
	return errors


## Converts the unbounded-above physical solution into the public standardized scale.
## This is the layer's semantic mapping, not a numerical repair of the solve.
static func public_concentration_from_raw(values) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(values.size())
	for index in values.size():
		result[index] = clampf(float(values[index]), 0.0, 1.0)
	return result


static func _clamped_float32(values) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(values.size())
	for index in values.size():
		result[index] = clampf(float(values[index]), 0.0, 1.0)
	return result


static func _raw_concentration_report(raw_concentration) -> Dictionary:
	var raw_minimum := INF
	var raw_maximum := -INF
	var finite := true
	var negative_count := 0
	var significantly_negative_count := 0
	var above_one_count := 0
	var above_110_count := 0
	var above_125_count := 0
	for value_variant in raw_concentration:
		var value := float(value_variant)
		finite = finite and is_finite(value)
		raw_minimum = minf(raw_minimum, value)
		raw_maximum = maxf(raw_maximum, value)
		if value < 0.0:
			negative_count += 1
		if value < -RAW_NEGATIVE_TOLERANCE:
			significantly_negative_count += 1
		if value > 1.0:
			above_one_count += 1
		if value > 1.10:
			above_110_count += 1
		if value > 1.25:
			above_125_count += 1
	if raw_concentration.size() == 0:
		raw_minimum = 0.0
		raw_maximum = 0.0
	return {
		"finite": finite,
		"raw_min": raw_minimum,
		"raw_max": raw_maximum,
		"raw_negative_count": negative_count,
		"raw_significantly_negative_count": significantly_negative_count,
		"raw_above_1": _count_statistics(above_one_count, raw_concentration.size()),
		"raw_above_1_10": _count_statistics(above_110_count, raw_concentration.size()),
		"raw_above_1_25": _count_statistics(above_125_count, raw_concentration.size()),
		"maximum_overload": maxf(raw_maximum - 1.0, 0.0),
	}


static func _build_diagnostics(
		graph: SpatialGraph,
		field: ArcaneFieldLayer,
		environment: ArcaneEnvironmentLayer,
		forcing: ArcaneForcingLayer,
		transport_projection: Dictionary,
		transport_faces: Dictionary,
		raw_concentration,
		stability_result: Dictionary,
		solver_report: Dictionary,
		settings: ArcaneEnvironmentSettings,
		performance: Dictionary
) -> Dictionary:
	var concentration_delta := PackedFloat64Array()
	var absolute_delta := PackedFloat64Array()
	concentration_delta.resize(environment.cell_count())
	absolute_delta.resize(environment.cell_count())
	var enriched_count := 0
	var depleted_count := 0
	var strong_enriched_count := 0
	var strong_depleted_count := 0
	var influenced_count := 0
	var below_75_count := 0
	var below_50_count := 0
	var below_25_count := 0
	var directly_forced_count := 0
	var significantly_anomalous_count := 0
	var significant_outside_forcing_count := 0
	var significant_within_leyline_count := 0
	var significant_outside_leyline_count := 0
	var low_flow_high_stability_count := 0
	var low_flow_low_stability_count := 0
	var high_flow_high_stability_count := 0
	var high_flow_low_stability_count := 0
	for cell_id in environment.cell_count():
		var delta := float(raw_concentration[cell_id]) - field.background_mana[cell_id]
		var directly_forced := forcing.source_rate[cell_id] > 0.0 \
				or forcing.sink_rate[cell_id] > 0.0
		var significantly_anomalous := absf(delta) > 0.05
		concentration_delta[cell_id] = delta
		absolute_delta[cell_id] = absf(delta)
		if delta > 0.05:
			enriched_count += 1
		if delta < -0.05:
			depleted_count += 1
		if delta > 0.10:
			strong_enriched_count += 1
		if delta < -0.10:
			strong_depleted_count += 1
		if directly_forced:
			directly_forced_count += 1
		if significantly_anomalous:
			significantly_anomalous_count += 1
			if not directly_forced:
				significant_outside_forcing_count += 1
			if float(transport_projection.web_influence[cell_id]) > 0.0:
				significant_within_leyline_count += 1
			else:
				significant_outside_leyline_count += 1
		if float(transport_projection.web_influence[cell_id]) > 0.0:
			influenced_count += 1
		if environment.mana_stability[cell_id] < 0.75:
			below_75_count += 1
		if environment.mana_stability[cell_id] < 0.50:
			below_50_count += 1
		if environment.mana_stability[cell_id] < 0.25:
			below_25_count += 1
		var low_flow := environment.mana_flowability[cell_id] < 0.50
		var low_stability := environment.mana_stability[cell_id] < 0.75
		if low_flow and not low_stability:
			low_flow_high_stability_count += 1
		elif low_flow and low_stability:
			low_flow_low_stability_count += 1
		elif not low_flow and not low_stability:
			high_flow_high_stability_count += 1
		else:
			high_flow_low_stability_count += 1
	var count := environment.cell_count()
	var absolute_statistics := _statistics(absolute_delta, [0.50, 0.90])
	return {
		"background_mana": _statistics(field.background_mana),
		"mana_concentration": _statistics(environment.mana_concentration),
		"public_mana_concentration": _statistics(environment.mana_concentration),
		"raw_concentration": _statistics(raw_concentration),
		"raw_above_1": solver_report.raw_above_1.duplicate(true),
		"raw_above_1_10": solver_report.raw_above_1_10.duplicate(true),
		"raw_above_1_25": solver_report.raw_above_1_25.duplicate(true),
		"maximum_overload": solver_report.maximum_overload,
		"concentration_delta": _statistics(concentration_delta),
		"absolute_concentration_delta": absolute_statistics,
		"enriched_cells": _count_statistics(enriched_count, count),
		"depleted_cells": _count_statistics(depleted_count, count),
		"strong_enriched_cells": _count_statistics(strong_enriched_count, count),
		"strong_depleted_cells": _count_statistics(strong_depleted_count, count),
		"directly_forced_cells": _count_statistics(directly_forced_count, count),
		"significantly_anomalous_cells": _count_statistics(
			significantly_anomalous_count, count
		),
		"significantly_anomalous_outside_forcing_cores": _count_statistics(
			significant_outside_forcing_count, count
		),
		"significant_anomaly_within_leyline_influence": _count_statistics(
			significant_within_leyline_count, count
		),
		"significant_anomaly_outside_leyline_influence": _count_statistics(
			significant_outside_leyline_count, count
		),
		"mana_flowability": _statistics(environment.mana_flowability),
		"leyline_influenced_cells": _count_statistics(influenced_count, count),
		"background_stability": _statistics(field.background_stability),
		"mana_stability": _statistics(environment.mana_stability),
		"mana_stability_below_75": _count_statistics(below_75_count, count),
		"mana_stability_below_50": _count_statistics(below_50_count, count),
		"mana_stability_below_25": _count_statistics(below_25_count, count),
		"low_mana_stability": _count_statistics(below_25_count, count),
		"forcing_disturbance": _statistics(
			stability_result.forcing_disturbance, [0.90]
		),
		"transport_imbalance": _statistics(
			stability_result.transport_imbalance, [0.90]
		),
		"persistent_disturbance": _statistics(
			stability_result.persistent_disturbance, [0.90]
		),
		"restoration_rate": _statistics(stability_result.restoration_rate),
		"low_flow_high_stability": _count_statistics(
			low_flow_high_stability_count, count
		),
		"low_flow_low_stability": _count_statistics(low_flow_low_stability_count, count),
		"high_flow_high_stability": _count_statistics(
			high_flow_high_stability_count, count
		),
		"high_flow_low_stability": _count_statistics(high_flow_low_stability_count, count),
		"flowability_stability_pearson": _pearson_correlation(
			environment.mana_flowability, environment.mana_stability
		),
		"forcing_sites": _forcing_site_diagnostics(
			graph, field, environment, forcing, stability_result.forcing_disturbance
		),
		"transport_tensor_max_eigenvalue": (
			transport_projection.tensor_max_eigenvalue.duplicate(true)
		),
		"face_diffusivity": transport_faces.face_diffusivity_statistics.duplicate(true),
		"drift_velocity_magnitude": (
			transport_projection.drift_velocity_magnitude.duplicate(true)
		),
		"maximum_abs_edge_flow": transport_projection.maximum_abs_edge_flow,
		"solver": solver_report.duplicate(true),
		"performance": performance.duplicate(true),
		"parameters": _settings_dictionary(settings),
	}


static func _statistics(values, percentiles: Array = []) -> Dictionary:
	if values.size() == 0:
		return {"min": 0.0, "mean": 0.0, "max": 0.0}
	var minimum := INF
	var maximum := -INF
	var sum := 0.0
	for value in values:
		minimum = minf(minimum, float(value))
		maximum = maxf(maximum, float(value))
		sum += float(value)
	var result := {
		"min": minimum,
		"mean": sum / float(values.size()),
		"max": maximum,
	}
	if not percentiles.is_empty():
		var sorted_values := Array(values)
		sorted_values.sort()
		for percentile in percentiles:
			var key := "p%d" % roundi(float(percentile) * 100.0)
			result[key] = _percentile(sorted_values, float(percentile))
	return result


static func _percentile(sorted_values: Array, fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var position := clampf(fraction, 0.0, 1.0) * float(sorted_values.size() - 1)
	var lower := floori(position)
	var upper := ceili(position)
	if lower == upper:
		return float(sorted_values[lower])
	return lerpf(float(sorted_values[lower]), float(sorted_values[upper]), position - lower)


static func _count_statistics(count: int, total: int) -> Dictionary:
	return {
		"count": count,
		"percentage": 100.0 * float(count) / float(total) if total > 0 else 0.0,
	}


static func _pearson_correlation(first, second) -> float:
	if first.size() == 0 or first.size() != second.size():
		return 0.0
	var first_mean := float(_statistics(first).mean)
	var second_mean := float(_statistics(second).mean)
	var covariance := 0.0
	var first_square := 0.0
	var second_square := 0.0
	for index in first.size():
		var first_delta := float(first[index]) - first_mean
		var second_delta := float(second[index]) - second_mean
		covariance += first_delta * second_delta
		first_square += first_delta * first_delta
		second_square += second_delta * second_delta
	var denominator := sqrt(first_square * second_square)
	return covariance / denominator if denominator > NUMERICAL_EPSILON else 0.0


static func _forcing_site_diagnostics(
		graph: SpatialGraph,
		field: ArcaneFieldLayer,
		environment: ArcaneEnvironmentLayer,
		forcing: ArcaneForcingLayer,
		forcing_disturbance
) -> Array:
	var result := []
	for site in forcing.sites:
		var center_cell_id := _nearest_cell(graph, site.world_position)
		if center_cell_id < 0:
			continue
		result.append({
			"site_id": site.id,
			"kind": site.kind_name(),
			"center_cell_id": center_cell_id,
			"center_flowability": environment.mana_flowability[center_cell_id],
			"center_background_stability": field.background_stability[center_cell_id],
			"center_forcing_disturbance": forcing_disturbance[center_cell_id],
			"center_mana_stability": environment.mana_stability[center_cell_id],
		})
	return result


static func _nearest_cell(graph: SpatialGraph, position: Vector2) -> int:
	var nearest_cell_id := -1
	var nearest_distance_squared := INF
	for cell_id in graph.cell_count():
		var distance_squared := graph.cell_centers[cell_id].distance_squared_to(position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_cell_id = cell_id
	return nearest_cell_id


static func _settings_dictionary(settings: ArcaneEnvironmentSettings) -> Dictionary:
	return {
		"leyline_influence_radius": settings.leyline_influence_radius,
		"ambient_flowability": settings.ambient_flowability,
		"ambient_mana_diffusivity": settings.ambient_mana_diffusivity,
		"leyline_parallel_diffusivity_multiplier": (
			settings.leyline_parallel_diffusivity_multiplier
		),
		"arcane_drift_speed_per_flow": settings.arcane_drift_speed_per_flow,
		"background_restoration_min_rate": settings.background_restoration_min_rate,
		"background_restoration_max_rate": settings.background_restoration_max_rate,
	}


static func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0
