class_name ArcaneExplicitTransportReference
extends RefCounted

## Test-only reference for the exact v2.3.3 amount-rate equation. Production never
## calls this explicit time-marching implementation.

const CFL_SAFETY := 0.40
const MAX_DT := 1.0
const MAX_ITERATIONS := 2000000
const DELTA_TOLERANCE := 1.0e-11
const LEGACY_DEFAULT_MAX_ITERATIONS := 1200
const LEGACY_DEFAULT_DELTA_TOLERANCE := 0.00001


static func forcing_concentration_rate(
		source_rate: float, sink_rate: float, concentration: float
) -> float:
	return source_rate * (1.0 - concentration) - sink_rate * concentration


## Compatibility harness for v2.3.3 physics regression tests. The public production
## API intentionally does not expose explicit iteration controls anymore.
static func solve_transport(
		graph: SpatialGraph,
		background_mana: PackedFloat32Array,
		background_stability: PackedFloat32Array,
		transport_tensor: PackedVector3Array,
		drift_field: PackedVector2Array,
		source_rate,
		sink_rate,
		settings: ArcaneEnvironmentSettings,
		initial_concentration = PackedFloat64Array(),
		include_boundary: bool = true,
		precomputed_faces: Dictionary = {}
) -> Dictionary:
	var faces := precomputed_faces if not precomputed_faces.is_empty() else (
		ArcaneEnvironmentGenerator.build_transport_faces(
			graph, transport_tensor, drift_field, settings, include_boundary
		)
	)
	var concentration := PackedFloat64Array()
	concentration.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		concentration[cell_id] = (
			float(initial_concentration[cell_id])
			if initial_concentration.size() == graph.cell_count()
			else float(background_mana[cell_id])
		)
	var dt := _stable_dt(
		graph, background_stability, faces, source_rate, sink_rate, settings
	)
	var maximum_iterations := int(settings.get_meta(
		"_explicit_max_iterations", LEGACY_DEFAULT_MAX_ITERATIONS
	))
	var tolerance := float(settings.get_meta(
		"_explicit_delta_tolerance", LEGACY_DEFAULT_DELTA_TOLERANCE
	))
	var final_delta := INF
	var iterations := 0
	var finite := true
	for iteration in maximum_iterations:
		var rate := amount_rate(
			graph, background_mana, background_stability, faces,
			source_rate, sink_rate, settings, concentration
		)
		final_delta = 0.0
		for cell_id in graph.cell_count():
			var delta := dt * rate[cell_id] / graph.cell_areas[cell_id]
			concentration[cell_id] += delta
			finite = finite and is_finite(concentration[cell_id])
			final_delta = maxf(final_delta, absf(delta))
		iterations = iteration + 1
		if not finite or final_delta < tolerance:
			break
	var minimum := INF
	var maximum := -INF
	for value in concentration:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	return {
		"concentration": concentration,
		"report": {
			"dt": dt,
			"iterations": iterations,
			"final_max_delta": final_delta,
			"converged": finite and final_delta < tolerance,
			"hit_iteration_cap": finite and final_delta >= tolerance,
			"finite": finite,
			"raw_min": minimum,
			"raw_max": maximum,
		},
	}


static func amount_rate(
		graph: SpatialGraph,
		background_mana: PackedFloat32Array,
		background_stability: PackedFloat32Array,
		faces: Dictionary,
		source_rate,
		sink_rate,
		settings: ArcaneEnvironmentSettings,
		concentration: PackedFloat64Array
) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(graph.cell_count())
	for face_index in faces.internal_a.size():
		var cell_a: int = faces.internal_a[face_index]
		var cell_b: int = faces.internal_b[face_index]
		var anomaly_a := concentration[cell_a] - float(background_mana[cell_a])
		var anomaly_b := concentration[cell_b] - float(background_mana[cell_b])
		var diffusion_flux: float = faces.internal_diffusion[face_index] * (
			anomaly_a - anomaly_b
		)
		var velocity_length: float = faces.internal_velocity_length[face_index]
		var upwind_concentration := (
			concentration[cell_a] if velocity_length >= 0.0 else concentration[cell_b]
		)
		var total_flux := diffusion_flux + velocity_length * upwind_concentration
		result[cell_a] -= total_flux
		result[cell_b] += total_flux
	for face_index in faces.boundary_cell.size():
		var cell_id: int = faces.boundary_cell[face_index]
		var background := float(background_mana[cell_id])
		var anomaly := concentration[cell_id] - background
		var diffusion_flux: float = faces.boundary_diffusion[face_index] * anomaly
		var velocity_length: float = faces.boundary_velocity_length[face_index]
		var upwind_concentration := (
			concentration[cell_id] if velocity_length > 0.0 else background
		)
		result[cell_id] -= diffusion_flux + velocity_length * upwind_concentration
	for cell_id in graph.cell_count():
		var restoration_rate := lerpf(
			settings.background_restoration_min_rate,
			settings.background_restoration_max_rate,
			background_stability[cell_id]
		)
		var concentration_value := concentration[cell_id]
		var forcing_rate := (
			float(source_rate[cell_id]) * (1.0 - concentration_value)
			- float(sink_rate[cell_id]) * concentration_value
		)
		result[cell_id] += graph.cell_areas[cell_id] * (
			restoration_rate * (
				float(background_mana[cell_id]) - concentration_value
			) + forcing_rate
		)
	return result


static func solve(
		graph: SpatialGraph,
		background_mana: PackedFloat32Array,
		background_stability: PackedFloat32Array,
		faces: Dictionary,
		source_rate,
		sink_rate,
		settings: ArcaneEnvironmentSettings
) -> Dictionary:
	var concentration := PackedFloat64Array()
	concentration.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		concentration[cell_id] = background_mana[cell_id]
	var dt := _stable_dt(
		graph, background_stability, faces, source_rate, sink_rate, settings
	)
	var iterations := 0
	var final_delta := INF
	for iteration in MAX_ITERATIONS:
		var rate := amount_rate(
			graph, background_mana, background_stability, faces,
			source_rate, sink_rate, settings, concentration
		)
		final_delta = 0.0
		for cell_id in graph.cell_count():
			var delta := dt * rate[cell_id] / graph.cell_areas[cell_id]
			concentration[cell_id] += delta
			final_delta = maxf(final_delta, absf(delta))
		iterations = iteration + 1
		if final_delta <= DELTA_TOLERANCE:
			break
	var final_rate := amount_rate(
		graph, background_mana, background_stability, faces,
		source_rate, sink_rate, settings, concentration
	)
	return {
		"concentration": concentration,
		"iterations": iterations,
		"final_delta": final_delta,
		"residual_l_inf": _norm_l_inf(final_rate),
		"converged": final_delta <= DELTA_TOLERANCE,
	}


static func _stable_dt(
		graph: SpatialGraph,
		background_stability: PackedFloat32Array,
		faces: Dictionary,
		source_rate,
		sink_rate,
		settings: ArcaneEnvironmentSettings
) -> float:
	var removal := PackedFloat64Array()
	removal.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		removal[cell_id] = lerpf(
			settings.background_restoration_min_rate,
			settings.background_restoration_max_rate,
			background_stability[cell_id]
		) + float(source_rate[cell_id]) + float(sink_rate[cell_id])
	for face_index in faces.internal_a.size():
		var cell_a: int = faces.internal_a[face_index]
		var cell_b: int = faces.internal_b[face_index]
		var diffusion: float = faces.internal_diffusion[face_index]
		var velocity_length: float = faces.internal_velocity_length[face_index]
		removal[cell_a] += diffusion / graph.cell_areas[cell_a]
		removal[cell_b] += diffusion / graph.cell_areas[cell_b]
		if velocity_length >= 0.0:
			removal[cell_a] += velocity_length / graph.cell_areas[cell_a]
		else:
			removal[cell_b] -= velocity_length / graph.cell_areas[cell_b]
	for face_index in faces.boundary_cell.size():
		var cell_id: int = faces.boundary_cell[face_index]
		removal[cell_id] += faces.boundary_diffusion[face_index] \
				/ graph.cell_areas[cell_id]
		var velocity_length: float = faces.boundary_velocity_length[face_index]
		if velocity_length > 0.0:
			removal[cell_id] += velocity_length / graph.cell_areas[cell_id]
	var maximum_rate := 0.0
	for rate in removal:
		maximum_rate = maxf(maximum_rate, rate)
	return minf(MAX_DT, CFL_SAFETY / maximum_rate) if maximum_rate > 0.0 else MAX_DT


static func _norm_l_inf(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, absf(value))
	return result
