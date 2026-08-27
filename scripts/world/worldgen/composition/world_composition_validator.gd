class_name WorldCompositionValidator
extends RefCounted


static func validate(layer: WorldCompositionLayer, graph: SpatialGraph) -> PackedStringArray:
	var errors := PackedStringArray()
	if layer == null:
		errors.append("layer is null")
		return errors
	if graph == null:
		errors.append("SpatialGraph is null")
		return errors
	if layer.config == null:
		errors.append("config is null")
	else:
		errors.append_array(layer.config.validate())
	if not CompositionTemplates.has_template(layer.template_id):
		errors.append("template_id is not a supported v1.1 template")
	if layer.continental_value.size() != graph.cell_count():
		errors.append(
			"continental_value length %d does not match Cell Count %d"
			% [layer.continental_value.size(), graph.cell_count()]
		)
	for cell_id in layer.continental_value.size():
		var value := layer.continental_value[cell_id]
		if value < 0 or value > 100:
			errors.append("continental_value[%d] is outside [0, 100]: %d" % [cell_id, value])
	var expected_operations := CompositionTemplates.operations_for(layer.template_id)
	if layer.operation_metadata.size() != expected_operations.size():
		errors.append(
			"executed operation count %d does not match template operation count %d"
			% [layer.operation_metadata.size(), expected_operations.size()]
		)
	for operation_index in layer.operation_metadata.size():
		var metadata: Dictionary = layer.operation_metadata[operation_index]
		if not bool(metadata.get("success", false)):
			errors.append(
				"operation %d (%s) failed: %s"
				% [operation_index, metadata.get("type", "unknown"), metadata.get("error", "no error reported")]
			)
		elif operation_index < expected_operations.size():
			var expected_type := StringName(expected_operations[operation_index].get("type", &""))
			if StringName(metadata.get("type", &"")) != expected_type:
				errors.append(
					"operation %d executed out of order: expected %s, got %s"
					% [operation_index, expected_type, metadata.get("type", "")]
				)
	return errors


static func validate_determinism(
		graph: SpatialGraph, config: WorldCompositionConfig
) -> PackedStringArray:
	var errors := PackedStringArray()
	var first := WorldCompositionGenerator.generate(graph, config)
	var second := WorldCompositionGenerator.generate(graph, config)
	if first == null or second == null:
		errors.append("determinism validation could not generate both layers")
	elif first.continental_value != second.continental_value:
		errors.append("same Seed + Composition Config + Template produced different values")
	return errors


static func statistics(layer: WorldCompositionLayer) -> Dictionary:
	if layer == null or layer.continental_value.is_empty():
		return {
			"min": 0,
			"max": 0,
			"mean": 0.0,
			"coverage_ge_5": 0.0,
			"coverage_ge_10": 0.0,
			"coverage_ge_20": 0.0,
			"coverage_ge_40": 0.0,
			"coverage_ge_60": 0.0,
		}
	var minimum := 100
	var maximum := 0
	var sum := 0.0
	var coverage_counts := {5: 0, 10: 0, 20: 0, 40: 0, 60: 0}
	for value in layer.continental_value:
		minimum = mini(minimum, value)
		maximum = maxi(maximum, value)
		sum += value
		for threshold in coverage_counts:
			if value >= threshold:
				coverage_counts[threshold] += 1
	var count := float(layer.continental_value.size())
	return {
		"min": minimum,
		"max": maximum,
		"mean": sum / count,
		"coverage_ge_5": float(coverage_counts[5]) / count,
		"coverage_ge_10": float(coverage_counts[10]) / count,
		"coverage_ge_20": float(coverage_counts[20]) / count,
		"coverage_ge_40": float(coverage_counts[40]) / count,
		"coverage_ge_60": float(coverage_counts[60]) / count,
	}
