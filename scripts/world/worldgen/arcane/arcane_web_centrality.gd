class_name ArcaneWebCentrality
extends RefCounted

const _DISTANCE_EPSILON := 1.0e-9


static func calculate(node_count: int, edges: Array[ArcaneWebEdge]) -> Dictionary:
	var node_scores := PackedFloat64Array()
	var edge_scores := PackedFloat64Array()
	node_scores.resize(node_count)
	edge_scores.resize(edges.size())
	if node_count <= 1:
		return {"nodes": node_scores, "edges": edge_scores}

	var adjacency: Array = []
	adjacency.resize(node_count)
	for node_id in node_count:
		adjacency[node_id] = []
	for edge in edges:
		adjacency[edge.node_a_id].append([edge.node_b_id, edge.id, edge.length])
		adjacency[edge.node_b_id].append([edge.node_a_id, edge.id, edge.length])
	for neighbors in adjacency:
		neighbors.sort_custom(func(first: Array, second: Array) -> bool:
			return first[0] < second[0] if first[0] != second[0] else first[1] < second[1]
		)

	for source in node_count:
		var stack := PackedInt32Array()
		var predecessors: Array = []
		predecessors.resize(node_count)
		var sigma := PackedFloat64Array()
		var distance := PackedFloat64Array()
		sigma.resize(node_count)
		distance.resize(node_count)
		distance.fill(INF)
		for node_id in node_count:
			predecessors[node_id] = []
		sigma[source] = 1.0
		distance[source] = 0.0
		var heap: Array = []
		_heap_push(heap, [0.0, source])
		while not heap.is_empty():
			var entry: Array = _heap_pop(heap)
			var current_distance: float = entry[0]
			var node_id: int = entry[1]
			if current_distance > distance[node_id] + _DISTANCE_EPSILON:
				continue
			stack.append(node_id)
			for neighbor_entry in adjacency[node_id]:
				var neighbor_id: int = neighbor_entry[0]
				var edge_id: int = neighbor_entry[1]
				var candidate := current_distance + float(neighbor_entry[2])
				if candidate < distance[neighbor_id] - _DISTANCE_EPSILON:
					distance[neighbor_id] = candidate
					_heap_push(heap, [candidate, neighbor_id])
					sigma[neighbor_id] = sigma[node_id]
					predecessors[neighbor_id] = [[node_id, edge_id]]
				elif absf(candidate - distance[neighbor_id]) <= _DISTANCE_EPSILON:
					sigma[neighbor_id] += sigma[node_id]
					predecessors[neighbor_id].append([node_id, edge_id])

		var dependency := PackedFloat64Array()
		dependency.resize(node_count)
		while not stack.is_empty():
			var node_id := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			if sigma[node_id] > 0.0:
				for predecessor_entry in predecessors[node_id]:
					var predecessor_id: int = predecessor_entry[0]
					var edge_id: int = predecessor_entry[1]
					var contribution := (
						sigma[predecessor_id] / sigma[node_id]
					) * (1.0 + dependency[node_id])
					dependency[predecessor_id] += contribution
					edge_scores[edge_id] += contribution
			if node_id != source:
				node_scores[node_id] += dependency[node_id]

	var node_scale := 1.0 / float((node_count - 1) * (node_count - 2)) \
			if node_count > 2 else 0.0
	var edge_scale := 1.0 / float(node_count * (node_count - 1))
	for node_id in node_scores.size():
		node_scores[node_id] = clampf(node_scores[node_id] * node_scale, 0.0, 1.0)
	for edge_id in edge_scores.size():
		edge_scores[edge_id] = clampf(edge_scores[edge_id] * edge_scale, 0.0, 1.0)
	return {"nodes": node_scores, "edges": edge_scores}


static func apply(layer: ArcaneWebLayer) -> void:
	var result := calculate(layer.nodes.size(), layer.edges)
	var node_scores: PackedFloat64Array = result.nodes
	var edge_scores: PackedFloat64Array = result.edges
	for node_id in layer.nodes.size():
		layer.nodes[node_id].structural_importance = node_scores[node_id]
	for edge_id in layer.edges.size():
		layer.edges[edge_id].structural_importance = edge_scores[edge_id]


static func _heap_less(first: Array, second: Array) -> bool:
	return first[0] < second[0] if first[0] != second[0] else first[1] < second[1]


static func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
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
