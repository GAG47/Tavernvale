class_name SpatialDebugView
extends Node2D

@export var seed: int = 1
@export var world_width: float = 1400.0
@export var world_height: float = 700.0
@export var target_cell_count: int = 10000
@export_range(0.0, 1.0) var jitter: float = 0.9

var graph: SpatialGraph
var selected_cell_id := -1
var show_voronoi := true
var show_delaunay := false
var show_seeds := false
var show_ids := false
var show_border_cells := true
var _generation_ms := 0
var _view_scale := 1.0
var _view_offset := Vector2.ZERO

const _MARGIN := 24.0
const _INFO_WIDTH := 330.0


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	var started := Time.get_ticks_msec()
	graph = SpatialGenerator.generate(
		SpatialConfig.new(seed, world_width, world_height, target_cell_count, jitter)
	)
	_generation_ms = Time.get_ticks_msec() - started
	_update_view_transform()
	queue_redraw()


func _on_viewport_size_changed() -> void:
	_update_view_transform()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_V:
				show_voronoi = not show_voronoi
			KEY_D:
				show_delaunay = not show_delaunay
			KEY_S:
				show_seeds = not show_seeds
			KEY_I:
				show_ids = not show_ids
			KEY_B:
				show_border_cells = not show_border_cells
			_:
				return
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_cell_at((event.position - _view_offset) / _view_scale)


func _draw() -> void:
	if graph == null:
		draw_string(ThemeDB.fallback_font, Vector2(24.0, 40.0), "SpatialGraph generation failed")
		return
	_draw_selection_fill()
	if show_voronoi:
		_draw_voronoi_edges()
	if show_border_cells:
		_draw_border_cells()
	if show_delaunay:
		_draw_delaunay_edges()
	if show_seeds:
		_draw_seed_points()
	if show_ids:
		_draw_cell_ids()
	_draw_selected_shared_edges()
	_draw_information()


func _draw_selection_fill() -> void:
	if selected_cell_id < 0:
		return
	for neighbor_id in graph.cell_neighbors[selected_cell_id]:
		draw_colored_polygon(_screen_polygon(graph.cell_polygons[neighbor_id]), Color(0.18, 0.45, 0.75, 0.35))
	draw_colored_polygon(
		_screen_polygon(graph.cell_polygons[selected_cell_id]), Color(1.0, 0.72, 0.15, 0.65)
	)


func _draw_voronoi_edges() -> void:
	for polygon in graph.cell_polygons:
		draw_polyline(_closed_screen_polygon(polygon), Color(0.72, 0.76, 0.82), 1.0)


func _draw_border_cells() -> void:
	for cell_id in graph.cell_count():
		if graph.cell_is_border[cell_id]:
			draw_polyline(
				_closed_screen_polygon(graph.cell_polygons[cell_id]), Color(1.0, 0.35, 0.2), 2.0
			)


func _draw_delaunay_edges() -> void:
	var drawn_edges := {}
	for triangle_start in range(0, graph.delaunay_triangles.size(), 3):
		var first := graph.delaunay_triangles[triangle_start]
		var second := graph.delaunay_triangles[triangle_start + 1]
		var third := graph.delaunay_triangles[triangle_start + 2]
		_draw_delaunay_edge(first, second, drawn_edges)
		_draw_delaunay_edge(second, third, drawn_edges)
		_draw_delaunay_edge(third, first, drawn_edges)


func _draw_delaunay_edge(first_cell: int, second_cell: int, drawn_edges: Dictionary) -> void:
	var edge := SpatialGeometry.canonical_edge(first_cell, second_cell)
	if drawn_edges.has(edge):
		return
	drawn_edges[edge] = true
	draw_line(
		_to_screen(graph.cell_centers[first_cell]),
		_to_screen(graph.cell_centers[second_cell]),
		Color(0.35, 0.8, 0.95, 0.45),
		1.0
	)


func _draw_selected_shared_edges() -> void:
	if selected_cell_id < 0:
		return
	for edge_id in graph.edge_count():
		var cells: PackedInt32Array = graph.edge_cells[edge_id]
		if cells.size() != 2 or not cells.has(selected_cell_id):
			continue
		var edge: Vector2i = graph.edge_vertex_ids[edge_id]
		draw_line(
			_to_screen(graph.vertex_positions[edge.x]),
			_to_screen(graph.vertex_positions[edge.y]),
			Color(0.2, 1.0, 0.45),
			4.0,
			true
		)


func _draw_seed_points() -> void:
	for center in graph.cell_centers:
		draw_circle(_to_screen(center), 2.2, Color(0.95, 0.25, 0.3))


func _draw_cell_ids() -> void:
	var font := ThemeDB.fallback_font
	for cell_id in graph.cell_count():
		draw_string(font, _to_screen(graph.cell_centers[cell_id]) + Vector2(3.0, -3.0), str(cell_id), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10)


func _draw_information() -> void:
	var viewport_width := get_viewport_rect().size.x
	var panel := Rect2(viewport_width - _INFO_WIDTH, 0.0, _INFO_WIDTH, get_viewport_rect().size.y)
	draw_rect(panel, Color(0.055, 0.065, 0.085, 0.96))
	var lines := PackedStringArray([
		"Spatial Skeleton Debug",
		"Cells: %d | Vertices: %d" % [graph.cell_count(), graph.vertex_positions.size()],
		"Generated: %d ms" % _generation_ms,
		"V Voronoi [%s]   D Delaunay [%s]" % [_on_off(show_voronoi), _on_off(show_delaunay)],
		"S Seeds [%s]      I IDs [%s]" % [_on_off(show_seeds), _on_off(show_ids)],
		"B Border [%s]     Click to inspect" % _on_off(show_border_cells),
	])
	if selected_cell_id >= 0:
		lines.append("")
		lines.append("Selected Cell #%d" % selected_cell_id)
		lines.append("Center: (%.3f, %.3f)" % [graph.cell_centers[selected_cell_id].x, graph.cell_centers[selected_cell_id].y])
		lines.append("Area: %.5f" % graph.cell_areas[selected_cell_id])
		lines.append("Neighbor Count: %d" % graph.cell_neighbors[selected_cell_id].size())
		lines.append("Neighbors: %s" % str(graph.cell_neighbors[selected_cell_id]))
		lines.append("Shared Edges: %d" % _selected_shared_edge_count())
		lines.append("is_border: %s" % str(bool(graph.cell_is_border[selected_cell_id])))
	var font := ThemeDB.fallback_font
	for line_index in lines.size():
		draw_string(font, Vector2(panel.position.x + 16.0, 28.0 + line_index * 21.0), lines[line_index], HORIZONTAL_ALIGNMENT_LEFT, _INFO_WIDTH - 32.0, 14)


func _select_cell_at(world_position: Vector2) -> void:
	if graph == null or not SpatialGeometry.point_in_world(
		world_position, graph.config.world_width, graph.config.world_height, 0.0
	):
		selected_cell_id = -1
		queue_redraw()
		return
	var epsilon := SpatialGeometry.epsilon_for_size(
		graph.config.world_width, graph.config.world_height
	)
	selected_cell_id = -1
	for cell_id in graph.cell_count():
		if SpatialGeometry.point_in_polygon(world_position, graph.cell_polygons[cell_id], epsilon):
			selected_cell_id = cell_id
			break
	queue_redraw()


func _update_view_transform() -> void:
	var available := get_viewport_rect().size - Vector2(_INFO_WIDTH + _MARGIN * 2.0, _MARGIN * 2.0)
	if available.x <= 0.0 or available.y <= 0.0 or world_width <= 0.0 or world_height <= 0.0:
		return
	_view_scale = minf(available.x / world_width, available.y / world_height)
	var map_size := Vector2(world_width, world_height) * _view_scale
	_view_offset = Vector2(
		_MARGIN + (available.x - map_size.x) * 0.5,
		_MARGIN + (available.y - map_size.y) * 0.5
	)


func _to_screen(world_position: Vector2) -> Vector2:
	return _view_offset + world_position * _view_scale


func _screen_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(polygon.size())
	for index in polygon.size():
		result[index] = _to_screen(polygon[index])
	return result


func _closed_screen_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := _screen_polygon(polygon)
	if not result.is_empty():
		result.append(result[0])
	return result


func _on_off(value: bool) -> String:
	return "ON" if value else "OFF"


func _selected_shared_edge_count() -> int:
	var count := 0
	for edge_cells in graph.edge_cells:
		if edge_cells.size() == 2 and edge_cells.has(selected_cell_id):
			count += 1
	return count
