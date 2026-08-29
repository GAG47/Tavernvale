extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_latitude_window()
	_test_temperature_relationships()
	_test_fixed_world_output()
	_finish()


func _test_latitude_window() -> void:
	var defaults := WorldClimateSettings.new()
	_expect(
		is_equal_approx(WorldClimateGenerator.latitude_at_y(0.0, 1000.0, defaults), 70.0),
		"top of the default map should be latitude +70"
	)
	_expect(
		is_equal_approx(WorldClimateGenerator.latitude_at_y(500.0, 1000.0, defaults), 25.0),
		"middle of the default map should linearly interpolate to latitude +25"
	)
	_expect(
		is_equal_approx(WorldClimateGenerator.latitude_at_y(1000.0, 1000.0, defaults), -20.0),
		"bottom of the default map should be latitude -20"
	)
	var custom := WorldClimateSettings.new(35.0, -35.0)
	_expect(
		is_equal_approx(WorldClimateGenerator.latitude_at_y(500.0, 1000.0, custom), 0.0),
		"latitude calculation should consume a custom configured window"
	)


func _test_temperature_relationships() -> void:
	var settings := WorldClimateSettings.new()
	var low_latitude := WorldClimateGenerator.temperature_at(5.0, 0.0, settings)
	var high_latitude := WorldClimateGenerator.temperature_at(65.0, 0.0, settings)
	_expect(
		low_latitude > high_latitude,
		"at the same height, low latitude should be warmer than high latitude"
	)
	var lowland := WorldClimateGenerator.temperature_at(30.0, 0.0, settings)
	var highland := WorldClimateGenerator.temperature_at(30.0, 80.0, settings)
	_expect(
		lowland > highland,
		"at the same latitude, lowland should be warmer than highland"
	)
	var deep_ocean := WorldClimateGenerator.temperature_at(30.0, -100.0, settings)
	var shallow_ocean := WorldClimateGenerator.temperature_at(30.0, -1.0, settings)
	_expect(
		is_equal_approx(deep_ocean, shallow_ocean),
		"ocean depth should not add terrain temperature cooling"
	)


func _test_fixed_world_output() -> void:
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
	var terrain_before := terrain.terrain_height.duplicate()
	var climate := WorldClimateGenerator.generate(graph, terrain, WorldClimateSettings.new())
	_expect(climate != null, "fixed-seed Climate should generate")
	if climate == null:
		return
	_expect(
		typeof(climate.temperature) == TYPE_PACKED_FLOAT32_ARRAY,
		"temperature should use PackedFloat32Array storage"
	)
	_expect(
		typeof(climate.precipitation) == TYPE_PACKED_FLOAT32_ARRAY,
		"precipitation should use PackedFloat32Array storage"
	)
	_expect(
		climate.temperature.size() == graph.cell_count(),
		"temperature should contain one value per Cell"
	)
	_expect(
		climate.precipitation.size() == graph.cell_count(),
		"precipitation should contain one value per Cell"
	)
	_expect(
		terrain.terrain_height == terrain_before,
		"Climate generation must not modify terrain_height"
	)
	var positive_precipitation_cells := 0
	for cell_id in graph.cell_count():
		_expect(
			is_finite(climate.temperature[cell_id]),
			"temperature[%d] should be finite" % cell_id
		)
		_expect(
			is_finite(climate.precipitation[cell_id]),
			"precipitation[%d] should be finite" % cell_id
		)
		_expect(
			climate.precipitation[cell_id] >= 0.0,
			"precipitation[%d] should be non-negative" % cell_id
		)
		if climate.precipitation[cell_id] > 0.0:
			positive_precipitation_cells += 1
	_expect(
		positive_precipitation_cells > 0,
		"fixed-seed Climate should transport moisture into at least one Cell"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Preliminary Climate: all 3 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Preliminary Climate: %d failures" % _failures.size())
		quit(1)
