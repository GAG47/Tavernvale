extends SceneTree

var _failures := PackedStringArray()
var _graph: SpatialGraph
var _default_graph: SpatialGraph
var _default_composition_ms := {}
var _default_statistics := {}


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_graph = SpatialGenerator.generate(SpatialConfig.new(24680, 300.0, 200.0, 400, 0.9))
	_expect(_graph != null, "shared primitive-test SpatialGraph should generate")
	if _graph == null:
		_finish()
		return

	var test_groups: Array[Callable] = [
		_test_determinism_and_seed_isolation,
		_test_different_seed,
		_test_uint8_integer_semantics_and_power_tables,
		_test_hill_neighbor_propagation,
		_test_pit_shared_height_algorithm,
		_test_range_path_and_prominence,
		_test_trough_path_bias_and_prominence,
		_test_strait_path_and_width,
		_test_multiply_reference_semantics,
		_test_smooth_simultaneous_update,
		_test_mask_preserves_spatial_graph,
		_test_template_order,
		_test_no_disallowed_pathfinding,
		_test_default_10k_templates_and_validator,
	]
	for test_group in test_groups:
		test_group.call()
	_finish()


func _test_determinism_and_seed_isolation() -> void:
	var config := WorldCompositionConfig.new(123456, CompositionTemplates.CONTINENTS)
	var spatial_rng := DeterministicRng.new(DeterministicRng.spatial_seed(777))
	var spatial_before := spatial_rng.next_float()
	var first := WorldCompositionGenerator.generate(_graph, config)
	var spatial_after := spatial_rng.next_float()
	var control_rng := DeterministicRng.new(DeterministicRng.spatial_seed(777))
	var control_before := control_rng.next_float()
	var control_after := control_rng.next_float()
	var second := WorldCompositionGenerator.generate(_graph, config)
	_expect(first != null and second != null, "determinism layers should generate")
	if first != null and second != null:
		_expect(
			first.continental_value == second.continental_value,
			"same Seed + Template must reproduce continental_value"
		)
		_expect(
			first.operation_metadata == second.operation_metadata,
			"same Seed + Template must reproduce operation metadata"
		)
		_expect(
			WorldCompositionValidator.validate_determinism(_graph, config).is_empty(),
			"Validator determinism check must pass"
		)
	_expect(
		spatial_before == control_before and spatial_after == control_after,
		"Composition RNG must not alter an independent Spatial RNG stream"
	)


func _test_different_seed() -> void:
	var first := WorldCompositionGenerator.generate(
		_graph, WorldCompositionConfig.new(101, CompositionTemplates.PANGEA)
	)
	var second := WorldCompositionGenerator.generate(
		_graph, WorldCompositionConfig.new(102, CompositionTemplates.PANGEA)
	)
	_expect(first != null and second != null, "different-seed layers should generate")
	if first != null and second != null:
		_expect(first.continental_value != second.continental_value, "different Seeds should change composition")


func _test_uint8_integer_semantics_and_power_tables() -> void:
	_expect(CompositionOperations.uint8_value(73.9) == 73, "Uint8 write must truncate 73.9 to 73")
	_expect(CompositionOperations.uint8_value(1.9) == 1, "Uint8 write must truncate 1.9 to 1")
	_expect(CompositionOperations.uint8_value(0.9) == 0, "Uint8 write must truncate 0.9 to 0")
	_expect(CompositionOperations.uint8_value(-4.2) == 0, "Uint8 write must clamp negatives")
	_expect(CompositionOperations.uint8_value(104.2) == 100, "Uint8 write must clamp values above 100")
	_expect(is_equal_approx(CompositionOperations.get_blob_power(10000), 0.98), "10k blobPower must be 0.98")
	_expect(is_equal_approx(CompositionOperations.get_line_power(10000), 0.81), "10k linePower must be 0.81")
	_expect(is_equal_approx(CompositionOperations.get_blob_power(1234), 0.98), "blobPower fallback must be 0.98")
	_expect(is_equal_approx(CompositionOperations.get_line_power(1234), 0.81), "linePower fallback must be 0.81")


func _test_hill_neighbor_propagation() -> void:
	var values := _filled_values(_graph.cell_count(), 0)
	var operations := CompositionOperations.new(_graph, values, CompositionRng.new(501))
	var metadata := operations.add_hill({
		"count": "1", "strength": "40", "range_x": "45-55", "range_y": "45-55"
	})
	_expect(metadata.algorithm == &"change_array_neighbor_propagation", "Hill must identify change-array propagation")
	_expect(metadata.instances.size() == 1, "Hill count 1 must execute one instance")
	if metadata.instances.size() == 1:
		var instance: Dictionary = metadata.instances[0]
		var start := int(instance.start)
		_expect(
			int(instance.changed_cells) > _graph.cell_neighbors[start].size() + 1,
			"Hill must propagate beyond the start radius through neighbors"
		)
	_expect(_all_values_valid(operations.continental_value), "Hill output must stay integer 0..100")


func _test_pit_shared_height_algorithm() -> void:
	var values := _filled_values(_graph.cell_count(), 60)
	var original_values := values.duplicate()
	var operations := CompositionOperations.new(_graph, values, CompositionRng.new(502))
	var metadata := operations.add_pit({
		"count": "1", "strength": "25", "range_x": "45-55", "range_y": "45-55"
	})
	_expect(metadata.algorithm == &"shared_h_neighbor_queue", "Pit must use its independent shared-h queue")
	_expect(metadata.instances.size() == 1, "Pit count 1 must execute one instance")
	if metadata.instances.size() == 1:
		_expect(int(metadata.instances[0].changed_cells) > 0, "Pit must subtract from propagated neighbors")
	_expect(operations.continental_value != original_values, "Pit must modify the value field")
	_expect(_all_values_valid(operations.continental_value), "Pit output must stay integer 0..100")


func _test_range_path_and_prominence() -> void:
	var operations := CompositionOperations.new(
		_graph, _filled_values(_graph.cell_count(), 0), CompositionRng.new(503)
	)
	var metadata := operations.add_range({
		"count": "1", "strength": "50", "range_x": "10-20", "range_y": "40-60"
	})
	_expect(is_equal_approx(float(metadata.wandering_bias), 0.15), "Range wandering bias must be 15%")
	_expect(bool(metadata.prominence_executed), "Range prominence must execute")
	_expect(metadata.instances.size() == 1, "Range count 1 must execute one path")
	if metadata.instances.size() == 1:
		var instance: Dictionary = metadata.instances[0]
		_expect(bool(instance.path_continuous), "each Range path step must be a Spatial neighbor")
		_expect(int(instance.prominence_writes) > 0, "Range prominence must perform writes")


func _test_trough_path_bias_and_prominence() -> void:
	var operations := CompositionOperations.new(
		_graph, _filled_values(_graph.cell_count(), 60), CompositionRng.new(504)
	)
	var metadata := operations.add_trough({
		"count": "1", "strength": "30", "range_x": "10-20", "range_y": "40-60"
	})
	_expect(is_equal_approx(float(metadata.wandering_bias), 0.2), "Trough wandering bias must be 20%")
	_expect(bool(metadata.prominence_executed), "Trough prominence must execute")
	_expect(metadata.instances.size() == 1, "Trough count 1 must execute one path")
	if metadata.instances.size() == 1:
		var instance: Dictionary = metadata.instances[0]
		_expect(bool(instance.path_continuous), "each Trough path step must be a Spatial neighbor")
		_expect(int(instance.prominence_writes) > 0, "Trough prominence must perform writes")


func _test_strait_path_and_width() -> void:
	var operations := CompositionOperations.new(
		_graph, _filled_values(_graph.cell_count(), 80), CompositionRng.new(505)
	)
	var metadata := operations.add_strait({"width": "2", "direction": &"vertical"})
	_expect(bool(metadata.success), "Strait should complete its wandering path")
	_expect(metadata.algorithm == &"wandering_neighbor_path_query_width", "Strait must use query-width behavior")
	if bool(metadata.success):
		_expect(bool(metadata.path_continuous), "each Strait path step must be a Spatial neighbor")
		_expect(int(metadata.width_iterations) == 2, "Strait width 2 must execute exactly two width iterations")
		_expect(not metadata.path.is_empty(), "Strait path must contain traversed cells")
		_expect(
			metadata.query_sizes.size() == 2
			and metadata.query_sizes[1] == metadata.query_sizes[0] + metadata.added_per_iteration[1],
			"Strait must retain the cumulative Azgaar query between width iterations"
		)
	_expect(_minimum_value(operations.continental_value) < 80, "Strait width expansion must reduce neighboring values")


func _test_multiply_reference_semantics() -> void:
	var values := _filled_values(_graph.cell_count(), 0)
	values[0] = 19
	values[1] = 20
	values[2] = 21
	values[3] = 100
	var operations := CompositionOperations.new(_graph, values, CompositionRng.new(506))
	var metadata := operations.multiply({"factor": 0.6, "target": &"land"})
	_expect(bool(metadata.success), "Multiply land should execute")
	_expect(operations.continental_value[0] == 19, "Multiply land must not modify values below 20")
	_expect(operations.continental_value[1] == 20, "Multiply land must preserve the 20 reference")
	_expect(operations.continental_value[2] == 20, "Multiply land must truncate around the 20 reference")
	_expect(operations.continental_value[3] == 68, "Multiply land must scale (value - 20) then restore 20")


func _test_smooth_simultaneous_update() -> void:
	var values := PackedInt32Array()
	values.resize(_graph.cell_count())
	for cell_id in _graph.cell_count():
		values[cell_id] = (cell_id * 37) % 101
	var old_values := values.duplicate()
	var expected := PackedInt32Array()
	expected.resize(_graph.cell_count())
	for cell_id in _graph.cell_count():
		var sum := float(old_values[cell_id])
		for neighbor_id in _graph.cell_neighbors[cell_id]:
			sum += old_values[neighbor_id]
		var mean := sum / float(_graph.cell_neighbors[cell_id].size() + 1)
		expected[cell_id] = CompositionOperations.uint8_value(mean)
	var operations := CompositionOperations.new(_graph, values, CompositionRng.new(507))
	var metadata := operations.smooth({"factor": 1})
	_expect(bool(metadata.simultaneous), "Smooth must report simultaneous old-array calculation")
	_expect(operations.continental_value == expected, "Smooth factor 1 must use the unchanged old array for every mean")


func _test_mask_preserves_spatial_graph() -> void:
	var old_centers := _graph.cell_centers.duplicate()
	var old_neighbors := _duplicate_neighbor_array(_graph.cell_neighbors)
	var operations := CompositionOperations.new(
		_graph, _filled_values(_graph.cell_count(), 80), CompositionRng.new(508)
	)
	operations.mask({"power": 4.0})
	_expect(_graph.cell_centers == old_centers, "Mask must not modify SpatialGraph centers")
	_expect(_graph.cell_neighbors == old_neighbors, "Mask must not modify SpatialGraph neighbors")
	_expect(_minimum_value(operations.continental_value) < 80, "Mask must attenuate values toward world edges")


func _test_template_order() -> void:
	var continents_signature := _template_signature(CompositionTemplates.operations_for(CompositionTemplates.CONTINENTS))
	var pangea_signature := _template_signature(CompositionTemplates.operations_for(CompositionTemplates.PANGEA))
	_expect(continents_signature == PackedStringArray([
		"Hill 1 80-85 60-80 40-60", "Hill 1 80-85 20-30 40-60",
		"Hill 6-7 15-30 25-75 15-85", "Multiply 0.6 land",
		"Hill 8-10 5-10 15-85 20-80", "Range 1-2 30-60 5-15 25-75",
		"Range 1-2 30-60 80-95 25-75", "Range 0-3 30-60 80-90 20-80",
		"Strait 2 vertical", "Strait 1 vertical", "Smooth 3",
		"Trough 3-4 15-20 15-85 20-80", "Trough 3-4 5-10 45-55 45-55",
		"Pit 3-4 10-20 15-85 20-80", "Mask 4",
	]), "Continents operation script and order must exactly match the specification")
	_expect(pangea_signature == PackedStringArray([
		"Hill 1-2 25-40 15-50 0-10", "Hill 1-2 5-40 50-85 0-10",
		"Hill 1-2 25-40 50-85 90-100", "Hill 1-2 5-40 15-50 90-100",
		"Hill 8-12 20-40 20-80 48-52", "Smooth 2", "Multiply 0.7 land",
		"Trough 3-4 25-35 5-95 10-20", "Trough 3-4 25-35 5-95 80-90",
		"Range 5-6 30-40 10-90 35-65",
	]), "Pangea operation script and order must exactly match the specification")


func _test_no_disallowed_pathfinding() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/world/worldgen/composition/composition_operations.gd").to_lower()
	_expect(not source.contains("dijkstra"), "Composition operations source must not use Dijkstra")
	_expect(not source.contains("shortest_path"), "Composition operations source must not use shortest_path")
	_expect(not source.contains("a_star") and not source.contains("astar"), "Composition operations source must not use A*")


func _test_default_10k_templates_and_validator() -> void:
	var graph_started := Time.get_ticks_msec()
	_default_graph = SpatialGenerator.generate(SpatialConfig.new())
	var graph_ms := Time.get_ticks_msec() - graph_started
	_expect(_default_graph != null, "default 10k SpatialGraph should generate for Composition")
	if _default_graph == null:
		return
	_expect(_default_graph.cell_count() == 10000, "default Composition graph must contain 10k Cells")
	for template_id in [CompositionTemplates.CONTINENTS, CompositionTemplates.PANGEA]:
		var started := Time.get_ticks_msec()
		var layer := WorldCompositionGenerator.generate(
			_default_graph, WorldCompositionConfig.new(1, template_id)
		)
		var elapsed := Time.get_ticks_msec() - started
		_default_composition_ms[String(template_id)] = elapsed
		_expect(layer != null, "%s must generate on default 10k Cells" % template_id)
		if layer == null:
			continue
		var validation_errors := WorldCompositionValidator.validate(layer, _default_graph)
		_expect(validation_errors.is_empty(), "%s validator must pass: %s" % [template_id, "; ".join(validation_errors)])
		_expect(_all_values_valid(layer.continental_value), "%s must contain only integer values in 0..100" % template_id)
		_default_statistics[String(template_id)] = WorldCompositionValidator.statistics(layer)
	print("Default SpatialGraph generation: %d ms" % graph_ms)


func _template_signature(operations: Array[Dictionary]) -> PackedStringArray:
	var result := PackedStringArray()
	for operation in operations:
		match StringName(operation.type):
			&"Hill", &"Pit", &"Range", &"Trough":
				result.append("%s %s %s %s %s" % [operation.type, operation.count, operation.strength, operation.range_x, operation.range_y])
			&"Multiply":
				result.append("Multiply %s %s" % [_format_number(operation.factor), operation.target])
			&"Strait":
				result.append("Strait %s %s" % [operation.width, operation.direction])
			&"Smooth":
				result.append("Smooth %s" % _format_number(operation.factor))
			&"Mask":
				result.append("Mask %s" % _format_number(operation.power))
	return result


func _format_number(value: Variant) -> String:
	var numeric := float(value)
	return str(int(numeric)) if numeric == float(int(numeric)) else str(numeric)


func _filled_values(count: int, value: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(count)
	result.fill(value)
	return result


func _all_values_valid(values: PackedInt32Array) -> bool:
	for value in values:
		if value < 0 or value > 100:
			return false
	return true


func _minimum_value(values: PackedInt32Array) -> int:
	var result := 101
	for value in values:
		result = mini(result, value)
	return result


func _duplicate_neighbor_array(source: Array) -> Array:
	var result: Array = []
	for neighbors in source:
		result.append(neighbors.duplicate())
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("World Composition: all 14 test groups passed")
		for template_id in _default_composition_ms:
			var stats: Dictionary = _default_statistics[template_id]
			print(
				"%s 10k: %d ms | min=%d max=%d mean=%.3f | >=5 %.3f%% >=10 %.3f%% >=20 %.3f%% >=40 %.3f%% >=60 %.3f%%"
				% [
					template_id,
					_default_composition_ms[template_id],
					stats.min,
					stats.max,
					stats.mean,
					stats.coverage_ge_5 * 100.0,
					stats.coverage_ge_10 * 100.0,
					stats.coverage_ge_20 * 100.0,
					stats.coverage_ge_40 * 100.0,
					stats.coverage_ge_60 * 100.0,
				]
			)
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("World Composition: %d failures" % _failures.size())
		quit(1)
