class_name ArcaneWebValidator
extends RefCounted


static func validate(layer: ArcaneWebLayer) -> PackedStringArray:
	var errors := PackedStringArray()
	if layer == null:
		errors.append("Arcane Web layer is null")
		return errors
	if not is_finite(layer.world_width) or not is_finite(layer.world_height) \
			or layer.world_width <= 0.0 or layer.world_height <= 0.0:
		errors.append("world extent must be finite and positive")
		return errors
	var epsilon := SpatialGeometry.epsilon_for_size(layer.world_width, layer.world_height)
	var previous_nucleus := Vector2(-INF, -INF)
	for domain_id in layer.domains.size():
		var domain := layer.domains[domain_id]
		if domain == null:
			errors.append("domain %d is null" % domain_id)
			continue
		if domain.id != domain_id:
			errors.append("domain IDs must be stable and continuous")
		if not _vector_is_finite(domain.nucleus_position) or not is_finite(domain.power_weight):
			errors.append("domain %d nucleus/weight must be finite" % domain_id)
		if domain.power_weight < 0.0:
			errors.append("domain %d power_weight must be non-negative" % domain_id)
		if domain_id > 0 and _position_less(domain.nucleus_position, previous_nucleus):
			errors.append("domains must follow nucleus x/y ordering")
		previous_nucleus = domain.nucleus_position
		if domain.polygon.size() < 3:
			errors.append("domain %d polygon must contain at least three vertices" % domain_id)
			continue
		var area := SpatialGeometry.polygon_area(domain.polygon)
		if not is_finite(area) or area <= epsilon:
			errors.append("domain %d polygon area must be finite and positive" % domain_id)
		for point in domain.polygon:
			if not _vector_is_finite(point):
				errors.append("domain %d polygon contains NaN/Inf" % domain_id)
			elif not SpatialGeometry.point_in_world(
				point, layer.world_width, layer.world_height, epsilon
			):
				errors.append("domain %d polygon leaves the World Extent" % domain_id)

	var previous_position := Vector2(-INF, -INF)
	for node_id in layer.nodes.size():
		var node := layer.nodes[node_id]
		if node == null:
			errors.append("node %d is null" % node_id)
			continue
		if node.id != node_id:
			errors.append("node IDs must be stable and continuous")
		if not _vector_is_finite(node.world_position):
			errors.append("node %d world_position contains NaN/Inf" % node_id)
		elif not SpatialGeometry.point_in_world(
			node.world_position, layer.world_width, layer.world_height, epsilon
		):
			errors.append("node %d leaves the World Extent" % node_id)
		if node_id > 0 and _position_less(node.world_position, previous_position):
			errors.append("nodes must follow world_position x/y ordering")
		previous_position = node.world_position
		if node.kind != ArcaneWebNode.Kind.JUNCTION \
				and node.kind != ArcaneWebNode.Kind.BOUNDARY_EXIT:
			errors.append("node %d has an invalid kind" % node_id)
		var on_boundary := _is_on_boundary(
			node.world_position, layer.world_width, layer.world_height, epsilon
		)
		if node.kind == ArcaneWebNode.Kind.BOUNDARY_EXIT and not on_boundary:
			errors.append("Boundary Exit %d must lie on the World Extent boundary" % node_id)
		if node.kind == ArcaneWebNode.Kind.JUNCTION and on_boundary:
			errors.append("a boundary-clipped node must be a Boundary Exit")
		if not _importance_is_valid(node.structural_importance):
			errors.append("node %d structural_importance must be inside [0, 1]" % node_id)

	var edge_pairs := {}
	var degree := PackedInt32Array()
	degree.resize(layer.nodes.size())
	for edge_id in layer.edges.size():
		var edge := layer.edges[edge_id]
		if edge == null:
			errors.append("edge %d is null" % edge_id)
			continue
		if edge.id != edge_id:
			errors.append("edge IDs must be stable and continuous")
		if edge.node_a_id < 0 or edge.node_b_id >= layer.nodes.size():
			errors.append("edge %d endpoint ID is out of range" % edge_id)
			continue
		if edge.node_a_id >= edge.node_b_id:
			errors.append("edge %d must satisfy node_a_id < node_b_id" % edge_id)
			continue
		var pair := Vector2i(edge.node_a_id, edge.node_b_id)
		if edge_pairs.has(pair):
			errors.append("edge %d duplicates endpoint pair %s" % [edge_id, pair])
		edge_pairs[pair] = true
		if edge_id > 0:
			var previous := layer.edges[edge_id - 1]
			if previous != null and (
				edge.node_a_id < previous.node_a_id or (
					edge.node_a_id == previous.node_a_id and edge.node_b_id < previous.node_b_id
				)
			):
				errors.append("edges must follow node_a_id/node_b_id ordering")
		if not is_finite(edge.length) or edge.length <= epsilon:
			errors.append("edge %d length must be finite and positive" % edge_id)
		else:
			var first := layer.nodes[edge.node_a_id].world_position
			var second := layer.nodes[edge.node_b_id].world_position
			if absf(first.distance_to(second) - edge.length) > epsilon:
				errors.append("edge %d length does not match its straight segment" % edge_id)
			if _segment_lies_on_world_boundary(
				first, second, layer.world_width, layer.world_height, epsilon
			):
				errors.append("edge %d incorrectly follows the World Rectangle" % edge_id)
		degree[edge.node_a_id] += 1
		degree[edge.node_b_id] += 1
		if not _importance_is_valid(edge.structural_importance):
			errors.append("edge %d structural_importance must be inside [0, 1]" % edge_id)

	for node_id in layer.nodes.size():
		var node := layer.nodes[node_id]
		if node == null:
			continue
		if degree[node_id] == 0:
			errors.append("node %d must be incident to a Ley Edge" % node_id)
		elif degree[node_id] == 1 and node.kind != ArcaneWebNode.Kind.BOUNDARY_EXIT:
			errors.append("degree-1 node %d must be a legal Boundary Exit" % node_id)
		elif node.kind == ArcaneWebNode.Kind.JUNCTION and degree[node_id] < 3:
			errors.append("internal Junction %d must have degree at least 3" % node_id)
	return errors


static func statistics(layer: ArcaneWebLayer) -> Dictionary:
	if layer == null:
		return {}
	var degree := PackedInt32Array()
	degree.resize(layer.nodes.size())
	var total_length := 0.0
	var edge_lengths := PackedFloat64Array()
	var edge_importance := PackedFloat64Array()
	var node_importance := PackedFloat64Array()
	for edge in layer.edges:
		degree[edge.node_a_id] += 1
		degree[edge.node_b_id] += 1
		total_length += edge.length
		edge_lengths.append(edge.length)
		edge_importance.append(edge.structural_importance)
	for node in layer.nodes:
		node_importance.append(node.structural_importance)
	var junction_count := 0
	var boundary_exit_count := 0
	var degree_1 := 0
	var degree_2 := 0
	var degree_3 := 0
	var degree_4_plus := 0
	var max_degree := 0
	for node_id in layer.nodes.size():
		if layer.nodes[node_id].kind == ArcaneWebNode.Kind.BOUNDARY_EXIT:
			boundary_exit_count += 1
		else:
			junction_count += 1
		max_degree = maxi(max_degree, degree[node_id])
		match degree[node_id]:
			1:
				degree_1 += 1
			2:
				degree_2 += 1
			3:
				degree_3 += 1
			_:
				if degree[node_id] >= 4:
					degree_4_plus += 1
	var components := _connected_component_count(layer)
	return {
		"generated_nucleus_count": layer.generated_nucleus_count,
		"visible_domain_count": layer.domains.size(),
		"node_count": layer.nodes.size(),
		"edge_count": layer.edges.size(),
		"junction_count": junction_count,
		"boundary_exit_count": boundary_exit_count,
		"connected_component_count": components,
		"cycle_rank": layer.edges.size() - layer.nodes.size() + components,
		"average_degree": 2.0 * float(layer.edges.size()) / float(layer.nodes.size()) \
				if not layer.nodes.is_empty() else 0.0,
		"max_degree": max_degree,
		"degree_1": degree_1,
		"degree_2": degree_2,
		"degree_3": degree_3,
		"degree_4_plus": degree_4_plus,
		"total_ley_length": total_length,
		"edge_length": _range_statistics(edge_lengths),
		"edge_importance": _range_statistics(edge_importance),
		"node_importance": _range_statistics(node_importance),
		"generation_time_ms": layer.generation_time_ms,
		"power_diagram_time_ms": layer.power_diagram_time_ms,
		"importance_time_ms": layer.importance_time_ms,
		"total_time_ms": layer.total_generation_time_ms,
	}


static func _connected_component_count(layer: ArcaneWebLayer) -> int:
	if layer.nodes.is_empty():
		return 0
	var visited := PackedByteArray()
	visited.resize(layer.nodes.size())
	var components := 0
	for start in layer.nodes.size():
		if visited[start] != 0:
			continue
		components += 1
		var pending := PackedInt32Array([start])
		visited[start] = 1
		while not pending.is_empty():
			var node_id := pending[pending.size() - 1]
			pending.resize(pending.size() - 1)
			for edge_id in layer.incident_edge_ids(node_id):
				var edge := layer.edges[edge_id]
				var neighbor := edge.node_b_id if edge.node_a_id == node_id else edge.node_a_id
				if visited[neighbor] == 0:
					visited[neighbor] = 1
					pending.append(neighbor)
	return components


static func _range_statistics(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty():
		return {"min": 0.0, "mean": 0.0, "max": 0.0}
	var minimum := INF
	var maximum := -INF
	var sum := 0.0
	for value in values:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
		sum += value
	return {"min": minimum, "mean": sum / values.size(), "max": maximum}


static func _vector_is_finite(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


static func _importance_is_valid(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0


static func _position_less(first: Vector2, second: Vector2) -> bool:
	return first.x < second.x if first.x != second.x else first.y < second.y


static func _is_on_boundary(
		position: Vector2, width: float, height: float, epsilon: float
) -> bool:
	return absf(position.x) <= epsilon or absf(position.x - width) <= epsilon \
			or absf(position.y) <= epsilon or absf(position.y - height) <= epsilon


static func _segment_lies_on_world_boundary(
		first: Vector2, second: Vector2, width: float, height: float, epsilon: float
) -> bool:
	return (absf(first.x) <= epsilon and absf(second.x) <= epsilon) \
			or (absf(first.x - width) <= epsilon and absf(second.x - width) <= epsilon) \
			or (absf(first.y) <= epsilon and absf(second.y) <= epsilon) \
			or (absf(first.y - height) <= epsilon and absf(second.y - height) <= epsilon)
