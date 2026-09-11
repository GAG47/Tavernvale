extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_default_settings()
	_test_synchronous_smoothing()
	var fixture := _standard_fixture()
	_test_generation_contract(fixture)
	_finish()


func _test_default_settings() -> void:
	var settings := TectonicPlateSettings.new()
	_expect(settings.plate_count == 5, "default plate_count must be 5")
	_expect(is_equal_approx(settings.macro_radius, 80.0), "macro_radius must match design")
	_expect(is_equal_approx(settings.regional_radius, 200.0), "regional_radius must match design")
	_expect(settings.anchor_candidates_per_plate == 96, "anchor candidate count must match design")
	_expect(is_equal_approx(settings.anchor_min_spacing_factor, 0.45), "anchor spacing factor must match design")
	_expect(settings.anchor_relax_attempts == 4, "anchor relaxation attempts must match design")
	_expect(is_equal_approx(settings.partition_terrain_weight, 2.5), "partition terrain weight must match design")
	_expect(is_equal_approx(settings.velocity_min_initial_speed, 0.8), "initial minimum speed must match design")
	_expect(is_equal_approx(settings.velocity_max_initial_speed, 1.2), "initial maximum speed must match design")
	_expect(settings.velocity_relaxation_iterations == 6, "velocity relaxation iterations must match design")
	_expect(is_equal_approx(settings.velocity_boundary_threshold, 0.35), "velocity boundary threshold must match design")
	_expect(is_equal_approx(settings.velocity_target_convergence, 0.50), "target convergence must match design")
	_expect(is_equal_approx(settings.velocity_correction_factor, 0.25), "velocity correction must match design")
	_expect(is_equal_approx(settings.velocity_min_final_speed, 0.75), "final minimum speed must match design")
	_expect(is_equal_approx(settings.velocity_max_final_speed, 1.25), "final maximum speed must match design")
	_expect(settings.validate().is_empty(), "default Tectonic Plate settings must validate")


func _test_synchronous_smoothing() -> void:
	var graph := _line_graph()
	var values := PackedFloat32Array([0.0, 100.0, 0.0])
	var smoothed := TectonicPlateGenerator.smooth_values(graph, values, 1)
	_expect(smoothed == PackedFloat32Array([50.0, 50.0, 50.0]), "one pass must update every Cell synchronously")
	_expect(values == PackedFloat32Array([0.0, 100.0, 0.0]), "smoothing must not modify its input")


func _test_generation_contract(fixture: Dictionary) -> void:
	_expect(not fixture.is_empty(), "standard Tectonic Plate fixture must generate")
	if fixture.is_empty():
		return
	var graph: SpatialGraph = fixture.graph
	var composition: WorldCompositionLayer = fixture.composition
	var terrain: TerrainHeightLayer = fixture.terrain
	var settings := TectonicPlateSettings.new()
	var centers_before := graph.cell_centers.duplicate()
	var neighbors_before := graph.cell_neighbors.duplicate(true)
	var distances_before := graph.cell_neighbor_distances.duplicate(true)
	var spacing_before := graph.spacing
	var composition_before := composition.continental_value.duplicate()
	var terrain_before := terrain.terrain_height.duplicate()
	var first := TectonicPlateGenerator.generate(graph, composition, terrain, 1, settings)
	var first_diagnostics := TectonicPlateGenerator.last_generation_diagnostics()
	var second := TectonicPlateGenerator.generate(graph, composition, terrain, 1, settings)
	_expect(first != null and second != null, "Tectonic Plate generation must succeed twice")
	if first == null or second == null:
		return
	_expect(first.plate_id == second.plate_id, "plate_id must be deterministic")
	_expect(first.plate_velocity == second.plate_velocity, "plate_velocity must be deterministic")
	_expect(first.cell_count() == graph.cell_count(), "every Cell must receive a plate")
	_expect(first.plate_count() == 5, "default generation must create five plates")
	_expect(TectonicPlateValidator.validate(graph, first, settings).is_empty(), "generated plates must validate")
	var anchor_ids: PackedInt32Array = first_diagnostics.anchor_cell_ids
	_expect(anchor_ids.size() == first.plate_count(), "Debug diagnostics must expose one generation anchor per plate")
	for plate_id in mini(anchor_ids.size(), first.plate_count()):
		_expect(first.plate_id[anchor_ids[plate_id]] == plate_id, "every plate must contain its own anchor")
	for cell_id in graph.cell_count():
		_expect(first.plate_id[cell_id] >= 0 and first.plate_id[cell_id] < 5, "every plate_id must be in range")
	for plate_id in first.plate_count():
		var velocity := first.plate_velocity[plate_id]
		_expect(is_finite(velocity.x) and is_finite(velocity.y), "plate velocity components must be finite")
		_expect(velocity.length() >= 0.75 - 0.000001, "plate speed must meet final minimum")
		_expect(velocity.length() <= 1.25 + 0.000001, "plate speed must meet final maximum")
	_expect(graph.cell_centers == centers_before, "Generator must not modify Cell centers")
	_expect(graph.cell_neighbors == neighbors_before, "Generator must not modify Cell neighbors")
	_expect(graph.cell_neighbor_distances == distances_before, "Generator must not modify neighbor distances")
	_expect(graph.spacing == spacing_before, "Generator must not modify graph spacing")
	_expect(composition.continental_value == composition_before, "Generator must not modify Composition")
	_expect(terrain.terrain_height == terrain_before, "Generator must not modify Terrain")
	var different := TectonicPlateGenerator.generate(graph, composition, terrain, 2, settings)
	_expect(different != null, "different-seed Tectonic Plate generation must succeed")
	if different != null:
		_expect(first.plate_id != different.plate_id \
				or first.plate_velocity != different.plate_velocity, "different world seeds must change partition or velocity")
	var counts := PackedInt32Array()
	counts.resize(first.plate_count())
	for plate_id in first.plate_id:
		counts[plate_id] += 1
	var structure: PackedFloat32Array = first_diagnostics.terrain_structure
	var structure_min := INF
	var structure_max := -INF
	var structure_sum := 0.0
	for value in structure:
		structure_min = minf(structure_min, value)
		structure_max = maxf(structure_max, value)
		structure_sum += value
	print("Tectonic Plate standard Seed 1 Continents 20k statistics:")
	print("  Plate Cell counts: %s" % str(counts))
	print("  Anchor Cell IDs: %s" % str(first_diagnostics.anchor_cell_ids))
	print("  Macro / Regional passes: %d / %d" % [first_diagnostics.macro_passes, first_diagnostics.regional_passes])
	print("  Terrain structure min/mean/max: %.6f / %.6f / %.6f" % [structure_min, structure_sum / structure.size(), structure_max])
	print("  Plate velocities: %s" % str(first.plate_velocity))
	print("  Active terrain-constrained boundary pairs: %d" % first_diagnostics.boundary_pair_count)


func _standard_fixture() -> Dictionary:
	var graph := SpatialGenerator.generate(
		SpatialConfig.new(1, 2000.0, 1000.0, 20000, 0.9)
	)
	if graph == null:
		return {}
	var composition := WorldCompositionGenerator.generate(
		graph, WorldCompositionConfig.new(1, CompositionTemplates.CONTINENTS)
	)
	if composition == null:
		return {}
	var projected := TerrainHeightProjector.project(composition.continental_value)
	var geology := GeologyGenerator.generate(graph, composition, projected)
	var climate := WorldClimateGenerator.generate(graph, projected, WorldClimateSettings.new())
	var preliminary_flow := PreliminaryFlowGenerator.generate(
		graph, projected, climate, WorldHydrologySettings.new()
	)
	var conditioning := HydrologyConditioner.condition(
		graph, projected, preliminary_flow, geology, HydrologyConditioningSettings.new()
	)
	if conditioning == null:
		return {}
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = conditioning.terrain_height.duplicate()
	return {"graph": graph, "composition": composition, "terrain": terrain}


func _line_graph() -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(1, 3.0, 1.0, 3, 0.9)
	graph.spacing = 1.0
	graph.cell_centers = PackedVector2Array([Vector2(0.5, 0.5), Vector2(1.5, 0.5), Vector2(2.5, 0.5)])
	graph.cell_neighbors = [PackedInt32Array([1]), PackedInt32Array([0, 2]), PackedInt32Array([1])]
	graph.cell_neighbor_distances = [PackedFloat64Array([1.0]), PackedFloat64Array([1.0, 1.0]), PackedFloat64Array([1.0])]
	return graph


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Tectonic Plate Foundation: all dedicated test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Tectonic Plate Foundation: %d failures" % _failures.size())
		quit(1)
