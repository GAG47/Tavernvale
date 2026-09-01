extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_sizes_ranges_settings_and_validator()
	_test_determinism_and_different_seed()
	_test_seed_domains_and_field_independence()
	_test_noise_configuration()
	_test_spatial_continuity()
	_test_resolution_independence()
	_test_spatial_graph_preservation()
	_finish()


func _test_sizes_ranges_settings_and_validator() -> void:
	var graph := _grid_graph(21, 11, 50.0, 101)
	var field := ArcaneFieldGenerator.generate(graph, 101)
	_expect(field != null, "Arcane Field fixture should generate")
	if field == null:
		return
	_expect(field.background_mana.size() == graph.cell_count(),
		"background_mana should contain one value per Cell")
	_expect(field.background_stability.size() == graph.cell_count(),
		"background_stability should contain one value per Cell")
	for values in [field.background_mana, field.background_stability]:
		for value in values:
			_expect(is_finite(value), "Arcane Field values should be finite")
			_expect(value >= 0.0 and value <= 1.0,
				"Arcane Field values should remain inside [0, 1]")
	_expect(ArcaneFieldValidator.validate(graph, field).is_empty(),
		"generated Arcane Field should pass its Validator")

	var invalid_settings := ArcaneFieldSettings.new()
	invalid_settings.mana_feature_scale = 0.0
	invalid_settings.stability_feature_scale = INF
	_expect(invalid_settings.validate().size() == 2,
		"Arcane Field Settings should reject non-positive or non-finite scales")
	var invalid_field := ArcaneFieldLayer.new()
	invalid_field.background_mana.resize(graph.cell_count())
	invalid_field.background_stability.resize(graph.cell_count())
	invalid_field.background_mana[0] = NAN
	invalid_field.background_stability[0] = INF
	_expect(ArcaneFieldValidator.validate(graph, invalid_field).size() >= 2,
		"Arcane Field Validator should reject NaN and INF")


func _test_determinism_and_different_seed() -> void:
	var graph := _grid_graph(31, 17, 50.0, 202)
	var settings := ArcaneFieldSettings.new()
	var first := ArcaneFieldGenerator.generate(graph, 202, settings)
	var repeat := ArcaneFieldGenerator.generate(graph, 202, settings)
	var other_seed := ArcaneFieldGenerator.generate(graph, 203, settings)
	_expect(first != null and repeat != null and other_seed != null,
		"Arcane determinism fixtures should generate")
	if first == null or repeat == null or other_seed == null:
		return
	_expect(first.background_mana == repeat.background_mana,
		"same inputs should reproduce background_mana exactly")
	_expect(first.background_stability == repeat.background_stability,
		"same inputs should reproduce background_stability exactly")
	_expect(first.background_mana != other_seed.background_mana,
		"a different World Seed should change background_mana")
	_expect(first.background_stability != other_seed.background_stability,
		"a different World Seed should change background_stability")


func _test_seed_domains_and_field_independence() -> void:
	_expect(ArcaneFieldGenerator.ARCANE_MANA_SEED_SALT == 0x4D414E41,
		"Mana must use the stable MANA seed salt")
	_expect(ArcaneFieldGenerator.ARCANE_STABILITY_SEED_SALT == 0x53544142,
		"Stability must use the stable STAB seed salt")
	var mana_seed := DeterministicRng.stable_mix(
		777, ArcaneFieldGenerator.ARCANE_MANA_SEED_SALT
	)
	var stability_seed := DeterministicRng.stable_mix(
		777, ArcaneFieldGenerator.ARCANE_STABILITY_SEED_SALT
	)
	_expect(mana_seed != stability_seed, "Mana and Stability must use independent seed domains")
	var graph := _grid_graph(41, 21, 50.0, 777)
	var field := ArcaneFieldGenerator.generate(graph, 777)
	_expect(field != null, "field-independence fixture should generate")
	if field == null:
		return
	_expect(field.background_mana != field.background_stability,
		"Mana and Stability must not be the same field")
	var exact_inverse := true
	var combinations := PackedByteArray()
	combinations.resize(4)
	for cell_id in graph.cell_count():
		if not is_equal_approx(
			field.background_stability[cell_id], 1.0 - field.background_mana[cell_id]
		):
			exact_inverse = false
		var combination := (2 if field.background_mana[cell_id] >= 0.5 else 0) + (
			1 if field.background_stability[cell_id] >= 0.5 else 0
		)
		combinations[combination] = 1
	_expect(not exact_inverse, "Stability must not be a simple inverse of Mana")
	var combination_count := 0
	for present in combinations:
		combination_count += present
	_expect(combination_count == 4,
		"fixed world should naturally contain all high/low Mana-Stability combinations")


func _test_noise_configuration() -> void:
	var mana_noise := ArcaneFieldGenerator._make_noise(
		1, 800.0, ArcaneFieldGenerator.MANA_OCTAVES,
		ArcaneFieldGenerator.MANA_LACUNARITY, ArcaneFieldGenerator.MANA_GAIN
	)
	var stability_noise := ArcaneFieldGenerator._make_noise(
		2, 500.0, ArcaneFieldGenerator.STABILITY_OCTAVES,
		ArcaneFieldGenerator.STABILITY_LACUNARITY, ArcaneFieldGenerator.STABILITY_GAIN
	)
	for noise in [mana_noise, stability_noise]:
		_expect(noise.noise_type == FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
			"Arcane fields should use Simplex Smooth noise")
		_expect(noise.fractal_type == FastNoiseLite.FRACTAL_FBM,
			"Arcane fields should use FBM")
		_expect(noise.fractal_octaves == 3, "Arcane fields should use three octaves")
		_expect(noise.fractal_lacunarity == 2.0,
			"Arcane fields should use lacunarity 2")
		_expect(noise.fractal_weighted_strength == 0.0,
			"Arcane fields should disable weighted strength")
		_expect(not noise.domain_warp_enabled, "Arcane fields should disable domain warp")
	_expect(is_equal_approx(mana_noise.frequency, 1.0 / 800.0),
		"Mana frequency should be 1 / 800 world units")
	_expect(is_equal_approx(mana_noise.fractal_gain, 0.40), "Mana gain should be 0.40")
	_expect(is_equal_approx(stability_noise.frequency, 1.0 / 500.0),
		"Stability frequency should be 1 / 500 world units")
	_expect(is_equal_approx(stability_noise.fractal_gain, 0.50),
		"Stability gain should be 0.50")


func _test_spatial_continuity() -> void:
	var graph := _grid_graph(41, 21, 50.0, 909)
	var field := ArcaneFieldGenerator.generate(graph, 909)
	_expect(field != null, "continuity fixture should generate")
	if field == null:
		return
	_expect(_mean_neighbor_delta(graph, field.background_mana) < 0.12,
		"Mana should be spatially continuous, not per-Cell random")
	_expect(_mean_neighbor_delta(graph, field.background_stability) < 0.12,
		"Stability should be spatially continuous, not per-Cell random")


func _test_resolution_independence() -> void:
	var coarse := _grid_graph(21, 11, 100.0, 31337)
	var dense := _grid_graph(41, 21, 50.0, 31337)
	var coarse_field := ArcaneFieldGenerator.generate(coarse, 31337)
	var dense_field := ArcaneFieldGenerator.generate(dense, 31337)
	_expect(coarse_field != null and dense_field != null,
		"resolution-independence fixtures should generate")
	if coarse_field == null or dense_field == null:
		return
	for y in 11:
		for x in 21:
			var coarse_id := y * 21 + x
			var dense_id := (y * 2) * 41 + x * 2
			_expect(coarse.cell_centers[coarse_id] == dense.cell_centers[dense_id],
				"resolution fixtures should share comparison coordinates")
			_expect(coarse_field.background_mana[coarse_id]
					== dense_field.background_mana[dense_id],
				"Mana should match at the same world coordinate across resolutions")
			_expect(coarse_field.background_stability[coarse_id]
					== dense_field.background_stability[dense_id],
				"Stability should match at the same world coordinate across resolutions")


func _test_spatial_graph_preservation() -> void:
	var graph := _grid_graph(21, 11, 50.0, 404)
	var centers_before := graph.cell_centers.duplicate()
	var neighbors_before := graph.cell_neighbors.duplicate(true)
	var field := ArcaneFieldGenerator.generate(graph, 404)
	_expect(field != null, "preservation fixture should generate")
	_expect(graph.cell_centers == centers_before,
		"Arcane Field generation must not modify SpatialGraph Cell centers")
	_expect(graph.cell_neighbors == neighbors_before,
		"Arcane Field generation must not modify SpatialGraph topology")


func _grid_graph(columns: int, rows: int, spacing: float, seed: int) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.columns = columns
	graph.rows = rows
	graph.spacing = spacing
	graph.config = SpatialConfig.new(
		seed, float(columns - 1) * spacing, float(rows - 1) * spacing,
		columns * rows, 0.9
	)
	for y in rows:
		for x in columns:
			graph.cell_centers.append(Vector2(float(x) * spacing, float(y) * spacing))
	graph.cell_neighbors.resize(columns * rows)
	for y in rows:
		for x in columns:
			var neighbors := PackedInt32Array()
			if x > 0:
				neighbors.append(y * columns + x - 1)
			if x + 1 < columns:
				neighbors.append(y * columns + x + 1)
			if y > 0:
				neighbors.append((y - 1) * columns + x)
			if y + 1 < rows:
				neighbors.append((y + 1) * columns + x)
			graph.cell_neighbors[y * columns + x] = neighbors
	return graph


func _mean_neighbor_delta(graph: SpatialGraph, values: PackedFloat32Array) -> float:
	var sum := 0.0
	var count := 0
	for cell_id in graph.cell_count():
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if neighbor_id > cell_id:
				sum += absf(values[cell_id] - values[neighbor_id])
				count += 1
	return sum / float(count) if count > 0 else 0.0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Arcane Field: all 7 test groups passed")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
