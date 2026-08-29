class_name PreliminaryFlowGenerator
extends RefCounted


static func generate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		preliminary_climate: WorldClimateLayer,
		settings: WorldHydrologySettings = null
) -> HydrologyFlowResult:
	var actual_settings := settings if settings != null else WorldHydrologySettings.new()
	if not _inputs_are_valid(graph, terrain, preliminary_climate, actual_settings):
		return null
	var flow := HydrologyFlowResult.new()
	flow.local_runoff = HydrologyFlowCalculator.calculate_local_runoff(
		graph, preliminary_climate.precipitation, actual_settings.runoff_modifier
	)
	if flow.local_runoff.is_empty():
		return null
	flow.flow_to = HydrologyFlowCalculator.calculate_flow_to(
		graph, terrain.terrain_height, PackedInt32Array(), true
	)
	if flow.flow_to.is_empty():
		return null
	var topology := HydrologyFlowCalculator.accumulate_flow(flow.local_runoff, flow.flow_to)
	if not topology.ok:
		push_error("Preliminary Flow flow_to contains a loop")
		return null
	flow.flow_accumulation = topology.accumulation
	return flow


static func _inputs_are_valid(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		settings: WorldHydrologySettings
) -> bool:
	if graph == null or terrain == null or climate == null:
		push_error("Preliminary Flow requires Spatial, projected terrain, and Preliminary Climate")
		return false
	var count := graph.cell_count()
	if count == 0 \
			or terrain.cell_count() != count \
			or climate.precipitation.size() != count:
		push_error("Preliminary Flow input arrays must contain one value per Cell")
		return false
	if graph.cell_areas.size() != count \
			or graph.cell_neighbors.size() != count \
			or graph.cell_neighbor_distances.size() != count \
			or graph.cell_is_border.size() != count:
		push_error("Preliminary Flow requires Cell area, neighbors, distances, and boundary flags")
		return false
	var setting_errors := settings.validate()
	if not setting_errors.is_empty():
		push_error("Invalid WorldHydrologySettings for Preliminary Flow: " + "; ".join(setting_errors))
		return false
	for cell_id in count:
		if not is_finite(graph.cell_areas[cell_id]) or graph.cell_areas[cell_id] <= 0.0:
			push_error("Preliminary Flow Cell areas must be finite and positive")
			return false
		if graph.cell_neighbor_distances[cell_id].size() != graph.cell_neighbors[cell_id].size():
			push_error("Preliminary Flow neighbor distances must align with Cell neighbors")
			return false
		for distance in graph.cell_neighbor_distances[cell_id]:
			if not is_finite(distance) or distance <= 0.0:
				push_error("Preliminary Flow neighbor distances must be finite and positive")
				return false
		if not is_finite(terrain.terrain_height[cell_id]) \
				or terrain.terrain_height[cell_id] < -100.0 \
				or terrain.terrain_height[cell_id] > 100.0:
			push_error("Preliminary Flow terrain_height must be finite and inside [-100, 100]")
			return false
		if not is_finite(climate.precipitation[cell_id]) \
				or climate.precipitation[cell_id] < 0.0:
			push_error("Preliminary Flow precipitation must be finite and non-negative")
			return false
	return true
