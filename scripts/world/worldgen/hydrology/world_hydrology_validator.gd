class_name WorldHydrologyValidator
extends RefCounted


static func validate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		closed_basin_id: PackedInt32Array,
		layer: WorldHydrologyLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or terrain == null or climate == null or layer == null:
		errors.append("Formal Hydrology validation inputs must not be null")
		return errors
	var count := graph.cell_count()
	if terrain.cell_count() != count \
			or climate.cell_count() != count \
			or climate.precipitation.size() != count \
			or closed_basin_id.size() != count \
			or graph.cell_neighbors.size() != count \
			or graph.cell_is_border.size() != count:
		errors.append("Formal Hydrology validation inputs must contain one value per Cell")
		return errors
	if layer.local_runoff.size() != count \
			or layer.flow_to.size() != count \
			or layer.flow_accumulation.size() != count \
			or layer.watershed_id.size() != count \
			or layer.river_network_id.size() != count \
			or layer.river_order.size() != count:
		errors.append("all Formal Hydrology PackedArrays must contain one value per Cell")
		return errors
	var indegree := PackedInt32Array()
	indegree.resize(count)
	var river_network_cell_counts := PackedInt32Array()
	river_network_cell_counts.resize(layer.river_networks.size())
	for cell_id in count:
		var runoff := layer.local_runoff[cell_id]
		var accumulation := layer.flow_accumulation[cell_id]
		if not is_finite(runoff) or runoff < 0.0:
			errors.append("local_runoff[%d] must be finite and non-negative" % cell_id)
		if not is_finite(accumulation) or accumulation < runoff:
			errors.append("flow_accumulation[%d] must be finite and at least local runoff" % cell_id)
		var downstream_id := layer.flow_to[cell_id]
		if downstream_id >= 0:
			if downstream_id >= count or not graph.cell_neighbors[cell_id].has(downstream_id):
				errors.append("flow_to[%d] must reference a neighboring Cell" % cell_id)
			else:
				indegree[downstream_id] += 1
				if terrain.terrain_height[downstream_id] >= terrain.terrain_height[cell_id]:
					errors.append("flow_to[%d] must be strictly downhill" % cell_id)
		elif terrain.terrain_height[cell_id] < 0.0:
			if downstream_id != WorldHydrologyLayer.FLOW_TO_WATER:
				errors.append("Water Cell %d must use the Water sentinel" % cell_id)
		elif closed_basin_id[cell_id] >= 0:
			if downstream_id != WorldHydrologyLayer.FLOW_TO_CLOSED_BASIN:
				errors.append("Closed Basin Cell %d must use the basin sentinel" % cell_id)
		elif graph.cell_is_border[cell_id] != 0:
			if downstream_id != WorldHydrologyLayer.FLOW_TO_BOUNDARY:
				errors.append("Boundary Cell %d must use the boundary sentinel" % cell_id)
		else:
			errors.append("ordinary Land Cell %d cannot use a terminal sentinel" % cell_id)
		if terrain.terrain_height[cell_id] >= 0.0 and layer.watershed_id[cell_id] < 0:
			errors.append("Land Cell %d must have a Watershed" % cell_id)
		elif terrain.terrain_height[cell_id] >= 0.0 \
				and layer.watershed_id[cell_id] >= layer.watershed_count:
			errors.append("Land Cell %d references an invalid Watershed" % cell_id)
		if layer.river_network_id[cell_id] >= 0:
			if layer.river_network_id[cell_id] >= layer.river_networks.size() \
					or terrain.terrain_height[cell_id] < 0.0 \
					or layer.river_order[cell_id] < 1:
				errors.append("River Network Cell %d must be Land with positive Strahler Order" % cell_id)
			else:
				river_network_cell_counts[layer.river_network_id[cell_id]] += 1
		elif layer.river_order[cell_id] != -1:
			errors.append("non-River Cell %d must use river_order -1" % cell_id)
	var queue := PackedInt32Array()
	for cell_id in count:
		if indegree[cell_id] == 0:
			queue.append(cell_id)
	var processed := 0
	var queue_index := 0
	while queue_index < queue.size():
		var cell_id := queue[queue_index]
		queue_index += 1
		processed += 1
		var downstream_id := layer.flow_to[cell_id]
		if downstream_id >= 0:
			indegree[downstream_id] -= 1
			if indegree[downstream_id] == 0:
				queue.append(downstream_id)
	if processed != count:
		errors.append("flow_to contains a loop")
	for network_index in layer.river_networks.size():
		var river_network: HydrologyRiverNetwork = layer.river_networks[network_index]
		if river_network.id != network_index \
				or river_network.source_cell < 0 \
				or river_network.mouth_cell < 0 \
				or not is_finite(river_network.discharge) \
				or river_network.discharge < 0.0 \
				or river_network.order < 1:
			errors.append("River Network %d metadata is invalid" % network_index)
		if layer.settings != null \
				and river_network_cell_counts[network_index] < layer.settings.formal_river_min_cells:
			errors.append(
				"River Network %d must contain at least %d Cells"
				% [network_index, layer.settings.formal_river_min_cells]
			)
	for basin in layer.closed_basin_inflows:
		if basin.closed_basin_id < 0 \
				or not is_finite(basin.catchment_area) \
				or basin.catchment_area < 0.0 \
				or not is_finite(basin.total_inflow) \
				or basin.total_inflow < 0.0 \
				or not is_finite(basin.mean_temperature):
			errors.append("Closed Basin inflow metadata is invalid")
	return errors
