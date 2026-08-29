class_name HydrologyConditioner
extends RefCounted

const MIN_HEIGHT := -100.0
const MAX_HEIGHT := 100.0
const MIN_MATERIAL_RESISTANCE := 0.75
const MAX_MATERIAL_RESISTANCE := 1.50


static func condition(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		preliminary_flow: HydrologyFlowResult,
		geology: GeologyLayer,
		settings: HydrologyConditioningSettings = null
) -> HydrologyConditioningResult:
	var actual_settings := settings if settings != null else HydrologyConditioningSettings.new()
	if not _inputs_are_valid(graph, terrain, preliminary_flow, geology, actual_settings):
		return null
	var result := _create_result(terrain)
	result.initial_sink_count = _count_initial_sinks(graph, result.terrain_height)

	var analysis := _priority_flood(graph, result.terrain_height)
	var depressions := _depression_components(graph, result.terrain_height, analysis.level)
	var naturally_drainable := _strictly_drainable_cells(graph, result.terrain_height)
	var next_basin_id := 0
	for depression in depressions:
		if _component_was_modified(depression.cells, result.conditioning_action):
			continue
		var filled := false
		if depression.cells.size() <= actual_settings.small_fill_max_cells \
				and depression.max_depth <= actual_settings.small_fill_max_depth:
			filled = _fill_depression(
				depression.cells,
				analysis.parent,
				graph,
				result,
				actual_settings.flow_epsilon
			)
			if filled:
				result.filled_depression_count += 1
		if filled:
			continue
		var depression_inflow := _depression_inflow(depression, preliminary_flow)
		if depression_inflow >= actual_settings.breach_min_inflow:
			var breach_path := _least_cost_breach(
				depression,
				graph,
				result.terrain_height,
				naturally_drainable,
				geology.erodibility,
				actual_settings
			)
			if not breach_path.is_empty():
				_apply_breach(breach_path, result)
				result.breached_depression_count += 1
				result.breached_by_sufficient_inflow_count += 1
				continue
		else:
			result.rejected_breach_by_low_inflow_count += 1
		if depression.cells.size() <= actual_settings.fallback_fill_max_cells \
				and depression.max_depth <= actual_settings.fallback_fill_max_depth:
			filled = _fill_depression(
				depression.cells,
				analysis.parent,
				graph,
				result,
				actual_settings.flow_epsilon
			)
			if filled:
				result.filled_depression_count += 1
		if not filled:
			_mark_closed_basin(depression.cells, next_basin_id, result)
			next_basin_id += 1

	# Stale components can remain after neighboring breaches. Mark those explicitly
	# before the final flat-resolution pass, rather than silently performing a large fill.
	var terminal_mask := _terminal_mask(graph, result)
	analysis = _priority_flood(graph, result.terrain_height, terminal_mask)
	for depression in _depression_components(graph, result.terrain_height, analysis.level):
		if _contains_unmarked_cell(depression.cells, result.closed_basin_id):
			var cells_to_mark := PackedInt32Array()
			for cell_id in depression.cells:
				if result.closed_basin_id[cell_id] < 0:
					cells_to_mark.append(cell_id)
			if not cells_to_mark.is_empty():
				_mark_closed_basin(cells_to_mark, next_basin_id, result)
				next_basin_id += 1

	_resolve_flats(graph, result, actual_settings.flow_epsilon, next_basin_id)
	_finalize_debug_data(result)
	var validation_errors := HydrologyConditioningValidator.validate(
		graph, result.original_height, result
	)
	if not validation_errors.is_empty():
		push_error("Hydrology conditioning failed final validation: " + "; ".join(validation_errors))
		return null
	return result


static func _inputs_are_valid(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		preliminary_flow: HydrologyFlowResult,
		geology: GeologyLayer,
		settings: HydrologyConditioningSettings
) -> bool:
	if graph == null or terrain == null or preliminary_flow == null or geology == null:
		push_error("HydrologyConditioner requires Spatial, terrain, Preliminary Flow, and Geology")
		return false
	var count := graph.cell_count()
	if count == 0 \
			or terrain.cell_count() != count \
			or preliminary_flow.local_runoff.size() != count \
			or preliminary_flow.flow_to.size() != count \
			or preliminary_flow.flow_accumulation.size() != count \
			or geology.erodibility.size() != count:
		push_error("HydrologyConditioner input sizes must match and be non-empty")
		return false
	if graph.cell_neighbors.size() != count or graph.cell_is_border.size() != count:
		push_error("HydrologyConditioner requires neighbors and boundary flags for every Cell")
		return false
	var errors := settings.validate()
	if not errors.is_empty():
		push_error("Invalid HydrologyConditioningSettings: " + "; ".join(errors))
		return false
	for cell_id in count:
		var height := terrain.terrain_height[cell_id]
		if not is_finite(height) or height < MIN_HEIGHT or height > MAX_HEIGHT:
			push_error("HydrologyConditioner terrain heights must be finite and inside [-100, 100]")
			return false
		if not is_finite(preliminary_flow.local_runoff[cell_id]) \
				or preliminary_flow.local_runoff[cell_id] < 0.0 \
				or not is_finite(preliminary_flow.flow_accumulation[cell_id]) \
				or preliminary_flow.flow_accumulation[cell_id] < preliminary_flow.local_runoff[cell_id]:
			push_error("HydrologyConditioner Preliminary Flow values must be finite and non-negative")
			return false
	var geology_errors := GeologyValidator.validate(graph, terrain, geology)
	if not geology_errors.is_empty():
		push_error("HydrologyConditioner received invalid Geology: " + "; ".join(geology_errors))
		return false
	return true


static func _depression_inflow(
		depression: Dictionary,
		preliminary_flow: HydrologyFlowResult
) -> float:
	var inflow := 0.0
	for cell_id in depression.cells:
		if preliminary_flow.flow_to[cell_id] == HydrologyFlowResult.FLOW_TO_SINK:
			inflow += preliminary_flow.flow_accumulation[cell_id]
	return inflow


static func _create_result(terrain: TerrainHeightLayer) -> HydrologyConditioningResult:
	var result := HydrologyConditioningResult.new()
	result.original_height = terrain.terrain_height.duplicate()
	result.terrain_height = terrain.terrain_height.duplicate()
	result.closed_basin_id.resize(terrain.cell_count())
	result.closed_basin_id.fill(-1)
	result.height_delta.resize(terrain.cell_count())
	result.conditioning_action.resize(terrain.cell_count())
	result.conditioning_action.fill(HydrologyConditioningResult.Action.NONE)
	return result


static func _count_initial_sinks(graph: SpatialGraph, heights: PackedFloat32Array) -> int:
	var sink_count := 0
	for cell_id in graph.cell_count():
		if heights[cell_id] < 0.0 or graph.cell_is_border[cell_id] != 0:
			continue
		var has_lower_neighbor := false
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if heights[neighbor_id] < heights[cell_id]:
				has_lower_neighbor = true
				break
		if not has_lower_neighbor:
			sink_count += 1
	return sink_count


static func _priority_flood(
		graph: SpatialGraph,
		heights: PackedFloat32Array,
		extra_terminal_mask: PackedByteArray = PackedByteArray()
) -> Dictionary:
	var count := graph.cell_count()
	var level := PackedFloat32Array()
	level.resize(count)
	level.fill(INF)
	var parent := PackedInt32Array()
	parent.resize(count)
	parent.fill(-1)
	var visited := PackedByteArray()
	visited.resize(count)
	var heap: Array = []
	for cell_id in count:
		var extra_terminal := extra_terminal_mask.size() == count and extra_terminal_mask[cell_id] != 0
		if heights[cell_id] < 0.0 or graph.cell_is_border[cell_id] != 0 or extra_terminal:
			level[cell_id] = heights[cell_id]
			_heap_push(heap, [level[cell_id], cell_id])
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var cell_id: int = entry[1]
		if visited[cell_id] != 0:
			continue
		visited[cell_id] = 1
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if visited[neighbor_id] != 0:
				continue
			var candidate := maxf(heights[neighbor_id], level[cell_id])
			if candidate < level[neighbor_id]:
				level[neighbor_id] = candidate
				parent[neighbor_id] = cell_id
				_heap_push(heap, [candidate, neighbor_id])
	# A malformed/disconnected component without an outlet is represented as its own basin seed.
	for cell_id in count:
		if is_inf(level[cell_id]):
			level[cell_id] = heights[cell_id]
			_heap_push(heap, [level[cell_id], cell_id])
			while not heap.is_empty():
				var entry: Array = _heap_pop(heap)
				var current: int = entry[1]
				if visited[current] != 0:
					continue
				visited[current] = 1
				for neighbor_id in graph.cell_neighbors[current]:
					if visited[neighbor_id] != 0:
						continue
					var candidate := maxf(heights[neighbor_id], level[current])
					if candidate < level[neighbor_id]:
						level[neighbor_id] = candidate
						parent[neighbor_id] = current
						_heap_push(heap, [candidate, neighbor_id])
	return {"level": level, "parent": parent}


static func _depression_components(
		graph: SpatialGraph,
		heights: PackedFloat32Array,
		flood_level: PackedFloat32Array
) -> Array:
	var depressed := PackedByteArray()
	depressed.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		if heights[cell_id] >= 0.0 and flood_level[cell_id] > heights[cell_id]:
			depressed[cell_id] = 1
	var assigned := PackedByteArray()
	assigned.resize(graph.cell_count())
	var components: Array = []
	for seed_id in graph.cell_count():
		if depressed[seed_id] == 0 or assigned[seed_id] != 0:
			continue
		var cells := PackedInt32Array()
		var queue := PackedInt32Array([seed_id])
		assigned[seed_id] = 1
		var queue_index := 0
		var lowest_cell := seed_id
		var max_depth := 0.0
		var spill_height := flood_level[seed_id]
		while queue_index < queue.size():
			var cell_id := queue[queue_index]
			queue_index += 1
			cells.append(cell_id)
			if heights[cell_id] < heights[lowest_cell]:
				lowest_cell = cell_id
			max_depth = maxf(max_depth, flood_level[cell_id] - heights[cell_id])
			spill_height = maxf(spill_height, flood_level[cell_id])
			for neighbor_id in graph.cell_neighbors[cell_id]:
				if depressed[neighbor_id] != 0 and assigned[neighbor_id] == 0:
					assigned[neighbor_id] = 1
					queue.append(neighbor_id)
		components.append({
			"cells": cells,
			"lowest_cell": lowest_cell,
			"max_depth": max_depth,
			"spill_height": spill_height,
		})
	return components


static func _fill_depression(
		cells: PackedInt32Array,
		parents: PackedInt32Array,
		graph: SpatialGraph,
		result: HydrologyConditioningResult,
		flow_epsilon: float
) -> bool:
	var member := PackedByteArray()
	member.resize(graph.cell_count())
	for cell_id in cells:
		member[cell_id] = 1
	var depth_buckets := {}
	var maximum_depth := 0
	for cell_id in cells:
		var depth := 1
		var current := cell_id
		var guard := 0
		while parents[current] >= 0 and member[parents[current]] != 0 and guard < cells.size():
			depth += 1
			current = parents[current]
			guard += 1
		if guard >= cells.size():
			return false
		if not depth_buckets.has(depth):
			depth_buckets[depth] = PackedInt32Array()
		var bucket: PackedInt32Array = depth_buckets[depth]
		bucket.append(cell_id)
		depth_buckets[depth] = bucket
		maximum_depth = maxi(maximum_depth, depth)
	var proposed := {}
	for depth in range(1, maximum_depth + 1):
		if not depth_buckets.has(depth):
			continue
		for cell_id in depth_buckets[depth]:
			var parent_id := parents[cell_id]
			if parent_id < 0:
				return false
			var parent_height := float(proposed.get(parent_id, result.terrain_height[parent_id]))
			var target := result.terrain_height[cell_id]
			if result.terrain_height[parent_id] >= 0.0:
				target = maxf(target, parent_height + flow_epsilon)
			if target > MAX_HEIGHT:
				return false
			proposed[cell_id] = target
	for cell_id in cells:
		var target: float = proposed.get(cell_id, result.terrain_height[cell_id])
		if target > result.terrain_height[cell_id]:
			result.terrain_height[cell_id] = target
			if result.conditioning_action[cell_id] == HydrologyConditioningResult.Action.NONE:
				result.conditioning_action[cell_id] = HydrologyConditioningResult.Action.FILL
	return true


static func _strictly_drainable_cells(
		graph: SpatialGraph,
		heights: PackedFloat32Array
) -> PackedByteArray:
	var drainable := PackedByteArray()
	drainable.resize(graph.cell_count())
	var queue := PackedInt32Array()
	for cell_id in graph.cell_count():
		if heights[cell_id] < 0.0 or graph.cell_is_border[cell_id] != 0:
			drainable[cell_id] = 1
			queue.append(cell_id)
	var index := 0
	while index < queue.size():
		var cell_id := queue[index]
		index += 1
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if drainable[neighbor_id] == 0 and heights[neighbor_id] > heights[cell_id]:
				drainable[neighbor_id] = 1
				queue.append(neighbor_id)
	return drainable


static func _least_cost_breach(
		depression: Dictionary,
		graph: SpatialGraph,
		heights: PackedFloat32Array,
		naturally_drainable: PackedByteArray,
		erodibility: PackedFloat32Array,
		settings: HydrologyConditioningSettings
) -> Array:
	var member := PackedByteArray()
	member.resize(graph.cell_count())
	for cell_id in depression.cells:
		member[cell_id] = 1
	var start: int = depression.lowest_cell
	var heap: Array = []
	var start_key := Vector2i(start, 0)
	var best := {start_key: 0.0}
	var planned_height := {start_key: float(heights[start])}
	var previous := {}
	var terminal_states := {}
	var serial := 0
	_heap_push(heap, [0.0, serial, start, 0, float(heights[start])])
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var cost: float = entry[0]
		var cell_id: int = entry[2]
		var distance: int = entry[3]
		var channel_height: float = entry[4]
		var key := Vector2i(cell_id, distance)
		if cost > float(best.get(key, INF)):
			continue
		if terminal_states.has(key):
			return _reconstruct_breach(key, previous, planned_height)
		if distance >= settings.max_breach_distance:
			continue
		for neighbor_id in graph.cell_neighbors[cell_id]:
			var next_distance := distance + 1
			var next_height := heights[neighbor_id]
			var next_cost := cost
			var is_water := heights[neighbor_id] < 0.0
			var is_boundary := graph.cell_is_border[neighbor_id] != 0
			var joins_strict_drainage := member[neighbor_id] == 0 \
					and naturally_drainable[neighbor_id] != 0 \
					and heights[neighbor_id] < channel_height - settings.flow_epsilon
			if is_water:
				next_height = heights[neighbor_id]
			elif is_boundary:
				next_height = minf(heights[neighbor_id], channel_height - settings.flow_epsilon)
				if next_height < 0.0:
					continue
				next_cost += material_adjusted_cut_cost(
					heights[neighbor_id] - next_height, erodibility[neighbor_id]
				)
			elif joins_strict_drainage:
				next_height = heights[neighbor_id]
			else:
				next_height = minf(heights[neighbor_id], channel_height - settings.flow_epsilon)
				if next_height < 0.0:
					continue
				next_cost += material_adjusted_cut_cost(
					heights[neighbor_id] - next_height, erodibility[neighbor_id]
				)
			if next_cost > settings.max_breach_cost:
				continue
			var next_key := Vector2i(neighbor_id, next_distance)
			if next_cost >= float(best.get(next_key, INF)):
				continue
			best[next_key] = next_cost
			planned_height[next_key] = next_height
			previous[next_key] = key
			if is_water or is_boundary or joins_strict_drainage:
				terminal_states[next_key] = true
			else:
				terminal_states.erase(next_key)
			serial += 1
			_heap_push(heap, [next_cost, serial, neighbor_id, next_distance, next_height])
	return []


static func material_resistance(erodibility: float) -> float:
	return lerpf(
		MAX_MATERIAL_RESISTANCE,
		MIN_MATERIAL_RESISTANCE,
		clampf(erodibility, 0.0, 1.0)
	)


static func material_adjusted_cut_cost(original_cut_cost: float, erodibility: float) -> float:
	return original_cut_cost * material_resistance(erodibility)


static func _reconstruct_breach(
		end_key: Vector2i,
		previous: Dictionary,
		planned_height: Dictionary
) -> Array:
	var reversed: Array = []
	var key := end_key
	while true:
		reversed.append({"cell_id": key.x, "height": float(planned_height[key])})
		if not previous.has(key):
			break
		key = previous[key]
	reversed.reverse()
	return reversed


static func _apply_breach(path: Array, result: HydrologyConditioningResult) -> void:
	for path_index in range(1, path.size()):
		var cell_id: int = path[path_index].cell_id
		var target: float = path[path_index].height
		if result.terrain_height[cell_id] >= 0.0 and target < result.terrain_height[cell_id]:
			result.terrain_height[cell_id] = maxf(0.0, target)
			result.conditioning_action[cell_id] = HydrologyConditioningResult.Action.CARVE


static func _mark_closed_basin(
		cells: PackedInt32Array,
		basin_id: int,
		result: HydrologyConditioningResult
) -> void:
	for cell_id in cells:
		result.closed_basin_id[cell_id] = basin_id
		if result.conditioning_action[cell_id] == HydrologyConditioningResult.Action.NONE:
			result.conditioning_action[cell_id] = HydrologyConditioningResult.Action.CLOSED_BASIN


static func _terminal_mask(
		graph: SpatialGraph,
		result: HydrologyConditioningResult
) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		if result.closed_basin_id[cell_id] >= 0 \
				or result.conditioning_action[cell_id] == HydrologyConditioningResult.Action.CARVE:
			mask[cell_id] = 1
	return mask


static func _resolve_flats(
		graph: SpatialGraph,
		result: HydrologyConditioningResult,
		flow_epsilon: float,
		next_basin_id: int
) -> void:
	var terminal := _terminal_mask(graph, result)
	var count := graph.cell_count()
	var target := PackedFloat32Array()
	target.resize(count)
	target.fill(INF)
	var visited := PackedByteArray()
	visited.resize(count)
	var heap: Array = []
	for cell_id in count:
		if result.terrain_height[cell_id] < 0.0 \
				or graph.cell_is_border[cell_id] != 0 \
				or terminal[cell_id] != 0:
			target[cell_id] = result.terrain_height[cell_id]
			_heap_push(heap, [target[cell_id], cell_id])
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var cell_id: int = entry[1]
		if visited[cell_id] != 0:
			continue
		visited[cell_id] = 1
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if visited[neighbor_id] != 0 or terminal[neighbor_id] != 0:
				continue
			var candidate := result.terrain_height[neighbor_id]
			if result.terrain_height[cell_id] >= 0.0:
				candidate = maxf(candidate, target[cell_id] + flow_epsilon)
			if candidate < target[neighbor_id]:
				target[neighbor_id] = candidate
				_heap_push(heap, [candidate, neighbor_id])
	var overflow := PackedInt32Array()
	for cell_id in count:
		if result.terrain_height[cell_id] >= 0.0 and target[cell_id] > MAX_HEIGHT:
			overflow.append(cell_id)
	if not overflow.is_empty():
		_mark_closed_basin(overflow, next_basin_id, result)
		_resolve_flats(graph, result, flow_epsilon, next_basin_id + 1)
		return
	for cell_id in count:
		if result.terrain_height[cell_id] >= 0.0 \
				and target[cell_id] > result.terrain_height[cell_id]:
			result.terrain_height[cell_id] = target[cell_id]
			if result.conditioning_action[cell_id] == HydrologyConditioningResult.Action.NONE:
				result.conditioning_action[cell_id] = HydrologyConditioningResult.Action.FILL


static func _finalize_debug_data(result: HydrologyConditioningResult) -> void:
	var modified_count := 0
	var basin_ids := {}
	for cell_id in result.cell_count():
		var delta := result.terrain_height[cell_id] - result.original_height[cell_id]
		result.height_delta[cell_id] = delta
		if not is_zero_approx(delta):
			modified_count += 1
		result.max_raise = maxf(result.max_raise, delta)
		result.max_cut = maxf(result.max_cut, -delta)
		if result.closed_basin_id[cell_id] >= 0:
			basin_ids[result.closed_basin_id[cell_id]] = true
	result.closed_basin_count = basin_ids.size()
	result.modified_cell_ratio = float(modified_count) / float(result.cell_count())


static func _component_was_modified(
		cells: PackedInt32Array,
		actions: PackedByteArray
) -> bool:
	for cell_id in cells:
		if actions[cell_id] != HydrologyConditioningResult.Action.NONE:
			return true
	return false


static func _contains_unmarked_cell(
		cells: PackedInt32Array,
		closed_basin_id: PackedInt32Array
) -> bool:
	for cell_id in cells:
		if closed_basin_id[cell_id] < 0:
			return true
	return false


static func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) >> 1
		if not _heap_less(entry, heap[parent]):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = entry


static func _heap_pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var tail: Array = heap.pop_back()
	if heap.is_empty():
		return result
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var child := left
		if right < heap.size() and _heap_less(heap[right], heap[left]):
			child = right
		if not _heap_less(heap[child], tail):
			break
		heap[index] = heap[child]
		index = child
	heap[index] = tail
	return result


static func _heap_less(first: Array, second: Array) -> bool:
	if float(first[0]) != float(second[0]):
		return float(first[0]) < float(second[0])
	return int(first[1]) < int(second[1])
