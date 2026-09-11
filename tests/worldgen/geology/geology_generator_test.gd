extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_determinism()
	_test_array_sizes_ranges_and_validator()
	_test_continental_support_semantics()
	_test_rock_catalog()
	_test_rock_region_assignment()
	_test_rock_layer_rules()
	_test_province_regions_are_continuous()
	_test_rock_regions_are_continuous()
	_test_flat_landmass_does_not_force_orogenic_quota()
	_test_local_mountain_seed_increases_orogenic_weight()
	_test_local_lowland_seed_increases_sedimentary_weight()
	_test_coastal_seed_increases_passive_margin_weight()
	_test_interior_flat_seed_increases_craton_weight()
	_test_same_landmass_local_weights_are_distinct()
	_test_zero_suitability_is_never_forced()
	_finish()


func _test_determinism() -> void:
	var graph := _line_graph(600, 42)
	var terrain := _mixed_terrain(600)
	var composition := _uniform_composition(600, 20)
	var first := GeologyGenerator.generate(graph, composition, terrain)
	var second := GeologyGenerator.generate(graph, composition, terrain)
	_expect(first != null and second != null, "determinism world should generate twice")
	if first == null or second == null:
		return
	_expect(first.province_id == second.province_id, "Province generation should be deterministic")
	_expect(first.rock_type_id == second.rock_type_id, "RockType generation should be deterministic")
	_expect(first.permeability == second.permeability, "Permeability should be deterministic")
	_expect(first.erodibility == second.erodibility, "Erodibility should be deterministic")


func _test_array_sizes_ranges_and_validator() -> void:
	var graph := _line_graph(600, 42)
	var terrain := _mixed_terrain(600)
	var composition := _uniform_composition(600, 20)
	var geology := GeologyGenerator.generate(graph, composition, terrain)
	_expect(geology != null, "range test world should generate")
	if geology == null:
		return
	for values in [
		geology.province_id,
		geology.rock_type_id,
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
		GeologyValidator.validate(graph, composition, terrain, geology).is_empty(),
		"generated Geology should pass its Validator"
	)


func _test_continental_support_semantics() -> void:
	var graph := _line_graph(7, 7)
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = PackedFloat32Array([20.0, 20.0, -10.0, -10.0, -10.0, 20.0, 20.0])
	var joined := _uniform_composition(7, GeologyGenerator.CONTINENTAL_PROVINCE_SUPPORT_THRESHOLD)
	var joined_geology := GeologyGenerator.generate(graph, joined, terrain)
	_expect(joined_geology != null, "submerged support bridge world should generate")
	if joined_geology != null:
		var province := joined_geology.province_id[0]
		for cell_id in graph.cell_count():
			_expect(joined_geology.province_id[cell_id] == province, "submerged support must connect and receive the land-seeded Province")
		_expect(province != GeologyCatalog.Province.OCEANIC_CRUST, "land-backed continental support must not remain Oceanic Crust")
	var split := _uniform_composition(7, 20)
	split.continental_value[3] = GeologyGenerator.CONTINENTAL_PROVINCE_SUPPORT_THRESHOLD - 1
	var split_components := GeologyGenerator._components_by_continental_support(graph, split)
	_expect(split_components.component_by_cell[3] == -1, "below-threshold Ocean must not belong to Province support")
	_expect(split_components.component_by_cell[2] != split_components.component_by_cell[4], "below-threshold Ocean must split continental support components")
	var split_geology := GeologyGenerator.generate(graph, split, terrain)
	_expect(split_geology != null, "split support world should generate")
	if split_geology != null:
		_expect(split_geology.province_id[3] == GeologyCatalog.Province.OCEANIC_CRUST, "below-threshold Cell must be Oceanic Crust")
	var submerged_terrain := TerrainHeightLayer.new()
	submerged_terrain.terrain_height = PackedFloat32Array([-10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0])
	var submerged_geology := GeologyGenerator.generate(graph, joined, submerged_terrain)
	_expect(submerged_geology != null, "pure submerged support world should generate")
	if submerged_geology != null:
		for province_id in submerged_geology.province_id:
			_expect(province_id == GeologyCatalog.Province.OCEANIC_CRUST, "support without a true-land seed must remain Oceanic Crust")


func _test_rock_catalog() -> void:
	var intrusive := RockCatalog.RockCategory.IGNEOUS_INTRUSIVE
	var extrusive := RockCatalog.RockCategory.IGNEOUS_EXTRUSIVE
	var metamorphic := RockCatalog.RockCategory.METAMORPHIC
	var sedimentary := RockCatalog.RockCategory.SEDIMENTARY
	var none := RockCatalog.IgneousComposition.NONE
	var expected_categories := [
		intrusive, intrusive, intrusive,
		extrusive, extrusive, extrusive, extrusive,
		sedimentary, sedimentary, sedimentary, sedimentary, sedimentary, sedimentary,
		sedimentary, sedimentary,
		metamorphic, metamorphic, metamorphic, metamorphic, metamorphic, metamorphic,
	]
	var expected_compositions := [
		RockCatalog.IgneousComposition.FELSIC,
		RockCatalog.IgneousComposition.INTERMEDIATE,
		RockCatalog.IgneousComposition.MAFIC,
		RockCatalog.IgneousComposition.FELSIC,
		RockCatalog.IgneousComposition.INTERMEDIATE,
		RockCatalog.IgneousComposition.INTERMEDIATE,
		RockCatalog.IgneousComposition.MAFIC,
		none, none, none, none, none, none, none, none, none, none, none, none, none, none,
	]
	var expected_permeability := [
		0.12, 0.10, 0.10, 0.15, 0.20, 0.18, 0.45, 0.60, 0.04, 0.03, 0.50,
		0.30, 0.32, 0.30, 0.05, 0.07, 0.08, 0.12, 0.12, 0.20, 0.05,
	]
	var expected_erodibility := [
		0.18, 0.17, 0.20, 0.25, 0.23, 0.24, 0.20, 0.55, 0.82, 0.88, 0.48,
		0.48, 0.40, 0.88, 0.10, 0.30, 0.38, 0.34, 0.20, 0.36, 0.08,
	]
	var expected_strength := [
		0.82, 0.85, 0.88, 0.75, 0.80, 0.78, 0.88, 0.45, 0.28, 0.20, 0.55,
		0.55, 0.62, 0.15, 0.90, 0.55, 0.48, 0.62, 0.80, 0.60, 0.95,
	]
	var karst_types := [
		RockCatalog.RockType.LIMESTONE, RockCatalog.RockType.DOLOMITE,
		RockCatalog.RockType.CHALK, RockCatalog.RockType.MARBLE,
	]
	_expect(RockCatalog.ROCK_TYPE_COUNT == 21, "RockCatalog must contain exactly 21 RockTypes")
	for rock_type in RockCatalog.ROCK_TYPE_COUNT:
		_expect(RockCatalog.is_valid_rock_type(rock_type), "every declared RockType must be valid")
		_expect(RockCatalog.category_for(rock_type) == expected_categories[rock_type], "Rock category must match the fixed table")
		_expect(RockCatalog.igneous_composition_for(rock_type) == expected_compositions[rock_type], "Rock composition must match the fixed table")
		_expect(is_equal_approx(RockCatalog.permeability_for(rock_type), expected_permeability[rock_type]), "Rock permeability must match the fixed table")
		_expect(is_equal_approx(RockCatalog.erodibility_for(rock_type), expected_erodibility[rock_type]), "Rock erodibility must match the fixed table")
		_expect(is_equal_approx(RockCatalog.rock_strength_for(rock_type), expected_strength[rock_type]), "Rock strength must match the fixed table")
		_expect(RockCatalog.karst_capable(rock_type) == (rock_type in karst_types), "only the four fixed RockTypes may be karst-capable")
		_expect(not RockCatalog.name_for(rock_type).begins_with("Unknown"), "every RockType must have a name")
		for value in [RockCatalog.permeability_for(rock_type), RockCatalog.erodibility_for(rock_type), RockCatalog.rock_strength_for(rock_type)]:
			_expect(value >= 0.0 and value <= 1.0, "continuous Rock properties must stay inside [0, 1]")
	_expect(not RockCatalog.is_valid_rock_type(-1) and not RockCatalog.is_valid_rock_type(21), "out-of-range RockTypes must be invalid")


func _test_rock_region_assignment() -> void:
	var graph := _line_graph(720, 1234)
	var provinces := PackedInt32Array()
	provinces.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		provinces[cell_id] = GeologyCatalog.Province.CRATON \
				if cell_id < 360 else GeologyCatalog.Province.SEDIMENTARY_BASIN
	var first := RockRegionAssigner.assign_seed_cells(graph, provinces, 41)
	var repeated := RockRegionAssigner.assign_seed_cells(graph, provinces, 41)
	var different := RockRegionAssigner.assign_seed_cells(graph, provinces, 42)
	_expect(first == repeated, "Rock Region assignment must be deterministic")
	_expect(first != different, "different world seeds should change Rock Regions")
	for cell_id in graph.cell_count():
		var seed_cell_id := first[cell_id]
		_expect(seed_cell_id >= 0 and seed_cell_id < graph.cell_count(), "every Cell must receive a valid Rock Region seed")
		_expect(provinces[seed_cell_id] == provinces[cell_id], "Rock Regions must not cross Province components")
	var region_cells := {}
	for cell_id in graph.cell_count():
		if not region_cells.has(first[cell_id]):
			region_cells[first[cell_id]] = PackedInt32Array()
		region_cells[first[cell_id]].append(cell_id)
	for region_seed in region_cells:
		_expect(_cells_are_connected(graph, region_cells[region_seed]), "every Rock Region must be graph-connected")


func _test_rock_layer_rules() -> void:
	_expect(RockLayerRules.validate_rules().is_empty(), "all Rock Layer roots must terminate at BOTTOM without cycles")
	var n := RockLayerRules.LayerNode
	var r := RockCatalog.RockType
	_expect(RockLayerRules.root_pool_for(GeologyCatalog.Province.OCEANIC_CRUST) == PackedInt32Array([n.EXTRUSIVE]), "Oceanic root pool must be EXTRUSIVE")
	_expect(RockLayerRules.root_pool_for(GeologyCatalog.Province.CRATON) == PackedInt32Array([n.INTRUSIVE, n.MM_HIGH_GRADE]), "Craton root pool must match the fixed mapping")
	_expect(RockLayerRules.root_pool_for(GeologyCatalog.Province.OROGENIC_BELT) == PackedInt32Array([n.UPLIFT, n.UPLIFT, n.UPLIFT, n.SEDIMENTARY]), "Orogenic root pool must be 75% UPLIFT")
	_expect(RockLayerRules.root_pool_for(GeologyCatalog.Province.SEDIMENTARY_BASIN) == PackedInt32Array([n.SEDIMENTARY]), "Basin root must be SEDIMENTARY")
	_expect(RockLayerRules.root_pool_for(GeologyCatalog.Province.PASSIVE_MARGIN) == PackedInt32Array([n.SEDIMENTARY]), "Passive Margin root must be SEDIMENTARY")
	_expect(RockLayerRules.root_pool_for(GeologyCatalog.Province.VOLCANIC_PROVINCE) == PackedInt32Array([n.EXTRUSIVE, n.EXTRUSIVE_X2, n.INTRUSIVE]), "Volcanic root pool must match the fixed mapping")
	_expect(RockLayerRules.transition_is_defined(n.SEDIMENTARY, r.SANDSTONE, n.MM_QUARTZITE), "Sandstone must transition to MM_QUARTZITE")
	var bottom_pool := RockLayerRules.bottom_pool()
	_expect(bottom_pool == PackedInt32Array([r.GNEISS, r.SCHIST, r.DIORITE, r.GRANITE, r.GABBRO]), "unified BOTTOM pool must match the fixed five rocks")
	var observed_terminals := {}
	var found_terminal_duplicate := false
	for province_id in GeologyCatalog.PROVINCE_COUNT:
		for seed_cell_id in 512:
			var sequence := RockLayerRules.sequence_for(province_id, 1, seed_cell_id)
			var raw := _raw_sequence_terminal(province_id, 1, seed_cell_id)
			_expect(not sequence.is_empty(), "every Province sequence must terminate")
			if sequence.is_empty():
				continue
			_expect(sequence[-1] in bottom_pool, "every sequence terminal must come from unified BOTTOM pool")
			observed_terminals[sequence[-1]] = true
			for index in range(1, sequence.size()):
				_expect(sequence[index] != sequence[index - 1], "complete sequence must remove an adjacent duplicate at BOTTOM")
			if raw.last_transition_rock == raw.terminal_rock:
				found_terminal_duplicate = true
				_expect(sequence[-1] == raw.terminal_rock, "deduplicated BOTTOM Rock must remain terminal")
				_expect(sequence.size() == 1 or sequence[-2] != raw.terminal_rock, "equal transition and BOTTOM Rock must be stored once")
	_expect(observed_terminals.size() == bottom_pool.size(), "deterministic coverage must observe all five BOTTOM rocks")
	_expect(found_terminal_duplicate, "deterministic coverage must include a transition/BOTTOM duplicate case")
	_test_all_transition_choices()


func _raw_sequence_terminal(province_id: int, world_seed: int, region_seed: int) -> Dictionary:
	var roots := RockLayerRules.root_pool_for(province_id)
	var rng_seed := DeterministicRng.stable_mix(
		DeterministicRng.stable_mix(world_seed, RockLayerRules.ROCK_SEQUENCE_SALT), region_seed
	)
	var rng := DeterministicRng.new(rng_seed)
	var node := roots[RockLayerRules._choice_index(rng.next_float(), roots.size())]
	var last_transition_rock := -1
	while node != RockLayerRules.LayerNode.BOTTOM:
		var choices := RockLayerRules.choices_for(node)
		var choice := choices[RockLayerRules._choice_index(rng.next_float(), choices.size())]
		last_transition_rock = choice.x
		node = choice.y
	var bottom_pool := RockLayerRules.bottom_pool()
	var terminal_rock := bottom_pool[
		RockLayerRules._choice_index(rng.next_float(), bottom_pool.size())
	]
	return {"last_transition_rock": last_transition_rock, "terminal_rock": terminal_rock}


func _test_all_transition_choices() -> void:
	var n := RockLayerRules.LayerNode
	var r := RockCatalog.RockType
	var expected := {
		n.FELSIC: [Vector2i(r.GRANITE, n.BOTTOM)],
		n.INTERMEDIATE: [Vector2i(r.DIORITE, n.BOTTOM)],
		n.MAFIC: [Vector2i(r.GABBRO, n.BOTTOM)],
		n.EXTRUSIVE: [Vector2i(r.RHYOLITE, n.FELSIC), Vector2i(r.ANDESITE, n.INTERMEDIATE), Vector2i(r.DACITE, n.INTERMEDIATE), Vector2i(r.BASALT, n.MAFIC)],
		n.EXTRUSIVE_X2: [Vector2i(r.RHYOLITE, n.EXTRUSIVE), Vector2i(r.ANDESITE, n.EXTRUSIVE), Vector2i(r.DACITE, n.EXTRUSIVE), Vector2i(r.BASALT, n.EXTRUSIVE)],
		n.INTRUSIVE: [Vector2i(r.GRANITE, n.FELSIC), Vector2i(r.DIORITE, n.INTERMEDIATE), Vector2i(r.GABBRO, n.MAFIC)],
		n.MM_HIGH_GRADE: [Vector2i(r.SCHIST, n.BOTTOM), Vector2i(r.GNEISS, n.BOTTOM)],
		n.MM_LOW_GRADE: [Vector2i(r.PHYLLITE, n.MM_HIGH_GRADE), Vector2i(r.SLATE, n.MM_HIGH_GRADE)],
		n.MM_MARBLE: [Vector2i(r.MARBLE, n.BOTTOM)],
		n.MM_QUARTZITE: [Vector2i(r.QUARTZITE, n.BOTTOM)],
		n.SEDIMENTARY: [Vector2i(r.SHALE, n.MM_LOW_GRADE), Vector2i(r.CLAYSTONE, n.MM_LOW_GRADE), Vector2i(r.CONGLOMERATE, n.MM_LOW_GRADE), Vector2i(r.LIMESTONE, n.MM_MARBLE), Vector2i(r.DOLOMITE, n.MM_MARBLE), Vector2i(r.CHALK, n.MM_MARBLE), Vector2i(r.CHERT, n.MM_QUARTZITE), Vector2i(r.SANDSTONE, n.MM_QUARTZITE)],
		n.UPLIFT: [Vector2i(r.SLATE, n.MM_HIGH_GRADE), Vector2i(r.PHYLLITE, n.MM_HIGH_GRADE), Vector2i(r.SCHIST, n.MM_HIGH_GRADE), Vector2i(r.GNEISS, n.MM_HIGH_GRADE), Vector2i(r.MARBLE, n.BOTTOM), Vector2i(r.QUARTZITE, n.BOTTOM), Vector2i(r.DIORITE, n.MM_LOW_GRADE), Vector2i(r.GRANITE, n.MM_LOW_GRADE), Vector2i(r.GABBRO, n.MM_LOW_GRADE)],
	}
	for node in expected:
		_expect(RockLayerRules.choices_for(node) == expected[node], "Rock Layer node %d choices must exactly match the fixed graph" % node)


func _test_province_regions_are_continuous() -> void:
	var count := 1200
	var graph := _line_graph(count, 99)
	var terrain := _all_land_terrain(count)
	var geology := GeologyGenerator.generate(graph, _uniform_composition(count, 20), terrain)
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


func _test_rock_regions_are_continuous() -> void:
	var count := 400
	var graph := _line_graph(count, 123)
	var terrain := _all_land_terrain(count)
	var geology := GeologyGenerator.generate(graph, _uniform_composition(count, 20), terrain)
	_expect(geology != null, "Rock Region continuity world should generate")
	if geology == null:
		return
	var expected_patch_count := ceili(
		float(count) / float(RockRegionAssigner.ROCK_REGION_TARGET_CELLS_PER_SEED)
	)
	_expect(
		_count_transitions(geology.rock_type_id) <= expected_patch_count,
		"Rock Region expansion should create patches, not independent Cell draws"
	)
	_expect(
		_minimum_run_length(geology.rock_type_id) > 2,
		"Rock Region generation should not create one- or two-Cell patches on the test line"
	)


func _test_flat_landmass_does_not_force_orogenic_quota() -> void:
	var count := 8000
	var graph := _line_graph(count, 31415)
	var terrain := _flat_terrain(count)
	var geology := GeologyGenerator.generate(graph, _uniform_composition(count, 20), terrain)
	_expect(geology != null, "flat landmass should generate Geology")
	if geology == null:
		return
	_expect(
		_province_ratio(geology, terrain, GeologyCatalog.Province.OROGENIC_BELT) < 0.20,
		"flat low-relief terrain should not receive the former 25% Orogenic quota"
	)


func _test_local_mountain_seed_increases_orogenic_weight() -> void:
	var graph := _line_graph(121, 31415)
	var terrain := _local_mountain_terrain(121, 30)
	var mountain_weights := _province_type_weights_at(graph, terrain, 30)
	var flat_weights := _province_type_weights_at(graph, terrain, 90)
	_expect(
		mountain_weights[GeologyCatalog.Province.OROGENIC_BELT] \
				> flat_weights[GeologyCatalog.Province.OROGENIC_BELT] * 2.0,
		"a high-relief local seed should have much more Orogenic weight than flat terrain"
	)


func _test_local_lowland_seed_increases_sedimentary_weight() -> void:
	var graph := _line_graph(121, 16180)
	var terrain := _local_lowland_terrain(121, 40)
	var lowland_weights := _province_type_weights_at(graph, terrain, 40)
	var level_weights := _province_type_weights_at(graph, terrain, 90)
	_expect(
		lowland_weights[GeologyCatalog.Province.SEDIMENTARY_BASIN] \
				> level_weights[GeologyCatalog.Province.SEDIMENTARY_BASIN],
		"a locally low, smooth seed should have more Sedimentary Basin weight"
	)


func _test_coastal_seed_increases_passive_margin_weight() -> void:
	var graph := _line_graph(121, 27182)
	var terrain := _coastal_flat_terrain(121, 10)
	var coastal_weights := _province_type_weights_at(graph, terrain, 10)
	var interior_weights := _province_type_weights_at(graph, terrain, 90)
	_expect(
		coastal_weights[GeologyCatalog.Province.PASSIVE_MARGIN] \
				> interior_weights[GeologyCatalog.Province.PASSIVE_MARGIN] * 2.0,
		"a low, smooth coastal seed should have much more Passive Margin weight"
	)


func _test_interior_flat_seed_increases_craton_weight() -> void:
	var graph := _line_graph(121, 27182)
	var terrain := _coastal_flat_terrain(121, 10)
	var coastal_weights := _province_type_weights_at(graph, terrain, 10)
	var interior_weights := _province_type_weights_at(graph, terrain, 90)
	_expect(
		interior_weights[GeologyCatalog.Province.CRATON] \
				> coastal_weights[GeologyCatalog.Province.CRATON],
		"a flat interior seed should have more Craton weight than a coastal seed"
	)


func _test_same_landmass_local_weights_are_distinct() -> void:
	var graph := _line_graph(121, 31415)
	var terrain := _local_mountain_terrain(121, 30)
	var mountain_weights := _province_type_weights_at(graph, terrain, 30)
	var flat_weights := _province_type_weights_at(graph, terrain, 90)
	_expect(
		mountain_weights != flat_weights,
		"different local terrain in one landmass must not share one type-weight distribution"
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


func _uniform_composition(cell_count: int, continental_value: int) -> WorldCompositionLayer:
	var composition := WorldCompositionLayer.new()
	composition.continental_value.resize(cell_count)
	composition.continental_value.fill(continental_value)
	return composition


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


func _local_mountain_terrain(cell_count: int, mountain_center: int) -> TerrainHeightLayer:
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height.resize(cell_count)
	terrain.terrain_height.fill(20.0)
	for cell_id in range(mountain_center - 2, mountain_center + 3):
		terrain.terrain_height[cell_id] = 90.0 if cell_id % 2 == 0 else 10.0
	return terrain


func _local_lowland_terrain(cell_count: int, lowland_center: int) -> TerrainHeightLayer:
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height.resize(cell_count)
	terrain.terrain_height.fill(40.0)
	for cell_id in range(lowland_center - 2, lowland_center + 3):
		terrain.terrain_height[cell_id] = 10.0
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


func _province_type_weights_at(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		seed_cell_id: int
) -> PackedFloat32Array:
	var land_cells := PackedInt32Array()
	for cell_id in graph.cell_count():
		if terrain.terrain_height[cell_id] >= 0.0:
			land_cells.append(cell_id)
	var cell_suitability := GeologyGenerator._province_suitability(graph, terrain)
	var landmass_context := GeologyGenerator._landmass_suitability(
		land_cells, cell_suitability
	)
	var local_suitability := GeologyGenerator._local_province_suitability(
		graph, terrain, seed_cell_id, GeologyGenerator._coast_steps(graph, terrain)
	)
	return GeologyGenerator.province_type_weights(local_suitability, landmass_context)


func _count_transitions(values: PackedInt32Array) -> int:
	var transitions := 0
	for cell_id in range(1, values.size()):
		if values[cell_id] != values[cell_id - 1]:
			transitions += 1
	return transitions


func _cells_are_connected(graph: SpatialGraph, cells: PackedInt32Array) -> bool:
	if cells.is_empty():
		return false
	var allowed := {}
	for cell_id in cells:
		allowed[cell_id] = true
	var reached := {cells[0]: true}
	var queue := PackedInt32Array([cells[0]])
	var index := 0
	while index < queue.size():
		var cell_id := queue[index]
		index += 1
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if allowed.has(neighbor_id) and not reached.has(neighbor_id):
				reached[neighbor_id] = true
				queue.append(neighbor_id)
	return reached.size() == cells.size()


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
		print("Geology RockType refactor: all dedicated test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Geology RockType refactor: %d failures" % _failures.size())
		quit(1)
