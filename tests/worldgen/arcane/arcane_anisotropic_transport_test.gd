extends SceneTree

const BACKGROUND := 0.2
const CORE_RADIUS := 30.0
const TOTAL_POWER := 70.0

var _failures := PackedStringArray()
var _calibration := {}


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_directional_diffusivity()
	_test_junction_tensor_is_bounded()
	_test_ambient_propagation_length()
	_test_passive_leyline_anisotropy()
	_test_active_leyline_drift()
	_test_near_but_not_on_leyline_capture()
	_test_anisotropic_diffusion_conservation()
	_test_drift_conservation()
	_test_background_equilibrium_invariant()
	_test_face_cache_and_cfl()
	print("Leyline anisotropic calibration: ", _calibration)
	_finish()


func _test_directional_diffusivity() -> void:
	var settings := ArcaneEnvironmentSettings.new()
	var horizontal_tensor := Vector3(1.0, 0.0, 0.0)
	var parallel := ArcaneEnvironmentGenerator.directional_diffusivity(
		horizontal_tensor, Vector2.RIGHT, settings
	)
	var perpendicular := ArcaneEnvironmentGenerator.directional_diffusivity(
		horizontal_tensor, Vector2.DOWN, settings
	)
	var diagonal := ArcaneEnvironmentGenerator.directional_diffusivity(
		horizontal_tensor, Vector2(1.0, 1.0), settings
	)
	_expect(absf(parallel - 504.0) < 0.000001,
		"a parallel face must receive full Leyline diffusivity")
	_expect(absf(perpendicular - 56.0) < 0.000001,
		"a perpendicular face must stay at ambient diffusivity")
	_expect(absf(diagonal - 280.0) < 0.0001,
		"45-degree alignment must continuously interpolate diffusivity")


func _test_junction_tensor_is_bounded() -> void:
	var tensor := Vector3.ZERO
	for degrees in [0.0, 120.0, 240.0]:
		var tangent := Vector2.from_angle(deg_to_rad(degrees))
		tensor += Vector3(
			tangent.x * tangent.x, tangent.x * tangent.y, tangent.y * tangent.y
		)
	var normalized := ArcaneEnvironmentGenerator.normalize_transport_tensor(tensor)
	var maximum_eigenvalue := ArcaneEnvironmentGenerator.tensor_max_eigenvalue(normalized)
	_expect(maximum_eigenvalue <= 1.0000001,
		"three crossing Leylines must not exceed the normalized tensor bound")
	_expect(ArcaneEnvironmentGenerator.tensor_alignment(normalized, Vector2.RIGHT) > 0.9
			and ArcaneEnvironmentGenerator.tensor_alignment(normalized, Vector2.DOWN) > 0.9,
		"a normalized Junction tensor must retain conductivity in multiple directions")


func _test_ambient_propagation_length() -> void:
	var simulation := _simulate_grid(
		410.0, 410.0, 10.0, Vector2(205.0, 205.0), -1.0, 0.0
	)
	var distance := _axis_extent(
		simulation, Vector2(205.0, 205.0), Vector2.RIGHT
	)
	_calibration["ambient_distance"] = distance
	_calibration["ambient_solver"] = simulation.result.report
	_expect(distance >= 20.0 and distance <= 40.0,
		"ambient 20%-peak propagation must be approximately 20..40 world units")
	_expect(simulation.result.report.converged,
		"ambient calibration must reach equilibrium")


func _test_passive_leyline_anisotropy() -> void:
	var simulation := _simulate_grid(
		810.0, 410.0, 10.0, Vector2(405.0, 205.0), 205.0, 0.0
	)
	var longitudinal := _axis_extent(
		simulation, Vector2(405.0, 205.0), Vector2.RIGHT
	)
	var perpendicular := _axis_extent(
		simulation, Vector2(405.0, 205.0), Vector2.DOWN
	)
	var ratio := longitudinal / maxf(perpendicular, 0.000001)
	_calibration["passive_longitudinal_distance"] = longitudinal
	_calibration["passive_perpendicular_distance"] = perpendicular
	_calibration["passive_ratio"] = ratio
	_calibration["passive_solver"] = simulation.result.report
	_expect(longitudinal >= 60.0 and longitudinal <= 100.0,
		"passive Leyline longitudinal propagation must be approximately 60..100 units")
	_expect(perpendicular >= 20.0 and perpendicular <= 40.0,
		"passive Leyline perpendicular propagation must remain approximately 20..40 units")
	_expect(ratio >= 2.0,
		"passive Leyline longitudinal/perpendicular propagation ratio must be at least two")
	_expect(simulation.result.report.converged,
		"passive Leyline calibration must reach equilibrium")


func _test_active_leyline_drift() -> void:
	var simulation := _simulate_grid(
		810.0, 410.0, 10.0, Vector2(405.0, 205.0), 205.0, 0.25
	)
	var downstream := _axis_extent(
		simulation, Vector2(405.0, 205.0), Vector2.RIGHT
	)
	var upstream := _axis_extent(
		simulation, Vector2(405.0, 205.0), Vector2.LEFT
	)
	_calibration["active_downstream_distance"] = downstream
	_calibration["active_upstream_distance"] = upstream
	_calibration["active_solver"] = simulation.result.report
	_expect(downstream >= 150.0 and downstream <= 300.0,
		"edge_flow 0.25 downstream propagation must be approximately 150..300 units")
	_expect(upstream < downstream,
		"active Leyline upstream propagation must be shorter than downstream")
	_expect(simulation.result.report.converged,
		"active Leyline calibration must reach equilibrium")


func _test_near_but_not_on_leyline_capture() -> void:
	var source_position := Vector2(405.0, 235.0)
	var captured := _simulate_grid(
		810.0, 410.0, 10.0, source_position, 205.0, 0.25
	)
	var ambient := _simulate_grid(
		810.0, 410.0, 10.0, source_position, -1.0, 0.0
	)
	var downstream_point := Vector2(605.0, 205.0)
	var captured_anomaly := _anomaly_at(captured, downstream_point)
	var ambient_anomaly := _anomaly_at(ambient, downstream_point)
	_calibration["near_leyline_source_distance"] = absf(source_position.y - 205.0)
	_calibration["near_leyline_downstream_anomaly"] = captured_anomaly
	_calibration["near_leyline_ambient_comparison"] = ambient_anomaly
	_expect(absf(source_position.y - 205.0) >= 25.0
			and absf(source_position.y - 205.0) <= 35.0,
		"near-Leyline Source must remain 25..35 units off the line without snapping")
	_expect(captured_anomaly > ambient_anomaly * 5.0 and captured_anomaly > 0.0001,
		"ordinary diffusion must feed an off-line Source anomaly into long-range Web transport")
	_expect(captured.result.report.converged and ambient.result.report.converged,
		"near-Leyline capture comparisons must both reach equilibrium")


func _test_anisotropic_diffusion_conservation() -> void:
	var graph := _two_cell_graph()
	var settings := _closed_transport_settings(1)
	var initial := PackedFloat64Array([0.8, 0.2])
	var tensor := PackedVector3Array([
		Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
	])
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([BACKGROUND, BACKGROUND]),
		PackedFloat32Array([0.5, 0.5]),
		tensor,
		PackedVector2Array([Vector2.ZERO, Vector2.ZERO]),
		PackedFloat64Array([0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0]),
		settings,
		initial,
		false
	)
	_expect(absf(_total_mass(graph, result.concentration) - _total_mass(graph, initial))
			< 0.0000001,
		"anisotropic internal diffusion must remain pairwise mass-conservative")


func _test_drift_conservation() -> void:
	var graph := _two_cell_graph()
	var settings := _closed_transport_settings(8)
	settings.ambient_mana_diffusivity = 0.0
	var initial := PackedFloat64Array([0.8, 0.2])
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([BACKGROUND, BACKGROUND]),
		PackedFloat32Array([0.5, 0.5]),
		_zero_tensor(graph),
		PackedVector2Array([Vector2(20.0, 0.0), Vector2(20.0, 0.0)]),
		PackedFloat64Array([0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0]),
		settings,
		initial,
		false
	)
	_expect(absf(_total_mass(graph, result.concentration) - _total_mass(graph, initial))
			< 0.0000001,
		"internal upwind Drift must remain pairwise mass-conservative")


func _test_background_equilibrium_invariant() -> void:
	var graph := _two_cell_graph()
	var background := PackedFloat32Array([0.1, 0.9])
	var tensor := PackedVector3Array([
		Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
	])
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		background,
		PackedFloat32Array([0.5, 0.5]),
		tensor,
		PackedVector2Array([Vector2.ZERO, Vector2.ZERO]),
		PackedFloat64Array([0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0]),
		ArcaneEnvironmentSettings.new(),
		PackedFloat64Array(),
		false
	)
	_expect(_approximately_equal(result.concentration, background, 0.0000001),
		"nonuniform C=B must remain invariant under anisotropic mu diffusion")


func _test_face_cache_and_cfl() -> void:
	var graph := _two_cell_graph()
	var settings := ArcaneEnvironmentSettings.new()
	var tensor := PackedVector3Array([
		Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
	])
	var faces := ArcaneEnvironmentGenerator.build_transport_faces(
		graph, tensor, PackedVector2Array([Vector2.ZERO, Vector2.ZERO]), settings, false
	)
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		PackedFloat32Array([BACKGROUND, BACKGROUND]),
		PackedFloat32Array([0.5, 0.5]),
		tensor,
		PackedVector2Array([Vector2.ZERO, Vector2.ZERO]),
		PackedFloat64Array([0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0]),
		settings,
		PackedFloat64Array([0.8, 0.2]),
		false,
		faces
	)
	_expect(absf(faces.face_diffusivity[0] - 504.0) < 0.000001,
		"face cache must store the directional physical diffusivity")
	_expect(result.report.dt < settings.solver_max_dt,
		"anisotropic face conductance must constrain the CFL timestep")


func _simulate_grid(
		width: float,
		height: float,
		spacing: float,
		source_position: Vector2,
		leyline_y: float,
		edge_flow: float
) -> Dictionary:
	var graph := _regular_grid_graph(width, height, spacing)
	var web := ArcaneWebLayer.new()
	var circulation := ArcaneCirculationLayer.new()
	if leyline_y >= 0.0:
		web.world_width = width
		web.world_height = height
		web.nodes = [
			ArcaneWebNode.new(0, Vector2(0.0, leyline_y), ArcaneWebNode.Kind.BOUNDARY_EXIT),
			ArcaneWebNode.new(1, Vector2(width, leyline_y), ArcaneWebNode.Kind.BOUNDARY_EXIT),
		]
		web.edges = [ArcaneWebEdge.new(0, 0, 1, width)]
		web.rebuild_incidence()
		circulation.edge_flow = PackedFloat32Array([edge_flow])
	var forcing := ArcaneForcingLayer.new()
	forcing.sites.append(ArcaneForcingSite.new(
		0, source_position, ArcaneForcingSite.Kind.SOURCE, CORE_RADIUS, TOTAL_POWER
	))
	ArcaneForcingGenerator.project_rates(graph, forcing, ArcaneForcingSettings.new())
	var settings := ArcaneEnvironmentSettings.new()
	settings.background_restoration_min_rate = 0.09
	settings.background_restoration_max_rate = 0.09
	var projection := ArcaneEnvironmentGenerator.project_leyline_transport(
		graph, web, circulation, settings
	)
	var background := PackedFloat32Array()
	background.resize(graph.cell_count())
	background.fill(BACKGROUND)
	var stability := PackedFloat32Array()
	stability.resize(graph.cell_count())
	stability.fill(0.5)
	var result := ArcaneEnvironmentGenerator.solve_transport(
		graph,
		background,
		stability,
		projection.transport_tensor,
		projection.drift_field,
		forcing.source_rate,
		forcing.sink_rate,
		settings,
		PackedFloat64Array(),
		true
	)
	return {
		"graph": graph,
		"spacing": spacing,
		"background": background,
		"result": result,
	}


func _axis_extent(
		simulation: Dictionary, origin: Vector2, direction: Vector2
) -> float:
	var graph: SpatialGraph = simulation.graph
	var normalized_direction := direction.normalized()
	var spacing: float = simulation.spacing
	var peak := 0.0
	for cell_id in graph.cell_count():
		var delta := graph.cell_centers[cell_id] - origin
		var signed_distance := delta.dot(normalized_direction)
		var perpendicular_distance := absf(delta.cross(normalized_direction))
		if signed_distance < CORE_RADIUS \
				or signed_distance >= CORE_RADIUS + spacing \
				or perpendicular_distance > 0.001:
			continue
		peak = maxf(peak, absf(
			float(simulation.result.concentration[cell_id])
					- float(simulation.background[cell_id])
		))
	var threshold := peak * 0.20
	var extent := 0.0
	for cell_id in graph.cell_count():
		var delta := graph.cell_centers[cell_id] - origin
		var signed_distance := delta.dot(normalized_direction)
		var perpendicular_distance := absf(delta.cross(normalized_direction))
		if signed_distance < CORE_RADIUS or perpendicular_distance > 0.001:
			continue
		var anomaly := absf(
			float(simulation.result.concentration[cell_id])
					- float(simulation.background[cell_id])
		)
		if anomaly >= threshold:
			extent = maxf(extent, signed_distance - CORE_RADIUS)
	return extent


func _anomaly_at(simulation: Dictionary, position: Vector2) -> float:
	var graph: SpatialGraph = simulation.graph
	var cell_id := _nearest_cell(graph, position)
	return absf(
		float(simulation.result.concentration[cell_id])
				- float(simulation.background[cell_id])
	)


func _nearest_cell(graph: SpatialGraph, position: Vector2) -> int:
	var nearest := -1
	var nearest_distance := INF
	for cell_id in graph.cell_count():
		var distance := graph.cell_centers[cell_id].distance_squared_to(position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = cell_id
	return nearest


func _regular_grid_graph(width: float, height: float, spacing: float) -> SpatialGraph:
	var columns := roundi(width / spacing)
	var rows := roundi(height / spacing)
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(1, width, height, columns * rows, 0.9)
	graph.columns = columns
	graph.rows = rows
	graph.spacing = spacing
	graph.cell_centers.resize(columns * rows)
	graph.cell_areas.resize(columns * rows)
	graph.cell_neighbors.resize(columns * rows)
	for cell_id in columns * rows:
		graph.cell_neighbors[cell_id] = PackedInt32Array()
	for row in rows:
		for column in columns:
			var cell_id := row * columns + column
			graph.cell_centers[cell_id] = Vector2(
				(column + 0.5) * spacing, (row + 0.5) * spacing
			)
			graph.cell_areas[cell_id] = spacing * spacing
			if column + 1 < columns:
				_add_grid_face(graph, cell_id, cell_id + 1, Vector2(
					(column + 1.0) * spacing, (row + 0.5) * spacing
				), Vector2(0.0, spacing * 0.5))
			if row + 1 < rows:
				_add_grid_face(graph, cell_id, cell_id + columns, Vector2(
					(column + 0.5) * spacing, (row + 1.0) * spacing
				), Vector2(spacing * 0.5, 0.0))
	for row in rows:
		_add_boundary_face(
			graph, row * columns, Vector2(0.0, (row + 0.5) * spacing),
			Vector2(0.0, spacing * 0.5)
		)
		_add_boundary_face(
			graph, row * columns + columns - 1,
			Vector2(width, (row + 0.5) * spacing),
			Vector2(0.0, spacing * 0.5)
		)
	for column in columns:
		_add_boundary_face(
			graph, column, Vector2((column + 0.5) * spacing, 0.0),
			Vector2(spacing * 0.5, 0.0)
		)
		_add_boundary_face(
			graph, (rows - 1) * columns + column,
			Vector2((column + 0.5) * spacing, height),
			Vector2(spacing * 0.5, 0.0)
		)
	return graph


func _add_grid_face(
		graph: SpatialGraph,
		cell_a: int,
		cell_b: int,
		midpoint: Vector2,
		half_face: Vector2
) -> void:
	var first_vertex := graph.vertex_positions.size()
	graph.vertex_positions.append(midpoint - half_face)
	graph.vertex_positions.append(midpoint + half_face)
	graph.edge_vertex_ids.append(Vector2i(first_vertex, first_vertex + 1))
	graph.edge_cells.append(PackedInt32Array([cell_a, cell_b]))
	graph.cell_neighbors[cell_a].append(cell_b)
	graph.cell_neighbors[cell_b].append(cell_a)


func _add_boundary_face(
		graph: SpatialGraph, cell_id: int, midpoint: Vector2, half_face: Vector2
) -> void:
	var first_vertex := graph.vertex_positions.size()
	graph.vertex_positions.append(midpoint - half_face)
	graph.vertex_positions.append(midpoint + half_face)
	graph.edge_vertex_ids.append(Vector2i(first_vertex, first_vertex + 1))
	graph.edge_cells.append(PackedInt32Array([cell_id]))


func _two_cell_graph() -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.cell_centers = PackedVector2Array([Vector2.ZERO, Vector2(10.0, 0.0)])
	graph.cell_areas = PackedFloat64Array([100.0, 100.0])
	graph.vertex_positions = PackedVector2Array([
		Vector2(5.0, -5.0), Vector2(5.0, 5.0),
	])
	graph.edge_vertex_ids = [Vector2i(0, 1)]
	graph.edge_cells = [PackedInt32Array([0, 1])]
	graph.cell_neighbors = [PackedInt32Array([1]), PackedInt32Array([0])]
	return graph


func _closed_transport_settings(iterations: int) -> ArcaneEnvironmentSettings:
	var settings := ArcaneEnvironmentSettings.new()
	settings.background_restoration_min_rate = 0.0
	settings.background_restoration_max_rate = 0.0
	settings.solver_max_iterations = iterations
	settings.solver_convergence_epsilon = 0.000000000001
	return settings


func _zero_tensor(graph: SpatialGraph) -> PackedVector3Array:
	var tensor := PackedVector3Array()
	tensor.resize(graph.cell_count())
	return tensor


func _total_mass(graph: SpatialGraph, concentration) -> float:
	var total := 0.0
	for cell_id in graph.cell_count():
		total += graph.cell_areas[cell_id] * float(concentration[cell_id])
	return total


func _approximately_equal(first, second, tolerance: float) -> bool:
	if first.size() != second.size():
		return false
	for index in first.size():
		if absf(float(first[index]) - float(second[index])) > tolerance:
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Leyline Anisotropic Transport: all 10 test groups passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	printerr("Leyline Anisotropic Transport: %d failures" % _failures.size())
	quit(1)
