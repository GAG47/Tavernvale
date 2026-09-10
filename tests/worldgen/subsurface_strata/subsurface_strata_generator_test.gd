extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	var fixture := _synthetic_fixture()
	_test_structure_surface_and_validator(fixture)
	_test_queries_and_bounds(fixture)
	_test_transition_rules()
	_test_deep_substrate_threshold()
	_test_oceanic_deep_substrate_routes()
	_test_validator_rejects_illegal_transition()
	_test_determinism_and_input_preservation(fixture)
	_test_invalid_layer_queries(fixture)
	var standard := _standard_world_fixture()
	_test_standard_world(standard)
	_finish()


func _test_structure_surface_and_validator(fixture: Dictionary) -> void:
	var graph: SpatialGraph = fixture.graph
	var composition: WorldCompositionLayer = fixture.composition
	var terrain: TerrainHeightLayer = fixture.terrain
	var geology: GeologyLayer = fixture.geology
	var strata: SubsurfaceStrataLayer = fixture.strata
	_expect(strata != null, "synthetic Subsurface Strata should generate")
	if strata == null:
		return
	_expect(strata.cell_offsets is PackedInt32Array, "cell_offsets must be PackedInt32Array")
	_expect(strata.material_ids is PackedInt32Array, "material_ids must be PackedInt32Array")
	_expect(strata.top_z is PackedFloat32Array, "top_z must be PackedFloat32Array")
	_expect(strata.cell_offsets.size() == graph.cell_count() + 1, "CSR offsets must match Cells")
	_expect(strata.cell_offsets[0] == 0, "first CSR offset must be zero")
	_expect(strata.cell_offsets[-1] == strata.material_ids.size(), "last offset must match records")
	_expect(strata.material_ids.size() == strata.top_z.size(), "record arrays must have equal sizes")
	_expect(
		SubsurfaceStrataValidator.validate(
			graph, composition, terrain, geology, strata, fixture.world_seed
		).is_empty(),
		"generated synthetic Strata should pass its Validator"
	)
	var settings := SubsurfaceStrataSettings.new()
	var base_seed := DeterministicRng.stable_mix(
		fixture.world_seed, SubsurfaceStrataGenerator.STRATA_SEED_SALT
	)
	var deep_noise := SubsurfaceStrataGenerator.make_deep_crust_noise(base_seed, settings)
	for cell_id in graph.cell_count():
		var record_range := strata.record_range_for_cell(cell_id)
		var layer_count := record_range.y - record_range.x
		_expect(layer_count >= 1 and layer_count <= 4, "every Cell must have 1..4 layers")
		_expect(strata.material_ids[record_range.x] == geology.material_id[cell_id], "surface Material must match Geology")
		_expect(is_equal_approx(strata.top_z[record_range.x], terrain.terrain_height[cell_id]), "surface top_z must match Final Terrain")
		var position := graph.cell_centers[cell_id]
		var is_deep_continental := SubsurfaceStrataGenerator.is_continental_deep_substrate(
			composition.continental_value[cell_id],
			deep_noise.get_noise_2d(position.x, position.y),
			settings
		)
		var expected_terminal := GeologyCatalog.MaterialType.CRYSTALLINE_ROCK
		if geology.province_id[cell_id] == GeologyCatalog.Province.OCEANIC_CRUST \
				and not is_deep_continental:
			expected_terminal = GeologyCatalog.MaterialType.VOLCANIC_ROCK
		_expect(strata.material_ids[record_range.y - 1] == expected_terminal, "terminal Material must match Province")
		for record_index in range(record_range.x, record_range.y - 1):
			_expect(strata.top_z[record_index + 1] < strata.top_z[record_index], "top_z must strictly descend")
			_expect(strata.material_ids[record_index + 1] != strata.material_ids[record_index], "adjacent Materials must differ")
			_expect(_transition_is_legal(
				geology.province_id[cell_id],
				strata.material_ids[record_index],
				strata.material_ids[record_index + 1],
				record_index - record_range.x,
				is_deep_continental
			), "generated transition must be legal")


func _test_queries_and_bounds(fixture: Dictionary) -> void:
	var graph: SpatialGraph = fixture.graph
	var terrain: TerrainHeightLayer = fixture.terrain
	var geology: GeologyLayer = fixture.geology
	var strata: SubsurfaceStrataLayer = fixture.strata
	if strata == null:
		return
	for cell_id in graph.cell_count():
		var record_range := strata.record_range_for_cell(cell_id)
		_expect(strata.material_at_z(cell_id, terrain.terrain_height[cell_id]) == geology.material_id[cell_id], "surface query must return Geology Material")
		_expect(strata.layer_index_at_z(cell_id, terrain.terrain_height[cell_id]) == 0, "surface layer index must be zero")
		_expect(strata.material_at_z(cell_id, terrain.terrain_height[cell_id] + 1.0) == SubsurfaceStrataLayer.NO_MATERIAL, "above-ground query must return NO_MATERIAL")
		_expect(strata.layer_index_at_z(cell_id, terrain.terrain_height[cell_id] + 1.0) == -1, "above-ground layer index must be -1")
		for record_index in range(record_range.x, record_range.y):
			var local_index := record_index - record_range.x
			if local_index > 0:
				var boundary_z := strata.top_z[record_index]
				_expect(
					strata.material_at_z(cell_id, boundary_z) \
							== strata.material_ids[record_index],
					"internal boundary must belong to the lower layer Material"
				)
				_expect(
					strata.layer_index_at_z(cell_id, boundary_z) == local_index,
					"internal boundary must belong to the lower local layer index"
				)
			var bounds := strata.layer_bounds(cell_id, local_index)
			var expected_bottom := -INF if record_index + 1 == record_range.y else strata.top_z[record_index + 1]
			_expect(bounds.x == strata.top_z[record_index], "layer_bounds top must match record top_z")
			_expect(bounds.y == expected_bottom, "layer_bounds bottom must be next top_z or -INF")
			if record_index + 1 < record_range.y:
				var midpoint := (strata.top_z[record_index] + strata.top_z[record_index + 1]) * 0.5
				_expect(strata.material_at_z(cell_id, midpoint) == strata.material_ids[record_index], "finite layer midpoint must query its Material")
				_expect(strata.layer_index_at_z(cell_id, midpoint) == local_index, "finite layer midpoint must query its local index")
		var last_index := record_range.y - 1
		_expect(strata.material_at_z(cell_id, strata.top_z[last_index] - 1000.0) == strata.material_ids[last_index], "terminal layer must extend arbitrarily deep")


func _test_transition_rules() -> void:
	var m := GeologyCatalog.MaterialType
	var p := GeologyCatalog.Province
	_expect(SubsurfaceStrataGenerator.next_material_for(p.OCEANIC_CRUST, m.MARINE_SEDIMENTARY_ROCK, 0, 0.5) == m.VOLCANIC_ROCK, "Oceanic sediment must transition to Volcanic")
	_expect(SubsurfaceStrataGenerator.next_material_for(p.OCEANIC_CRUST, m.VOLCANIC_ROCK, 0, 0.5) == SubsurfaceStrataLayer.NO_MATERIAL, "Oceanic Volcanic must terminate")
	_expect(SubsurfaceStrataGenerator.next_material_for(p.CRATON, m.SANDSTONE, 0, 0.34) == m.METAMORPHIC_ROCK, "Craton lower selector must enter Metamorphic")
	_expect(SubsurfaceStrataGenerator.next_material_for(p.CRATON, m.SANDSTONE, 0, 0.35) == m.CRYSTALLINE_ROCK, "Craton threshold must enter Crystalline")
	_expect(SubsurfaceStrataGenerator.next_material_for(p.OROGENIC_BELT, m.VOLCANIC_ROCK, 0, 0.79) == m.METAMORPHIC_ROCK, "Orogenic lower selector must enter Metamorphic")
	_expect(SubsurfaceStrataGenerator.next_material_for(p.OROGENIC_BELT, m.VOLCANIC_ROCK, 0, 0.80) == m.CRYSTALLINE_ROCK, "Orogenic threshold must enter Crystalline")
	_expect(SubsurfaceStrataGenerator.next_material_for(p.SEDIMENTARY_BASIN, m.SANDSTONE, 0, 0.59) == m.SHALE_MUDSTONE, "Basin Sandstone first layer must alternate sediment")
	_expect(SubsurfaceStrataGenerator.next_material_for(p.SEDIMENTARY_BASIN, m.SANDSTONE, 1, 0.64) == m.METAMORPHIC_ROCK, "deep Basin sediment must enter Metamorphic")
	_expect(SubsurfaceStrataGenerator.next_material_for(p.PASSIVE_MARGIN, m.CARBONATE_ROCK, 0, 0.30) == m.SANDSTONE, "Passive Margin Carbonate second band must enter Sandstone")
	_expect(SubsurfaceStrataGenerator.next_material_for(p.VOLCANIC_PROVINCE, m.SHALE_MUDSTONE, 0, 0.59) == m.VOLCANIC_ROCK, "Volcanic Province sediment should commonly enter Volcanic")
	_expect(SubsurfaceStrataGenerator.next_material_for(p.CRATON, m.CRYSTALLINE_ROCK, 0, 0.0) == SubsurfaceStrataLayer.NO_MATERIAL, "continental Crystalline must terminate")
	_expect(SubsurfaceStrataGenerator.next_material_for(p.CRATON, m.METAMORPHIC_ROCK, 0, 1.0) == m.CRYSTALLINE_ROCK, "continental Metamorphic must enter Crystalline")
	var settings := SubsurfaceStrataSettings.new()
	settings.max_layers = 3
	_expect(not settings.validate().is_empty(), "v3.0.1 settings must reject max_layers other than four")


func _test_deep_substrate_threshold() -> void:
	var settings := SubsurfaceStrataSettings.new()
	_expect(
		SubsurfaceStrataGenerator.is_continental_deep_substrate(20, -1.0, settings),
		"continental value 20 with deep noise -1 must remain Continental"
	)
	_expect(
		SubsurfaceStrataGenerator.is_continental_deep_substrate(14, 0.0, settings),
		"deep score exactly 14 must be Continental"
	)
	_expect(
		not SubsurfaceStrataGenerator.is_continental_deep_substrate(13, 0.0, settings),
		"deep score 13 must be Oceanic"
	)
	_expect(
		not SubsurfaceStrataGenerator.is_continental_deep_substrate(17, -1.0, settings),
		"continental value 17 with deep noise -1 must be Oceanic"
	)
	_expect(
		SubsurfaceStrataGenerator.is_continental_deep_substrate(17, 1.0, settings),
		"continental value 17 with deep noise +1 must be Continental"
	)


func _test_oceanic_deep_substrate_routes() -> void:
	var m := GeologyCatalog.MaterialType
	var oceanic := _oceanic_route(0, m.MARINE_SEDIMENTARY_ROCK)
	_expect(
		oceanic.material_ids == PackedInt32Array([m.MARINE_SEDIMENTARY_ROCK, m.VOLCANIC_ROCK]),
		"Oceanic surface plus Oceanic Deep Substrate must terminate in Volcanic"
	)
	var continental := _oceanic_route(20, m.MARINE_SEDIMENTARY_ROCK)
	_expect(
		continental.material_ids == PackedInt32Array([
			m.MARINE_SEDIMENTARY_ROCK, m.VOLCANIC_ROCK, m.CRYSTALLINE_ROCK
		]),
		"Oceanic surface plus Continental Deep Substrate must enter Crystalline"
	)
	var volcanic_continental := _oceanic_route(20, m.VOLCANIC_ROCK)
	_expect(
		volcanic_continental.material_ids == PackedInt32Array([
			m.VOLCANIC_ROCK, m.CRYSTALLINE_ROCK
		]),
		"Oceanic surface Volcanic plus Continental Deep Substrate must enter Crystalline"
	)


func _test_validator_rejects_illegal_transition() -> void:
	var graph := SpatialGraph.new()
	graph.cell_centers = PackedVector2Array([Vector2.ZERO])
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = PackedFloat32Array([10.0])
	var composition := WorldCompositionLayer.new()
	composition.continental_value = PackedInt32Array([20])
	var geology := GeologyLayer.new()
	geology.province_id = PackedInt32Array([GeologyCatalog.Province.SEDIMENTARY_BASIN])
	geology.material_id = PackedInt32Array([GeologyCatalog.MaterialType.SANDSTONE])
	var strata := SubsurfaceStrataLayer.new()
	strata.cell_offsets = PackedInt32Array([0, 3])
	strata.material_ids = PackedInt32Array([
		GeologyCatalog.MaterialType.SANDSTONE,
		GeologyCatalog.MaterialType.VOLCANIC_ROCK,
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
	])
	strata.top_z = PackedFloat32Array([10.0, -10.0, -30.0])
	var errors := SubsurfaceStrataValidator.validate(
		graph, composition, terrain, geology, strata, 1
	)
	_expect(
		not errors.is_empty(),
		"Validator must reject a structurally valid column with an illegal transition"
	)
	var reported_transition_error := false
	for error in errors:
		if "transition is not allowed" in error:
			reported_transition_error = true
			break
	_expect(reported_transition_error, "Validator must identify the illegal transition")


func _test_determinism_and_input_preservation(fixture: Dictionary) -> void:
	var graph: SpatialGraph = fixture.graph
	var composition: WorldCompositionLayer = fixture.composition
	var terrain: TerrainHeightLayer = fixture.terrain
	var geology: GeologyLayer = fixture.geology
	var centers_before := graph.cell_centers.duplicate()
	var continental_values_before := composition.continental_value.duplicate()
	var heights_before := terrain.terrain_height.duplicate()
	var provinces_before := geology.province_id.duplicate()
	var materials_before := geology.material_id.duplicate()
	var first := SubsurfaceStrataGenerator.generate(
		graph, composition, terrain, geology, fixture.world_seed
	)
	var second := SubsurfaceStrataGenerator.generate(
		graph, composition, terrain, geology, fixture.world_seed
	)
	_expect(first != null and second != null, "determinism fixture should generate twice")
	if first != null and second != null:
		_expect(first.cell_offsets == second.cell_offsets, "cell_offsets must be deterministic")
		_expect(first.material_ids == second.material_ids, "material_ids must be deterministic")
		_expect(first.top_z == second.top_z, "top_z must be deterministic")
	_expect(graph.cell_centers == centers_before, "Generator must not modify SpatialGraph")
	_expect(
		composition.continental_value == continental_values_before,
		"Generator must not modify World Composition"
	)
	_expect(terrain.terrain_height == heights_before, "Generator must not modify Final Terrain")
	_expect(geology.province_id == provinces_before, "Generator must not modify Geology Provinces")
	_expect(geology.material_id == materials_before, "Generator must not modify Geology Materials")


func _test_invalid_layer_queries(fixture: Dictionary) -> void:
	var strata: SubsurfaceStrataLayer = fixture.strata
	if strata == null:
		return
	_expect(strata.record_range_for_cell(-1) == Vector2i(-1, -1), "negative Cell query must be safe")
	_expect(strata.material_at_z(9999, 0.0) == SubsurfaceStrataLayer.NO_MATERIAL, "invalid Cell material query must be safe")
	_expect(strata.layer_index_at_z(0, NAN) == -1, "non-finite z query must be safe")
	var invalid_bounds := strata.layer_bounds(0, 9999)
	_expect(is_nan(invalid_bounds.x) and is_nan(invalid_bounds.y), "invalid bounds query must return NaN sentinel")


func _test_standard_world(fixture: Dictionary) -> void:
	_expect(not fixture.is_empty(), "standard 20k final conditioned Terrain fixture should generate")
	if fixture.is_empty():
		return
	var graph: SpatialGraph = fixture.graph
	var composition: WorldCompositionLayer = fixture.composition
	var projected: TerrainHeightLayer = fixture.projected
	var terrain: TerrainHeightLayer = fixture.terrain
	var geology: GeologyLayer = fixture.geology
	var strata: SubsurfaceStrataLayer = fixture.strata
	_expect(graph.cell_count() == 20000, "standard statistics world must contain 20,000 Cells")
	_expect(strata != null, "standard world Strata should generate")
	if strata == null:
		return
	_expect(
		SubsurfaceStrataValidator.validate(
			graph, composition, terrain, geology, strata, fixture.world_seed
		).is_empty(),
		"standard world must pass Strata validation"
	)
	var conditioned_changes := 0
	for cell_id in graph.cell_count():
		if terrain.terrain_height[cell_id] != projected.terrain_height[cell_id]:
			conditioned_changes += 1
		var begin := strata.cell_offsets[cell_id]
		_expect(strata.top_z[begin] == terrain.terrain_height[cell_id], "standard Strata must use conditioned Terrain")
	_expect(conditioned_changes > 0, "standard fixture should exercise Hydrology-conditioned Terrain")

	var statistics := _strata_statistics(
		graph, composition, terrain, geology, strata, fixture.world_seed
	)
	print("Subsurface Strata standard 20k statistics:")
	print("  World layers mean %.4f / P50 %.1f / P95 %.1f / max %.0f" % [statistics.world_mean, statistics.world_p50, statistics.world_p95, statistics.world_max])
	for province_id in GeologyCatalog.PROVINCE_COUNT:
		var province: Dictionary = statistics.provinces[province_id]
		print("  %s: Cells %d, layers mean %.4f / P50 %.1f / P95 %.1f, terminals %s" % [GeologyCatalog.province_name(province_id), province.count, province.mean, province.p50, province.p95, str(province.terminals)])
	print("  Material record counts: %s" % str(statistics.material_records))
	print("  Matching same-province/surface adjacent sequences: %d / %d (%.4f)" % [statistics.matching_pairs, statistics.eligible_pairs, statistics.adjacent_sequence_ratio])
	print("  Land Cells: %d" % statistics.land_count)
	print("  Ocean Cells: %d" % statistics.ocean_count)
	print("  Land + Continental Deep Substrate: %d" % statistics.land_continental_deep_count)
	print("  Land + Oceanic Deep Substrate: %d" % statistics.land_oceanic_deep_count)
	print("  Ocean + Continental Deep Substrate: %d (%.4f)" % [statistics.ocean_continental_deep_count, statistics.ocean_continental_deep_ratio])
	print("  Ocean + Oceanic Deep Substrate: %d (%.4f)" % [statistics.ocean_oceanic_deep_count, statistics.ocean_oceanic_deep_ratio])
	print("  Surface Land/Water Boundary Edges: %d" % statistics.surface_boundary_edges)
	print("  Deep Substrate Boundary Edges: %d" % statistics.deep_boundary_edges)
	print("  Coincident Deep/Surface Boundary Edges: %d" % statistics.coincident_boundary_edges)
	print("  Deep boundary / surface coincidence ratio: %.4f" % statistics.deep_boundary_surface_coincidence_ratio)
	_expect(
		statistics.land_oceanic_deep_count == 0,
		"normal Land Cells must never use Oceanic Deep Substrate"
	)
	for cell_id in graph.cell_count():
		if terrain.terrain_height[cell_id] < 0.0:
			continue
		var record_range := strata.record_range_for_cell(cell_id)
		_expect(
			strata.material_ids[record_range.y - 1] \
					== GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
			"normal Land Cells must retain Crystalline terminal Material"
		)

	var basin: Dictionary = statistics.provinces[GeologyCatalog.Province.SEDIMENTARY_BASIN]
	var craton: Dictionary = statistics.provinces[GeologyCatalog.Province.CRATON]
	var orogenic: Dictionary = statistics.provinces[GeologyCatalog.Province.OROGENIC_BELT]
	if basin.count >= 100 and craton.count >= 100:
		_expect(basin.mean > craton.mean, "Sedimentary Basin mean layer count must exceed Craton")
	if orogenic.count >= 100 and craton.count >= 100:
		_expect(orogenic.metamorphic_ratio > craton.metamorphic_ratio, "Orogenic Metamorphic-column ratio must exceed Craton")


func _oceanic_route(
		continental_value: int, surface_material: int
) -> SubsurfaceStrataLayer:
	var graph := SpatialGraph.new()
	graph.cell_centers = PackedVector2Array([Vector2(100.0, 100.0)])
	var composition := WorldCompositionLayer.new()
	composition.continental_value = PackedInt32Array([continental_value])
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = PackedFloat32Array([-10.0])
	var geology := GeologyLayer.new()
	geology.province_id = PackedInt32Array([GeologyCatalog.Province.OCEANIC_CRUST])
	geology.material_id = PackedInt32Array([surface_material])
	return SubsurfaceStrataGenerator.generate(graph, composition, terrain, geology, 1)


func _synthetic_fixture() -> Dictionary:
	var graph := SpatialGraph.new()
	var count := 18
	graph.cell_centers.resize(count)
	graph.cell_neighbors.resize(count)
	for cell_id in count:
		graph.cell_centers[cell_id] = Vector2(float(cell_id % 6) * 90.0, float(cell_id / 6) * 90.0)
		var neighbors := PackedInt32Array()
		if cell_id > 0:
			neighbors.append(cell_id - 1)
		if cell_id + 1 < count:
			neighbors.append(cell_id + 1)
		graph.cell_neighbors[cell_id] = neighbors
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height.resize(count)
	var composition := WorldCompositionLayer.new()
	composition.continental_value.resize(count)
	var geology := GeologyLayer.new()
	geology.province_id.resize(count)
	geology.material_id.resize(count)
	var surface_materials := PackedInt32Array([
		GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK,
		GeologyCatalog.MaterialType.VOLCANIC_ROCK,
		GeologyCatalog.MaterialType.SANDSTONE,
		GeologyCatalog.MaterialType.METAMORPHIC_ROCK,
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
		GeologyCatalog.MaterialType.VOLCANIC_ROCK,
		GeologyCatalog.MaterialType.SHALE_MUDSTONE,
		GeologyCatalog.MaterialType.SANDSTONE,
		GeologyCatalog.MaterialType.CARBONATE_ROCK,
		GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK,
		GeologyCatalog.MaterialType.SANDSTONE,
		GeologyCatalog.MaterialType.CARBONATE_ROCK,
		GeologyCatalog.MaterialType.SHALE_MUDSTONE,
		GeologyCatalog.MaterialType.VOLCANIC_ROCK,
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
		GeologyCatalog.MaterialType.VOLCANIC_ROCK,
		GeologyCatalog.MaterialType.SANDSTONE,
		GeologyCatalog.MaterialType.METAMORPHIC_ROCK,
	])
	for cell_id in count:
		geology.province_id[cell_id] = cell_id / 3
		geology.material_id[cell_id] = surface_materials[cell_id]
		terrain.terrain_height[cell_id] = -20.0 - cell_id if geology.province_id[cell_id] == GeologyCatalog.Province.OCEANIC_CRUST else 10.0 + cell_id
		composition.continental_value[cell_id] = 0 \
				if geology.province_id[cell_id] == GeologyCatalog.Province.OCEANIC_CRUST else 20
	return {
		"graph": graph,
		"composition": composition,
		"terrain": terrain,
		"geology": geology,
		"world_seed": 12345,
		"strata": SubsurfaceStrataGenerator.generate(
			graph, composition, terrain, geology, 12345
		),
	}


func _standard_world_fixture() -> Dictionary:
	var graph := SpatialGenerator.generate(SpatialConfig.new(1, 2000.0, 1000.0, 20000, 0.9))
	if graph == null:
		return {}
	var composition := WorldCompositionGenerator.generate(graph, WorldCompositionConfig.new(1, &"continents"))
	if composition == null:
		return {}
	var projected := TerrainHeightProjector.project(composition.continental_value)
	var geology := GeologyGenerator.generate(graph, projected)
	var climate_settings := WorldClimateSettings.new(70.0, -20.0)
	var preliminary_climate := WorldClimateGenerator.generate(graph, projected, climate_settings)
	var hydrology_settings := WorldHydrologySettings.new()
	var preliminary_flow := PreliminaryFlowGenerator.generate(graph, projected, preliminary_climate, hydrology_settings)
	var conditioning := HydrologyConditioner.condition(graph, projected, preliminary_flow, geology, HydrologyConditioningSettings.new())
	if conditioning == null:
		return {}
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = conditioning.terrain_height.duplicate()
	return {
		"graph": graph,
		"composition": composition,
		"projected": projected,
		"terrain": terrain,
		"geology": geology,
		"world_seed": 1,
		"strata": SubsurfaceStrataGenerator.generate(
			graph, composition, terrain, geology, 1
		),
	}


func _transition_is_legal(
		province_id: int,
		current: int,
		next: int,
		layer_index: int,
		is_deep_continental: bool
) -> bool:
	for selector in [0.0, 0.29, 0.34, 0.44, 0.49, 0.54, 0.59, 0.64, 0.74, 0.79, 0.99]:
		if SubsurfaceStrataGenerator.next_material_for(
			province_id, current, layer_index, selector, is_deep_continental
		) == next:
			return true
	return false


func _strata_statistics(
		graph: SpatialGraph,
		composition: WorldCompositionLayer,
		terrain: TerrainHeightLayer,
		geology: GeologyLayer,
		strata: SubsurfaceStrataLayer,
		world_seed: int
) -> Dictionary:
	var layer_counts := PackedFloat32Array()
	var material_records := {}
	var province_counts: Array = []
	var province_layers: Array = []
	var province_terminals: Array = []
	var province_metamorphic_counts := PackedInt32Array()
	province_metamorphic_counts.resize(GeologyCatalog.PROVINCE_COUNT)
	var deep_continental := PackedByteArray()
	deep_continental.resize(graph.cell_count())
	var settings := SubsurfaceStrataSettings.new()
	var base_seed := DeterministicRng.stable_mix(
		world_seed, SubsurfaceStrataGenerator.STRATA_SEED_SALT
	)
	var deep_noise := SubsurfaceStrataGenerator.make_deep_crust_noise(base_seed, settings)
	var land_count := 0
	var ocean_count := 0
	var land_continental_deep_count := 0
	var land_oceanic_deep_count := 0
	var ocean_continental_deep_count := 0
	var ocean_oceanic_deep_count := 0
	for province_id in GeologyCatalog.PROVINCE_COUNT:
		province_counts.append(0)
		province_layers.append(PackedFloat32Array())
		province_terminals.append({})
	for cell_id in graph.cell_count():
		var position := graph.cell_centers[cell_id]
		var is_deep_continental := SubsurfaceStrataGenerator.is_continental_deep_substrate(
			composition.continental_value[cell_id],
			deep_noise.get_noise_2d(position.x, position.y),
			settings
		)
		deep_continental[cell_id] = 1 if is_deep_continental else 0
		if terrain.terrain_height[cell_id] >= 0.0:
			land_count += 1
			if is_deep_continental:
				land_continental_deep_count += 1
			else:
				land_oceanic_deep_count += 1
		else:
			ocean_count += 1
			if is_deep_continental:
				ocean_continental_deep_count += 1
			else:
				ocean_oceanic_deep_count += 1
		var begin := strata.cell_offsets[cell_id]
		var end := strata.cell_offsets[cell_id + 1]
		var count := end - begin
		var province_id := geology.province_id[cell_id]
		layer_counts.append(count)
		province_counts[province_id] += 1
		province_layers[province_id].append(count)
		var terminal := strata.material_ids[end - 1]
		province_terminals[province_id][terminal] = int(province_terminals[province_id].get(terminal, 0)) + 1
		var has_metamorphic := false
		for record_index in range(begin, end):
			var material := strata.material_ids[record_index]
			material_records[material] = int(material_records.get(material, 0)) + 1
			if material == GeologyCatalog.MaterialType.METAMORPHIC_ROCK:
				has_metamorphic = true
		if has_metamorphic:
			province_metamorphic_counts[province_id] += 1
	var provinces: Array = []
	for province_id in GeologyCatalog.PROVINCE_COUNT:
		var values: PackedFloat32Array = province_layers[province_id]
		var count: int = province_counts[province_id]
		provinces.append({
			"count": count,
			"mean": _mean(values),
			"p50": _percentile(values, 0.50),
			"p95": _percentile(values, 0.95),
			"terminals": province_terminals[province_id],
			"metamorphic_ratio": float(province_metamorphic_counts[province_id]) / maxf(float(count), 1.0),
		})
	var eligible_pairs := 0
	var matching_pairs := 0
	var surface_boundary_edges := 0
	var deep_boundary_edges := 0
	var coincident_boundary_edges := 0
	for cell_id in graph.cell_count():
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if neighbor_id <= cell_id:
				continue
			var is_surface_boundary := (
				terrain.terrain_height[cell_id] >= 0.0
			) != (
				terrain.terrain_height[neighbor_id] >= 0.0
			)
			var is_deep_boundary := deep_continental[cell_id] != deep_continental[neighbor_id]
			if is_surface_boundary:
				surface_boundary_edges += 1
			if is_deep_boundary:
				deep_boundary_edges += 1
				if is_surface_boundary:
					coincident_boundary_edges += 1
			if geology.province_id[neighbor_id] != geology.province_id[cell_id] \
					or geology.material_id[neighbor_id] != geology.material_id[cell_id]:
				continue
			eligible_pairs += 1
			if _same_sequence(strata, cell_id, neighbor_id):
				matching_pairs += 1
	return {
		"world_mean": _mean(layer_counts),
		"world_p50": _percentile(layer_counts, 0.50),
		"world_p95": _percentile(layer_counts, 0.95),
		"world_max": _maximum(layer_counts),
		"provinces": provinces,
		"material_records": material_records,
		"eligible_pairs": eligible_pairs,
		"matching_pairs": matching_pairs,
		"adjacent_sequence_ratio": float(matching_pairs) / maxf(float(eligible_pairs), 1.0),
		"land_count": land_count,
		"ocean_count": ocean_count,
		"land_continental_deep_count": land_continental_deep_count,
		"land_oceanic_deep_count": land_oceanic_deep_count,
		"ocean_continental_deep_count": ocean_continental_deep_count,
		"ocean_oceanic_deep_count": ocean_oceanic_deep_count,
		"ocean_continental_deep_ratio": float(ocean_continental_deep_count) \
				/ maxf(float(ocean_count), 1.0),
		"ocean_oceanic_deep_ratio": float(ocean_oceanic_deep_count) \
				/ maxf(float(ocean_count), 1.0),
		"surface_boundary_edges": surface_boundary_edges,
		"deep_boundary_edges": deep_boundary_edges,
		"coincident_boundary_edges": coincident_boundary_edges,
		"deep_boundary_surface_coincidence_ratio": float(coincident_boundary_edges) \
				/ maxf(float(deep_boundary_edges), 1.0),
	}


func _same_sequence(strata: SubsurfaceStrataLayer, cell_a: int, cell_b: int) -> bool:
	var range_a := strata.record_range_for_cell(cell_a)
	var range_b := strata.record_range_for_cell(cell_b)
	if range_a.y - range_a.x != range_b.y - range_b.x:
		return false
	for local_index in range_a.y - range_a.x:
		if strata.material_ids[range_a.x + local_index] != strata.material_ids[range_b.x + local_index]:
			return false
	return true


func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _maximum(values: PackedFloat32Array) -> float:
	var result := -INF
	for value in values:
		result = maxf(result, value)
	return result if not values.is_empty() else 0.0


func _percentile(values: PackedFloat32Array, percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var position := float(sorted.size() - 1) * percentile
	var lower := floori(position)
	var upper := ceili(position)
	return sorted[lower] if lower == upper else lerpf(sorted[lower], sorted[upper], position - lower)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Subsurface Strata: all dedicated test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Subsurface Strata: %d failures" % _failures.size())
		quit(1)
