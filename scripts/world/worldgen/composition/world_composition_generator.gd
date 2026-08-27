class_name WorldCompositionGenerator
extends RefCounted


static func generate(
		graph: SpatialGraph, config: WorldCompositionConfig
) -> WorldCompositionLayer:
	if graph == null:
		push_error("WorldCompositionGenerator: SpatialGraph is null")
		return null
	if config == null:
		push_error("WorldCompositionGenerator: config is null")
		return null
	var config_errors := config.validate()
	if not config_errors.is_empty():
		push_error("WorldCompositionGenerator: invalid config: " + "; ".join(config_errors))
		return null
	if graph.cell_count() <= 0 or graph.config == null:
		push_error("WorldCompositionGenerator: SpatialGraph is incomplete")
		return null

	var layer := WorldCompositionLayer.new()
	layer.config = config.duplicate_config()
	layer.seed = config.seed
	layer.template_id = config.template_id
	layer.composition_seed = CompositionRng.composition_seed(config)
	layer.continental_value.resize(graph.cell_count())

	var rng := CompositionRng.new(layer.composition_seed)
	var operations := CompositionOperations.new(graph, layer.continental_value, rng)
	var template_operations := CompositionTemplates.operations_for(config.template_id)
	for operation_index in template_operations.size():
		var metadata := operations.execute(template_operations[operation_index])
		metadata["operation_index"] = operation_index
		layer.operation_metadata.append(metadata)
		if not bool(metadata.get("success", false)):
			break
	layer.continental_value = operations.continental_value

	var validation_errors := WorldCompositionValidator.validate(layer, graph)
	if not validation_errors.is_empty():
		push_error(
			"WorldCompositionGenerator: generated invalid composition:\n"
			+ "\n".join(validation_errors)
		)
		return null
	return layer
