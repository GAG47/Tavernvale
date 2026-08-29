class_name WorldCompositionDebugView
extends Node2D

@export var seed: int = 1
@export var world_width: float = 2000.0
@export var world_height: float = 1000.0
@export var target_cell_count: int = 20000
@export_range(0.000001, 1.0) var jitter: float = 0.9
@export_enum("continents", "pangea", "archipelago", "mediterranean", "old_world", "shattered") var template_id := "continents"
@export_range(-90.0, 90.0) var latitude_north: float = 70.0
@export_range(-90.0, 90.0) var latitude_south: float = -20.0

var graph: SpatialGraph
var composition: WorldCompositionLayer
var terrain: TerrainHeightLayer
var hydrology: HydrologyConditioningResult
var climate: WorldClimateLayer
var climate_settings: WorldClimateSettings
var selected_cell_id := -1
var view_mode := ViewMode.RAW_COMPOSITION
var _spatial_generation_ms := 0
var _composition_generation_ms := 0
var _terrain_projection_ms := 0
var _hydrology_conditioning_ms := 0
var _climate_generation_ms := 0
var _view_scale := 1.0
var _view_offset := Vector2.ZERO
var _statistics := {}
var _terrain_statistics := {}
var _climate_statistics := {}

const _MARGIN := 24.0
const _INFO_WIDTH := 350.0

enum ViewMode {
	RAW_COMPOSITION,
	TERRAIN_HEIGHT,
	LAND_WATER,
	TEMPERATURE,
	PRECIPITATION,
	HYDROLOGY_CONDITIONING,
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
			KEY_C:
				view_mode = ViewMode.TEMPERATURE
			KEY_P:
				view_mode = ViewMode.PRECIPITATION
			KEY_D:
				view_mode = ViewMode.HYDROLOGY_CONDITIONING
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
	if graph == null or composition == null or terrain == null or hydrology == null or climate == null:
		draw_string(ThemeDB.fallback_font, Vector2(24.0, 40.0), "World generation failed")
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
		ViewMode.LAND_WATER:
			return Color(0.64, 0.55, 0.34) if terrain.is_land(cell_id) else Color(0.08, 0.24, 0.46)
		ViewMode.TEMPERATURE:
			return _temperature_color(climate.temperature[cell_id])
		ViewMode.PRECIPITATION:
			return _precipitation_color(climate.precipitation[cell_id])
		_:
			return _hydrology_action_color(cell_id)


func _hydrology_action_color(cell_id: int) -> Color:
	if hydrology.closed_basin_id[cell_id] >= 0:
		return Color(0.62, 0.22, 0.78)
	match hydrology.conditioning_action[cell_id]:
		HydrologyConditioningResult.Action.FILL:
			return Color(0.96, 0.72, 0.12)
		HydrologyConditioningResult.Action.CARVE:
			return Color(0.94, 0.22, 0.36)
		_:
			return Color(0.18, 0.22, 0.25) if terrain.is_land(cell_id) else Color(0.06, 0.14, 0.22)


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


func _temperature_color(temperature: float) -> Color:
	if temperature < -20.0:
		return Color(0.08, 0.18, 0.65)
	if temperature < 0.0:
		return Color(0.08, 0.18, 0.65).lerp(Color(0.10, 0.78, 0.88), (temperature + 20.0) / 20.0)
	if temperature < 15.0:
		return Color(0.10, 0.78, 0.88).lerp(Color(0.30, 0.68, 0.24), temperature / 15.0)
	if temperature < 25.0:
		return Color(0.30, 0.68, 0.24).lerp(Color(0.95, 0.78, 0.16), (temperature - 15.0) / 10.0)
	if temperature < 35.0:
		return Color(0.95, 0.78, 0.16).lerp(Color(0.88, 0.16, 0.08), (temperature - 25.0) / 10.0)
	return Color(0.66, 0.03, 0.04)


func _precipitation_color(precipitation: float) -> Color:
	var maximum := float(_climate_statistics.get("max_precipitation", 0.0))
	var normalized := sqrt(clampf(precipitation / maximum, 0.0, 1.0)) if maximum > 0.0 else 0.0
	if normalized < 0.25:
		return Color(0.72, 0.50, 0.20).lerp(Color(0.55, 0.68, 0.25), normalized / 0.25)
	if normalized < 0.55:
		return Color(0.55, 0.68, 0.25).lerp(Color(0.10, 0.68, 0.58), (normalized - 0.25) / 0.30)
	if normalized < 0.8:
		return Color(0.10, 0.68, 0.58).lerp(Color(0.08, 0.48, 0.82), (normalized - 0.55) / 0.25)
	return Color(0.08, 0.48, 0.82).lerp(Color(0.03, 0.14, 0.48), (normalized - 0.8) / 0.2)


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
		hydrology = null
		climate = null
		return
	var started := Time.get_ticks_msec()
	composition = WorldCompositionGenerator.generate(
		graph, WorldCompositionConfig.new(seed, StringName(template_id))
	)
	_composition_generation_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	var projected_terrain: TerrainHeightLayer = null if composition == null else TerrainHeightProjector.project(
		composition.continental_value
	)
	_terrain_projection_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	climate_settings = WorldClimateSettings.new(latitude_north, latitude_south)
	climate = null if projected_terrain == null else WorldClimateGenerator.generate(
		graph, projected_terrain, climate_settings
	)
	_climate_generation_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	hydrology = null if projected_terrain == null else HydrologyConditioner.condition(
		graph, projected_terrain
	)
	terrain = null
	if hydrology != null:
		terrain = TerrainHeightLayer.new()
		terrain.terrain_height = hydrology.terrain_height.duplicate()
	_hydrology_conditioning_ms = Time.get_ticks_msec() - started
	_statistics = WorldCompositionValidator.statistics(composition)
	_terrain_statistics = _calculate_terrain_statistics()
	_climate_statistics = _calculate_climate_statistics()
	selected_cell_id = -1
	queue_redraw()


func _draw_information() -> void:
	var viewport_width := get_viewport_rect().size.x
	var panel := Rect2(viewport_width - _INFO_WIDTH, 0.0, _INFO_WIDTH, get_viewport_rect().size.y)
	draw_rect(panel, Color(0.055, 0.065, 0.085, 0.97))
	var mode := _view_mode_name()
	var lines := PackedStringArray([
		"Hydrology Conditioning v1.4 Debug",
		"Template: %s" % CompositionTemplates.display_name(StringName(template_id)),
		"Seed: %d" % seed,
		"World: %d x %d" % [int(world_width), int(world_height)],
		"Cells: %d" % graph.cell_count(),
		"Spatial: %d ms | Composition: %d ms" % [_spatial_generation_ms, _composition_generation_ms],
		"Terrain projection: %d ms" % _terrain_projection_ms,
		"Climate: %d ms" % _climate_generation_ms,
		"Hydrology: %d ms" % _hydrology_conditioning_ms,
		"Mode: " + mode,
		"V Raw   H Terrain   L Land/Water",
		"C Temperature   P Precipitation",
		"D Hydrology Conditioning",
		"T Template   R Seed+1",
		"Click a Cell to inspect",
		"",
	])
	_append_mode_statistics(lines)
	if selected_cell_id >= 0:
		lines.append("")
		lines.append("Cell ID: %d" % selected_cell_id)
		if view_mode == ViewMode.HYDROLOGY_CONDITIONING:
			lines.append("Original Height: %.3f" % hydrology.original_height[selected_cell_id])
			lines.append("Conditioned Height: %.3f" % hydrology.terrain_height[selected_cell_id])
			lines.append("Height Delta: %+.3f" % hydrology.height_delta[selected_cell_id])
			lines.append("Action: %s" % hydrology.action_name(selected_cell_id))
			lines.append("Closed Basin ID: %d" % hydrology.closed_basin_id[selected_cell_id])
		else:
			lines.append("Terrain Height: %.2f" % terrain.terrain_height[selected_cell_id])
		lines.append("Latitude: %.2f" % WorldClimateGenerator.latitude_at(
			selected_cell_id, graph, climate_settings
		))
		lines.append("Temperature: %.2f °C" % climate.temperature[selected_cell_id])
		lines.append("Precipitation: %.2f" % climate.precipitation[selected_cell_id])
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


func _append_mode_statistics(lines: PackedStringArray) -> void:
	match view_mode:
		ViewMode.RAW_COMPOSITION:
			lines.append(
				"Min %d | Max %d | Mean %.2f"
				% [_statistics.min, _statistics.max, _statistics.mean]
			)
			lines.append(">= 5: %.2f%%" % (_statistics.coverage_ge_5 * 100.0))
			lines.append(">=10: %.2f%%" % (_statistics.coverage_ge_10 * 100.0))
			lines.append(">=20: %.2f%% (composition reference)" % (_statistics.coverage_ge_20 * 100.0))
			lines.append(">=40: %.2f%%" % (_statistics.coverage_ge_40 * 100.0))
			lines.append(">=60: %.2f%%" % (_statistics.coverage_ge_60 * 100.0))
		ViewMode.TERRAIN_HEIGHT:
			lines.append("Min Height: %.2f" % _terrain_statistics.min_height)
			lines.append("Max Height: %.2f" % _terrain_statistics.max_height)
			lines.append("Mean Height: %.2f" % _terrain_statistics.mean_height)
			_append_land_water_statistics(lines)
		ViewMode.LAND_WATER:
			_append_land_water_statistics(lines)
		ViewMode.TEMPERATURE:
			lines.append("Min Temperature: %.2f °C" % _climate_statistics.min_temperature)
			lines.append("Max Temperature: %.2f °C" % _climate_statistics.max_temperature)
			lines.append("Mean Temperature: %.2f °C" % _climate_statistics.mean_temperature)
		ViewMode.PRECIPITATION:
			lines.append("Min Precipitation: %.2f" % _climate_statistics.min_precipitation)
			lines.append("Max Precipitation: %.2f" % _climate_statistics.max_precipitation)
			lines.append("Mean Precipitation: %.2f" % _climate_statistics.mean_precipitation)
			lines.append("P25: %.2f" % _climate_statistics.precipitation_p25)
			lines.append("P50 / Median: %.2f" % _climate_statistics.precipitation_p50)
			lines.append("P75: %.2f" % _climate_statistics.precipitation_p75)
			lines.append("P90: %.2f" % _climate_statistics.precipitation_p90)
		ViewMode.HYDROLOGY_CONDITIONING:
			lines.append("Initial Sink Count: %d" % hydrology.initial_sink_count)
			lines.append("Filled Depression Count: %d" % hydrology.filled_depression_count)
			lines.append("Breached Depression Count: %d" % hydrology.breached_depression_count)
			lines.append("Closed Basin Count: %d" % hydrology.closed_basin_count)
			lines.append("Modified Cell: %.2f%%" % (hydrology.modified_cell_ratio * 100.0))
			lines.append("Max Raise: %.3f" % hydrology.max_raise)
			lines.append("Max Cut: %.3f" % hydrology.max_cut)
			lines.append("")
			lines.append("Legend:")
			lines.append("Yellow = Fill")
			lines.append("Red / Pink = Carve")
			lines.append("Purple = Closed Basin")
			lines.append("Dark Gray = Unchanged Land")
			lines.append("Dark Blue = Water")


func _append_land_water_statistics(lines: PackedStringArray) -> void:
	lines.append("Land: %.2f%%" % (_terrain_statistics.land_ratio * 100.0))
	lines.append("Water: %.2f%%" % (_terrain_statistics.water_ratio * 100.0))


func _calculate_terrain_statistics() -> Dictionary:
	if terrain == null or terrain.terrain_height.is_empty():
		return {
			"min_height": 0.0,
			"max_height": 0.0,
			"mean_height": 0.0,
			"land_ratio": 0.0,
			"water_ratio": 0.0,
		}
	var minimum := 100.0
	var maximum := -100.0
	var sum := 0.0
	var land_count := 0
	for cell_id in terrain.cell_count():
		var height := terrain.terrain_height[cell_id]
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)
		sum += height
		if terrain.is_land(cell_id):
			land_count += 1
	var count := float(terrain.cell_count())
	var land_ratio := float(land_count) / count
	return {
		"min_height": minimum,
		"max_height": maximum,
		"mean_height": sum / count,
		"land_ratio": land_ratio,
		"water_ratio": 1.0 - land_ratio,
	}


func _calculate_climate_statistics() -> Dictionary:
	if climate == null or climate.temperature.is_empty():
		return {
			"min_temperature": 0.0,
			"max_temperature": 0.0,
			"mean_temperature": 0.0,
			"min_precipitation": 0.0,
			"max_precipitation": 0.0,
			"mean_precipitation": 0.0,
			"precipitation_p25": 0.0,
			"precipitation_p50": 0.0,
			"precipitation_p75": 0.0,
			"precipitation_p90": 0.0,
		}
	var min_temperature := INF
	var max_temperature := -INF
	var temperature_sum := 0.0
	var min_precipitation := INF
	var max_precipitation := 0.0
	var precipitation_sum := 0.0
	for cell_id in climate.cell_count():
		var temperature := climate.temperature[cell_id]
		var precipitation := climate.precipitation[cell_id]
		min_temperature = minf(min_temperature, temperature)
		max_temperature = maxf(max_temperature, temperature)
		temperature_sum += temperature
		min_precipitation = minf(min_precipitation, precipitation)
		max_precipitation = maxf(max_precipitation, precipitation)
		precipitation_sum += precipitation
	var sorted_precipitation := climate.precipitation.duplicate()
	sorted_precipitation.sort()
	var count := float(climate.cell_count())
	return {
		"min_temperature": min_temperature,
		"max_temperature": max_temperature,
		"mean_temperature": temperature_sum / count,
		"min_precipitation": min_precipitation,
		"max_precipitation": max_precipitation,
		"mean_precipitation": precipitation_sum / count,
		"precipitation_p25": _percentile(sorted_precipitation, 0.25),
		"precipitation_p50": _percentile(sorted_precipitation, 0.50),
		"precipitation_p75": _percentile(sorted_precipitation, 0.75),
		"precipitation_p90": _percentile(sorted_precipitation, 0.90),
	}


func _percentile(sorted_values: PackedFloat32Array, percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var position := float(sorted_values.size() - 1) * percentile
	var lower_index := floori(position)
	var upper_index := ceili(position)
	if lower_index == upper_index:
		return sorted_values[lower_index]
	return lerpf(
		sorted_values[lower_index],
		sorted_values[upper_index],
		position - lower_index
	)


func _view_mode_name() -> String:
	match view_mode:
		ViewMode.RAW_COMPOSITION:
			return "Raw Composition"
		ViewMode.TERRAIN_HEIGHT:
			return "Terrain Height"
		ViewMode.LAND_WATER:
			return "Land / Water"
		ViewMode.TEMPERATURE:
			return "Temperature"
		ViewMode.PRECIPITATION:
			return "Precipitation"
		_:
			return "Hydrology Conditioning"


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
