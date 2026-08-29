class_name WorldHydrologyGenerator
extends RefCounted


static func generate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		closed_basin_id: PackedInt32Array,
		settings: WorldHydrologySettings = null
) -> WorldHydrologyLayer:
	var actual_settings := settings if settings != null else WorldHydrologySettings.new()
	if not _inputs_are_valid(
		graph, terrain, climate, closed_basin_id, actual_settings
	):
		return null
	var layer := WorldHydrologyLayer.new()
	layer.settings = actual_settings.duplicate_settings()
	layer.local_runoff = HydrologyFlowCalculator.calculate_local_runoff(
		graph, climate.precipitation, actual_settings.runoff_modifier
	)
	if layer.local_runoff.is_empty():
		return null
	layer.flow_to = HydrologyFlowCalculator.calculate_flow_to(
		graph, terrain.terrain_height, closed_basin_id
	)
	if layer.flow_to.is_empty():
		return null
	var topology := HydrologyFlowCalculator.accumulate_flow(layer.local_runoff, layer.flow_to)
	if not topology.ok:
		push_error("Formal Hydrology flow_to contains a loop")
		return null
	layer.flow_accumulation = topology.accumulation
	var river_mask := _river_mask(
		terrain.terrain_height, layer.flow_accumulation, actual_settings.river_runoff_threshold
	)
	layer.river_order = _calculate_strahler_order(
		river_mask, layer.flow_to, topology.topological_order
	)
	var networks := _build_river_networks(
		graph,
		river_mask,
		layer.flow_to,
		topology.upstream,
		layer.flow_accumulation,
		layer.river_order
	)
	layer.river_network_id = networks.river_network_id
	layer.river_networks = networks.river_networks
	var watersheds := _calculate_watersheds(
		graph, terrain.terrain_height, closed_basin_id, layer.flow_to
	)
	if not watersheds.ok:
		push_error("Formal Hydrology could not assign every Land Cell to a Watershed")
		return null
	layer.watershed_id = watersheds.watershed_id
	layer.watershed_count = watersheds.count
	layer.closed_basin_inflows = _calculate_closed_basin_inflows(
		graph,
		terrain.terrain_height,
		climate.temperature,
		closed_basin_id,
		layer.local_runoff,
		layer.watershed_id,
		watersheds.watershed_basin_id
	)
	var validation_errors := WorldHydrologyValidator.validate(
		graph, terrain, climate, closed_basin_id, layer
	)
	if not validation_errors.is_empty():
		push_error("Formal Hydrology validation failed: " + "; ".join(validation_errors))
		return null
	return layer


static func _inputs_are_valid(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		closed_basin_id: PackedInt32Array,
		settings: WorldHydrologySettings
) -> bool:
	if graph == null or terrain == null or climate == null:
		push_error("Formal Hydrology requires Spatial, terrain, and climate inputs")
		return false
	var count := graph.cell_count()
	if count == 0 \
			or terrain.cell_count() != count \
			or climate.cell_count() != count \
			or climate.precipitation.size() != count \
			or closed_basin_id.size() != count:
		push_error("Formal Hydrology input arrays must contain one value per Cell")
		return false
	if graph.cell_areas.size() != count \
			or graph.cell_neighbors.size() != count \
			or graph.cell_neighbor_distances.size() != count \
			or graph.cell_is_border.size() != count:
		push_error("Formal Hydrology requires Cell area, neighbors, distances, and boundary flags")
		return false
	var setting_errors := settings.validate()
	if not setting_errors.is_empty():
		push_error("Invalid WorldHydrologySettings: " + "; ".join(setting_errors))
		return false
	for cell_id in count:
		if not is_finite(graph.cell_areas[cell_id]) or graph.cell_areas[cell_id] <= 0.0:
			push_error("Formal Hydrology Cell areas must be finite and positive")
			return false
		if graph.cell_neighbor_distances[cell_id].size() != graph.cell_neighbors[cell_id].size():
			push_error("Formal Hydrology neighbor distances must align with Cell neighbors")
			return false
		for distance in graph.cell_neighbor_distances[cell_id]:
			if not is_finite(distance) or distance <= 0.0:
				push_error("Formal Hydrology neighbor distances must be finite and positive")
				return false
		if not is_finite(terrain.terrain_height[cell_id]) \
				or terrain.terrain_height[cell_id] < -100.0 \
				or terrain.terrain_height[cell_id] > 100.0:
			push_error("Formal Hydrology terrain_height must be finite and inside [-100, 100]")
			return false
		if not is_finite(climate.precipitation[cell_id]) \
				or climate.precipitation[cell_id] < 0.0 \
				or not is_finite(climate.temperature[cell_id]):
			push_error("Formal Hydrology climate values must be finite and precipitation non-negative")
			return false
		if closed_basin_id[cell_id] < -1:
			push_error("Formal Hydrology closed_basin_id must be -1 or non-negative")
			return false
	return true


static func _river_mask(
		heights: PackedFloat32Array,
		flow_accumulation: PackedFloat32Array,
		threshold: float
) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(heights.size())
	for cell_id in heights.size():
		if heights[cell_id] >= 0.0 and flow_accumulation[cell_id] >= threshold:
			mask[cell_id] = 1
	return mask


static func _calculate_strahler_order(
		river_mask: PackedByteArray,
		flow_to: PackedInt32Array,
		topological_order: PackedInt32Array
) -> PackedInt32Array:
	var river_order := PackedInt32Array()
	river_order.resize(river_mask.size())
	river_order.fill(-1)
	var maximum_upstream := PackedInt32Array()
	maximum_upstream.resize(river_mask.size())
	var maximum_count := PackedInt32Array()
	maximum_count.resize(river_mask.size())
	for cell_id in topological_order:
		if river_mask[cell_id] == 0:
			continue
		var order := 1
		if maximum_upstream[cell_id] > 0:
			order = maximum_upstream[cell_id] + 1 \
					if maximum_count[cell_id] >= 2 else maximum_upstream[cell_id]
		river_order[cell_id] = order
		var downstream_id := flow_to[cell_id]
		if downstream_id < 0 or river_mask[downstream_id] == 0:
			continue
		if order > maximum_upstream[downstream_id]:
			maximum_upstream[downstream_id] = order
			maximum_count[downstream_id] = 1
		elif order == maximum_upstream[downstream_id]:
			maximum_count[downstream_id] += 1
	return river_order


static func _build_river_networks(
		graph: SpatialGraph,
		river_mask: PackedByteArray,
		flow_to: PackedInt32Array,
		upstream: Array,
		flow_accumulation: PackedFloat32Array,
		river_order: PackedInt32Array
) -> Dictionary:
	var river_network_id := PackedInt32Array()
	river_network_id.resize(graph.cell_count())
	river_network_id.fill(-1)
	var river_networks: Array = []
	for seed_id in graph.cell_count():
		if river_mask[seed_id] == 0 or river_network_id[seed_id] >= 0:
			continue
		var id := river_networks.size()
		var cells := PackedInt32Array()
		var queue := PackedInt32Array([seed_id])
		river_network_id[seed_id] = id
		var queue_index := 0
		while queue_index < queue.size():
			var cell_id := queue[queue_index]
			queue_index += 1
			cells.append(cell_id)
			for neighbor_id in graph.cell_neighbors[cell_id]:
				if river_mask[neighbor_id] != 0 \
						and river_network_id[neighbor_id] < 0 \
						and (flow_to[cell_id] == neighbor_id or flow_to[neighbor_id] == cell_id):
					river_network_id[neighbor_id] = id
					queue.append(neighbor_id)
		var river_network := HydrologyRiverNetwork.new()
		river_network.id = id
		for cell_id in cells:
			var has_river_upstream := false
			for upstream_id in upstream[cell_id]:
				if river_mask[upstream_id] != 0:
					has_river_upstream = true
					break
			if not has_river_upstream \
					and (river_network.source_cell < 0 \
					or flow_accumulation[cell_id] > flow_accumulation[river_network.source_cell]):
				river_network.source_cell = cell_id
			var downstream_id := flow_to[cell_id]
			if downstream_id < 0 or river_mask[downstream_id] == 0:
				if river_network.mouth_cell < 0 \
						or flow_accumulation[cell_id] > flow_accumulation[river_network.mouth_cell]:
					river_network.mouth_cell = cell_id
			river_network.order = maxi(river_network.order, river_order[cell_id])
		if river_network.source_cell < 0:
			river_network.source_cell = cells[0]
		if river_network.mouth_cell < 0:
			river_network.mouth_cell = cells[0]
		river_network.discharge = flow_accumulation[river_network.mouth_cell]
		river_networks.append(river_network)
	return {
		"river_network_id": river_network_id,
		"river_networks": river_networks,
	}


static func _calculate_watersheds(
		graph: SpatialGraph,
		heights: PackedFloat32Array,
		closed_basin_id: PackedInt32Array,
		flow_to: PackedInt32Array
) -> Dictionary:
	var watershed_id := PackedInt32Array()
	watershed_id.resize(graph.cell_count())
	watershed_id.fill(-1)
	var terminal_by_cell := {}
	var watershed_by_terminal := {}
	var watershed_basin_ids := PackedInt32Array()
	for start_id in graph.cell_count():
		if heights[start_id] < 0.0:
			continue
		var path := PackedInt32Array()
		var cell_id := start_id
		var terminal := ""
		while terminal.is_empty():
			if terminal_by_cell.has(cell_id):
				terminal = terminal_by_cell[cell_id]
				break
			path.append(cell_id)
			var downstream_id := flow_to[cell_id]
			if downstream_id >= 0:
				cell_id = downstream_id
				if heights[cell_id] < 0.0:
					terminal = "water:%d" % cell_id
			elif downstream_id == WorldHydrologyLayer.FLOW_TO_BOUNDARY:
				terminal = "boundary:%d" % cell_id
			elif downstream_id == WorldHydrologyLayer.FLOW_TO_CLOSED_BASIN:
				terminal = "basin:%d" % closed_basin_id[cell_id]
			elif downstream_id == WorldHydrologyLayer.FLOW_TO_WATER:
				terminal = "water:%d" % cell_id
			else:
				return {"ok": false}
		for path_cell_id in path:
			terminal_by_cell[path_cell_id] = terminal
		if not watershed_by_terminal.has(terminal):
			var next_id := watershed_by_terminal.size()
			watershed_by_terminal[terminal] = next_id
			var basin_id := -1
			if terminal.begins_with("basin:"):
				basin_id = int(terminal.trim_prefix("basin:"))
			watershed_basin_ids.append(basin_id)
		watershed_id[start_id] = watershed_by_terminal[terminal]
	return {
		"ok": true,
		"watershed_id": watershed_id,
		"count": watershed_by_terminal.size(),
		"watershed_basin_id": watershed_basin_ids,
	}


static func _calculate_closed_basin_inflows(
		graph: SpatialGraph,
		heights: PackedFloat32Array,
		temperature: PackedFloat32Array,
		closed_basin_id: PackedInt32Array,
		local_runoff: PackedFloat32Array,
		watershed_id: PackedInt32Array,
		watershed_basin_id: PackedInt32Array
) -> Array:
	var basin_ids := {}
	for basin_id in closed_basin_id:
		if basin_id >= 0:
			basin_ids[basin_id] = true
	var sorted_ids := PackedInt32Array()
	for basin_id in basin_ids:
		sorted_ids.append(basin_id)
	sorted_ids.sort()
	var inflows: Array = []
	var index_by_id := {}
	var temperature_area_sum := PackedFloat64Array()
	temperature_area_sum.resize(sorted_ids.size())
	for basin_id in sorted_ids:
		var inflow := ClosedBasinInflow.new()
		inflow.closed_basin_id = basin_id
		index_by_id[basin_id] = inflows.size()
		inflows.append(inflow)
	for cell_id in graph.cell_count():
		if heights[cell_id] < 0.0:
			continue
		var cell_watershed_id := watershed_id[cell_id]
		var basin_id := watershed_basin_id[cell_watershed_id]
		if basin_id < 0:
			continue
		var inflow_index: int = index_by_id[basin_id]
		var inflow: ClosedBasinInflow = inflows[inflow_index]
		inflow.catchment_area += graph.cell_areas[cell_id]
		inflow.total_inflow += local_runoff[cell_id]
		temperature_area_sum[inflow_index] += temperature[cell_id] * graph.cell_areas[cell_id]
	for inflow_index in inflows.size():
		var inflow: ClosedBasinInflow = inflows[inflow_index]
		if inflow.catchment_area > 0.0:
			inflow.mean_temperature = temperature_area_sum[inflow_index] / inflow.catchment_area
	return inflows
