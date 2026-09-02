class_name ArcaneCirculationValidator
extends RefCounted

const FLOW_VALUE_EPSILON := 0.00001
const JUNCTION_CONSERVATION_EPSILON := 0.00001
const NON_ZERO_FLOW_EPSILON := 0.000001


static func validate(
		arcane_web: ArcaneWebLayer,
		circulation: ArcaneCirculationLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if arcane_web == null or circulation == null:
		errors.append("Arcane Circulation validation requires Web and Circulation layers")
		return errors
	if circulation.edge_flow.size() != arcane_web.edges.size():
		errors.append("edge_flow must be index-aligned with ArcaneWebLayer.edges")
		return errors
	for edge in arcane_web.edges:
		var flow := circulation.edge_flow[edge.id]
		if not is_finite(flow):
			errors.append("edge_flow[%d] must be finite" % edge.id)
			continue
		var expected := ArcaneCirculationGenerator.expected_flow_for_edge(
			arcane_web, edge
		)
		if not bool(expected.get("valid", false)):
			errors.append("Edge %d must resolve exactly two left/right Domains" % edge.id)
		elif absf(flow - float(expected.flow)) > FLOW_VALUE_EPSILON:
			errors.append(
				"edge_flow[%d] does not match left minus right for node_a -> node_b" % edge.id
			)
	for node in arcane_web.nodes:
		if node.kind != ArcaneWebNode.Kind.JUNCTION:
			continue
		var error := absf(node_net_flow(arcane_web, circulation, node.id))
		if error > JUNCTION_CONSERVATION_EPSILON:
			errors.append(
				"Junction %d conservation error %.9f exceeds %.9f"
				% [node.id, error, JUNCTION_CONSERVATION_EPSILON]
			)
	return errors


static func node_net_flow(
		arcane_web: ArcaneWebLayer,
		circulation: ArcaneCirculationLayer,
		node_id: int
) -> float:
	var net_flow := 0.0
	for edge_id in arcane_web.incident_edge_ids(node_id):
		var edge := arcane_web.edges[edge_id]
		var flow := circulation.edge_flow[edge_id]
		net_flow += flow if edge.node_b_id == node_id else -flow
	return net_flow


static func statistics(
		arcane_web: ArcaneWebLayer, circulation: ArcaneCirculationLayer
) -> Dictionary:
	if arcane_web == null or circulation == null \
			or circulation.edge_flow.size() != arcane_web.edges.size():
		return {}
	var absolute_minimum := INF
	var absolute_maximum := 0.0
	var absolute_sum := 0.0
	var signed_minimum := INF
	var signed_maximum := -INF
	var non_zero_edges := 0
	for flow in circulation.edge_flow:
		var magnitude := absf(flow)
		absolute_minimum = minf(absolute_minimum, magnitude)
		absolute_maximum = maxf(absolute_maximum, magnitude)
		absolute_sum += magnitude
		signed_minimum = minf(signed_minimum, flow)
		signed_maximum = maxf(signed_maximum, flow)
		if magnitude > NON_ZERO_FLOW_EPSILON:
			non_zero_edges += 1
	var junction_error_sum := 0.0
	var junction_error_max := 0.0
	var junction_count := 0
	var boundary_inflow := 0.0
	var boundary_outflow := 0.0
	for node in arcane_web.nodes:
		var net_flow := node_net_flow(arcane_web, circulation, node.id)
		if node.kind == ArcaneWebNode.Kind.JUNCTION:
			var error := absf(net_flow)
			junction_error_sum += error
			junction_error_max = maxf(junction_error_max, error)
			junction_count += 1
		elif net_flow < 0.0:
			boundary_inflow += -net_flow
		else:
			boundary_outflow += net_flow
	var edge_count := circulation.edge_flow.size()
	if edge_count == 0:
		absolute_minimum = 0.0
		signed_minimum = 0.0
		signed_maximum = 0.0
	return {
		"edge_count": edge_count,
		"non_zero_flow_edges": non_zero_edges,
		"absolute_flow_min": absolute_minimum,
		"absolute_flow_mean": absolute_sum / float(edge_count) if edge_count > 0 else 0.0,
		"absolute_flow_max": absolute_maximum,
		"signed_flow_min": signed_minimum,
		"signed_flow_max": signed_maximum,
		"junction_conservation_error_mean": junction_error_sum / float(junction_count)
				if junction_count > 0 else 0.0,
		"junction_conservation_error_max": junction_error_max,
		"boundary_inflow": boundary_inflow,
		"boundary_outflow": boundary_outflow,
	}
