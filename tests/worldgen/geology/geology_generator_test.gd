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
	_test_flat_landmass_does_not_force_orogenic_quota()
	_test_mountainous_landmass_increases_orogenic_share()
	_test_coastal_landmass_increases_passive_margin_share()
	_test_zero_suitability_is_never_forced()
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


func _test_flat_landmass_does_not_force_orogenic_quota() -> void:
	var count := 8000
	var graph := _line_graph(count, 31415)
	var terrain := _flat_terrain(count)
	var geology := GeologyGenerator.generate(graph, terrain)
	_expect(geology != null, "flat landmass should generate Geology")
	if geology == null:
		return
	_expect(
		_province_ratio(geology, terrain, GeologyCatalog.Province.OROGENIC_BELT) < 0.20,
		"flat low-relief terrain should not receive the former 25% Orogenic quota"
	)


func _test_mountainous_landmass_increases_orogenic_share() -> void:
	var count := 8000
	var graph := _line_graph(count, 31415)
	var flat_terrain := _flat_terrain(count)
	var mountain_terrain := _mountainous_terrain(count)
	_expect(
		_province_type_weight(
			graph, mountain_terrain, GeologyCatalog.Province.OROGENIC_BELT
		) > _province_type_weight(graph, flat_terrain, GeologyCatalog.Province.OROGENIC_BELT),
		"high-relief mountain terrain should increase the Orogenic selection weight"
	)


func _test_coastal_landmass_increases_passive_margin_share() -> void:
	var inland_count := 8000
	var coastal_count := 8200
	var inland_graph := _line_graph(inland_count, 27182)
	var coastal_graph := _line_graph(coastal_count, 27182)
	var inland_terrain := _flat_terrain(inland_count)
	var coastal_terrain := _coastal_flat_terrain(coastal_count, 100)
	_expect(
		_province_type_weight(
			coastal_graph, coastal_terrain, GeologyCatalog.Province.PASSIVE_MARGIN
		) > _province_type_weight(
			inland_graph, inland_terrain, GeologyCatalog.Province.PASSIVE_MARGIN
		),
		"a long low coast should increase the Passive Margin selection weight"
	)


func _test_zero_suitability_is_never_forced() -> void:
	var no_orogenic := PackedFloat32Array([0.0, 1.0, 0.0, 1.0, 1.0, 0.5])
	var no_volcanic := PackedFloat32Array([0.0, 1.0, 1.0, 1.0, 1.0, 0.0])
	for sample_index in 100:
		var deterministic_value := (float(sample_index) + 0.5) / 100.0
		_expect(
			GeologyGenerator.select_province_type(no_orogenic, deterministic_value) \
					!= GeologyCatalog.Province.OROGENIC_BELT,
			"zero Orogenic suitability must never be overridden by a fixed quota"
		)
		_expect(
			GeologyGenerator.select_province_type(no_volcanic, deterministic_value) \
					!= GeologyCatalog.Province.VOLCANIC_PROVINCE,
			"zero Volcanic suitability must never be overridden by a fixed quota"
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


func _flat_terrain(cell_count: int) -> TerrainHeightLayer:
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height.resize(cell_count)
	terrain.terrain_height.fill(10.0)
	return terrain


func _mountainous_terrain(cell_count: int) -> TerrainHeightLayer:
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height.resize(cell_count)
	for cell_id in cell_count:
		terrain.terrain_height[cell_id] = 90.0 if cell_id % 2 == 0 else 10.0
	return terrain


func _coastal_flat_terrain(cell_count: int, ocean_width: int) -> TerrainHeightLayer:
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height.resize(cell_count)
	for cell_id in cell_count:
		terrain.terrain_height[cell_id] = -10.0 \
				if cell_id < ocean_width or cell_id >= cell_count - ocean_width else 10.0
	return terrain


func _province_ratio(
		geology: GeologyLayer,
		terrain: TerrainHeightLayer,
		province_id: int
) -> float:
	var land_count := 0
	var province_count := 0
	for cell_id in geology.cell_count():
		if terrain.terrain_height[cell_id] < 0.0:
			continue
		land_count += 1
		if geology.province_id[cell_id] == province_id:
			province_count += 1
	return float(province_count) / float(land_count)


func _province_type_weight(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		province_id: int
) -> float:
	var land_cells := PackedInt32Array()
	for cell_id in graph.cell_count():
		if terrain.terrain_height[cell_id] >= 0.0:
			land_cells.append(cell_id)
	var cell_suitability := GeologyGenerator._province_suitability(graph, terrain)
	var representative := GeologyGenerator._landmass_suitability(
		land_cells, cell_suitability
	)
	return GeologyGenerator.PROVINCE_BASE_PRIOR[province_id] * representative[province_id]


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
		print("Geology / Subsurface Foundation: all 10 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Geology / Subsurface Foundation: %d failures" % _failures.size())
		quit(1)
