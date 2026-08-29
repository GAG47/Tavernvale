extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_key_mappings()
	_test_output_range_and_land_water_equivalence()
	_test_fixed_seed_world_projection()
	_finish()


func _test_key_mappings() -> void:
	var expected := {
		0: -100.0,
		10: -50.0,
		20: 0.0,
		40: 25.0,
		60: 50.0,
		80: 75.0,
		100: 100.0,
	}
	for raw in expected:
		_expect(
			TerrainHeightProjector.project_value(float(raw)) == float(expected[raw]),
			"raw %d should project to terrain_height %.1f" % [raw, expected[raw]]
		)


func _test_output_range_and_land_water_equivalence() -> void:
	var raw_values := PackedInt32Array()
	for raw in range(101):
		raw_values.append(raw)
	var terrain := TerrainHeightProjector.project(raw_values)
	_expect(terrain != null, "projector should return a TerrainHeightLayer")
	if terrain == null:
		return
	_expect(
		terrain.terrain_height.size() == raw_values.size(),
		"terrain_height should preserve the raw Cell count"
	)
	_expect(
		typeof(terrain.terrain_height) == TYPE_PACKED_FLOAT32_ARRAY,
		"terrain_height should use PackedFloat32Array storage"
	)
	for cell_id in raw_values.size():
		var height := terrain.terrain_height[cell_id]
		_expect(
			height >= -100.0 and height <= 100.0,
			"terrain_height[%d] should stay inside [-100, 100]" % cell_id
		)
		_expect(
			(raw_values[cell_id] >= 20) == terrain.is_land(cell_id),
			"raw and terrain_height land/water should agree at raw %d" % raw_values[cell_id]
		)


func _test_fixed_seed_world_projection() -> void:
	var graph := SpatialGenerator.generate(SpatialConfig.new(24680, 300.0, 200.0, 400, 0.9))
	_expect(graph != null, "fixed-seed SpatialGraph should generate")
	if graph == null:
		return
	var composition := WorldCompositionGenerator.generate(
		graph, WorldCompositionConfig.new(24680, CompositionTemplates.CONTINENTS)
	)
	_expect(composition != null, "fixed-seed Composition should generate")
	if composition == null:
		return
	var terrain := TerrainHeightProjector.project(composition.continental_value)
	_expect(
		terrain.cell_count() == graph.cell_count(),
		"fixed-seed terrain_height should contain one value per Cell"
	)
	for cell_id in terrain.cell_count():
		var height := terrain.terrain_height[cell_id]
		_expect(
			height >= -100.0 and height <= 100.0,
			"fixed-seed terrain_height[%d] should stay inside [-100, 100]" % cell_id
		)
		_expect(
			(composition.continental_value[cell_id] >= 20) == terrain.is_land(cell_id),
			"fixed-seed land/water should agree at Cell %d" % cell_id
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Terrain Height Foundation: all 3 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Terrain Height Foundation: %d failures" % _failures.size())
		quit(1)
