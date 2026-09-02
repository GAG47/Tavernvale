class_name ArcaneWebLayer
extends RefCounted

## Stable world-space geometry for the cyclic Arcane Web skeleton. This layer
## does not assign Leyline strength, Nexus strength, mana flow, or circulation.

var domains: Array[ArcaneWebDomain] = []
var nodes: Array[ArcaneWebNode] = []
var edges: Array[ArcaneWebEdge] = []

var world_seed: int = 0
var world_width: float = 0.0
var world_height: float = 0.0
var settings: ArcaneWebSettings
var generated_nucleus_count: int = 0
var generation_time_ms: float = 0.0
var power_diagram_time_ms: float = 0.0
var total_generation_time_ms: float = 0.0

var _incident_edges: Array[PackedInt32Array] = []


func rebuild_incidence() -> void:
	_incident_edges.clear()
	_incident_edges.resize(nodes.size())
	for node_id in nodes.size():
		_incident_edges[node_id] = PackedInt32Array()
	for edge in edges:
		if edge.node_a_id >= 0 and edge.node_a_id < nodes.size():
			_incident_edges[edge.node_a_id].append(edge.id)
		if edge.node_b_id >= 0 and edge.node_b_id < nodes.size():
			_incident_edges[edge.node_b_id].append(edge.id)


func incident_edge_ids(node_id: int) -> PackedInt32Array:
	if node_id < 0 or node_id >= _incident_edges.size():
		return PackedInt32Array()
	return _incident_edges[node_id].duplicate()
