extends SceneTree

var _failures := PackedStringArray()
var _seed_one_web: ArcaneWebLayer
var _seed_one_circulation: ArcaneCirculationLayer


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_seed_one_web = ArcaneWebGenerator.generate(1, 2000.0, 1000.0)
	_seed_one_circulation = ArcaneCirculationGenerator.generate(_seed_one_web) \
			if _seed_one_web != null else null
	_expect(_seed_one_web != null and _seed_one_circulation != null,
		"Seed 1 Arcane Circulation fixture should generate")
	if _seed_one_web == null or _seed_one_circulation == null:
		_finish()
		return
	_test_seed_domain_noise_and_layer_contract()
	_test_determinism_and_different_seed()
	_test_edge_alignment_and_signed_direction()
	_test_junction_conservation()
	_test_boundary_exit_flow()
	_test_no_structural_proxy_and_web_preservation()
	_test_resolution_independence()
	_test_artificial_left_right_direction()
	_print_seed_one_statistics()
	_finish()


func _test_seed_domain_noise_and_layer_contract() -> void:
	_expect(ArcaneCirculationGenerator.CIRCULATION_SEED_SALT == 0x43495243,
		"Arcane Circulation must use the stable CIRC seed salt")
	_expect(ArcaneCirculationGenerator.CIRCULATION_FEATURE_SCALE == 700.0,
		"circulation noise scale must remain 700 world units")
	var noise := ArcaneCirculationGenerator._make_circulation_noise(123)
	_expect(noise.noise_type == FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
		"circulation potential must use Simplex Smooth")
	_expect(noise.fractal_type == FastNoiseLite.FRACTAL_FBM,
		"circulation potential must use FBM")
	_expect(noise.fractal_octaves == 3 and noise.fractal_lacunarity == 2.0
			and noise.fractal_gain == 0.50,
		"circulation potential must use the fixed octave/lacunarity/gain")
	_expect(is_equal_approx(noise.frequency, 1.0 / 700.0),
		"circulation frequency must be 1/700 world units")
	_expect(not noise.domain_warp_enabled,
		"circulation potential must not use domain warp")
	for domain in _seed_one_web.domains:
		var potential := ArcaneCirculationGenerator.circulation_potential_for(
			_seed_one_web, domain
		)
		_expect(is_finite(potential) and potential >= -1.0 and potential <= 1.0,
			"raw circulation potential must remain finite inside [-1, 1]")
	_expect(_seed_one_circulation.edge_count() == _seed_one_web.edges.size(),
		"ArcaneCirculationLayer must expose exactly one flow per Web Edge")


func _test_determinism_and_different_seed() -> void:
	var repeat := ArcaneCirculationGenerator.generate(_seed_one_web)
	var other_web := ArcaneWebGenerator.generate(2, 2000.0, 1000.0)
	var other_seed := ArcaneCirculationGenerator.generate(other_web) \
			if other_web != null else null
	_expect(repeat != null and other_web != null and other_seed != null,
		"circulation determinism fixtures should generate")
	if repeat == null or other_web == null or other_seed == null:
		return
	_expect(_seed_one_circulation.edge_flow == repeat.edge_flow,
		"same World Seed must reproduce the Web-derived edge_flow exactly")
	var different := _seed_one_circulation.edge_flow.size() != other_seed.edge_flow.size()
	for edge_index in mini(
		_seed_one_circulation.edge_flow.size(), other_seed.edge_flow.size()
	):
		if _seed_one_circulation.edge_flow[edge_index] != other_seed.edge_flow[edge_index]:
			different = true
			break
	_expect(different,
		"different World Seeds must produce at least partially different edge_flow")


func _test_edge_alignment_and_signed_direction() -> void:
	_expect(_seed_one_circulation.edge_flow.size() == _seed_one_web.edges.size(),
		"edge_flow must be strictly index-aligned with ArcaneWebLayer.edges")
	for edge_index in _seed_one_web.edges.size():
		var edge := _seed_one_web.edges[edge_index]
		_expect(edge.id == edge_index, "Web Edge IDs must remain aligned with array indices")
		_expect(_seed_one_circulation.flow_for_edge_index(edge_index)
				== _seed_one_circulation.edge_flow[edge_index],
			"flow query must preserve index alignment")
		var expected := ArcaneCirculationGenerator.expected_flow_for_edge(
			_seed_one_web, edge
		)
		_expect(bool(expected.get("valid", false)),
			"every Edge must resolve a left and right Domain")
		if bool(expected.get("valid", false)):
			_expect(absf(_seed_one_circulation.edge_flow[edge_index] - float(expected.flow))
					<= ArcaneCirculationValidator.FLOW_VALUE_EPSILON,
				"signed flow must equal left potential minus right potential for node_a -> node_b")
	_expect(ArcaneCirculationValidator.validate(
		_seed_one_web, _seed_one_circulation
	).is_empty(), "generated circulation should pass its Validator")


func _test_junction_conservation() -> void:
	for node in _seed_one_web.nodes:
		if node.kind != ArcaneWebNode.Kind.JUNCTION:
			continue
		var error := absf(ArcaneCirculationValidator.node_net_flow(
			_seed_one_web, _seed_one_circulation, node.id
		))
		_expect(error <= ArcaneCirculationValidator.JUNCTION_CONSERVATION_EPSILON,
			"every internal Junction must conserve signed mana flow")


func _test_boundary_exit_flow() -> void:
	var non_zero_boundary_exits := 0
	for node in _seed_one_web.nodes:
		if node.kind == ArcaneWebNode.Kind.BOUNDARY_EXIT and absf(
			ArcaneCirculationValidator.node_net_flow(
				_seed_one_web, _seed_one_circulation, node.id
			)
		) > ArcaneCirculationValidator.NON_ZERO_FLOW_EPSILON:
			non_zero_boundary_exits += 1
	_expect(non_zero_boundary_exits > 0,
		"Boundary Exits must be allowed to carry non-zero flow across the world window")
	var statistics := ArcaneCirculationValidator.statistics(
		_seed_one_web, _seed_one_circulation
	)
	_expect(statistics.boundary_inflow > 0.0 and statistics.boundary_outflow > 0.0,
		"Seed 1 should contain natural boundary inflow and outflow")


func _test_no_structural_proxy_and_web_preservation() -> void:
	var before := _web_geometry_signature(_seed_one_web)
	var repeated := ArcaneCirculationGenerator.generate(_seed_one_web)
	_expect(repeated != null, "Web preservation fixture should generate")
	_expect(before == _web_geometry_signature(_seed_one_web),
		"Arcane Circulation must not change Web geometry, IDs, node count, or edge count")
	_expect(not _object_has_property(ArcaneWebNode.new(), &"structural_importance"),
		"ArcaneWebNode must not regain structural importance")
	_expect(not _object_has_property(ArcaneWebEdge.new(), &"structural_importance"),
		"ArcaneWebEdge must not regain structural importance")
	for edge in _seed_one_web.edges:
		var expected := ArcaneCirculationGenerator.expected_flow_for_edge(
			_seed_one_web, edge
		)
		_expect(absf(_seed_one_circulation.edge_flow[edge.id] - float(expected.flow))
				<= ArcaneCirculationValidator.FLOW_VALUE_EPSILON,
			"flow strength must come only from adjacent Cell circulation potentials")


func _test_resolution_independence() -> void:
	var coarse := SpatialConfig.new(31337, 1000.0, 600.0, 400, 0.9)
	var dense := SpatialConfig.new(31337, 1000.0, 600.0, 4000, 0.9)
	var coarse_web := ArcaneWebGenerator.generate(
		coarse.seed, coarse.world_width, coarse.world_height
	)
	var dense_web := ArcaneWebGenerator.generate(
		dense.seed, dense.world_width, dense.world_height
	)
	var coarse_flow := ArcaneCirculationGenerator.generate(coarse_web)
	var dense_flow := ArcaneCirculationGenerator.generate(dense_web)
	_expect(coarse_web != null and dense_web != null
			and coarse_flow != null and dense_flow != null,
		"resolution independence fixtures should generate")
	if coarse_web == null or dense_web == null or coarse_flow == null or dense_flow == null:
		return
	_expect(_web_geometry_signature(coarse_web) == _web_geometry_signature(dense_web),
		"Arcane Web geometry must remain independent of SpatialGraph resolution")
	_expect(coarse_flow.edge_flow == dense_flow.edge_flow,
		"edge_flow must remain independent of SpatialGraph resolution")


func _test_artificial_left_right_direction() -> void:
	var web := ArcaneWebLayer.new()
	web.world_seed = 99
	web.world_width = 100.0
	web.world_height = 100.0
	web.settings = ArcaneWebSettings.new()
	web.generated_nucleus_count = 2
	web.domains = [
		ArcaneWebDomain.new(0, Vector2(25.0, 50.0), 0.0, PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(50.0, 0.0), Vector2(50.0, 100.0), Vector2(0.0, 100.0)
		])),
		ArcaneWebDomain.new(1, Vector2(75.0, 50.0), 0.0, PackedVector2Array([
			Vector2(50.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0), Vector2(50.0, 100.0)
		])),
	]
	web.nodes = [
		ArcaneWebNode.new(0, Vector2(50.0, 0.0), ArcaneWebNode.Kind.BOUNDARY_EXIT),
		ArcaneWebNode.new(1, Vector2(50.0, 100.0), ArcaneWebNode.Kind.BOUNDARY_EXIT),
	]
	web.edges = [ArcaneWebEdge.new(0, 0, 1, 100.0)]
	web.rebuild_incidence()
	var sides := ArcaneCirculationGenerator.domains_for_edge(web, web.edges[0])
	_expect(bool(sides.get("valid", false)), "artificial Edge should resolve both Domains")
	if bool(sides.get("valid", false)):
		_expect(sides.left_domain_id == 0 and sides.right_domain_id == 1,
			"for downward node_a -> node_b, the western Domain must be left")
	var circulation := ArcaneCirculationGenerator.generate(web)
	_expect(circulation != null, "artificial signed-direction circulation should generate")
	if circulation != null:
		var left_potential := ArcaneCirculationGenerator.circulation_potential_for(
			web, web.domains[0]
		)
		var right_potential := ArcaneCirculationGenerator.circulation_potential_for(
			web, web.domains[1]
		)
		_expect(absf(circulation.edge_flow[0] - (left_potential - right_potential))
				<= ArcaneCirculationValidator.FLOW_VALUE_EPSILON,
			"positive/negative flow must use the canonical node_a -> node_b direction")


func _print_seed_one_statistics() -> void:
	print("Arcane Circulation Seed 1 statistics: ", ArcaneCirculationValidator.statistics(
		_seed_one_web, _seed_one_circulation
	))


func _web_geometry_signature(web: ArcaneWebLayer) -> Array:
	var signature := [
		web.world_seed, web.world_width, web.world_height,
		web.generated_nucleus_count, web.nodes.size(), web.edges.size(),
	]
	for domain in web.domains:
		signature.append([domain.id, domain.nucleus_position, domain.power_weight, domain.polygon])
	for node in web.nodes:
		signature.append([node.id, node.world_position, node.kind])
	for edge in web.edges:
		signature.append([edge.id, edge.node_a_id, edge.node_b_id, edge.length])
	return signature


func _object_has_property(object: Object, property_name: StringName) -> bool:
	for property in object.get_property_list():
		if StringName(property.name) == property_name:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Arcane Circulation: all 8 test groups passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	printerr("Arcane Circulation: %d failures" % _failures.size())
	quit(1)
