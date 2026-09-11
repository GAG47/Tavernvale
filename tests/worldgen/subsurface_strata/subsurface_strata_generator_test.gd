extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	var fixture := _world_fixture(1200)
	_test_structure_surface_and_validator(fixture)
	_test_queries_and_bounds(fixture)
	_test_settings_and_thickness()
	_test_adjacent_duplicate_normalization()
	_test_determinism_and_input_preservation(fixture)
	_test_validator_rejects_wrong_sequence(fixture)
	var standard := _world_fixture(20000)
	_test_standard_world(standard)
	_finish()


func _test_structure_surface_and_validator(fixture: Dictionary) -> void:
	_expect(not fixture.is_empty(), "synthetic Strata fixture must generate")
	if fixture.is_empty():
		return
	var graph: SpatialGraph = fixture.graph
	var terrain: TerrainHeightLayer = fixture.terrain
	var geology: GeologyLayer = fixture.geology
	var strata: SubsurfaceStrataLayer = fixture.strata
	_expect(strata != null, "Subsurface Strata must generate")
	if strata == null:
		return
	_expect(strata.cell_offsets is PackedInt32Array, "cell_offsets must be PackedInt32Array")
	_expect(strata.rock_type_ids is PackedInt32Array, "rock_type_ids must be PackedInt32Array")
	_expect(strata.top_z is PackedFloat32Array, "top_z must be PackedFloat32Array")
	_expect(strata.cell_offsets.size() == graph.cell_count() + 1, "CSR offsets must match Cells")
	_expect(strata.cell_offsets[0] == 0, "first CSR offset must be zero")
	_expect(strata.cell_offsets[-1] == strata.rock_type_ids.size(), "last offset must match records")
	_expect(strata.rock_type_ids.size() == strata.top_z.size(), "record arrays must have equal sizes")
	_expect(SubsurfaceStrataValidator.validate(
		graph, terrain, geology, strata, 1
	).is_empty(), "generated Strata must pass its Validator")
	for cell_id in graph.cell_count():
		var record_range := strata.record_range_for_cell(cell_id)
		_expect(record_range.y > record_range.x, "every Cell must have a terminating Rock sequence")
		_expect(strata.rock_type_ids[record_range.x] == geology.rock_type_id[cell_id], "surface RockType must match Geology")
		_expect(is_equal_approx(strata.top_z[record_range.x], terrain.terrain_height[cell_id]), "first top_z must match Final Terrain")
		for record_index in range(record_range.x, record_range.y):
			_expect(RockCatalog.is_valid_rock_type(strata.rock_type_ids[record_index]), "every stored RockType must be valid")
			if record_index + 1 < record_range.y:
				_expect(strata.top_z[record_index + 1] < strata.top_z[record_index], "top_z must strictly descend")
				_expect(strata.rock_type_ids[record_index + 1] != strata.rock_type_ids[record_index], "adjacent stored RockTypes must be normalized")


func _test_queries_and_bounds(fixture: Dictionary) -> void:
	if fixture.is_empty() or fixture.strata == null:
		return
	var graph: SpatialGraph = fixture.graph
	var terrain: TerrainHeightLayer = fixture.terrain
	var geology: GeologyLayer = fixture.geology
	var strata: SubsurfaceStrataLayer = fixture.strata
	for cell_id in graph.cell_count():
		var surface_z := terrain.terrain_height[cell_id]
		var record_range := strata.record_range_for_cell(cell_id)
		_expect(strata.rock_type_at_z(cell_id, surface_z) == geology.rock_type_id[cell_id], "surface query must return Geology RockType")
		_expect(strata.layer_index_at_z(cell_id, surface_z) == 0, "surface layer index must be zero")
		_expect(strata.rock_type_at_z(cell_id, surface_z + 1.0) == SubsurfaceStrataLayer.NO_ROCK, "above terrain must return NO_ROCK")
		for record_index in range(record_range.x, record_range.y):
			var local_index := record_index - record_range.x
			if local_index > 0:
				var boundary_z := strata.top_z[record_index]
				_expect(strata.rock_type_at_z(cell_id, boundary_z) == strata.rock_type_ids[record_index], "internal boundary must belong to lower Rock layer")
				_expect(strata.layer_index_at_z(cell_id, boundary_z) == local_index, "internal boundary must return lower local index")
			var bounds := strata.layer_bounds(cell_id, local_index)
			_expect(bounds.x == strata.top_z[record_index], "layer_bounds top must match top_z")
			if record_index + 1 == record_range.y:
				_expect(is_inf(bounds.y) and bounds.y < 0.0, "terminal basement must extend to -INF")
			else:
				_expect(bounds.y == strata.top_z[record_index + 1], "finite bottom must match next top_z")
		var terminal_index := record_range.y - 1
		_expect(strata.rock_type_at_z(cell_id, strata.top_z[terminal_index] - 10000.0) == strata.rock_type_ids[terminal_index], "terminal Rock must query arbitrarily deep")
	_expect(strata.rock_type_at_z(999999, 0.0) == SubsurfaceStrataLayer.NO_ROCK, "invalid Cell Rock query must be safe")


func _test_settings_and_thickness() -> void:
	var settings := SubsurfaceStrataSettings.new()
	var property_names := PackedStringArray()
	for property in settings.get_property_list():
		property_names.append(property.name)
	_expect("max_layers" not in property_names, "Subsurface Strata settings must not contain max_layers")
	_expect(settings.validate().is_empty(), "default Strata settings must be valid")
	_expect(is_equal_approx(SubsurfaceStrataGenerator.thickness_for(
		GeologyCatalog.Province.CRATON, 0, 0.5, settings
	), 24.0), "layer 0 must use depth factor 1.0")
	_expect(is_equal_approx(SubsurfaceStrataGenerator.thickness_for(
		GeologyCatalog.Province.CRATON, 1, 0.5, settings
	), 26.4), "layer 1 must use depth factor 1.1")
	_expect(is_equal_approx(SubsurfaceStrataGenerator.thickness_for(
		GeologyCatalog.Province.CRATON, 8, 0.5, settings
	), 28.8), "all deeper layers must cap depth factor at 1.2")
	var base_seed := DeterministicRng.stable_mix(1, SubsurfaceStrataGenerator.STRATA_SEED_SALT)
	_expect(SubsurfaceStrataGenerator.stable_layer_offset(base_seed, 2, 300.0) == SubsurfaceStrataGenerator.stable_layer_offset(base_seed, 2, 300.0), "thickness layer offset must be deterministic")
	_expect(SubsurfaceStrataGenerator.stable_layer_offset(base_seed, 1, 300.0) != SubsurfaceStrataGenerator.stable_layer_offset(base_seed, 2, 300.0), "logical layers must use distinct stable noise offsets")


func _test_adjacent_duplicate_normalization() -> void:
	for province_id in GeologyCatalog.PROVINCE_COUNT:
		for region_seed in 1024:
			var sequence := RockLayerRules.sequence_for(province_id, 1, region_seed)
			for index in range(1, sequence.size()):
				_expect(sequence[index] != sequence[index - 1], "sequence_for must normalize adjacent BOTTOM duplicates")


func _test_determinism_and_input_preservation(fixture: Dictionary) -> void:
	if fixture.is_empty():
		return
	var graph: SpatialGraph = fixture.graph
	var composition: WorldCompositionLayer = fixture.composition
	var terrain: TerrainHeightLayer = fixture.terrain
	var geology: GeologyLayer = fixture.geology
	var centers_before := graph.cell_centers.duplicate()
	var continental_before := composition.continental_value.duplicate()
	var heights_before := terrain.terrain_height.duplicate()
	var provinces_before := geology.province_id.duplicate()
	var rocks_before := geology.rock_type_id.duplicate()
	var first := SubsurfaceStrataGenerator.generate(graph, terrain, geology, 1)
	var second := SubsurfaceStrataGenerator.generate(graph, terrain, geology, 1)
	_expect(first != null and second != null, "Strata must generate twice")
	if first != null and second != null:
		_expect(first.cell_offsets == second.cell_offsets, "cell_offsets must be deterministic")
		_expect(first.rock_type_ids == second.rock_type_ids, "rock_type_ids must be deterministic")
		_expect(first.top_z == second.top_z, "top_z must be deterministic")
	_expect(graph.cell_centers == centers_before, "Strata must not modify SpatialGraph")
	_expect(composition.continental_value == continental_before, "Strata must not modify Composition")
	_expect(terrain.terrain_height == heights_before, "Strata must not modify Final Terrain")
	_expect(geology.province_id == provinces_before and geology.rock_type_id == rocks_before, "Strata must not modify Geology")


func _test_validator_rejects_wrong_sequence(fixture: Dictionary) -> void:
	if fixture.is_empty() or fixture.strata == null:
		return
	var bad: SubsurfaceStrataLayer = _duplicate_strata(fixture.strata)
	var changed := false
	for cell_id in fixture.graph.cell_count():
		var record_range := bad.record_range_for_cell(cell_id)
		if record_range.y - record_range.x < 2:
			continue
		var record_index := record_range.x + 1
		bad.rock_type_ids[record_index] = (bad.rock_type_ids[record_index] + 1) % RockCatalog.ROCK_TYPE_COUNT
		changed = true
		break
	_expect(changed, "validator fixture must contain a multi-layer Cell")
	var errors := SubsurfaceStrataValidator.validate(
		fixture.graph, fixture.terrain, fixture.geology, bad, 1
	)
	_expect(not errors.is_empty(), "Validator must reject a structurally plausible wrong Rock sequence")


func _test_standard_world(fixture: Dictionary) -> void:
	_expect(not fixture.is_empty() and fixture.strata != null, "standard 20k Strata world must generate")
	if fixture.is_empty() or fixture.strata == null:
		return
	var statistics := _standard_statistics(fixture)
	print("Province / RockType / Strata standard Seed 1 Continents 20k statistics:")
	print("  Surface RockType counts: %s" % str(statistics.surface_rock_counts))
	print("  Surface RockCategory counts: %s" % str(statistics.surface_category_counts))
	print("  Province counts total: %s" % str(statistics.province_counts))
	print("  Province counts land: %s" % str(statistics.land_province_counts))
	print("  Province counts ocean: %s" % str(statistics.ocean_province_counts))
	print("  Province components min/P50/P90/max: %s" % str(statistics.province_component_summary))
	print("  Cell 14185: %s" % str(statistics.cell_14185))
	print("  Rock Regions total/min/P10/P50/P90/max/size1/size2/size3-5/disconnected/cross: %s" % str(statistics.rock_region_summary))
	print("  Stored layer count mean/P50/P95/max: %.4f / %.1f / %.1f / %d" % [statistics.layer_mean, statistics.layer_p50, statistics.layer_p95, statistics.layer_max])
	print("  Terminal RockType counts [Gneiss, Schist, Diorite, Granite, Gabbro, Other]: %s" % str(statistics.terminal_counts))
	print("  Same Province + surface Rock neighbor exact sequence: %d/%d (%.6f)" % [statistics.sequence_match_count, statistics.sequence_pair_count, statistics.sequence_match_ratio])
	print("  Invalid Rocks / adjacent duplicates / unterminated: %d / %d / %d" % [statistics.invalid_rocks, statistics.adjacent_duplicates, statistics.unterminated])
	_expect(statistics.invalid_rocks == 0, "standard world must contain no invalid RockType")
	_expect(statistics.adjacent_duplicates == 0, "standard world must contain no adjacent stored duplicate")
	_expect(statistics.unterminated == 0, "standard world must contain no unterminated sequence")
	_expect(statistics.terminal_counts[5] == 0, "all terminal Rocks must use the unified BOTTOM pool")
	_expect(statistics.rock_region_summary.disconnected == 0, "all Rock Regions must be connected")
	_expect(statistics.rock_region_summary.cross_province == 0, "Rock Regions must not cross Province")


func _standard_statistics(fixture: Dictionary) -> Dictionary:
	var graph: SpatialGraph = fixture.graph
	var composition: WorldCompositionLayer = fixture.composition
	var terrain: TerrainHeightLayer = fixture.terrain
	var geology: GeologyLayer = fixture.geology
	var strata: SubsurfaceStrataLayer = fixture.strata
	var surface_rock_counts := PackedInt32Array()
	surface_rock_counts.resize(RockCatalog.ROCK_TYPE_COUNT)
	var surface_category_counts := PackedInt32Array()
	surface_category_counts.resize(RockCatalog.ROCK_CATEGORY_COUNT)
	var province_counts := PackedInt32Array()
	province_counts.resize(GeologyCatalog.PROVINCE_COUNT)
	var land_province_counts := PackedInt32Array()
	land_province_counts.resize(GeologyCatalog.PROVINCE_COUNT)
	var ocean_province_counts := PackedInt32Array()
	ocean_province_counts.resize(GeologyCatalog.PROVINCE_COUNT)
	var terminal_counts := PackedInt32Array()
	terminal_counts.resize(6)
	var layer_counts := PackedFloat32Array()
	var layer_total := 0.0
	var layer_max := 0
	var invalid_rocks := 0
	var adjacent_duplicates := 0
	var unterminated := 0
	var bottom_pool := RockLayerRules.bottom_pool()
	for cell_id in graph.cell_count():
		var surface_rock := geology.rock_type_id[cell_id]
		if RockCatalog.is_valid_rock_type(surface_rock):
			surface_rock_counts[surface_rock] += 1
			surface_category_counts[RockCatalog.category_for(surface_rock)] += 1
		else:
			invalid_rocks += 1
		province_counts[geology.province_id[cell_id]] += 1
		if terrain.terrain_height[cell_id] >= 0.0:
			land_province_counts[geology.province_id[cell_id]] += 1
		else:
			ocean_province_counts[geology.province_id[cell_id]] += 1
		var record_range := strata.record_range_for_cell(cell_id)
		var layer_count := record_range.y - record_range.x
		layer_counts.append(layer_count)
		layer_total += layer_count
		layer_max = maxi(layer_max, layer_count)
		if layer_count <= 0:
			unterminated += 1
			continue
		for record_index in range(record_range.x, record_range.y):
			if not RockCatalog.is_valid_rock_type(strata.rock_type_ids[record_index]):
				invalid_rocks += 1
			if record_index + 1 < record_range.y \
					and strata.rock_type_ids[record_index] == strata.rock_type_ids[record_index + 1]:
				adjacent_duplicates += 1
		var terminal := strata.rock_type_ids[record_range.y - 1]
		var bottom_index := bottom_pool.find(terminal)
		terminal_counts[bottom_index if bottom_index >= 0 else 5] += 1
	var sequence_pair_count := 0
	var sequence_match_count := 0
	for cell_id in graph.cell_count():
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if neighbor_id <= cell_id \
					or geology.province_id[neighbor_id] != geology.province_id[cell_id] \
					or geology.rock_type_id[neighbor_id] != geology.rock_type_id[cell_id]:
				continue
			sequence_pair_count += 1
			if _stored_sequence_equal(strata, cell_id, neighbor_id):
				sequence_match_count += 1
	layer_counts.sort()
	var province_component_summary := _province_component_summary(graph, geology)
	var rock_region_seed_cells := RockRegionAssigner.assign_seed_cells(graph, geology.province_id, 1)
	var rock_region_summary := _rock_region_summary(graph, geology, rock_region_seed_cells)
	var cell_14185 := _cell_regression_statistics(
		14185, graph, composition, terrain, geology, rock_region_seed_cells
	)
	return {
		"surface_rock_counts": surface_rock_counts,
		"surface_category_counts": surface_category_counts,
		"province_counts": province_counts,
		"land_province_counts": land_province_counts,
		"ocean_province_counts": ocean_province_counts,
		"province_component_summary": province_component_summary,
		"cell_14185": cell_14185,
		"rock_region_summary": rock_region_summary,
		"layer_mean": layer_total / float(graph.cell_count()),
		"layer_p50": _percentile(layer_counts, 0.50),
		"layer_p95": _percentile(layer_counts, 0.95),
		"layer_max": layer_max,
		"terminal_counts": terminal_counts,
		"sequence_pair_count": sequence_pair_count,
		"sequence_match_count": sequence_match_count,
		"sequence_match_ratio": float(sequence_match_count) / maxf(float(sequence_pair_count), 1.0),
		"invalid_rocks": invalid_rocks,
		"adjacent_duplicates": adjacent_duplicates,
		"unterminated": unterminated,
	}


func _province_component_summary(graph: SpatialGraph, geology: GeologyLayer) -> Dictionary:
	var visited := PackedByteArray()
	visited.resize(graph.cell_count())
	var sizes_by_province := {}
	for province_id in GeologyCatalog.PROVINCE_COUNT:
		sizes_by_province[province_id] = PackedFloat32Array()
	for start in graph.cell_count():
		if visited[start] != 0:
			continue
		var province_id := geology.province_id[start]
		var queue := PackedInt32Array([start])
		visited[start] = 1
		var index := 0
		while index < queue.size():
			var cell_id := queue[index]
			index += 1
			for neighbor_id in graph.cell_neighbors[cell_id]:
				if visited[neighbor_id] == 0 and geology.province_id[neighbor_id] == province_id:
					visited[neighbor_id] = 1
					queue.append(neighbor_id)
		sizes_by_province[province_id].append(queue.size())
	var result := {}
	for province_id in GeologyCatalog.PROVINCE_COUNT:
		var sizes: PackedFloat32Array = sizes_by_province[province_id]
		sizes.sort()
		result[GeologyCatalog.province_name(province_id)] = {
			"components": sizes.size(),
			"min": 0.0 if sizes.is_empty() else sizes[0],
			"p50": _percentile(sizes, 0.50),
			"p90": _percentile(sizes, 0.90),
			"max": 0.0 if sizes.is_empty() else sizes[-1],
		}
	return result


func _rock_region_summary(
		graph: SpatialGraph, geology: GeologyLayer, seeds: PackedInt32Array
) -> Dictionary:
	var cells_by_seed := {}
	for cell_id in graph.cell_count():
		var seed := seeds[cell_id]
		if not cells_by_seed.has(seed):
			cells_by_seed[seed] = PackedInt32Array()
		cells_by_seed[seed].append(cell_id)
	var sizes := PackedFloat32Array()
	var size_1 := 0
	var size_2 := 0
	var size_3_5 := 0
	var disconnected := 0
	var cross_province := 0
	for seed in cells_by_seed:
		var cells: PackedInt32Array = cells_by_seed[seed]
		sizes.append(cells.size())
		size_1 += int(cells.size() == 1)
		size_2 += int(cells.size() == 2)
		size_3_5 += int(cells.size() >= 3 and cells.size() <= 5)
		var allowed := {}
		for cell_id in cells:
			allowed[cell_id] = true
			if geology.province_id[cell_id] != geology.province_id[seed]:
				cross_province += 1
				break
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
		if reached.size() != cells.size():
			disconnected += 1
	sizes.sort()
	return {
		"total": sizes.size(), "min": sizes[0], "p10": _percentile(sizes, 0.10),
		"p50": _percentile(sizes, 0.50), "p90": _percentile(sizes, 0.90),
		"max": sizes[-1], "size_1": size_1, "size_2": size_2, "size_3_5": size_3_5,
		"disconnected": disconnected, "cross_province": cross_province,
	}


func _cell_regression_statistics(
		cell_id: int, graph: SpatialGraph, composition: WorldCompositionLayer,
		terrain: TerrainHeightLayer, geology: GeologyLayer, region_seeds: PackedInt32Array
) -> Dictionary:
	var support := GeologyGenerator._components_by_continental_support(graph, composition)
	var support_component_id: int = support.component_by_cell[cell_id]
	var support_size: int = 0 if support_component_id < 0 \
			else support.components[support_component_id].size()
	var region_seed := region_seeds[cell_id]
	var terrain_component_size := _matching_component_size(graph, cell_id, func(id: int) -> bool: return terrain.terrain_height[id] >= 0.0)
	var province_component_size := _matching_component_size(graph, cell_id, func(id: int) -> bool: return geology.province_id[id] == geology.province_id[cell_id])
	var region_size := _matching_component_size(graph, cell_id, func(id: int) -> bool: return region_seeds[id] == region_seed)
	return {
		"terrain_land_component_size": terrain_component_size,
		"continental_support_component_size": support_size,
		"province": GeologyCatalog.province_name(geology.province_id[cell_id]),
		"province_component_size": province_component_size,
		"rock_region_size": region_size,
		"surface_rock": RockCatalog.name_for(geology.rock_type_id[cell_id]),
	}


func _matching_component_size(graph: SpatialGraph, start: int, predicate: Callable) -> int:
	if not predicate.call(start):
		return 0
	var reached := {start: true}
	var queue := PackedInt32Array([start])
	var index := 0
	while index < queue.size():
		var cell_id := queue[index]
		index += 1
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if not reached.has(neighbor_id) and predicate.call(neighbor_id):
				reached[neighbor_id] = true
				queue.append(neighbor_id)
	return reached.size()


func _world_fixture(cell_count: int) -> Dictionary:
	var graph := SpatialGenerator.generate(
		SpatialConfig.new(1, 2000.0, 1000.0, cell_count, 0.9)
	)
	if graph == null:
		return {}
	var composition := WorldCompositionGenerator.generate(
		graph, WorldCompositionConfig.new(1, &"continents")
	)
	var projected := TerrainHeightProjector.project(composition.continental_value)
	var geology := GeologyGenerator.generate(graph, composition, projected)
	var climate_settings := WorldClimateSettings.new(70.0, -20.0)
	var preliminary_climate := WorldClimateGenerator.generate(graph, projected, climate_settings)
	var hydrology_settings := WorldHydrologySettings.new()
	var preliminary_flow := PreliminaryFlowGenerator.generate(
		graph, projected, preliminary_climate, hydrology_settings
	)
	var conditioning := HydrologyConditioner.condition(
		graph, projected, preliminary_flow, geology, HydrologyConditioningSettings.new()
	)
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = conditioning.terrain_height.duplicate()
	var strata := SubsurfaceStrataGenerator.generate(
		graph, terrain, geology, 1, SubsurfaceStrataSettings.new()
	)
	return {
		"graph": graph,
		"composition": composition,
		"terrain": terrain,
		"geology": geology,
		"strata": strata,
	}


func _single_cell_graph(world_seed: int) -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(world_seed, 1.0, 1.0, 1, 0.9)
	graph.spacing = 1.0
	graph.cell_centers = PackedVector2Array([Vector2.ZERO])
	graph.cell_neighbors = [PackedInt32Array()]
	graph.cell_neighbor_distances = [PackedFloat64Array()]
	return graph


func _duplicate_strata(source: SubsurfaceStrataLayer) -> SubsurfaceStrataLayer:
	var result := SubsurfaceStrataLayer.new()
	result.cell_offsets = source.cell_offsets.duplicate()
	result.rock_type_ids = source.rock_type_ids.duplicate()
	result.top_z = source.top_z.duplicate()
	return result


func _stored_sequence_equal(strata: SubsurfaceStrataLayer, first: int, second: int) -> bool:
	var first_range := strata.record_range_for_cell(first)
	var second_range := strata.record_range_for_cell(second)
	if first_range.y - first_range.x != second_range.y - second_range.x:
		return false
	for local_index in first_range.y - first_range.x:
		if strata.rock_type_ids[first_range.x + local_index] \
				!= strata.rock_type_ids[second_range.x + local_index]:
			return false
	return true


func _percentile(sorted: PackedFloat32Array, percentile: float) -> float:
	if sorted.is_empty():
		return 0.0
	var position := float(sorted.size() - 1) * percentile
	var lower := floori(position)
	var upper := ceili(position)
	return sorted[lower] if lower == upper else lerpf(
		sorted[lower], sorted[upper], position - lower
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("RockType / Subsurface Strata: all dedicated test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("RockType / Subsurface Strata: %d failures" % _failures.size())
		quit(1)
