extends SceneTree

var _failures := PackedStringArray()
var _maximum_operator_error := 0.0
var _maximum_reference_mae := 0.0
var _maximum_reference_error := 0.0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_operator_rhs_equivalence()
	_test_restoration_only()
	_test_source_analytical()
	_test_sink_analytical()
	_test_diffusion_reference()
	_test_upwind_drift_reference()
	_test_open_boundary_reference()
	_test_full_synthetic_reference()
	_test_internal_face_conservation()
	print("Sparse steady-state calibration: ", {
		"maximum_operator_rhs_error": _maximum_operator_error,
		"maximum_explicit_reference_mae": _maximum_reference_mae,
		"maximum_explicit_reference_error": _maximum_reference_error,
	})
	_finish()


func _test_operator_rhs_equivalence() -> void:
	var fixture := _full_fixture()
	var build := _build_operator(fixture)
	_expect(build.errors.is_empty(), "full operator fixture must build")
	if not build.errors.is_empty():
		return
	var operator: ArcaneSteadyStateOperator = build.operator
	for concentration in [
		PackedFloat64Array([0.11, 0.37, 0.72, 0.93]),
		PackedFloat64Array([0.84, 0.22, 0.49, 0.06]),
		PackedFloat64Array([0.50, 0.50, 0.50, 0.50]),
	]:
		var old_rhs := ArcaneExplicitTransportReference.amount_rate(
			fixture.graph, fixture.background, fixture.stability, fixture.faces,
			fixture.source, fixture.sink, fixture.settings, concentration
		)
		var linear_rhs := PackedFloat64Array()
		linear_rhs.resize(concentration.size())
		operator.residual_into(concentration, linear_rhs)
		var error := _max_abs_difference(old_rhs, linear_rhs)
		_maximum_operator_error = maxf(_maximum_operator_error, error)
		_expect(error <= 0.0000000001,
			"old explicit RHS and b-A*C must agree to strict floating tolerance")


func _test_restoration_only() -> void:
	var graph := _isolated_graph(3)
	var fixture := _fixture(
		graph,
		PackedFloat32Array([0.13, 0.51, 0.88]),
		PackedFloat32Array([0.0, 0.5, 1.0]),
		_empty_faces(),
		PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0])
	)
	var result := _steady_solve(fixture)
	_expect(result.report.converged and not result.report.breakdown,
		"restoration-only BiCGSTAB must converge without breakdown")
	_expect(_max_abs_difference(result.concentration, fixture.background) <= 1.0e-12,
		"restoration-only steady state must be C=B")


func _test_source_analytical() -> void:
	var fixture := _single_cell_forcing_fixture(0.08, 0.0)
	var result := _steady_solve(fixture)
	var k := 0.09
	var expected := (k * 0.5 + 0.08) / (k + 0.08)
	_expect(result.report.converged and not result.report.breakdown,
		"Source-only BiCGSTAB must converge")
	_expect(absf(result.concentration[0] - expected) <= 1.0e-12,
		"Source-only steady state must match its analytical equilibrium")


func _test_sink_analytical() -> void:
	var fixture := _single_cell_forcing_fixture(0.0, 0.08)
	var result := _steady_solve(fixture)
	var k := 0.09
	var expected := k * 0.5 / (k + 0.08)
	_expect(result.report.converged and not result.report.breakdown,
		"Sink-only BiCGSTAB must converge")
	_expect(absf(result.concentration[0] - expected) <= 1.0e-12,
		"Sink-only steady state must match its analytical equilibrium")


func _test_diffusion_reference() -> void:
	var graph := _line_graph(3, false)
	var settings := ArcaneEnvironmentSettings.new()
	var faces := ArcaneEnvironmentGenerator.build_transport_faces(
		graph, _uniform_tensor(3, Vector3.ZERO), _uniform_drift(3, Vector2.ZERO),
		settings, false
	)
	var fixture := _fixture(
		graph,
		PackedFloat32Array([0.20, 0.45, 0.75]),
		PackedFloat32Array([0.3, 0.6, 0.9]),
		faces,
		PackedFloat64Array([0.12, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]),
		settings
	)
	_compare_with_explicit(fixture, "diffusion + restoration")


func _test_upwind_drift_reference() -> void:
	var graph := _line_graph(3, false)
	var settings := ArcaneEnvironmentSettings.new()
	settings.ambient_mana_diffusivity = 0.0
	var faces := ArcaneEnvironmentGenerator.build_transport_faces(
		graph, _uniform_tensor(3, Vector3.ZERO), _uniform_drift(3, Vector2(0.4, 0.0)),
		settings, false
	)
	var fixture := _fixture(
		graph,
		PackedFloat32Array([0.2, 0.2, 0.2]),
		PackedFloat32Array([0.5, 0.5, 0.5]),
		faces,
		PackedFloat64Array([0.0, 0.08, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]),
		settings
	)
	var result := _compare_with_explicit(fixture, "upwind drift")
	if not result.is_empty():
		_expect(result.concentration[2] - 0.2 > result.concentration[0] - 0.2,
			"positive upwind velocity must carry the Source anomaly downstream")


func _test_open_boundary_reference() -> void:
	var graph := _single_boundary_cell_graph()
	var settings := ArcaneEnvironmentSettings.new()
	var faces := ArcaneEnvironmentGenerator.build_transport_faces(
		graph,
		PackedVector3Array([Vector3(0.7, 0.1, 0.3)]),
		PackedVector2Array([Vector2(0.4, 0.0)]),
		settings,
		true
	)
	var fixture := _fixture(
		graph,
		PackedFloat32Array([0.6]),
		PackedFloat32Array([0.5]),
		faces,
		PackedFloat64Array([0.08]),
		PackedFloat64Array([0.0]),
		settings
	)
	_compare_with_explicit(fixture, "open boundary")


func _test_full_synthetic_reference() -> void:
	_compare_with_explicit(_full_fixture(), "full synthetic")


func _test_internal_face_conservation() -> void:
	var graph := _line_graph(3, false)
	var settings := ArcaneEnvironmentSettings.new()
	settings.background_restoration_min_rate = 0.0
	settings.background_restoration_max_rate = 0.0
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	var concentration := PackedFloat64Array([0.8, 0.3, 0.1])
	for drift in [Vector2.ZERO, Vector2(0.4, 0.0)]:
		var local_settings := settings.duplicate_settings()
		if drift != Vector2.ZERO:
			local_settings.ambient_mana_diffusivity = 0.0
		var faces := ArcaneEnvironmentGenerator.build_transport_faces(
			graph, _uniform_tensor(3, Vector3.ZERO), _uniform_drift(3, drift),
			local_settings, false
		)
		var rate := ArcaneExplicitTransportReference.amount_rate(
			graph,
			PackedFloat32Array([0.2, 0.2, 0.2]),
			PackedFloat32Array([0.5, 0.5, 0.5]),
			faces, zero, zero, local_settings, concentration
		)
		var total_rate := 0.0
		for value in rate:
			total_rate += value
		_expect(absf(total_rate) <= 1.0e-12,
			"internal diffusion/drift face flux must remain pairwise conservative")


func _compare_with_explicit(fixture: Dictionary, label: String) -> Dictionary:
	var explicit := ArcaneExplicitTransportReference.solve(
		fixture.graph, fixture.background, fixture.stability, fixture.faces,
		fixture.source, fixture.sink, fixture.settings
	)
	var steady := _steady_solve(fixture)
	_expect(explicit.converged,
		"%s explicit reference must reach high accuracy" % label)
	_expect(steady.report.converged and not steady.report.breakdown,
		"%s BiCGSTAB must converge without breakdown" % label)
	if not explicit.converged or not steady.report.converged:
		return {}
	var mae := _mean_abs_difference(steady.concentration, explicit.concentration)
	var maximum := _max_abs_difference(steady.concentration, explicit.concentration)
	_maximum_reference_mae = maxf(_maximum_reference_mae, mae)
	_maximum_reference_error = maxf(_maximum_reference_error, maximum)
	_expect(mae <= 0.00001 and maximum <= 0.0001,
		"%s steady-state result must match the high-accuracy explicit reference" % label)
	return steady


func _steady_solve(fixture: Dictionary) -> Dictionary:
	var build := _build_operator(fixture)
	_expect(build.errors.is_empty(), "steady-state operator diagonal must be valid")
	if not build.errors.is_empty():
		return {"concentration": PackedFloat64Array(), "report": {
			"converged": false, "breakdown": true,
		}}
	var initial := PackedFloat64Array()
	initial.resize(fixture.graph.cell_count())
	for cell_id in fixture.graph.cell_count():
		initial[cell_id] = fixture.background[cell_id]
	return ArcaneBiCGSTABSolver.solve(build.operator, initial)


func _build_operator(fixture: Dictionary) -> Dictionary:
	return ArcaneEnvironmentGenerator.build_steady_state_operator(
		fixture.graph, fixture.background, fixture.stability,
		fixture.source, fixture.sink, fixture.settings, fixture.faces
	)


func _full_fixture() -> Dictionary:
	var graph := _square_graph_with_boundary()
	var settings := ArcaneEnvironmentSettings.new()
	var tensor := PackedVector3Array([
		Vector3(0.8, 0.1, 0.2), Vector3(0.4, -0.1, 0.7),
		Vector3(0.6, 0.2, 0.5), Vector3(0.3, 0.0, 0.9),
	])
	var drift := PackedVector2Array([
		Vector2(0.30, 0.10), Vector2(0.45, -0.05),
		Vector2(-0.20, 0.35), Vector2(0.10, 0.25),
	])
	var faces := ArcaneEnvironmentGenerator.build_transport_faces(
		graph, tensor, drift, settings, true
	)
	return _fixture(
		graph,
		PackedFloat32Array([0.18, 0.42, 0.67, 0.81]),
		PackedFloat32Array([0.15, 0.45, 0.70, 0.95]),
		faces,
		PackedFloat64Array([0.10, 0.0, 0.03, 0.0]),
		PackedFloat64Array([0.0, 0.06, 0.0, 0.02]),
		settings
	)


func _single_cell_forcing_fixture(source: float, sink: float) -> Dictionary:
	var settings := ArcaneEnvironmentSettings.new()
	settings.background_restoration_min_rate = 0.09
	settings.background_restoration_max_rate = 0.09
	return _fixture(
		_isolated_graph(1), PackedFloat32Array([0.5]), PackedFloat32Array([0.5]),
		_empty_faces(), PackedFloat64Array([source]), PackedFloat64Array([sink]),
		settings
	)


func _fixture(
		graph: SpatialGraph,
		background: PackedFloat32Array,
		stability: PackedFloat32Array,
		faces: Dictionary,
		source: PackedFloat64Array,
		sink: PackedFloat64Array,
		settings: ArcaneEnvironmentSettings = null
) -> Dictionary:
	return {
		"graph": graph,
		"background": background,
		"stability": stability,
		"faces": faces,
		"source": source,
		"sink": sink,
		"settings": settings if settings != null else ArcaneEnvironmentSettings.new(),
	}


func _empty_faces() -> Dictionary:
	return {
		"internal_a": PackedInt32Array(),
		"internal_b": PackedInt32Array(),
		"internal_diffusion": PackedFloat64Array(),
		"internal_velocity_length": PackedFloat64Array(),
		"boundary_cell": PackedInt32Array(),
		"boundary_diffusion": PackedFloat64Array(),
		"boundary_velocity_length": PackedFloat64Array(),
	}


func _isolated_graph(count: int) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.cell_centers.resize(count)
	graph.cell_areas.resize(count)
	graph.cell_neighbors.resize(count)
	for cell_id in count:
		graph.cell_centers[cell_id] = Vector2(cell_id * 10.0, 0.0)
		graph.cell_areas[cell_id] = 100.0 + cell_id * 30.0
		graph.cell_neighbors[cell_id] = PackedInt32Array()
	return graph


func _line_graph(count: int, with_boundary: bool) -> SpatialGraph:
	var graph := _isolated_graph(count)
	for cell_id in count - 1:
		_add_face(
			graph, PackedInt32Array([cell_id, cell_id + 1]),
			Vector2((cell_id + 0.5) * 10.0, 0.0), Vector2(0.0, 5.0)
		)
		graph.cell_neighbors[cell_id].append(cell_id + 1)
		graph.cell_neighbors[cell_id + 1].append(cell_id)
	if with_boundary:
		_add_face(graph, PackedInt32Array([0]), Vector2(-5.0, 0.0), Vector2(0.0, 5.0))
		_add_face(
			graph, PackedInt32Array([count - 1]),
			Vector2((count - 0.5) * 10.0, 0.0), Vector2(0.0, 5.0)
		)
	return graph


func _single_boundary_cell_graph() -> SpatialGraph:
	var graph := _isolated_graph(1)
	_add_face(graph, PackedInt32Array([0]), Vector2(5.0, 0.0), Vector2(0.0, 5.0))
	return graph


func _square_graph_with_boundary() -> SpatialGraph:
	var graph := _isolated_graph(4)
	graph.cell_centers = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(10.0, 0.0),
		Vector2(0.0, 10.0), Vector2(10.0, 10.0),
	])
	graph.cell_areas = PackedFloat64Array([100.0, 120.0, 90.0, 110.0])
	for pair in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 3), Vector2i(2, 3)]:
		var midpoint := 0.5 * (
			graph.cell_centers[pair.x] + graph.cell_centers[pair.y]
		)
		var half_face := (graph.cell_centers[pair.y] - graph.cell_centers[pair.x]) \
				.normalized().orthogonal() * 5.0
		_add_face(graph, PackedInt32Array([pair.x, pair.y]), midpoint, half_face)
		graph.cell_neighbors[pair.x].append(pair.y)
		graph.cell_neighbors[pair.y].append(pair.x)
	for boundary in [
		[0, Vector2(-5.0, 0.0), Vector2(0.0, 5.0)],
		[1, Vector2(15.0, 0.0), Vector2(0.0, 5.0)],
		[2, Vector2(0.0, 15.0), Vector2(5.0, 0.0)],
		[3, Vector2(10.0, 15.0), Vector2(5.0, 0.0)],
	]:
		_add_face(graph, PackedInt32Array([boundary[0]]), boundary[1], boundary[2])
	return graph


func _add_face(
		graph: SpatialGraph,
		cells: PackedInt32Array,
		midpoint: Vector2,
		half_face: Vector2
) -> void:
	var first_vertex := graph.vertex_positions.size()
	graph.vertex_positions.append(midpoint - half_face)
	graph.vertex_positions.append(midpoint + half_face)
	graph.edge_vertex_ids.append(Vector2i(first_vertex, first_vertex + 1))
	graph.edge_cells.append(cells)


func _uniform_tensor(count: int, value: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(count)
	result.fill(value)
	return result


func _uniform_drift(count: int, value: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(count)
	result.fill(value)
	return result


func _mean_abs_difference(first, second) -> float:
	var result := 0.0
	for index in first.size():
		result += absf(float(first[index]) - float(second[index]))
	return result / float(first.size()) if first.size() > 0 else 0.0


func _max_abs_difference(first, second) -> float:
	var result := 0.0
	for index in first.size():
		result = maxf(result, absf(float(first[index]) - float(second[index])))
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Sparse steady-state Arcane Solver: all 9 targeted groups passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	printerr("Sparse steady-state Arcane Solver: %d failures" % _failures.size())
	quit(1)
