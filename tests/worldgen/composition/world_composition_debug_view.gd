class_name WorldCompositionDebugView
extends Node2D

@export var seed: int = 1
@export var world_width: float = 1000.0
@export var world_height: float = 1000.0
@export var target_cell_count: int = 10000
@export_range(0.0, 1.0) var jitter: float = 0.9
@export_enum("continents", "pangea") var template_id := "continents"

var graph: SpatialGraph
var composition: WorldCompositionLayer
var selected_cell_id := -1
var show_continuous_value := true
var _spatial_generation_ms := 0
var _composition_generation_ms := 0
var _view_scale := 1.0
var _view_offset := Vector2.ZERO
var _statistics := {}

const _MARGIN := 24.0
const _INFO_WIDTH := 350.0


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
				show_continuous_value = true
			KEY_L:
				show_continuous_value = false
			KEY_T:
				template_id = "pangea" if template_id == "continents" else "continents"
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
	if graph == null or composition == null:
		draw_string(ThemeDB.fallback_font, Vector2(24.0, 40.0), "World Composition generation failed")
		return
	for cell_id in graph.cell_count():
		var color := _value_color(composition.continental_value[cell_id])
		draw_colored_polygon(_screen_polygon(graph.cell_polygons[cell_id]), color)
	if selected_cell_id >= 0:
		draw_polyline(
			_closed_screen_polygon(graph.cell_polygons[selected_cell_id]),
			Color(1.0, 0.72, 0.12),
			3.0,
			true
		)
	_draw_information()


func _value_color(value: int) -> Color:
	if show_continuous_value:
		var grayscale := float(value) / 100.0
		return Color(grayscale, grayscale, grayscale)
	return Color(0.64, 0.55, 0.34) if value >= CompositionOperations.COMPOSITION_LAND_REFERENCE else Color(0.08, 0.24, 0.46)


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
		return
	var started := Time.get_ticks_msec()
	composition = WorldCompositionGenerator.generate(
		graph, WorldCompositionConfig.new(seed, StringName(template_id))
	)
	_composition_generation_ms = Time.get_ticks_msec() - started
	_statistics = WorldCompositionValidator.statistics(composition)
	selected_cell_id = -1
	queue_redraw()


func _draw_information() -> void:
	var viewport_width := get_viewport_rect().size.x
	var panel := Rect2(viewport_width - _INFO_WIDTH, 0.0, _INFO_WIDTH, get_viewport_rect().size.y)
	draw_rect(panel, Color(0.055, 0.065, 0.085, 0.97))
	var mode := "V: continuous grayscale" if show_continuous_value else "L: >=20 reference outline"
	var lines := PackedStringArray([
		"World Composition v1.1 Debug",
		"Template: %s | Seed: %d" % [template_id, seed],
		"Cells: %d" % graph.cell_count(),
		"Spatial: %d ms | Composition: %d ms" % [_spatial_generation_ms, _composition_generation_ms],
		"Mode: " + mode,
		"V Value   L Reference   T Template   R Seed+1",
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
		lines.append("continental_value: %d" % composition.continental_value[selected_cell_id])
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


func _closed_screen_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := _screen_polygon(polygon)
	if not result.is_empty():
		result.append(result[0])
	return result
