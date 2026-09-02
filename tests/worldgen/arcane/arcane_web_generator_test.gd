extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_settings_seed_domain_and_generated_validity()
	_test_determinism_and_different_seed()
	_test_resolution_independence()
	_test_poisson_separation()
	_test_power_diagram_correctness_and_weight_effect()
	_test_boundary_cropping_excludes_world_rectangle()
	_test_topology()
	_test_structural_importance()
	_test_layer_incidence_query()
	_print_seed_one_statistics()
	_finish()


func _test_settings_seed_domain_and_generated_validity() -> void:
	_expect(ArcaneWebGenerator.ARCANE_WEB_SEED_SALT == 0x41574542,
		"Arcane Web must use the stable AWEB seed salt")
	_expect(ArcaneWebGenerator.BRIDSON_CANDIDATES == 30,
		"Bridson sampling must use fixed k=30")
	_expect(ArcaneWebGenerator.WEIGHT_RADIUS_MIN_FACTOR == 0.15
			and ArcaneWebGenerator.WEIGHT_RADIUS_MAX_FACTOR == 1.00,
		"Power weight radius factors must remain fixed at 0.15..1.00")
	var settings := ArcaneWebSettings.new()
	_expect(settings.web_generation_margin == 300.0,
		"default generation margin must be 300 world units")
	_expect(settings.web_nucleus_min_separation == 170.0,
		"default nucleus separation must be 170 world units")
	_expect(settings.validate().is_empty(), "default Arcane Web settings should validate")
	settings.web_generation_margin = NAN
	settings.web_nucleus_min_separation = 0.0
	_expect(settings.validate().size() == 2, "settings should reject invalid formal parameters")
	var layer := ArcaneWebGenerator.generate(1, 800.0, 400.0)
	_expect(layer != null, "fixed Arcane Web fixture should generate")
	if layer != null:
		_expect(ArcaneWebValidator.validate(layer).is_empty(),
			"generated Arcane Web should pass its Validator")
		_expect(not layer.domains.is_empty() and not layer.nodes.is_empty()
				and not layer.edges.is_empty(), "generated Arcane Web should contain formal output")


func _test_determinism_and_different_seed() -> void:
	var first := ArcaneWebGenerator.generate(202, 900.0, 500.0)
	var repeat := ArcaneWebGenerator.generate(202, 900.0, 500.0)
	var other := ArcaneWebGenerator.generate(203, 900.0, 500.0)
	_expect(first != null and repeat != null and other != null,
		"determinism fixtures should generate")
	if first == null or repeat == null or other == null:
		return
	_expect(_web_signature(first) == _web_signature(repeat),
		"same Seed + World Extent must reproduce nuclei/domains/nodes/edges/importance")
	_expect(_web_signature(first) != _web_signature(other),
		"different World Seed must change Arcane Web geometry")


func _test_resolution_independence() -> void:
	var coarse := SpatialConfig.new(31337, 1000.0, 600.0, 400, 0.9)
	var dense := SpatialConfig.new(31337, 1000.0, 600.0, 4000, 0.9)
	var coarse_web := ArcaneWebGenerator.generate(
		coarse.seed, coarse.world_width, coarse.world_height
	)
	var dense_web := ArcaneWebGenerator.generate(
		dense.seed, dense.world_width, dense.world_height
	)
	_expect(coarse_web != null and dense_web != null,
		"resolution independence fixtures should generate")
	if coarse_web != null and dense_web != null:
		_expect(_web_signature(coarse_web) == _web_signature(dense_web),
			"SpatialGraph cell count/resolution must not affect Arcane Web")


func _test_poisson_separation() -> void:
	var settings := ArcaneWebSettings.new()
	var generation_rect := Rect2(
		Vector2(-settings.web_generation_margin, -settings.web_generation_margin),
		Vector2(1600.0, 1100.0)
	)
	var nuclei := ArcaneWebGenerator.sample_weighted_nuclei(
		404, generation_rect, settings.web_nucleus_min_separation
	)
	_expect(nuclei.size() > 10, "Poisson fixture should produce a world-scale nucleus set")
	for first_index in nuclei.size():
		for second_index in range(first_index + 1, nuclei.size()):
			_expect(
				nuclei[first_index].position.distance_to(nuclei[second_index].position)
						>= settings.web_nucleus_min_separation - 0.0001,
				"all generated nuclei must satisfy the 170-unit Poisson separation"
			)
		if first_index > 0:
			var previous: Vector2 = nuclei[first_index - 1].position
			var current: Vector2 = nuclei[first_index].position
			_expect(previous.x < current.x or (previous.x == current.x and previous.y <= current.y),
				"nuclei must use stable x/y ordering")
		var radius := sqrt(float(nuclei[first_index].weight))
		_expect(radius >= 170.0 * 0.15 and radius < 170.0 * 1.00,
			"nucleus weight radius must use the fixed deterministic range")


func _test_power_diagram_correctness_and_weight_effect() -> void:
	var positions := PackedVector2Array([Vector2(25.0, 50.0), Vector2(75.0, 50.0)])
	var equal_weights := PackedFloat64Array([0.0, 0.0])
	var rect := Rect2(Vector2.ZERO, Vector2(100.0, 100.0))
	var first_cell := ArcaneWebGenerator.build_power_cell(positions, equal_weights, 0, rect)
	var second_cell := ArcaneWebGenerator.build_power_cell(positions, equal_weights, 1, rect)
	_expect(not first_cell.is_empty() and not second_cell.is_empty(),
		"artificial Power Cells should generate")
	for point in first_cell:
		_expect(ArcaneWebGenerator.power_value(point, positions[0], equal_weights[0])
				<= ArcaneWebGenerator.power_value(point, positions[1], equal_weights[1]) + 0.0001,
			"first Power Cell must satisfy the formal minimum power definition")
	for point in second_cell:
		_expect(ArcaneWebGenerator.power_value(point, positions[1], equal_weights[1])
				<= ArcaneWebGenerator.power_value(point, positions[0], equal_weights[0]) + 0.0001,
			"second Power Cell must satisfy the formal minimum power definition")
	_expect(is_equal_approx(_maximum_x(first_cell), 50.0),
		"equal weights should place the bisector at x=50")

	var weighted := PackedFloat64Array([1000.0, 0.0])
	var larger_cell := ArcaneWebGenerator.build_power_cell(positions, weighted, 0, rect)
	_expect(_maximum_x(larger_cell) > _maximum_x(first_cell),
		"a higher Power Weight must enlarge that nucleus influence region")


func _test_boundary_cropping_excludes_world_rectangle() -> void:
	var positions := PackedVector2Array([Vector2(25.0, 50.0), Vector2(75.0, 50.0)])
	var weights := PackedFloat64Array([0.0, 0.0])
	var segment := ArcaneWebGenerator.power_bisector_segment(
		positions,
		weights,
		0,
		1,
		Rect2(Vector2(-100.0, -100.0), Vector2(300.0, 300.0)),
		Rect2(Vector2.ZERO, Vector2(100.0, 100.0))
	)
	_expect(segment.size() == 2, "true artificial bisector should survive world cropping")
	if segment.size() == 2:
		_expect(is_equal_approx(segment[0].x, 50.0) and is_equal_approx(segment[1].x, 50.0),
			"cropped Leyline should remain on the true Power bisector")
		_expect((is_equal_approx(segment[0].y, 0.0) and is_equal_approx(segment[1].y, 100.0))
				or (is_equal_approx(segment[1].y, 0.0) and is_equal_approx(segment[0].y, 100.0)),
			"true Leyline should stop exactly where it exits the World Extent")
	var layer := ArcaneWebGenerator.generate(505, 900.0, 500.0)
	_expect(layer != null, "boundary fixture should generate")
	if layer != null:
		for edge in layer.edges:
			var first := layer.nodes[edge.node_a_id].world_position
			var second := layer.nodes[edge.node_b_id].world_position
			_expect(not _lies_on_border(first, second, layer.world_width, layer.world_height),
				"World Rectangle clipping edges must never become Ley Edges")


func _test_topology() -> void:
	var layer := ArcaneWebGenerator.generate(606, 1200.0, 700.0)
	_expect(layer != null, "topology fixture should generate")
	if layer == null:
		return
	var degree := PackedInt32Array()
	degree.resize(layer.nodes.size())
	for edge in layer.edges:
		degree[edge.node_a_id] += 1
		degree[edge.node_b_id] += 1
	var junction_count := 0
	var degree_three_junctions := 0
	for node in layer.nodes:
		if node.kind == ArcaneWebNode.Kind.BOUNDARY_EXIT:
			_expect(degree[node.id] >= 1, "Boundary Exit may terminate a cropped true Leyline")
		else:
			junction_count += 1
			if degree[node.id] == 3:
				degree_three_junctions += 1
			_expect(degree[node.id] >= 3, "internal Power Diagram vertices must be Junctions")
	_expect(junction_count > 0 and degree_three_junctions * 10 >= junction_count * 9,
		"at least 90% of internal Junctions should be true three-way vertices")
	var stats := ArcaneWebValidator.statistics(layer)
	_expect(stats.cycle_rank > 0, "visible Arcane Web should contain natural closed loops")


func _test_structural_importance() -> void:
	var edges: Array[ArcaneWebEdge] = [
		ArcaneWebEdge.new(0, 0, 1, 1.0),
		ArcaneWebEdge.new(1, 1, 2, 1.0),
		ArcaneWebEdge.new(2, 2, 3, 1.0),
	]
	var result := ArcaneWebCentrality.calculate(4, edges)
	var nodes: PackedFloat64Array = result.nodes
	var edge_scores: PackedFloat64Array = result.edges
	_expect(is_equal_approx(nodes[0], 0.0) and is_equal_approx(nodes[3], 0.0),
		"path endpoints should have zero normalized node betweenness")
	_expect(is_equal_approx(nodes[1], 2.0 / 3.0) and is_equal_approx(nodes[2], 2.0 / 3.0),
		"path interior nodes should have standard normalized node betweenness")
	_expect(is_equal_approx(edge_scores[0], 0.5) and is_equal_approx(edge_scores[2], 0.5)
			and is_equal_approx(edge_scores[1], 2.0 / 3.0),
		"path edges should have standard undirected normalized edge betweenness")


func _test_layer_incidence_query() -> void:
	var layer := ArcaneWebGenerator.generate(707, 800.0, 400.0)
	_expect(layer != null, "incidence query fixture should generate")
	if layer == null:
		return
	for node in layer.nodes:
		for edge_id in layer.incident_edge_ids(node.id):
			var edge := layer.edges[edge_id]
			_expect(edge.node_a_id == node.id or edge.node_b_id == node.id,
				"incident_edge_ids must return only incident Ley Edges")


func _print_seed_one_statistics() -> void:
	var layer := ArcaneWebGenerator.generate(1, 2000.0, 1000.0)
	_expect(layer != null, "Seed 1 formal acceptance Web should generate")
	if layer == null:
		return
	var stats := ArcaneWebValidator.statistics(layer)
	print("Arcane Web Seed 1 statistics: ", stats)


func _web_signature(layer: ArcaneWebLayer) -> Array:
	var signature := [layer.generated_nucleus_count]
	for domain in layer.domains:
		signature.append([domain.id, domain.nucleus_position, domain.power_weight, domain.polygon])
	for node in layer.nodes:
		signature.append([node.id, node.world_position, node.kind, node.structural_importance])
	for edge in layer.edges:
		signature.append([
			edge.id, edge.node_a_id, edge.node_b_id, edge.length, edge.structural_importance
		])
	return signature


func _maximum_x(polygon: PackedVector2Array) -> float:
	var result := -INF
	for point in polygon:
		result = maxf(result, point.x)
	return result


func _lies_on_border(first: Vector2, second: Vector2, width: float, height: float) -> bool:
	var epsilon := SpatialGeometry.epsilon_for_size(width, height)
	return (absf(first.x) <= epsilon and absf(second.x) <= epsilon) \
			or (absf(first.x - width) <= epsilon and absf(second.x - width) <= epsilon) \
			or (absf(first.y) <= epsilon and absf(second.y) <= epsilon) \
			or (absf(first.y - height) <= epsilon and absf(second.y - height) <= epsilon)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Arcane Web: all 9 test groups passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	printerr("Arcane Web: %d failures" % _failures.size())
	quit(1)
