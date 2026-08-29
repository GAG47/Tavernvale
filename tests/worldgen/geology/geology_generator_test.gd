extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_determinism()
	_test_array_sizes_ranges_and_validator()
	_test_oceanic_crust_assignment()
	_test_material_lookup_and_weight_tables()
	_test_province_regions_are_continuous()
	_test_material_patches_are_continuous()
	_finish()


func _test_determinism() -> void:
	var graph := _line_graph(600, 42)
	var terrain := _mixed_terrain(600)
	var first := GeologyGenerator.generate(graph, terrain)
	var second := GeologyGenerator.generate(graph, terrain)
	_expect(first != null and second != null, "determinism world should generate twice")
	if first == null or second == null:
		return
	_expect(first.province_id == second.province_id, "Province generation should be deterministic")
	_expect(first.material_id == second.material_id, "Material generation should be deterministic")
	_expect(first.permeability == second.permeability, "Permeability should be deterministic")
	_expect(first.erodibility == second.erodibility, "Erodibility should be deterministic")


func _test_array_sizes_ranges_and_validator() -> void:
	var graph := _line_graph(600, 42)
	var terrain := _mixed_terrain(600)
	var geology := GeologyGenerator.generate(graph, terrain)
	_expect(geology != null, "range test world should generate")
	if geology == null:
		return
	for values in [
		geology.province_id,
		geology.material_id,
		geology.permeability,
		geology.erodibility,
	]:
		_expect(values.size() == graph.cell_count(), "every Geology array should match Cell Count")
	for cell_id in graph.cell_count():
		_expect(
			geology.permeability[cell_id] >= 0.0 and geology.permeability[cell_id] <= 1.0,
			"permeability should remain inside [0, 1]"
		)
		_expect(
			geology.erodibility[cell_id] >= 0.0 and geology.erodibility[cell_id] <= 1.0,
			"erodibility should remain inside [0, 1]"
		)
	_expect(
		GeologyValidator.validate(graph, terrain, geology).is_empty(),
		"generated Geology should pass its Validator"
	)


func _test_oceanic_crust_assignment() -> void:
	var graph := _line_graph(120, 7)
	var terrain := _mixed_terrain(120)
	var geology := GeologyGenerator.generate(graph, terrain)
	_expect(geology != null, "Ocean assignment world should generate")
	if geology == null:
		return
	for cell_id in graph.cell_count():
		if terrain.terrain_height[cell_id] < 0.0:
			_expect(
				geology.province_id[cell_id] == GeologyCatalog.Province.OCEANIC_CRUST,
				"every Ocean Cell should use Oceanic Crust"
			)


func _test_material_lookup_and_weight_tables() -> void:
	var expected_permeability := [0.15, 0.12, 0.65, 0.12, 0.80, 0.40, 0.45]
	var expected_erodibility := [0.15, 0.18, 0.55, 0.75, 0.45, 0.30, 0.60]
	for material_id in GeologyCatalog.MATERIAL_COUNT:
		_expect(
			is_equal_approx(
				GeologyCatalog.permeability_for(material_id), expected_permeability[material_id]
			),
			"Material %d permeability lookup should match the v1.7 table" % material_id
		)
		_expect(
			is_equal_approx(
				GeologyCatalog.erodibility_for(material_id), expected_erodibility[material_id]
			),
			"Material %d erodibility lookup should match the v1.7 table" % material_id
		)
	for province_id in GeologyCatalog.PROVINCE_COUNT:
		var weights := GeologyCatalog.material_weights(province_id)
		var total := 0.0
		var non_zero := 0
		for weight in weights:
			total += weight
			if weight > 0.0:
				non_zero += 1
		_expect(is_equal_approx(total, 1.0), "Province Material weights should total one")
		_expect(non_zero >= 2, "no Province should map one-to-one to a single Material")


func _test_province_regions_are_continuous() -> void:
	var count := 1200
	var graph := _line_graph(count, 99)
	var terrain := _all_land_terrain(count)
	var geology := GeologyGenerator.generate(graph, terrain)
	_expect(geology != null, "Province continuity world should generate")
	if geology == null:
		return
	var expected_seed_count := ceili(
		float(count) / float(GeologyGenerator.PROVINCE_TARGET_CELLS_PER_SEED)
	)
	_expect(
		_count_transitions(geology.province_id) <= expected_seed_count,
		"Province region growing should create large line intervals, not per-Cell noise"
	)
	_expect(
		_minimum_run_length(geology.province_id) > 2,
		"Province generation should not create one- or two-Cell islands on the test line"
	)


func _test_material_patches_are_continuous() -> void:
	var count := 400
	var graph := _line_graph(count, 123)
	var terrain := _all_land_terrain(count)
	var geology := GeologyGenerator.generate(graph, terrain)
	_expect(geology != null, "Material continuity world should generate")
	if geology == null:
		return
	var expected_patch_count := ceili(
		float(count) / float(GeologyGenerator.MATERIAL_TARGET_CELLS_PER_SEED)
	)
	_expect(
		_count_transitions(geology.material_id) <= expected_patch_count,
		"Material seed expansion should create patches, not independent Cell draws"
	)
	_expect(
		_minimum_run_length(geology.material_id) > 2,
		"Material generation should not create one- or two-Cell patches on the test line"
	)


func _line_graph(cell_count: int, world_seed: int) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(world_seed, float(cell_count), 1.0, cell_count, 0.9)
	graph.spacing = 1.0
	graph.cell_centers.resize(cell_count)
	graph.cell_neighbors.resize(cell_count)
	graph.cell_neighbor_distances.resize(cell_count)
	graph.cell_is_border.resize(cell_count)
	graph.cell_is_border[0] = 1
	graph.cell_is_border[cell_count - 1] = 1
	for cell_id in cell_count:
		graph.cell_centers[cell_id] = Vector2(cell_id, 0.5)
		var neighbors := PackedInt32Array()
		if cell_id > 0:
			neighbors.append(cell_id - 1)
		if cell_id + 1 < cell_count:
			neighbors.append(cell_id + 1)
		graph.cell_neighbors[cell_id] = neighbors
		var distances := PackedFloat64Array()
		distances.resize(neighbors.size())
		distances.fill(1.0)
		graph.cell_neighbor_distances[cell_id] = distances
	return graph


func _mixed_terrain(cell_count: int) -> TerrainHeightLayer:
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height.resize(cell_count)
	var ocean_width := maxi(1, cell_count / 8)
	for cell_id in cell_count:
		if cell_id < ocean_width or cell_id >= cell_count - ocean_width:
			terrain.terrain_height[cell_id] = -20.0
		else:
			var normalized := float(cell_id - ocean_width) \
					/ float(maxi(1, cell_count - ocean_width * 2 - 1))
			terrain.terrain_height[cell_id] = 10.0 + 55.0 * absf(normalized * 2.0 - 1.0)
	return terrain


func _all_land_terrain(cell_count: int) -> TerrainHeightLayer:
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height.resize(cell_count)
	for cell_id in cell_count:
		var normalized := float(cell_id) / float(maxi(1, cell_count - 1))
		terrain.terrain_height[cell_id] = 15.0 + 45.0 * absf(normalized * 2.0 - 1.0)
	return terrain


func _count_transitions(values: PackedInt32Array) -> int:
	var transitions := 0
	for cell_id in range(1, values.size()):
		if values[cell_id] != values[cell_id - 1]:
			transitions += 1
	return transitions


func _minimum_run_length(values: PackedInt32Array) -> int:
	var minimum := values.size()
	var run_length := 1
	for cell_id in range(1, values.size()):
		if values[cell_id] == values[cell_id - 1]:
			run_length += 1
		else:
			minimum = mini(minimum, run_length)
			run_length = 1
	return mini(minimum, run_length)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Geology / Subsurface Foundation: all 6 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Geology / Subsurface Foundation: %d failures" % _failures.size())
		quit(1)
