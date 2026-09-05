extends SceneTree

const G := ArcaneEcologyCatalog.NaturalEcologyGroup
const B := EcologyCatalog.Biome
var _failures := PackedStringArray()
var _groups := 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	for test in [_test_mapping, _test_natural_bases, _test_trapezoid, _test_profile_winners,
		_test_concentration_independence, _test_classification, _test_ties_and_zero,
		_test_settings, _test_invalid_inputs, _test_output_validation,
		_test_determinism_range_and_immutability, _test_diagnostics, _test_debug_maps]:
		test.call()
		_groups += 1
	if _failures.is_empty():
		print("Arcane Ecology: all %d test groups passed" % _groups)
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		quit(1)


func _test_mapping() -> void:
	var expected := {
		B.MARINE: G.AQUATIC, B.LAKE: G.AQUATIC, B.GLACIER: G.BARREN_EXTREME,
		B.TUNDRA: G.OPEN_VEGETATION, B.COLD_DESERT: G.BARREN_EXTREME,
		B.HOT_DESERT: G.BARREN_EXTREME, B.GRASSLAND: G.OPEN_VEGETATION,
		B.SAVANNA: G.OPEN_VEGETATION, B.TAIGA: G.WOODLAND,
		B.TEMPERATE_FOREST: G.WOODLAND, B.TEMPERATE_RAINFOREST: G.WOODLAND,
		B.TROPICAL_SEASONAL_FOREST: G.WOODLAND, B.TROPICAL_RAINFOREST: G.WOODLAND,
		B.WETLAND: G.WETLAND,
	}
	_expect(expected.size() == EcologyCatalog.BIOME_COUNT, "mapping covers all existing biomes")
	for biome in EcologyCatalog.BIOME_COUNT:
		_expect(ArcaneEcologyCatalog.natural_group_for_biome(biome) == expected.get(biome, -2),
			"biome %d has expected group" % biome)
	_expect(ArcaneEcologyCatalog.natural_group_for_biome(-1) == -1, "invalid biome has no group")
	_expect(ArcaneEcologyCatalog.state_name(2) == "DOMINANT", "state names")
	_expect(ArcaneEcologyCatalog.response_profile_name(-1) == "NO_RESPONSE_PROFILE", "no-profile name")


func _test_natural_bases() -> void:
	var settings := ArcaneEcologySettings.new()
	for group in [G.WOODLAND, G.OPEN_VEGETATION]:
		var floor_value := 0.45 if group == G.WOODLAND else 0.60
		_close(ArcaneEcologyGenerator.natural_base_for(group, 0.1, 0.0, settings), floor_value, "natural floor")
		_close(ArcaneEcologyGenerator.natural_base_for(group, 0.1, 1.0, settings), 1.0, "natural ceiling")
		var previous := -1.0
		for step in 11:
			var value := ArcaneEcologyGenerator.natural_base_for(group, 0.1, step / 10.0, settings)
			_expect(value > previous, "woodland/open base increases with vegetation")
			previous = value
	_close(ArcaneEcologyGenerator.natural_base_for(G.WETLAND, 0.9, 0.1, settings), 0.955, "wetland uses high moisture")
	_close(ArcaneEcologyGenerator.natural_base_for(G.WETLAND, 0.1, 0.9, settings), 0.955, "wetland uses high vegetation")
	_close(ArcaneEcologyGenerator.natural_base_for(G.WETLAND, 0.0, 0.0, settings), 0.55, "wetland floor")
	for group in [G.BARREN_EXTREME, G.AQUATIC]:
		for vegetation in [0.0, 0.5, 1.0]:
			_close(ArcaneEcologyGenerator.natural_base_for(group, 0.2, vegetation, settings), 0.75,
				"barren/aquatic base ignores ordinary vegetation")
	_expect(settings.profile_affinities == [PackedFloat64Array([1.0, 0.75, 0.45]),
		PackedFloat64Array([0.70, 1.0, 0.75]), PackedFloat64Array([0.75, 1.0, 0.85]),
		PackedFloat64Array([0.65, 0.70, 1.0]), PackedFloat64Array([0.70, 1.0, 0.70])],
		"all fifteen default affinities match specification")


func _test_trapezoid() -> void:
	for pair in [[0.0, 0.0], [0.1, 0.0], [0.2, 0.5], [0.3, 1.0],
		[0.5, 1.0], [0.7, 1.0], [0.8, 0.5], [0.9, 0.0], [1.0, 0.0]]:
		_close(ArcaneEcologyGenerator.trapezoid_suitability(pair[0], 0.1, 0.3, 0.7, 0.9),
			pair[1], "trapezoid endpoint/ramp/plateau")
	_close(ArcaneEcologyGenerator.trapezoid_suitability(0.0, 0.0, 0.0, 0.5, 1.0), 1.0, "collapsed left")
	_close(ArcaneEcologyGenerator.trapezoid_suitability(1.0, 0.0, 0.5, 1.0, 1.0), 1.0, "collapsed right")
	_close(ArcaneEcologyGenerator.trapezoid_suitability(0.5, 0.5, 0.5, 0.5, 0.5), 1.0, "all anchors equal")
	_close(ArcaneEcologyGenerator.trapezoid_suitability(0.49, 0.5, 0.5, 0.5, 0.5), 0.0, "outside collapsed plateau")
	var s := ArcaneEcologySettings.new()
	_expect(s.stability_anchors == [PackedFloat64Array([0.35, 0.70, 1, 1]),
		PackedFloat64Array([0.20, 0.50, 1, 1]), PackedFloat64Array([0, 0.15, 0.50, 0.85])], "default stability anchors")
	_expect(s.flowability_anchors == [PackedFloat64Array([0, 0.10, 0.45, 0.80]),
		PackedFloat64Array([0.30, 0.65, 1, 1]), PackedFloat64Array([0.25, 0.55, 1, 1])], "default flow anchors")


func _test_profile_winners() -> void:
	for fixture in [[B.TEMPERATE_FOREST, 0.9, 0.2, 0, 1.0],
		[B.GRASSLAND, 0.9, 0.8, 1, 1.0], [B.HOT_DESERT, 0.3, 0.8, 2, 0.75]]:
		var inputs := _fixture(fixture[0], fixture[1], fixture[2])
		var layer := ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment)
		_expect(layer != null, "synthetic winner generates")
		if layer != null:
			_expect(layer.arcane_response_profile_id[0] == fixture[3], "each profile can win")
			_close(layer.arcane_ecology_potential[0], fixture[4], "synthetic winning potential")
	# Isolate one response to verify multiplication and geometric (not arithmetic) match.
	var inputs := _fixture(B.TEMPERATE_FOREST, 0.525, 0.05)
	var settings := ArcaneEcologySettings.new()
	settings.profile_affinities[G.WOODLAND] = PackedFloat64Array([0.8, 0, 0])
	var result := ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment, settings)
	_expect(result != null, "fractional suitability generates")
	if result != null:
		_close(result.arcane_ecology_potential[0], 0.8 * sqrt(0.5 * 0.5), "geometric match times response")
	inputs.environment.mana_flowability[0] = 0.0
	result = ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment, settings)
	_expect(result != null and result.arcane_ecology_potential[0] == 0, "one unsuitable coordinate cannot be compensated")


func _test_concentration_independence() -> void:
	var inputs := _fixture(B.TEMPERATE_FOREST, 0.9, 0.2, 3)
	inputs.environment.mana_concentration = PackedFloat32Array([0.1, 0.5, 0.9])
	var layer := ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment)
	_expect(layer != null, "independent concentration fixture")
	if layer == null:
		return
	_expect(layer.arcane_ecology_potential == PackedFloat32Array([1, 1, 1]), "mana cannot affect potential")
	_expect(layer.arcane_response_profile_id == PackedInt32Array([0, 0, 0]), "mana cannot affect profile")
	_expect(layer.arcane_ecology_state == PackedInt32Array([0, 1, 2]), "mana independently changes state")


func _test_classification() -> void:
	var s := ArcaneEcologySettings.new()
	var values := [0.2, 0.5, 0.9]
	var expected := [[0, 0, 0], [0, 1, 1], [0, 1, 2]]
	for mana in 3:
		for potential in 3:
			_expect(ArcaneEcologyGenerator.state_for(values[mana], values[potential], s) == expected[mana][potential],
				"classification table (%d, %d), including high/low corners" % [mana, potential])
	# Also exercise all nine combinations through formal Packed arrays and generate().
	var inputs := _fixture(B.TEMPERATE_FOREST, 0.9, 0.2, 9)
	var table_settings := s.duplicate_settings()
	table_settings.woodland_response_floor = 0.0
	for mana in 3:
		for potential in 3:
			inputs.environment.mana_concentration[mana * 3 + potential] = values[mana]
			inputs.ecology.vegetation_potential[mana * 3 + potential] = values[potential]
	var table_layer := ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment, table_settings)
	_expect(table_layer != null and table_layer.arcane_ecology_state == PackedInt32Array([
		0, 0, 0, 0, 1, 1, 0, 1, 2]), "all nine classifications through generator")
	for pair in [[0.399999, 0], [0.4, 1], [0.699999, 1], [0.7, 2], [1.0, 2]]:
		_expect(ArcaneEcologyGenerator.band_for(pair[0], 0.4, 0.7) == pair[1], "exact hard threshold boundaries")
	s.mana_concentration_medium_threshold = 0.2
	s.mana_concentration_high_threshold = 0.8
	s.arcane_ecology_potential_medium_threshold = 0.3
	s.arcane_ecology_potential_high_threshold = 0.9
	_expect(ArcaneEcologyGenerator.state_for(0.8, 0.9, s) == 2, "custom independent thresholds")


func _test_ties_and_zero() -> void:
	var inputs := _fixture(B.GRASSLAND, 0.5, 0.5)
	var s := ArcaneEcologySettings.new()
	for profile in 3:
		s.stability_anchors[profile] = PackedFloat64Array([0, 0, 1, 1])
		s.flowability_anchors[profile] = PackedFloat64Array([0, 0, 1, 1])
	s.profile_affinities[G.OPEN_VEGETATION] = PackedFloat64Array([1, 1, 1])
	var layer := ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment, s)
	_expect(layer != null and layer.arcane_response_profile_id[0] == 0, "three-way tie picks first enum")
	s.profile_affinities[G.OPEN_VEGETATION] = PackedFloat64Array([0, 1, 1])
	layer = ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment, s)
	_expect(layer != null and layer.arcane_response_profile_id[0] == 1, "two-way tie picks first enum")
	inputs.environment.mana_flowability[0] = 0
	layer = ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment)
	_expect(layer != null and layer.arcane_ecology_potential[0] == 0
		and layer.arcane_response_profile_id[0] == -1 and layer.arcane_ecology_state[0] == 0,
		"all zero profiles use sentinel and NORMAL even with high mana")


func _test_settings() -> void:
	var s := ArcaneEcologySettings.new()
	_expect(s.validate().is_empty(), "default settings validate")
	var copy := s.duplicate_settings()
	copy.profile_affinities[0][0] = 0
	copy.stability_anchors[0][0] = 0
	copy.flowability_anchors[0][0] = 0.01
	copy.woodland_response_floor = 0.1
	_expect(s.profile_affinities[0][0] == 1 and s.stability_anchors[0][0] == 0.35
		and s.flowability_anchors[0][0] == 0 and s.woodland_response_floor == 0.45, "deep settings copy")
	for parameter in s._SCALAR_PARAMETERS:
		for invalid in [NAN, INF, -0.1, 1.1]:
			copy = s.duplicate_settings()
			copy.set(parameter, invalid)
			_expect(not copy.validate().is_empty(), "invalid scalar rejected: " + parameter)
	for table_name in ["profile_affinities", "stability_anchors", "flowability_anchors"]:
		copy = s.duplicate_settings()
		copy.get(table_name).pop_back()
		_expect(not copy.validate().is_empty(), "wrong table rows rejected")
		copy = s.duplicate_settings()
		copy.get(table_name)[0] = PackedFloat64Array([0])
		_expect(not copy.validate().is_empty(), "wrong table columns rejected")
		for invalid in [NAN, INF, -0.1, 1.1]:
			copy = s.duplicate_settings()
			copy.get(table_name)[0][0] = invalid
			_expect(not copy.validate().is_empty(), "invalid table value rejected")
	copy = s.duplicate_settings()
	copy.stability_anchors[0] = PackedFloat64Array([0.5, 0.4, 0.9, 1])
	_expect(not copy.validate().is_empty(), "unordered anchors rejected")
	copy = s.duplicate_settings()
	copy.flowability_anchors[0] = PackedFloat64Array([0, 0.8, 0.7, 1])
	_expect(not copy.validate().is_empty(), "unordered flow anchors rejected")
	copy = s.duplicate_settings()
	copy.mana_concentration_high_threshold = copy.mana_concentration_medium_threshold
	_expect(not copy.validate().is_empty(), "equal thresholds rejected")
	copy = s.duplicate_settings()
	copy.arcane_ecology_potential_high_threshold = 0.1
	_expect(not copy.validate().is_empty(), "reversed potential thresholds rejected")
	var inputs := _fixture()
	print("Expected Arcane Ecology validation errors begin")
	_expect(ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment, copy) == null, "invalid settings fail generation")


func _test_invalid_inputs() -> void:
	var inputs := _fixture()
	_expect(ArcaneEcologyGenerator.generate(null, inputs.environment) == null, "null ecology rejected")
	_expect(ArcaneEcologyGenerator.generate(inputs.ecology, null) == null, "null environment rejected")
	for name in ["ecological_moisture", "vegetation_potential", "biome_id",
		"mana_concentration", "mana_flowability", "mana_stability", "drainage_index"]:
		inputs = _fixture()
		var owner: RefCounted = inputs.environment if name.begins_with("mana") else inputs.ecology
		var values = owner.get(name)
		values.resize(0)
		owner.set(name, values)
		_expect(ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment) == null, "wrong size rejected: " + name)
	for invalid in [-1, EcologyCatalog.BIOME_COUNT]:
		inputs = _fixture()
		inputs.ecology.biome_id[0] = invalid
		_expect(ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment) == null, "invalid biome rejected")
	for name in ["ecological_moisture", "vegetation_potential", "mana_concentration", "mana_flowability", "mana_stability"]:
		for invalid in [NAN, INF, -0.1, 1.1]:
			inputs = _fixture()
			var owner: RefCounted = inputs.environment if name.begins_with("mana") else inputs.ecology
			var values: PackedFloat32Array = owner.get(name)
			values[0] = invalid
			owner.set(name, values)
			_expect(ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment) == null, "invalid continuous input rejected: " + name)
	print("Expected Arcane Ecology validation errors end")


func _test_output_validation() -> void:
	_expect(not ArcaneEcologyValidator.validate(1, null).is_empty(), "null output rejected")
	for name in ["arcane_ecology_potential", "arcane_ecology_state", "arcane_response_profile_id"]:
		var layer := _valid_output()
		var values = layer.get(name)
		values.resize(0)
		layer.set(name, values)
		_expect(not ArcaneEcologyValidator.validate(1, layer).is_empty(), "output size rejected")
	for value in [NAN, INF, -0.1, 1.1]:
		var layer := _valid_output()
		layer.arcane_ecology_potential[0] = value
		_expect(not ArcaneEcologyValidator.validate(1, layer).is_empty(), "invalid output potential")
	for value in [-1, 3]:
		var layer := _valid_output()
		layer.arcane_ecology_state[0] = value
		_expect(not ArcaneEcologyValidator.validate(1, layer).is_empty(), "invalid output state")
	for value in [-2, -1, 3]:
		var layer := _valid_output()
		layer.arcane_response_profile_id[0] = value
		_expect(not ArcaneEcologyValidator.validate(1, layer).is_empty(), "invalid profile/sentinel")
	var zero := _valid_output()
	zero.arcane_ecology_potential[0] = 0
	zero.arcane_response_profile_id[0] = -1
	_expect(ArcaneEcologyValidator.validate(1, zero).is_empty(), "zero potential sentinel valid")
	var fields := []
	for property in zero.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields.append(property.name)
	_expect(fields == ["arcane_ecology_potential", "arcane_ecology_state", "arcane_response_profile_id"], "only three formal layer fields")


func _test_determinism_range_and_immutability() -> void:
	var inputs := _fixture(B.MARINE, 0, 0, 14 * 11 * 11)
	var cell := 0
	for biome in 14:
		for stability in 11:
			for flow in 11:
				inputs.ecology.biome_id[cell] = biome
				inputs.ecology.vegetation_potential[cell] = stability / 10.0
				inputs.ecology.ecological_moisture[cell] = flow / 10.0
				inputs.environment.mana_stability[cell] = stability / 10.0
				inputs.environment.mana_flowability[cell] = flow / 10.0
				cell += 1
	var before := _signature(inputs)
	var first := ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment)
	var second := ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment)
	_expect(first != null and second != null, "all biome/environment combinations generate")
	if first == null or second == null:
		return
	_expect(ArcaneEcologyValidator.validate(cell, first).is_empty(), "all output values finite and bounded")
	_expect(first.arcane_ecology_potential == second.arcane_ecology_potential
		and first.arcane_ecology_state == second.arcane_ecology_state
		and first.arcane_response_profile_id == second.arcane_response_profile_id, "exact deterministic arrays")
	_expect(before == _signature(inputs), "all input arrays remain exactly unchanged")
	inputs.ecology.drainage_index.fill(0.99)
	second = ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment)
	_expect(second != null and first.arcane_ecology_potential == second.arcane_ecology_potential,
		"unused drainage values do not affect potential")
	# Reordering Cells has no neighborhood or region effects.
	inputs.ecology.biome_id.reverse()
	inputs.ecology.ecological_moisture.reverse()
	inputs.ecology.vegetation_potential.reverse()
	inputs.environment.mana_stability.reverse()
	inputs.environment.mana_flowability.reverse()
	second = ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment)
	first.arcane_ecology_potential.reverse()
	first.arcane_ecology_state.reverse()
	first.arcane_response_profile_id.reverse()
	_expect(second != null and first.arcane_ecology_potential == second.arcane_ecology_potential
		and first.arcane_ecology_state == second.arcane_ecology_state
		and first.arcane_response_profile_id == second.arcane_response_profile_id, "strictly per-Cell derivation")


func _test_diagnostics() -> void:
	var inputs := _fixture(B.TEMPERATE_FOREST, 0.9, 0.2, 3)
	inputs.environment.mana_concentration = PackedFloat32Array([0.1, 0.5, 0.9])
	var layer := ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment)
	var stats := ArcaneEcologyGenerator.statistics(inputs.ecology, inputs.environment, layer)
	_expect(stats.mana_by_potential == [[0, 0, 1], [0, 0, 1], [0, 0, 1]], "diagnostic 3x3 table")
	_expect(stats.group_by_state == [[1, 1, 1], [0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]], "diagnostic group table")
	for key in ["mana_bands", "potential_bands", "states", "profiles"]:
		var count := 0
		var percentage := 0.0
		for entry in stats[key]:
			count += int(entry.count)
			percentage += float(entry.percentage)
		_expect(count == 3, "diagnostic counts sum to Cell count")
		_close(percentage, 100, "diagnostic percentages sum to 100")
	_close(stats.potential.min, 1, "diagnostic minimum")
	_close(stats.potential.mean, 1, "diagnostic mean")
	_close(stats.potential.max, 1, "diagnostic maximum")
	inputs = _fixture(B.MARINE, 0, 0, 0)
	layer = ArcaneEcologyGenerator.generate(inputs.ecology, inputs.environment)
	_expect(layer != null and layer.cell_count() == 0, "empty aligned layers generate")
	stats = ArcaneEcologyGenerator.statistics(inputs.ecology, inputs.environment, layer)
	_expect(stats.potential.mean == 0 and stats.profiles[3].percentage == 0, "empty diagnostics stay finite")


func _test_debug_maps() -> void:
	var view := WorldCompositionDebugView.new()
	var inputs := _fixture(B.TEMPERATE_FOREST, 0.9, 0.2, 4)
	view.ecology = inputs.ecology
	view.arcane_environment = inputs.environment
	view.arcane_ecology = ArcaneEcologyGenerator.generate(view.ecology, view.arcane_environment)
	view._arcane_ecology_statistics = ArcaneEcologyGenerator.statistics(view.ecology, view.arcane_environment, view.arcane_ecology)
	view.debug_page = WorldCompositionDebugView.DebugPage.ARCANE_ECOLOGY
	for index in 3:
		view._select_current_page_view(index)
		_expect(view._is_arcane_ecology_view(), "all three debug maps accessible by page hotkeys")
		var lines := PackedStringArray()
		view._append_mode_statistics(lines)
		view._append_arcane_ecology_cell_inspection(lines, 0)
		_expect(lines.size() > 10, "debug maps include statistics and inspection")
		_expect(view._cell_color(0).a == 1.0, "debug map has opaque fixed/continuous color")
	view.view_mode = WorldCompositionDebugView.ViewMode.ARCANE_ECOLOGY_STATE
	view.arcane_ecology.arcane_ecology_state = PackedInt32Array([0, 1, 2, 0])
	_expect(view._cell_color(0) != view._cell_color(1) and view._cell_color(1) != view._cell_color(2)
		and view._cell_color(0) != view._cell_color(2), "three distinct state colors")
	view.view_mode = WorldCompositionDebugView.ViewMode.ARCANE_RESPONSE_PROFILE
	view.arcane_ecology.arcane_response_profile_id = PackedInt32Array([-1, 0, 1, 2])
	for a in 4:
		for b in range(a + 1, 4):
			_expect(view._cell_color(a) != view._cell_color(b), "four distinct profile colors")
	view.free()


func _fixture(biome: int = B.TEMPERATE_FOREST, stability: float = 0.9,
		flow: float = 0.2, count: int = 1) -> Dictionary:
	var ecology := EcologyLayer.new()
	ecology.drainage_index.resize(count)
	ecology.ecological_moisture.resize(count)
	ecology.ecological_moisture.fill(0.5)
	ecology.vegetation_potential.resize(count)
	ecology.vegetation_potential.fill(1.0)
	ecology.biome_id.resize(count)
	ecology.biome_id.fill(biome)
	var environment := ArcaneEnvironmentLayer.new()
	environment.mana_concentration.resize(count)
	environment.mana_concentration.fill(0.9)
	environment.mana_stability.resize(count)
	environment.mana_stability.fill(stability)
	environment.mana_flowability.resize(count)
	environment.mana_flowability.fill(flow)
	return {"ecology": ecology, "environment": environment}


func _signature(inputs: Dictionary) -> Array:
	return [inputs.ecology.drainage_index.duplicate(), inputs.ecology.ecological_moisture.duplicate(),
		inputs.ecology.vegetation_potential.duplicate(), inputs.ecology.biome_id.duplicate(),
		inputs.environment.mana_concentration.duplicate(), inputs.environment.mana_stability.duplicate(),
		inputs.environment.mana_flowability.duplicate()]


func _valid_output() -> ArcaneEcologyLayer:
	var layer := ArcaneEcologyLayer.new()
	layer.arcane_ecology_potential = PackedFloat32Array([0.5])
	layer.arcane_ecology_state = PackedInt32Array([1])
	layer.arcane_response_profile_id = PackedInt32Array([0])
	return layer


func _close(actual: float, expected: float, message: String) -> void:
	_expect(is_finite(actual) and absf(actual - expected) < 0.000001,
		"%s: expected %.8f, got %.8f" % [message, expected, actual])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
