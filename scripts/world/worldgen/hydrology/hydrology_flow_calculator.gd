class_name HydrologyFlowCalculator
extends RefCounted


static func calculate_local_runoff(
		graph: SpatialGraph,
		precipitation: PackedFloat32Array,
		runoff_modifier: float
) -> PackedFloat32Array:
	var runoff := PackedFloat32Array()
	runoff.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		var value := precipitation[cell_id] * graph.cell_areas[cell_id] * runoff_modifier
		runoff[cell_id] = value
		if not is_finite(runoff[cell_id]) or runoff[cell_id] < 0.0:
			push_error("Hydrology local runoff overflowed Float32 storage")
			return PackedFloat32Array()
	return runoff


static func calculate_flow_to(
		graph: SpatialGraph,
		heights: PackedFloat32Array,
		closed_basin_id: PackedInt32Array = PackedInt32Array(),
		allow_sinks: bool = false
) -> PackedInt32Array:
	var has_closed_basins := closed_basin_id.size() == graph.cell_count()
	var flow_to := PackedInt32Array()
	flow_to.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		if heights[cell_id] < 0.0:
			flow_to[cell_id] = WorldHydrologyLayer.FLOW_TO_WATER
			continue
		if has_closed_basins and closed_basin_id[cell_id] >= 0:
			flow_to[cell_id] = WorldHydrologyLayer.FLOW_TO_CLOSED_BASIN
			continue
		if graph.cell_is_border[cell_id] != 0:
			flow_to[cell_id] = WorldHydrologyLayer.FLOW_TO_BOUNDARY
			continue
		var best_neighbor := -1
		var best_slope := 0.0
		var neighbors: PackedInt32Array = graph.cell_neighbors[cell_id]
		var distances: PackedFloat64Array = graph.cell_neighbor_distances[cell_id]
		for neighbor_index in neighbors.size():
			var neighbor_id := neighbors[neighbor_index]
			var height_drop := heights[cell_id] - heights[neighbor_id]
			if height_drop <= 0.0:
				continue
			var slope := height_drop / distances[neighbor_index]
			if slope > best_slope \
					or (is_equal_approx(slope, best_slope) and neighbor_id < best_neighbor):
				best_slope = slope
				best_neighbor = neighbor_id
		if best_neighbor < 0:
			if allow_sinks:
				flow_to[cell_id] = HydrologyFlowResult.FLOW_TO_SINK
				continue
			push_error("Hydrology Flow found an unconditioned Sink at Cell %d" % cell_id)
			return PackedInt32Array()
		flow_to[cell_id] = best_neighbor
	return flow_to


static func accumulate_flow(
		local_runoff: PackedFloat32Array,
		flow_to: PackedInt32Array
) -> Dictionary:
	var count := local_runoff.size()
	var indegree := PackedInt32Array()
	indegree.resize(count)
	var upstream: Array = []
	upstream.resize(count)
	for cell_id in count:
		upstream[cell_id] = PackedInt32Array()
		if flow_to[cell_id] >= 0:
			indegree[flow_to[cell_id]] += 1
	for cell_id in count:
		var downstream_id := flow_to[cell_id]
		if downstream_id >= 0:
			var sources: PackedInt32Array = upstream[downstream_id]
			sources.append(cell_id)
			upstream[downstream_id] = sources
	var queue := PackedInt32Array()
	for cell_id in count:
		if indegree[cell_id] == 0:
			queue.append(cell_id)
	var accumulation64 := PackedFloat64Array()
	accumulation64.resize(count)
	for cell_id in count:
		accumulation64[cell_id] = local_runoff[cell_id]
	var topological_order := PackedInt32Array()
	var queue_index := 0
	while queue_index < queue.size():
		var cell_id := queue[queue_index]
		queue_index += 1
		topological_order.append(cell_id)
		var downstream_id := flow_to[cell_id]
		if downstream_id >= 0:
			accumulation64[downstream_id] += accumulation64[cell_id]
			indegree[downstream_id] -= 1
			if indegree[downstream_id] == 0:
				queue.append(downstream_id)
	if topological_order.size() != count:
		return {"ok": false}
	var accumulation := PackedFloat32Array()
	accumulation.resize(count)
	for cell_id in count:
		accumulation[cell_id] = accumulation64[cell_id]
		if not is_finite(accumulation[cell_id]) or accumulation[cell_id] < local_runoff[cell_id]:
			return {"ok": false}
	return {
		"ok": true,
		"accumulation": accumulation,
		"topological_order": topological_order,
		"upstream": upstream,
	}
