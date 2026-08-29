class_name WorldCompositionDebugView
extends Node2D

@export var seed: int = 1
@export var world_width: float = 2000.0
@export var world_height: float = 1000.0
@export var target_cell_count: int = 20000
@export_range(0.000001, 1.0) var jitter: float = 0.9
@export_enum("continents", "pangea", "archipelago", "mediterranean", "old_world", "shattered") var template_id := "continents"

var graph: SpatialGraph
var composition: WorldCompositionLayer
var terrain: TerrainHeightLayer
var selected_cell_id := -1
var view_mode := ViewMode.RAW_COMPOSITION
var _spatial_generation_ms := 0
var _composition_generation_ms := 0
var _terrain_projection_ms := 0
var _view_scale := 1.0
var _view_offset := Vector2.ZERO
var _statistics := {}

const _MARGIN := 24.0
const _INFO_WIDTH := 350.0

enum ViewMode {
	RAW_COMPOSITION,
	TERRAIN_HEIGHT,
	LAND_WATER,
}


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_regenerate()


func _on_viewport_size_changed() -> void:
	_update_view_transform()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_V:
				view_mode = ViewMode.RAW_COMPOSITION
			KEY_H:
				view_mode = ViewMode.TERRAIN_HEIGHT
			KEY_L:
				view_mode = ViewMode.LAND_WATER
			KEY_T:
				var template_ids := CompositionTemplates.template_ids()
				var current_index := template_ids.find(template_id)
				template_id = template_ids[(current_index + 1) % template_ids.size()]
				_regenerate_composition()
			KEY_R:
				seed += 1
				_regenerate()
			_:
				return
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_cell_at((event.position - _view_offset) / _view_scale)


func _draw() -> void:
	if graph == null or composition == null or terrain == null:
		draw_string(ThemeDB.fallback_font, Vector2(24.0, 40.0), "World Composition generation failed")
		return
	for cell_id in graph.cell_count():
		var color := _cell_color(cell_id)
		_draw_cell_triangle_fan(cell_id, color)
	if selected_cell_id >= 0:
		draw_polyline(
			_closed_screen_polygon(graph.cell_polygons[selected_cell_id]),
			Color(1.0, 0.72, 0.12),
			3.0,
			true
		)
	_mask_outside_logical_world()
	_draw_information()


func _draw_cell_triangle_fan(cell_id: int, color: Color) -> void:
	var vertex_ids: PackedInt32Array = graph.cell_vertex_ids[cell_id]
	if vertex_ids.size() < 3:
		return
	var center := graph.cell_centers[cell_id]
	var epsilon := SpatialGeometry.epsilon_for_size(
		graph.config.world_width, graph.config.world_height
	)
	for vertex_index in vertex_ids.size():
		var first := graph.vertex_positions[vertex_ids[vertex_index]]
		var second := graph.vertex_positions[
			vertex_ids[(vertex_index + 1) % vertex_ids.size()]
		]
		var triangle_area := absf((first - center).cross(second - center)) * 0.5
		if triangle_area < epsilon:
			continue
		draw_primitive(
			PackedVector2Array([
				_to_screen(center),
				_to_screen(first),
				_to_screen(second),
			]),
			PackedColorArray([color, color, color]),
			PackedVector2Array()
		)


func _mask_outside_logical_world() -> void:
	var viewport_size := get_viewport_rect().size
	var map_rect := Rect2(
		_view_offset, Vector2(graph.config.world_width, graph.config.world_height) * _view_scale
	)
	var background := Color(0.035, 0.04, 0.055)
	draw_rect(Rect2(Vector2.ZERO, Vector2(map_rect.position.x, viewport_size.y)), background)
	draw_rect(
		Rect2(
			Vector2(map_rect.end.x, 0.0),
			Vector2(maxf(0.0, viewport_size.x - map_rect.end.x), viewport_size.y)
		),
		background
	)
	draw_rect(
		Rect2(Vector2(map_rect.position.x, 0.0), Vector2(map_rect.size.x, map_rect.position.y)),
		background
	)
	draw_rect(
		Rect2(
			Vector2(map_rect.position.x, map_rect.end.y),
			Vector2(map_rect.size.x, maxf(0.0, viewport_size.y - map_rect.end.y))
		),
		background
	)
	draw_rect(map_rect, Color(0.72, 0.76, 0.82), false, 2.0)


func _cell_color(cell_id: int) -> Color:
	match view_mode:
		ViewMode.RAW_COMPOSITION:
			var grayscale := float(composition.continental_value[cell_id]) / 100.0
			return Color(grayscale, grayscale, grayscale)
		ViewMode.TERRAIN_HEIGHT:
			return _terrain_height_color(terrain.terrain_height[cell_id])
		_:
			return Color(0.64, 0.55, 0.34) if terrain.is_land(cell_id) else Color(0.08, 0.24, 0.46)


func _terrain_height_color(height: float) -> Color:
	if height < -60.0:
		return Color(0.025, 0.10, 0.30)
	if height < -20.0:
		return Color(0.04, 0.25, 0.58)
	if height < 0.0:
		return Color(0.18, 0.55, 0.82)
	if height < 20.0:
		return Color(0.25, 0.55, 0.22)
	if height < 40.0:
		return Color(0.55, 0.66, 0.24)
	if height < 60.0:
		return Color(0.72, 0.58, 0.27)
	if height < 80.0:
		return Color(0.48, 0.31, 0.18)
	return Color(0.88, 0.90, 0.91)


func _regenerate() -> void:
	selected_cell_id = -1
	var started := Time.get_ticks_msec()
	graph = SpatialGenerator.generate(
		SpatialConfig.new(seed, world_width, world_height, target_cell_count, jitter)
	)
	_spatial_generation_ms = Time.get_ticks_msec() - started
	_regenerate_composition()
	_update_view_transform()


func _regenerate_composition() -> void:
	if graph == null:
		composition = null
		terrain = null
		return
	var started := Time.get_ticks_msec()
	composition = WorldCompositionGenerator.generate(
		graph, WorldCompositionConfig.new(seed, StringName(template_id))
	)
	_composition_generation_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	terrain = null if composition == null else TerrainHeightProjector.project(
		composition.continental_value
	)
	_terrain_projection_ms = Time.get_ticks_msec() - started
	_statistics = WorldCompositionValidator.statistics(composition)
	selected_cell_id = -1
	queue_redraw()


func _draw_information() -> void:
	var viewport_width := get_viewport_rect().size.x
	var panel := Rect2(viewport_width - _INFO_WIDTH, 0.0, _INFO_WIDTH, get_viewport_rect().size.y)
	draw_rect(panel, Color(0.055, 0.065, 0.085, 0.97))
	var mode := _view_mode_name()
	var lines := PackedStringArray([
		"Terrain Height Foundation v1.2 Debug",
		"Template: %s" % CompositionTemplates.display_name(StringName(template_id)),
		"Seed: %d" % seed,
		"World: %d x %d" % [int(world_width), int(world_height)],
		"Cells: %d" % graph.cell_count(),
		"Spatial: %d ms | Composition: %d ms" % [_spatial_generation_ms, _composition_generation_ms],
		"Terrain projection: %d ms" % _terrain_projection_ms,
		"Mode: " + mode,
		"V Raw   H Terrain   L Land/Water",
		"T Template   R Seed+1",
		"Click a Cell to inspect",
		"",
		"Min %d | Max %d | Mean %.2f" % [_statistics.min, _statistics.max, _statistics.mean],
		">= 5: %.2f%%" % (_statistics.coverage_ge_5 * 100.0),
		">=10: %.2f%%" % (_statistics.coverage_ge_10 * 100.0),
		">=20: %.2f%% (composition reference)" % (_statistics.coverage_ge_20 * 100.0),
		">=40: %.2f%%" % (_statistics.coverage_ge_40 * 100.0),
		">=60: %.2f%%" % (_statistics.coverage_ge_60 * 100.0),
	])
	if selected_cell_id >= 0:
		lines.append("")
		lines.append("Cell ID: %d" % selected_cell_id)
		lines.append("Raw Composition Value: %d" % composition.continental_value[selected_cell_id])
		lines.append("Terrain Height: %.2f" % terrain.terrain_height[selected_cell_id])
		lines.append("Land / Water: %s" % ("Land" if terrain.is_land(selected_cell_id) else "Water"))
	var font := ThemeDB.fallback_font
	for line_index in lines.size():
		draw_string(
			font,
			Vector2(panel.position.x + 16.0, 28.0 + line_index * 21.0),
			lines[line_index],
			HORIZONTAL_ALIGNMENT_LEFT,
			_INFO_WIDTH - 32.0,
			14
		)


func _view_mode_name() -> String:
	match view_mode:
		ViewMode.RAW_COMPOSITION:
			return "Raw Composition"
		ViewMode.TERRAIN_HEIGHT:
			return "Terrain Height"
		_:
			return "Land / Water"


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


func _screen_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(polygon.size())
	for index in polygon.size():
		result[index] = _view_offset + polygon[index] * _view_scale
	return result


func _to_screen(world_position: Vector2) -> Vector2:
	return _view_offset + world_position * _view_scale


func _closed_screen_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := _screen_polygon(polygon)
	if not result.is_empty():
		result.append(result[0])
	return result
