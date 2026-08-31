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
	var upstream_by_cell: Array[PackedInt32Array] = []
	for cell_id in count:
		upstream_by_cell.append(PackedInt32Array())
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
				var upstream_cells: PackedInt32Array = upstream_by_cell[downstream_id]
				upstream_cells.append(cell_id)
				upstream_by_cell[downstream_id] = upstream_cells
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
	var topological_order := PackedInt32Array()
	while queue_index < queue.size():
		var cell_id := queue[queue_index]
		queue_index += 1
		processed += 1
		topological_order.append(cell_id)
		var downstream_id := layer.flow_to[cell_id]
		if downstream_id >= 0:
			indegree[downstream_id] -= 1
			if indegree[downstream_id] == 0:
				queue.append(downstream_id)
	if processed != count:
		errors.append("flow_to contains a loop")
	var expected_river_order := _expected_strahler_order(
		layer.river_network_id, layer.flow_to, topological_order
	)
	for cell_id in count:
		if layer.river_order[cell_id] != expected_river_order[cell_id]:
			errors.append("river_order[%d] does not match the final River mask" % cell_id)
	var river_threshold := layer.settings.river_runoff_threshold if layer.settings != null else 0.0
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
		if layer.settings != null \
				and river_network.discharge < layer.settings.formal_river_min_discharge:
			errors.append(
				"River Network %d discharge must be at least %.4f"
				% [network_index, layer.settings.formal_river_min_discharge]
			)
		if river_network.source_cell >= 0 and river_network.source_cell < count \
				and layer.river_network_id[river_network.source_cell] != network_index:
			errors.append("River Network %d source_cell must belong to the Network" % network_index)
		if river_network.mouth_cell >= 0 and river_network.mouth_cell < count:
			if layer.river_network_id[river_network.mouth_cell] != network_index:
				errors.append("River Network %d mouth_cell must belong to the Network" % network_index)
			elif not is_equal_approx(
					river_network.discharge,
					layer.flow_accumulation[river_network.mouth_cell]
			):
				errors.append("River Network %d discharge must match its mouth" % network_index)
			var mouth_downstream := layer.flow_to[river_network.mouth_cell]
			if mouth_downstream >= 0 and terrain.terrain_height[mouth_downstream] >= 0.0:
				errors.append("River Network %d must not end at a Land Cell" % network_index)
			elif mouth_downstream < 0 \
					and mouth_downstream != WorldHydrologyLayer.FLOW_TO_WATER \
					and mouth_downstream != WorldHydrologyLayer.FLOW_TO_BOUNDARY \
					and mouth_downstream != WorldHydrologyLayer.FLOW_TO_CLOSED_BASIN:
				errors.append("River Network %d has an invalid outlet" % network_index)

	for cell_id in count:
		var network_id := layer.river_network_id[cell_id]
		if network_id < 0:
			continue
		var downstream_id := layer.flow_to[cell_id]
		if downstream_id >= 0 and terrain.terrain_height[downstream_id] >= 0.0:
			if layer.river_network_id[downstream_id] != network_id:
				errors.append("River Cell %d is disconnected from its formal Network" % cell_id)
		var has_river_upstream := false
		var traced_upstream_count := 0
		for upstream_id in upstream_by_cell[cell_id]:
			if layer.river_network_id[upstream_id] == network_id:
				has_river_upstream = true
				if layer.flow_accumulation[upstream_id] < river_threshold:
					traced_upstream_count += 1
		if traced_upstream_count > 1:
			errors.append("River Cell %d has multiple traced upstream branches" % cell_id)
		if not has_river_upstream:
			for upstream_id in upstream_by_cell[cell_id]:
				if terrain.terrain_height[upstream_id] >= 0.0:
					errors.append("River Source %d did not reach its Natural Headwater" % cell_id)
					break
		if layer.flow_accumulation[cell_id] >= river_threshold:
			continue
		if downstream_id < 0 \
				or downstream_id >= count \
				or layer.river_network_id[downstream_id] != network_id:
			errors.append("Traced River Cell %d must flow into its original Network" % cell_id)
			continue
		if layer.watershed_id[cell_id] != layer.watershed_id[downstream_id]:
			errors.append("Traced River Cell %d must remain in its Watershed" % cell_id)
		var expected_predecessor := _main_upstream_predecessor(
			downstream_id, terrain.terrain_height, upstream_by_cell, layer.flow_accumulation
		)
		if expected_predecessor != cell_id:
			errors.append("Traced River Cell %d is not the main upstream predecessor" % cell_id)
		var path_cell := cell_id
		var visited := {}
		var reached_candidate := false
		while path_cell >= 0 and path_cell < count:
			if layer.flow_accumulation[path_cell] >= river_threshold:
				reached_candidate = true
				break
			if visited.has(path_cell):
				break
			visited[path_cell] = true
			if layer.river_network_id[path_cell] != network_id:
				break
			path_cell = layer.flow_to[path_cell]
		if not reached_candidate:
			errors.append("Traced River Cell %d does not reach an original candidate" % cell_id)
	for basin in layer.closed_basin_inflows:
		if basin.closed_basin_id < 0 \
				or not is_finite(basin.catchment_area) \
				or basin.catchment_area < 0.0 \
				or not is_finite(basin.total_inflow) \
				or basin.total_inflow < 0.0 \
				or not is_finite(basin.mean_temperature):
			errors.append("Closed Basin inflow metadata is invalid")
	return errors


static func _expected_strahler_order(
		river_network_id: PackedInt32Array,
		flow_to: PackedInt32Array,
		topological_order: PackedInt32Array
) -> PackedInt32Array:
	var river_order := PackedInt32Array()
	river_order.resize(river_network_id.size())
	river_order.fill(-1)
	var maximum_upstream := PackedInt32Array()
	maximum_upstream.resize(river_network_id.size())
	var maximum_count := PackedInt32Array()
	maximum_count.resize(river_network_id.size())
	for cell_id in topological_order:
		if river_network_id[cell_id] < 0:
			continue
		var order := 1
		if maximum_upstream[cell_id] > 0:
			order = maximum_upstream[cell_id] + 1 \
					if maximum_count[cell_id] >= 2 else maximum_upstream[cell_id]
		river_order[cell_id] = order
		var downstream_id := flow_to[cell_id]
		if downstream_id < 0 \
				or river_network_id[downstream_id] != river_network_id[cell_id]:
			continue
		if order > maximum_upstream[downstream_id]:
			maximum_upstream[downstream_id] = order
			maximum_count[downstream_id] = 1
		elif order == maximum_upstream[downstream_id]:
			maximum_count[downstream_id] += 1
	return river_order


static func _main_upstream_predecessor(
		current_cell: int,
		heights: PackedFloat32Array,
		upstream_by_cell: Array[PackedInt32Array],
		flow_accumulation: PackedFloat32Array
) -> int:
	var best_cell := -1
	var best_accumulation := -INF
	for upstream_id in upstream_by_cell[current_cell]:
		if heights[upstream_id] < 0.0:
			continue
		var accumulation := flow_accumulation[upstream_id]
		if accumulation > best_accumulation \
				or (is_equal_approx(accumulation, best_accumulation) \
				and (best_cell < 0 or upstream_id < best_cell)):
			best_cell = upstream_id
			best_accumulation = accumulation
	return best_cell
