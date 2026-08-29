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
var projected_terrain: TerrainHeightLayer
var geology: GeologyLayer
var terrain: TerrainHeightLayer
var hydrology: HydrologyConditioningResult
var preliminary_flow: HydrologyFlowResult
var formal_hydrology: WorldHydrologyLayer
var surface_water: SurfaceWaterLayer
var preliminary_climate: WorldClimateLayer
var climate: WorldClimateLayer
var climate_settings: WorldClimateSettings
var hydrology_conditioning_settings: HydrologyConditioningSettings
var hydrology_settings: WorldHydrologySettings
var surface_water_settings: SurfaceWaterSettings
var selected_cell_id := -1
var view_mode := ViewMode.RAW_COMPOSITION
var _spatial_generation_ms := 0
var _composition_generation_ms := 0
var _terrain_projection_ms := 0
var _geology_generation_ms := 0
var _hydrology_conditioning_ms := 0
var _preliminary_flow_generation_ms := 0
var _formal_hydrology_generation_ms := 0
var _surface_water_generation_ms := 0
var _preliminary_climate_generation_ms := 0
var _final_climate_generation_ms := 0
var _view_scale := 1.0
var _view_offset := Vector2.ZERO
var _statistics := {}
var _terrain_statistics := {}
var _climate_statistics := {}
var _climate_delta_statistics := {}
var _formal_hydrology_statistics := {}
var _geology_statistics := {}
var _surface_water_statistics := {}

const _MARGIN := 24.0
const _INFO_WIDTH := 350.0

enum ViewMode {
	RAW_COMPOSITION,
	TERRAIN_HEIGHT,
	LAND_WATER,
	TEMPERATURE,
	PRECIPITATION,
	HYDROLOGY_CONDITIONING,
	FLOW_ACCUMULATION,
	RIVER_NETWORKS,
	WATERSHEDS,
	GEOLOGIC_PROVINCE,
	DOMINANT_MATERIAL,
	PERMEABILITY,
	ERODIBILITY,
	TEMPERATURE_DELTA,
	PRECIPITATION_DELTA,
	LAKE_EXTENT,
	LAKE_DEPTH,
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
				view_mode = ViewMode.TEMPERATURE_DELTA \
						if event.shift_pressed else ViewMode.TEMPERATURE
			KEY_P:
				view_mode = ViewMode.PRECIPITATION_DELTA \
						if event.shift_pressed else ViewMode.PRECIPITATION
			KEY_D:
				view_mode = ViewMode.HYDROLOGY_CONDITIONING
			KEY_F:
				view_mode = ViewMode.FLOW_ACCUMULATION
			KEY_N:
				view_mode = ViewMode.RIVER_NETWORKS
			KEY_W:
				view_mode = ViewMode.WATERSHEDS
			KEY_G:
				view_mode = ViewMode.GEOLOGIC_PROVINCE
			KEY_M:
				view_mode = ViewMode.DOMINANT_MATERIAL
			KEY_K:
				view_mode = ViewMode.PERMEABILITY
			KEY_E:
				view_mode = ViewMode.ERODIBILITY
			KEY_O:
				view_mode = ViewMode.LAKE_DEPTH if event.shift_pressed else ViewMode.LAKE_EXTENT
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
	if graph == null \
			or composition == null \
			or projected_terrain == null \
			or geology == null \
			or terrain == null \
			or hydrology == null \
			or preliminary_flow == null \
			or formal_hydrology == null \
			or surface_water == null \
			or preliminary_climate == null \
			or climate == null:
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
		ViewMode.HYDROLOGY_CONDITIONING:
			return _hydrology_action_color(cell_id)
		ViewMode.FLOW_ACCUMULATION:
			return _flow_accumulation_color(cell_id)
		ViewMode.RIVER_NETWORKS:
			return _river_color(cell_id)
		ViewMode.WATERSHEDS:
			return _watershed_color(cell_id)
		ViewMode.GEOLOGIC_PROVINCE:
			return _province_color(geology.province_id[cell_id])
		ViewMode.DOMINANT_MATERIAL:
			return _material_color(geology.material_id[cell_id])
		ViewMode.PERMEABILITY:
			return Color(0.24, 0.14, 0.10).lerp(
				Color(0.08, 0.78, 0.86), geology.permeability[cell_id]
			)
		ViewMode.ERODIBILITY:
			return Color(0.16, 0.20, 0.26).lerp(
				Color(0.96, 0.48, 0.08), geology.erodibility[cell_id]
			)
		ViewMode.LAKE_EXTENT:
			return _lake_extent_color(cell_id)
		ViewMode.LAKE_DEPTH:
			return _lake_depth_color(cell_id)
		ViewMode.TEMPERATURE_DELTA:
			return _temperature_delta_color(cell_id)
		_:
			return _precipitation_delta_color(cell_id)


func _lake_extent_color(cell_id: int) -> Color:
	if terrain.terrain_height[cell_id] < 0.0:
		return Color(0.04, 0.14, 0.30)
	if surface_water.lake_id[cell_id] >= 0:
		return Color(0.08, 0.48, 0.88)
	if hydrology.closed_basin_id[cell_id] >= 0:
		return Color(0.30, 0.22, 0.34)
	return Color(0.20, 0.22, 0.23)


func _lake_depth_color(cell_id: int) -> Color:
	if terrain.terrain_height[cell_id] < 0.0:
		return Color(0.04, 0.14, 0.30)
	var depth := surface_water.surface_water_depth[cell_id]
	if depth <= 0.0:
		return Color(0.20, 0.22, 0.23)
	var maximum := float(_surface_water_statistics.get("max_depth", 0.0))
	var normalized := clampf(depth / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	return Color(0.42, 0.82, 0.96).lerp(Color(0.02, 0.16, 0.52), sqrt(normalized))


func _province_color(province_id: int) -> Color:
	match province_id:
		GeologyCatalog.Province.OCEANIC_CRUST:
			return Color(0.05, 0.20, 0.48)
		GeologyCatalog.Province.CRATON:
			return Color(0.66, 0.48, 0.20)
		GeologyCatalog.Province.OROGENIC_BELT:
			return Color(0.78, 0.20, 0.16)
		GeologyCatalog.Province.SEDIMENTARY_BASIN:
			return Color(0.88, 0.70, 0.26)
		GeologyCatalog.Province.PASSIVE_MARGIN:
			return Color(0.12, 0.66, 0.54)
		_:
			return Color(0.72, 0.16, 0.68)


func _material_color(material_id: int) -> Color:
	match material_id:
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK:
			return Color(0.58, 0.60, 0.64)
		GeologyCatalog.MaterialType.METAMORPHIC_ROCK:
			return Color(0.48, 0.30, 0.60)
		GeologyCatalog.MaterialType.SANDSTONE:
			return Color(0.82, 0.62, 0.30)
		GeologyCatalog.MaterialType.SHALE_MUDSTONE:
			return Color(0.34, 0.24, 0.18)
		GeologyCatalog.MaterialType.CARBONATE_ROCK:
			return Color(0.70, 0.84, 0.82)
		GeologyCatalog.MaterialType.VOLCANIC_ROCK:
			return Color(0.34, 0.12, 0.12)
		_:
			return Color(0.18, 0.42, 0.62)


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


func _flow_accumulation_color(cell_id: int) -> Color:
	if not terrain.is_land(cell_id):
		return Color(0.05, 0.16, 0.28)
	var maximum := float(_formal_hydrology_statistics.get("max_accumulation", 0.0))
	var value := formal_hydrology.flow_accumulation[cell_id]
	var normalized := log(1.0 + value) / log(1.0 + maximum) if maximum > 0.0 else 0.0
	return Color(0.18, 0.15, 0.10).lerp(Color(0.06, 0.72, 0.88), normalized)


func _river_color(cell_id: int) -> Color:
	if not terrain.is_land(cell_id):
		return Color(0.05, 0.14, 0.24)
	var order := formal_hydrology.river_order[cell_id]
	if order < 1:
		return Color(0.16, 0.18, 0.18)
	var maximum_order := maxi(1, int(_formal_hydrology_statistics.get("max_river_order", 1)))
	var strength := float(order) / float(maximum_order)
	return Color(0.10, 0.42, 0.72).lerp(Color(0.58, 0.92, 1.0), strength)


func _watershed_color(cell_id: int) -> Color:
	if not terrain.is_land(cell_id):
		return Color(0.05, 0.14, 0.24)
	var watershed_id := formal_hydrology.watershed_id[cell_id]
	var hue := fmod(float(watershed_id) * 0.61803398875, 1.0)
	return Color.from_hsv(hue, 0.56, 0.68)


func _temperature_delta_color(cell_id: int) -> Color:
	var delta := climate.temperature[cell_id] - preliminary_climate.temperature[cell_id]
	var maximum_absolute := float(_climate_delta_statistics.get("max_abs_temperature", 0.0))
	return _diverging_color(
		delta,
		maximum_absolute,
		Color(0.08, 0.30, 0.78),
		Color(0.56, 0.56, 0.53),
		Color(0.86, 0.16, 0.12)
	)


func _precipitation_delta_color(cell_id: int) -> Color:
	var delta := climate.precipitation[cell_id] - preliminary_climate.precipitation[cell_id]
	var maximum_absolute := float(_climate_delta_statistics.get("max_abs_precipitation", 0.0))
	return _diverging_color(
		delta,
		maximum_absolute,
		Color(0.88, 0.38, 0.08),
		Color(0.56, 0.56, 0.53),
		Color(0.06, 0.48, 0.88)
	)


func _diverging_color(
		value: float,
		maximum_absolute: float,
		negative_color: Color,
		neutral_color: Color,
		positive_color: Color
) -> Color:
	if maximum_absolute <= 0.0:
		return neutral_color
	var normalized := clampf(value / maximum_absolute, -1.0, 1.0)
	if normalized < 0.0:
		return negative_color.lerp(neutral_color, normalized + 1.0)
	return neutral_color.lerp(positive_color, normalized)


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
		projected_terrain = null
		geology = null
		terrain = null
		hydrology = null
		preliminary_flow = null
		formal_hydrology = null
		surface_water = null
		preliminary_climate = null
		climate = null
		return
	var started := Time.get_ticks_msec()
	composition = WorldCompositionGenerator.generate(
		graph, WorldCompositionConfig.new(seed, StringName(template_id))
	)
	_composition_generation_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	projected_terrain = null if composition == null else TerrainHeightProjector.project(
		composition.continental_value
	)
	_terrain_projection_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	geology = null if projected_terrain == null else GeologyGenerator.generate(graph, projected_terrain)
	_geology_generation_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	climate_settings = WorldClimateSettings.new(latitude_north, latitude_south)
	hydrology_conditioning_settings = HydrologyConditioningSettings.new()
	preliminary_climate = null if geology == null else WorldClimateGenerator.generate(
		graph, projected_terrain, climate_settings
	)
	_preliminary_climate_generation_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	hydrology_settings = WorldHydrologySettings.new()
	preliminary_flow = null if preliminary_climate == null else PreliminaryFlowGenerator.generate(
		graph, projected_terrain, preliminary_climate, hydrology_settings
	)
	_preliminary_flow_generation_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	hydrology = null if preliminary_flow == null else HydrologyConditioner.condition(
		graph, projected_terrain, preliminary_flow, geology, hydrology_conditioning_settings
	)
	terrain = null
	if hydrology != null:
		terrain = TerrainHeightLayer.new()
		terrain.terrain_height = hydrology.terrain_height.duplicate()
	_hydrology_conditioning_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	climate = null if terrain == null else WorldClimateGenerator.generate(
		graph, terrain, climate_settings
	)
	_final_climate_generation_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	formal_hydrology = null if terrain == null else WorldHydrologyGenerator.generate(
		graph, terrain, climate, hydrology.closed_basin_id, hydrology_settings
	)
	_formal_hydrology_generation_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	surface_water_settings = SurfaceWaterSettings.new()
	surface_water = null if formal_hydrology == null else SurfaceWaterGenerator.generate(
		graph,
		terrain,
		climate,
		formal_hydrology,
		hydrology.closed_basin_id,
		geology,
		surface_water_settings
	)
	_surface_water_generation_ms = Time.get_ticks_msec() - started
	_statistics = WorldCompositionValidator.statistics(composition)
	_terrain_statistics = _calculate_terrain_statistics()
	_climate_statistics = _calculate_climate_statistics()
	_climate_delta_statistics = _calculate_climate_delta_statistics()
	_formal_hydrology_statistics = _calculate_formal_hydrology_statistics()
	_geology_statistics = _calculate_geology_statistics()
	_surface_water_statistics = _calculate_surface_water_statistics()
	selected_cell_id = -1
	queue_redraw()


func _draw_information() -> void:
	var viewport_width := get_viewport_rect().size.x
	var panel := Rect2(viewport_width - _INFO_WIDTH, 0.0, _INFO_WIDTH, get_viewport_rect().size.y)
	draw_rect(panel, Color(0.055, 0.065, 0.085, 0.97))
	var mode := _view_mode_name()
	var lines := PackedStringArray([
		"Surface Water / Lakes v1.8 Debug",
		"Template: %s" % CompositionTemplates.display_name(StringName(template_id)),
		"Seed: %d" % seed,
		"World: %d x %d" % [int(world_width), int(world_height)],
		"Cells: %d" % graph.cell_count(),
		"Spatial: %d ms | Composition: %d ms" % [_spatial_generation_ms, _composition_generation_ms],
		"Terrain: %d ms | Geology: %d ms" % [_terrain_projection_ms, _geology_generation_ms],
		"Prelim Climate: %d ms | Flow: %d ms"
		% [_preliminary_climate_generation_ms, _preliminary_flow_generation_ms],
		"Conditioning: %d ms" % _hydrology_conditioning_ms,
		"Final Climate: %d ms" % _final_climate_generation_ms,
		"Formal Hydrology: %d ms" % _formal_hydrology_generation_ms,
		"Surface Water: %d ms" % _surface_water_generation_ms,
		"Mode: " + mode,
		"V Raw   H Terrain   L Land/Water",
		"C Final Temp   P Final Precip",
		"Shift+C Temp Δ   Shift+P Precip Δ",
		"D Hydrology Conditioning",
		"F Flow Accum   N River Network",
		"W Watersheds",
		"G Province   M Material",
		"K Permeability   E Erodibility",
		"O Lake Extent   Shift+O Lake Depth",
		"T Template   R Seed+1",
		"Click a Cell to inspect",
		"",
	])
	_append_mode_statistics(lines)
	if selected_cell_id >= 0:
		lines.append("")
		lines.append("Cell ID: %d" % selected_cell_id)
		if view_mode == ViewMode.TEMPERATURE_DELTA:
			lines.append("Conditioned Height: %.3f" % terrain.terrain_height[selected_cell_id])
			lines.append("Preliminary Temp: %.3f °C" % preliminary_climate.temperature[selected_cell_id])
			lines.append("Final Temp: %.3f °C" % climate.temperature[selected_cell_id])
			lines.append(
				"Temperature Delta: %+.3f °C"
				% (climate.temperature[selected_cell_id] - preliminary_climate.temperature[selected_cell_id])
			)
		elif view_mode == ViewMode.PRECIPITATION_DELTA:
			lines.append("Conditioned Height: %.3f" % terrain.terrain_height[selected_cell_id])
			lines.append("Preliminary Precip: %.3f" % preliminary_climate.precipitation[selected_cell_id])
			lines.append("Final Precip: %.3f" % climate.precipitation[selected_cell_id])
			lines.append(
				"Precipitation Delta: %+.3f"
				% (climate.precipitation[selected_cell_id] - preliminary_climate.precipitation[selected_cell_id])
			)
		elif view_mode == ViewMode.HYDROLOGY_CONDITIONING:
			lines.append("Original Height: %.3f" % hydrology.original_height[selected_cell_id])
			lines.append("Conditioned Height: %.3f" % hydrology.terrain_height[selected_cell_id])
			lines.append("Height Delta: %+.3f" % hydrology.height_delta[selected_cell_id])
			lines.append("Action: %s" % hydrology.action_name(selected_cell_id))
			lines.append("Material: %s" % GeologyCatalog.material_name(geology.material_id[selected_cell_id]))
			lines.append("Erodibility: %.2f" % geology.erodibility[selected_cell_id])
			lines.append(
				"Material Resistance: %.3f"
				% HydrologyConditioner.material_resistance(geology.erodibility[selected_cell_id])
			)
		elif _is_surface_water_view():
			lines.append("Terrain Height: %.3f" % terrain.terrain_height[selected_cell_id])
			lines.append("Closed Basin ID: %d" % hydrology.closed_basin_id[selected_cell_id])
			lines.append("Lake ID: %d" % surface_water.lake_id[selected_cell_id])
			lines.append(
				"Surface Water Depth: %.3f"
				% surface_water.surface_water_depth[selected_cell_id]
			)
			var lake_id := surface_water.lake_id[selected_cell_id]
			if lake_id >= 0:
				var lake: SurfaceWaterLake = surface_water.lakes[lake_id]
				lines.append("Lake Water Level: %.3f" % lake.water_level)
				lines.append("Lake Area: %.3f" % lake.area)
		elif _is_geology_view():
			lines.append("Projected Height: %.3f" % projected_terrain.terrain_height[selected_cell_id])
			lines.append("Province: %s" % GeologyCatalog.province_name(geology.province_id[selected_cell_id]))
			lines.append("Material: %s" % GeologyCatalog.material_name(geology.material_id[selected_cell_id]))
			lines.append("Permeability: %.2f" % geology.permeability[selected_cell_id])
			lines.append("Erodibility: %.2f" % geology.erodibility[selected_cell_id])
		if view_mode != ViewMode.TEMPERATURE_DELTA \
				and view_mode != ViewMode.PRECIPITATION_DELTA \
				and not _is_geology_view() \
				and not _is_surface_water_view():
			if view_mode != ViewMode.HYDROLOGY_CONDITIONING:
				lines.append("Conditioned Height: %.2f" % terrain.terrain_height[selected_cell_id])
			lines.append("Latitude: %.2f" % WorldClimateGenerator.latitude_at(
				selected_cell_id, graph, climate_settings
			))
			lines.append("Final Temperature: %.2f °C" % climate.temperature[selected_cell_id])
			lines.append("Final Precipitation: %.2f" % climate.precipitation[selected_cell_id])
			lines.append("Land / Water: %s" % ("Land" if terrain.is_land(selected_cell_id) else "Water"))
			lines.append("Local Runoff: %.3f" % formal_hydrology.local_runoff[selected_cell_id])
			lines.append("Flow To: %s" % _flow_to_text(selected_cell_id))
			lines.append("Flow Accumulation: %.3f" % formal_hydrology.flow_accumulation[selected_cell_id])
			lines.append("River Network ID: %d" % formal_hydrology.river_network_id[selected_cell_id])
			lines.append("River Order: %d" % formal_hydrology.river_order[selected_cell_id])
			lines.append("Watershed ID: %d" % formal_hydrology.watershed_id[selected_cell_id])
			lines.append("Closed Basin ID: %d" % hydrology.closed_basin_id[selected_cell_id])
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
			lines.append("Min Final Temperature: %.2f °C" % _climate_statistics.min_temperature)
			lines.append("Max Final Temperature: %.2f °C" % _climate_statistics.max_temperature)
			lines.append("Mean Final Temperature: %.2f °C" % _climate_statistics.mean_temperature)
		ViewMode.PRECIPITATION:
			lines.append("Min Final Precipitation: %.2f" % _climate_statistics.min_precipitation)
			lines.append("Max Final Precipitation: %.2f" % _climate_statistics.max_precipitation)
			lines.append("Mean Final Precipitation: %.2f" % _climate_statistics.mean_precipitation)
			lines.append("P25: %.2f" % _climate_statistics.precipitation_p25)
			lines.append("P50 / Median: %.2f" % _climate_statistics.precipitation_p50)
			lines.append("P75: %.2f" % _climate_statistics.precipitation_p75)
			lines.append("P90: %.2f" % _climate_statistics.precipitation_p90)
		ViewMode.HYDROLOGY_CONDITIONING:
			lines.append("Initial Sink Count: %d" % hydrology.initial_sink_count)
			lines.append("Filled Depression Count: %d" % hydrology.filled_depression_count)
			lines.append("Breached Depression Count: %d" % hydrology.breached_depression_count)
			lines.append(
				"Breached By Sufficient Inflow: %d"
				% hydrology.breached_by_sufficient_inflow_count
			)
			lines.append(
				"Rejected Breach By Low Inflow: %d"
				% hydrology.rejected_breach_by_low_inflow_count
			)
			lines.append("Breach Min Inflow: %.1f" % hydrology_conditioning_settings.breach_min_inflow)
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
		ViewMode.FLOW_ACCUMULATION:
			lines.append("Min: %.3f" % _formal_hydrology_statistics.min_accumulation)
			lines.append("Mean: %.3f" % _formal_hydrology_statistics.mean_accumulation)
			lines.append("Median: %.3f" % _formal_hydrology_statistics.median_accumulation)
			lines.append("P75: %.3f" % _formal_hydrology_statistics.accumulation_p75)
			lines.append("P90: %.3f" % _formal_hydrology_statistics.accumulation_p90)
			lines.append("Max: %.3f" % _formal_hydrology_statistics.max_accumulation)
		ViewMode.RIVER_NETWORKS:
			lines.append("River Network Count: %d" % formal_hydrology.river_networks.size())
			lines.append("River Cell Count: %d" % _formal_hydrology_statistics.river_cell_count)
			lines.append("Max Strahler Order: %d" % _formal_hydrology_statistics.max_river_order)
			lines.append("Largest Discharge: %.3f" % _formal_hydrology_statistics.largest_discharge)
		ViewMode.WATERSHEDS:
			lines.append("Watershed Count: %d" % formal_hydrology.watershed_count)
			lines.append("Closed Basin Count: %d" % formal_hydrology.closed_basin_inflows.size())
		ViewMode.GEOLOGIC_PROVINCE:
			for province_id in GeologyCatalog.PROVINCE_COUNT:
				var count: int = _geology_statistics.province_counts[province_id]
				lines.append(
					"%s: %d (%.2f%%)"
					% [
						GeologyCatalog.province_name(province_id),
						count,
						float(count) / float(graph.cell_count()) * 100.0,
					]
				)
		ViewMode.DOMINANT_MATERIAL:
			for material_id in GeologyCatalog.MATERIAL_COUNT:
				var count: int = _geology_statistics.material_counts[material_id]
				lines.append(
					"%s: %d (%.2f%%)"
					% [
						GeologyCatalog.material_name(material_id),
						count,
						float(count) / float(graph.cell_count()) * 100.0,
					]
				)
		ViewMode.PERMEABILITY:
			lines.append("Min Permeability: %.2f" % _geology_statistics.min_permeability)
			lines.append("Max Permeability: %.2f" % _geology_statistics.max_permeability)
			lines.append("Mean Permeability: %.3f" % _geology_statistics.mean_permeability)
		ViewMode.ERODIBILITY:
			lines.append("Min Erodibility: %.2f" % _geology_statistics.min_erodibility)
			lines.append("Max Erodibility: %.2f" % _geology_statistics.max_erodibility)
			lines.append("Mean Erodibility: %.3f" % _geology_statistics.mean_erodibility)
		ViewMode.LAKE_EXTENT, ViewMode.LAKE_DEPTH:
			lines.append("Closed Basin Count: %d" % formal_hydrology.closed_basin_inflows.size())
			lines.append("Lake Count: %d" % surface_water.lakes.size())
			lines.append("Lake Cells: %d" % _surface_water_statistics.lake_cell_count)
			lines.append("Lake Area Total: %.3f" % _surface_water_statistics.total_lake_area)
			lines.append("Largest Lake Area: %.3f" % _surface_water_statistics.largest_lake_area)
			lines.append("Mean Lake Area: %.3f" % _surface_water_statistics.mean_lake_area)
			lines.append("Max Surface Water Depth: %.3f" % _surface_water_statistics.max_depth)
			lines.append("Rejected Small Lake Count: %d" % surface_water.rejected_small_lake_count)
			lines.append("No-Lake Basin Count: %d" % surface_water.no_lake_basin_count)
		ViewMode.TEMPERATURE_DELTA:
			lines.append("Min Delta: %+.4f °C" % _climate_delta_statistics.min_temperature_delta)
			lines.append("Max Delta: %+.4f °C" % _climate_delta_statistics.max_temperature_delta)
			lines.append("Mean Absolute Delta: %.4f °C" % _climate_delta_statistics.mean_abs_temperature_delta)
		ViewMode.PRECIPITATION_DELTA:
			lines.append("Min Delta: %+.4f" % _climate_delta_statistics.min_precipitation_delta)
			lines.append("Max Delta: %+.4f" % _climate_delta_statistics.max_precipitation_delta)
			lines.append("Mean Absolute Delta: %.4f" % _climate_delta_statistics.mean_abs_precipitation_delta)


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


func _calculate_climate_delta_statistics() -> Dictionary:
	if preliminary_climate == null or climate == null or climate.temperature.is_empty():
		return {
			"min_temperature_delta": 0.0,
			"max_temperature_delta": 0.0,
			"mean_abs_temperature_delta": 0.0,
			"max_abs_temperature": 0.0,
			"min_precipitation_delta": 0.0,
			"max_precipitation_delta": 0.0,
			"mean_abs_precipitation_delta": 0.0,
			"max_abs_precipitation": 0.0,
		}
	var min_temperature_delta := INF
	var max_temperature_delta := -INF
	var temperature_absolute_sum := 0.0
	var min_precipitation_delta := INF
	var max_precipitation_delta := -INF
	var precipitation_absolute_sum := 0.0
	for cell_id in climate.cell_count():
		var temperature_delta := (
			climate.temperature[cell_id] - preliminary_climate.temperature[cell_id]
		)
		var precipitation_delta := (
			climate.precipitation[cell_id] - preliminary_climate.precipitation[cell_id]
		)
		min_temperature_delta = minf(min_temperature_delta, temperature_delta)
		max_temperature_delta = maxf(max_temperature_delta, temperature_delta)
		temperature_absolute_sum += absf(temperature_delta)
		min_precipitation_delta = minf(min_precipitation_delta, precipitation_delta)
		max_precipitation_delta = maxf(max_precipitation_delta, precipitation_delta)
		precipitation_absolute_sum += absf(precipitation_delta)
	var count := float(climate.cell_count())
	return {
		"min_temperature_delta": min_temperature_delta,
		"max_temperature_delta": max_temperature_delta,
		"mean_abs_temperature_delta": temperature_absolute_sum / count,
		"max_abs_temperature": maxf(absf(min_temperature_delta), absf(max_temperature_delta)),
		"min_precipitation_delta": min_precipitation_delta,
		"max_precipitation_delta": max_precipitation_delta,
		"mean_abs_precipitation_delta": precipitation_absolute_sum / count,
		"max_abs_precipitation": maxf(absf(min_precipitation_delta), absf(max_precipitation_delta)),
	}


func _calculate_formal_hydrology_statistics() -> Dictionary:
	if formal_hydrology == null or formal_hydrology.flow_accumulation.is_empty():
		return {
			"min_accumulation": 0.0,
			"mean_accumulation": 0.0,
			"median_accumulation": 0.0,
			"accumulation_p75": 0.0,
			"accumulation_p90": 0.0,
			"max_accumulation": 0.0,
			"river_cell_count": 0,
			"max_river_order": 0,
			"largest_discharge": 0.0,
		}
	var minimum := INF
	var maximum := 0.0
	var sum := 0.0
	var river_cell_count := 0
	var max_river_order := 0
	for cell_id in formal_hydrology.cell_count():
		var accumulation := formal_hydrology.flow_accumulation[cell_id]
		minimum = minf(minimum, accumulation)
		maximum = maxf(maximum, accumulation)
		sum += accumulation
		if formal_hydrology.river_network_id[cell_id] >= 0:
			river_cell_count += 1
			max_river_order = maxi(max_river_order, formal_hydrology.river_order[cell_id])
	var largest_discharge := 0.0
	for river_network in formal_hydrology.river_networks:
		largest_discharge = maxf(largest_discharge, river_network.discharge)
	var sorted_accumulation := formal_hydrology.flow_accumulation.duplicate()
	sorted_accumulation.sort()
	return {
		"min_accumulation": minimum,
		"mean_accumulation": sum / float(formal_hydrology.cell_count()),
		"median_accumulation": _percentile(sorted_accumulation, 0.50),
		"accumulation_p75": _percentile(sorted_accumulation, 0.75),
		"accumulation_p90": _percentile(sorted_accumulation, 0.90),
		"max_accumulation": maximum,
		"river_cell_count": river_cell_count,
		"max_river_order": max_river_order,
		"largest_discharge": largest_discharge,
	}


func _calculate_geology_statistics() -> Dictionary:
	var province_counts := PackedInt32Array()
	province_counts.resize(GeologyCatalog.PROVINCE_COUNT)
	var material_counts := PackedInt32Array()
	material_counts.resize(GeologyCatalog.MATERIAL_COUNT)
	var min_permeability := INF
	var max_permeability := -INF
	var permeability_sum := 0.0
	var min_erodibility := INF
	var max_erodibility := -INF
	var erodibility_sum := 0.0
	for cell_id in geology.cell_count():
		province_counts[geology.province_id[cell_id]] += 1
		material_counts[geology.material_id[cell_id]] += 1
		min_permeability = minf(min_permeability, geology.permeability[cell_id])
		max_permeability = maxf(max_permeability, geology.permeability[cell_id])
		permeability_sum += geology.permeability[cell_id]
		min_erodibility = minf(min_erodibility, geology.erodibility[cell_id])
		max_erodibility = maxf(max_erodibility, geology.erodibility[cell_id])
		erodibility_sum += geology.erodibility[cell_id]
	return {
		"province_counts": province_counts,
		"material_counts": material_counts,
		"min_permeability": min_permeability,
		"max_permeability": max_permeability,
		"mean_permeability": permeability_sum / float(geology.cell_count()),
		"min_erodibility": min_erodibility,
		"max_erodibility": max_erodibility,
		"mean_erodibility": erodibility_sum / float(geology.cell_count()),
	}


func _calculate_surface_water_statistics() -> Dictionary:
	var lake_cell_count := 0
	var total_lake_area := 0.0
	var largest_lake_area := 0.0
	var maximum_depth := 0.0
	for cell_id in surface_water.cell_count():
		if surface_water.lake_id[cell_id] >= 0:
			lake_cell_count += 1
		maximum_depth = maxf(maximum_depth, surface_water.surface_water_depth[cell_id])
	for lake in surface_water.lakes:
		total_lake_area += lake.area
		largest_lake_area = maxf(largest_lake_area, lake.area)
	return {
		"lake_cell_count": lake_cell_count,
		"total_lake_area": total_lake_area,
		"largest_lake_area": largest_lake_area,
		"mean_lake_area": total_lake_area / float(surface_water.lakes.size()) \
				if not surface_water.lakes.is_empty() else 0.0,
		"max_depth": maximum_depth,
	}


func _flow_to_text(cell_id: int) -> String:
	var downstream_id := formal_hydrology.flow_to[cell_id]
	match downstream_id:
		WorldHydrologyLayer.FLOW_TO_WATER:
			return "Water"
		WorldHydrologyLayer.FLOW_TO_BOUNDARY:
			return "World Boundary"
		WorldHydrologyLayer.FLOW_TO_CLOSED_BASIN:
			return "Closed Basin"
		_:
			return str(downstream_id)


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
			return "Final Temperature"
		ViewMode.PRECIPITATION:
			return "Final Precipitation"
		ViewMode.HYDROLOGY_CONDITIONING:
			return "Hydrology Conditioning"
		ViewMode.FLOW_ACCUMULATION:
			return "Flow Accumulation"
		ViewMode.RIVER_NETWORKS:
			return "River Network"
		ViewMode.WATERSHEDS:
			return "Watersheds"
		ViewMode.GEOLOGIC_PROVINCE:
			return "Geologic Province"
		ViewMode.DOMINANT_MATERIAL:
			return "Dominant Material"
		ViewMode.PERMEABILITY:
			return "Permeability"
		ViewMode.ERODIBILITY:
			return "Erodibility"
		ViewMode.LAKE_EXTENT:
			return "Lake Extent"
		ViewMode.LAKE_DEPTH:
			return "Lake Depth"
		ViewMode.TEMPERATURE_DELTA:
			return "Temperature Delta"
		_:
			return "Precipitation Delta"


func _is_geology_view() -> bool:
	return view_mode == ViewMode.GEOLOGIC_PROVINCE \
			or view_mode == ViewMode.DOMINANT_MATERIAL \
			or view_mode == ViewMode.PERMEABILITY \
			or view_mode == ViewMode.ERODIBILITY


func _is_surface_water_view() -> bool:
	return view_mode == ViewMode.LAKE_EXTENT or view_mode == ViewMode.LAKE_DEPTH


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
