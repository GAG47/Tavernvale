extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_high_supply_low_loss_forms_lake()
	_test_low_supply_high_loss_rejects_lake()
	_test_supply_monotonicity()
	_test_temperature_loss()
	_test_permeability_loss()
	_test_terrain_hypsometry()
	_test_spill_cap()
	_test_minimum_lake_area()
	_test_terrain_is_immutable()
	_test_determinism()
	_test_ocean_exclusion()
	_test_array_sizes_finite_and_validator()
	_finish()


func _test_high_supply_low_loss_forms_lake() -> void:
	var result := _make_case(8.0, -20.0, 0.0, _unit_loss_settings(2.0))
	var layer: SurfaceWaterLayer = result.layer
	_expect(layer != null and layer.lakes.size() == 1, "high supply and low loss should form one Lake")
	if layer == null or layer.lakes.is_empty():
		return
	_expect(layer.lakes[0].basin_id == 0, "Lake should retain its Closed Basin identity")
	_expect(layer.lakes[0].area >= 8.0, "stable Lake area should reach the target at Cell resolution")


func _test_low_supply_high_loss_rejects_lake() -> void:
	var settings := SurfaceWaterSettings.new(2.0, 1.0, 10.0, 10.0, 10.0, 10.0)
	var result := _make_case(1.0, 35.0, 1.0, settings)
	var layer: SurfaceWaterLayer = result.layer
	_expect(layer != null and layer.lakes.is_empty(), "low supply and high loss should not form a Lake")
	if layer != null:
		_expect(layer.rejected_small_lake_count == 1, "sub-minimum stable water should be rejected")


func _test_supply_monotonicity() -> void:
	var settings := _unit_loss_settings(0.5)
	var low: SurfaceWaterLayer = _make_case(3.0, 10.0, 0.0, settings).layer
	var high: SurfaceWaterLayer = _make_case(8.0, 10.0, 0.0, settings).layer
	_expect(low != null and high != null, "supply comparison cases should generate")
	if low == null or high == null or low.lakes.is_empty() or high.lakes.is_empty():
		return
	_expect(high.lakes[0].area >= low.lakes[0].area, "raising inflow must not reduce Lake area")


func _test_temperature_loss() -> void:
	var settings := SurfaceWaterSettings.new(0.5, 1.0, 1.0, 10.0, 0.0, 0.0)
	var cold: SurfaceWaterLayer = _make_case(30.0, -20.0, 0.0, settings).layer
	var hot: SurfaceWaterLayer = _make_case(30.0, 35.0, 0.0, settings).layer
	_expect(cold != null and hot != null, "temperature comparison cases should generate")
	if cold == null or hot == null or cold.lakes.is_empty() or hot.lakes.is_empty():
		return
	_expect(hot.lakes[0].area <= cold.lakes[0].area, "higher temperature must not increase Lake area")


func _test_permeability_loss() -> void:
	var settings := SurfaceWaterSettings.new(0.5, 1.0, 1.0, 1.0, 0.0, 9.0)
	var sealed: SurfaceWaterLayer = _make_case(30.0, 10.0, 0.0, settings).layer
	var permeable: SurfaceWaterLayer = _make_case(30.0, 10.0, 1.0, settings).layer
	_expect(sealed != null and permeable != null, "permeability comparison cases should generate")
	if sealed == null or permeable == null \
			or sealed.lakes.is_empty() or permeable.lakes.is_empty():
		return
	_expect(
		permeable.lakes[0].area <= sealed.lakes[0].area,
		"higher lakebed permeability must not increase Lake area"
	)


func _test_terrain_hypsometry() -> void:
	var result := _make_case(3.0, 10.0, 0.0, _unit_loss_settings(0.5))
	var layer: SurfaceWaterLayer = result.layer
	_expect(layer != null and layer.lakes.size() == 1, "stepped Basin should form a Lake")
	if layer == null or layer.lakes.is_empty():
		return
	_expect(layer.lake_id[0] == 0 and layer.lake_id[1] == 0, "lowest two Cells should flood first")
	_expect(layer.lake_id[2] == -1 and layer.lake_id[3] == -1, "higher Cells should remain dry")
	_expect(is_equal_approx(layer.lakes[0].area, 3.0), "Lake area must sum actual unequal Cell areas")


func _test_spill_cap() -> void:
	var result := _make_case(1000.0, 10.0, 0.0, _unit_loss_settings(0.5))
	var layer: SurfaceWaterLayer = result.layer
	_expect(layer != null and layer.lakes.size() == 1, "over-supplied Basin should form a capped Lake")
	if layer == null or layer.lakes.is_empty():
		return
	_expect(layer.lakes[0].water_level <= 10.0, "Lake level must not exceed the Basin spill height")
	_expect(is_equal_approx(layer.lakes[0].water_level, 10.0), "over-supplied Lake should stop at spill height")


func _test_minimum_lake_area() -> void:
	var result := _make_case(1.0, 10.0, 0.0, _unit_loss_settings(2.0))
	var layer: SurfaceWaterLayer = result.layer
	_expect(layer != null and layer.lakes.is_empty(), "target area below minimum_lake_area must be rejected")
	if layer != null:
		_expect(layer.no_lake_basin_count == 1, "rejected candidate must leave its Closed Basin intact")


func _test_terrain_is_immutable() -> void:
	var result := _make_case(8.0, -20.0, 0.0, _unit_loss_settings(2.0))
	var terrain: TerrainHeightLayer = result.terrain
	_expect(
		terrain.terrain_height == result.terrain_before,
		"Surface Water generation must not modify terrain_height"
	)


func _test_determinism() -> void:
	var settings := _unit_loss_settings(0.5)
	var first: SurfaceWaterLayer = _make_case(8.0, 10.0, 0.2, settings).layer
	var second: SurfaceWaterLayer = _make_case(8.0, 10.0, 0.2, settings).layer
	_expect(first != null and second != null, "determinism cases should generate")
	if first == null or second == null:
		return
	_expect(first.lake_id == second.lake_id, "lake_id should be deterministic")
	_expect(first.surface_water_depth == second.surface_water_depth, "Lake depth should be deterministic")
	_expect(first.lakes.size() == second.lakes.size(), "Lake count should be deterministic")
	if not first.lakes.is_empty() and not second.lakes.is_empty():
		_expect(first.lakes[0].water_level == second.lakes[0].water_level, "Lake level should be deterministic")
		_expect(first.lakes[0].area == second.lakes[0].area, "Lake area should be deterministic")


func _test_ocean_exclusion() -> void:
	var result := _make_case(1000.0, 10.0, 0.0, _unit_loss_settings(0.5))
	var layer: SurfaceWaterLayer = result.layer
	_expect(layer != null, "Ocean exclusion case should generate")
	if layer == null:
		return
	_expect(layer.lake_id[5] == -1, "Ocean Cell must never receive a Lake ID")
	_expect(layer.surface_water_depth[5] == 0.0, "Ocean Cell must not receive inland water depth")


func _test_array_sizes_finite_and_validator() -> void:
	var settings := _unit_loss_settings(0.5)
	var result := _make_case(8.0, 10.0, 0.2, settings)
	var layer: SurfaceWaterLayer = result.layer
	_expect(layer != null, "validation case should generate")
	if layer == null:
		return
	_expect(layer.lake_id.size() == result.graph.cell_count(), "lake_id length must match Cell Count")
	_expect(
		layer.surface_water_depth.size() == result.graph.cell_count(),
		"surface_water_depth length must match Cell Count"
	)
	for depth in layer.surface_water_depth:
		_expect(is_finite(depth) and depth >= 0.0, "every Surface Water depth must be finite and non-negative")
	for lake in layer.lakes:
		_expect(is_finite(lake.water_level), "Lake water level must be finite")
		_expect(is_finite(lake.area) and lake.area >= 0.0, "Lake area must be finite and non-negative")
	var zero_rate_settings := SurfaceWaterSettings.new(0.5, 1.0, 0.0, 0.0, 0.0, 0.0)
	_expect(
		is_equal_approx(
			SurfaceWaterGenerator.target_lake_area(8.0, 10.0, 0.0, zero_rate_settings),
			8.0
		),
		"minimum_loss_per_area must prevent division by zero"
	)
	_expect(
		SurfaceWaterValidator.validate(
			result.graph,
			result.terrain,
			result.climate,
			result.hydrology,
			result.closed_basin_id,
			result.geology,
			layer,
			settings
		).is_empty(),
		"generated Surface Water should pass its Validator"
	)


func _make_case(
		water_supply: float,
		temperature: float,
		permeability: float,
		settings: SurfaceWaterSettings
) -> Dictionary:
	var graph := _stepped_basin_graph()
	var terrain := TerrainHeightLayer.new()
	terrain.terrain_height = PackedFloat32Array([0.0, 2.0, 4.0, 6.0, 10.0, -10.0])
	var climate := WorldClimateLayer.new()
	climate.temperature.resize(graph.cell_count())
	climate.temperature.fill(temperature)
	climate.precipitation.resize(graph.cell_count())
	var geology := GeologyLayer.new()
	geology.permeability.resize(graph.cell_count())
	geology.permeability.fill(permeability)
	var closed_basin_id := PackedInt32Array([0, 0, 0, 0, -1, -1])
	var hydrology := WorldHydrologyLayer.new()
	hydrology.local_runoff.resize(graph.cell_count())
	var inflow := ClosedBasinInflow.new()
	inflow.closed_basin_id = 0
	inflow.total_inflow = water_supply
	hydrology.closed_basin_inflows.append(inflow)
	var terrain_before := terrain.terrain_height.duplicate()
	var layer := SurfaceWaterGenerator.generate(
		graph, terrain, climate, hydrology, closed_basin_id, geology, settings
	)
	return {
		"graph": graph,
		"terrain": terrain,
		"climate": climate,
		"hydrology": hydrology,
		"closed_basin_id": closed_basin_id,
		"geology": geology,
		"terrain_before": terrain_before,
		"layer": layer,
	}


func _stepped_basin_graph() -> SpatialGraph:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(1, 6.0, 1.0, 6, 0.9)
	graph.cell_centers.resize(6)
	for cell_id in 6:
		graph.cell_centers[cell_id] = Vector2(cell_id, 0.5)
	graph.cell_neighbors = [
		PackedInt32Array([1]),
		PackedInt32Array([0, 2]),
		PackedInt32Array([1, 3]),
		PackedInt32Array([2, 4]),
		PackedInt32Array([3, 5]),
		PackedInt32Array([4]),
	]
	graph.cell_areas = PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 1.0, 1.0])
	return graph


func _unit_loss_settings(minimum_area: float) -> SurfaceWaterSettings:
	return SurfaceWaterSettings.new(minimum_area, 1.0, 1.0, 1.0, 0.0, 0.0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Surface Water / Lakes: all 12 test groups passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("Surface Water / Lakes: %d failures" % _failures.size())
		quit(1)
