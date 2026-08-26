class_name SpatialGraph
extends RefCounted

## Pure spatial data. A cell is its stable index in each cell_* array.

var config: SpatialConfig
var columns: int = 0
var rows: int = 0

var cell_centers := PackedVector2Array()
var cell_polygons: Array = [] # PackedVector2Array per cell
var cell_neighbors: Array = [] # PackedInt32Array per cell
var cell_neighbor_distances: Array = [] # PackedFloat64Array per cell
var cell_vertex_ids: Array = [] # PackedInt32Array per cell
var cell_areas := PackedFloat64Array()
var cell_is_border := PackedByteArray()

var vertex_positions := PackedVector2Array()
var vertex_cells: Array = [] # PackedInt32Array per vertex

# Canonical undirected edge (min vertex id, max vertex id) and its one or two cells.
var edge_vertex_ids: Array = [] # Vector2i per edge
var edge_cells: Array = [] # PackedInt32Array per edge

# Retained as compact debug data; neighbor relationships still remain authoritative.
var delaunay_triangles := PackedInt32Array()


func cell_count() -> int:
	return cell_centers.size()


func edge_count() -> int:
	return edge_vertex_ids.size()
