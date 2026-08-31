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
var ecology: EcologyLayer
var soil: SoilLayer
var preliminary_climate: WorldClimateLayer
var climate: WorldClimateLayer
var climate_settings: WorldClimateSettings
var hydrology_conditioning_settings: HydrologyConditioningSettings
var hydrology_settings: WorldHydrologySettings
var surface_water_settings: SurfaceWaterSettings
var ecology_settings: EcologySettings
var soil_settings: SoilSettings
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
var _ecology_generation_ms := 0
var _soil_generation_ms := 0
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
var _ecology_statistics := {}
var _soil_statistics := {}

const _MARGIN := 24.0
const _INFO_WIDTH := 350.0
const _HIGH_DEPOSITION_THRESHOLD := 0.50

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
	DRAINAGE,
	ECOLOGICAL_MOISTURE,
	VEGETATION_POTENTIAL,
	BIOME,
	SOIL_DEPTH,
	SOIL_TEXTURE,
	ORGANIC_MATTER,
	SOIL_FERTILITY,
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
				view_mode = ViewMode.VEGETATION_POTENTIAL \
						if event.shift_pressed else ViewMode.RAW_COMPOSITION
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
				view_mode = ViewMode.DRAINAGE \
						if event.shift_pressed else ViewMode.HYDROLOGY_CONDITIONING
			KEY_F:
				view_mode = ViewMode.FLOW_ACCUMULATION
			KEY_N:
				view_mode = ViewMode.RIVER_NETWORKS
			KEY_W:
				view_mode = ViewMode.WATERSHEDS
			KEY_G:
				view_mode = ViewMode.GEOLOGIC_PROVINCE
			KEY_M:
				view_mode = ViewMode.ECOLOGICAL_MOISTURE \
						if event.shift_pressed else ViewMode.DOMINANT_MATERIAL
			KEY_B:
				view_mode = ViewMode.BIOME
			KEY_S:
				view_mode = ViewMode.SOIL_TEXTURE \
						if event.shift_pressed else ViewMode.SOIL_DEPTH
			KEY_U:
				view_mode = ViewMode.SOIL_FERTILITY \
						if event.shift_pressed else ViewMode.ORGANIC_MATTER
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
			or ecology == null \
			or soil == null \
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
		ViewMode.DRAINAGE:
			return _drainage_color(cell_id)
		ViewMode.ECOLOGICAL_MOISTURE:
			return _ecological_moisture_color(cell_id)
		ViewMode.VEGETATION_POTENTIAL:
			return _vegetation_potential_color(cell_id)
		ViewMode.BIOME:
			return _biome_color(ecology.biome_id[cell_id])
		ViewMode.SOIL_DEPTH:
			return _soil_depth_color(cell_id)
		ViewMode.SOIL_TEXTURE:
			return _soil_texture_color(cell_id)
		ViewMode.ORGANIC_MATTER:
			return _organic_matter_color(cell_id)
		ViewMode.SOIL_FERTILITY:
			return _soil_fertility_color(cell_id)
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


func _drainage_color(cell_id: int) -> Color:
	if terrain.terrain_height[cell_id] < 0.0:
		return Color(0.03, 0.13, 0.28)
	if surface_water.lake_id[cell_id] >= 0:
		return Color(0.06, 0.34, 0.58)
	return Color(0.05, 0.25, 0.30).lerp(
		Color(0.94, 0.76, 0.28), ecology.drainage_index[cell_id]
	)


func _ecological_moisture_color(cell_id: int) -> Color:
	if terrain.terrain_height[cell_id] < 0.0:
		return Color(0.03, 0.12, 0.30)
	if surface_water.lake_id[cell_id] >= 0:
		return Color(0.04, 0.40, 0.72)
	var moisture := ecology.ecological_moisture[cell_id]
	if moisture < 0.30:
		return Color(0.48, 0.26, 0.10).lerp(Color(0.84, 0.68, 0.24), moisture / 0.30)
	if moisture < 0.70:
		return Color(0.84, 0.68, 0.24).lerp(
			Color(0.10, 0.62, 0.30), (moisture - 0.30) / 0.40
		)
	return Color(0.10, 0.62, 0.30).lerp(
		Color(0.04, 0.34, 0.78), (moisture - 0.70) / 0.30
	)


func _vegetation_potential_color(cell_id: int) -> Color:
	if terrain.terrain_height[cell_id] < 0.0:
		return Color(0.03, 0.12, 0.28)
	if surface_water.lake_id[cell_id] >= 0:
		return Color(0.04, 0.36, 0.66)
	var potential := ecology.vegetation_potential[cell_id]
	if potential < 0.35:
		return Color(0.34, 0.29, 0.23).lerp(Color(0.68, 0.60, 0.30), potential / 0.35)
	return Color(0.68, 0.60, 0.30).lerp(
		Color(0.04, 0.44, 0.16), (potential - 0.35) / 0.65
	)


func _biome_color(biome_id: int) -> Color:
	match biome_id:
		EcologyCatalog.Biome.MARINE:
			return Color(0.03, 0.16, 0.42)
		EcologyCatalog.Biome.LAKE:
			return Color(0.05, 0.45, 0.82)
		EcologyCatalog.Biome.GLACIER:
			return Color(0.84, 0.94, 0.98)
		EcologyCatalog.Biome.TUNDRA:
			return Color(0.58, 0.62, 0.58)
		EcologyCatalog.Biome.COLD_DESERT:
			return Color(0.62, 0.54, 0.42)
		EcologyCatalog.Biome.HOT_DESERT:
			return Color(0.90, 0.66, 0.24)
		EcologyCatalog.Biome.GRASSLAND:
			return Color(0.56, 0.72, 0.24)
		EcologyCatalog.Biome.SAVANNA:
			return Color(0.76, 0.64, 0.20)
		EcologyCatalog.Biome.TAIGA:
			return Color(0.16, 0.40, 0.30)
		EcologyCatalog.Biome.TEMPERATE_FOREST:
			return Color(0.12, 0.52, 0.22)
		EcologyCatalog.Biome.TEMPERATE_RAINFOREST:
			return Color(0.05, 0.42, 0.32)
		EcologyCatalog.Biome.TROPICAL_SEASONAL_FOREST:
			return Color(0.22, 0.62, 0.18)
		EcologyCatalog.Biome.TROPICAL_RAINFOREST:
			return Color(0.02, 0.34, 0.12)
		_:
			return Color(0.16, 0.46, 0.52)


func _soil_depth_color(cell_id: int) -> Color:
	var special_color := _soil_special_surface_color(cell_id)
	if special_color.a > 0.0:
		return special_color
	return Color(0.24, 0.16, 0.10).lerp(
		Color(0.72, 0.58, 0.30), soil.soil_depth[cell_id]
	)


func _soil_texture_color(cell_id: int) -> Color:
	var special_color := _soil_special_surface_color(cell_id)
	if special_color.a > 0.0:
		return special_color
	match soil.soil_texture_id[cell_id]:
		SoilCatalog.TextureType.SANDY:
			return Color(0.82, 0.68, 0.38)
		SoilCatalog.TextureType.LOAMY:
			return Color(0.50, 0.34, 0.18)
		SoilCatalog.TextureType.SILTY:
			return Color(0.54, 0.52, 0.38)
		SoilCatalog.TextureType.CLAYEY:
			return Color(0.58, 0.24, 0.18)
		_:
			return Color(0.12, 0.12, 0.14)


func _organic_matter_color(cell_id: int) -> Color:
	var special_color := _soil_special_surface_color(cell_id)
	if special_color.a > 0.0:
		return special_color
	return Color(0.64, 0.52, 0.30).lerp(
		Color(0.10, 0.24, 0.08), soil.organic_matter[cell_id]
	)


func _soil_fertility_color(cell_id: int) -> Color:
	var special_color := _soil_special_surface_color(cell_id)
	if special_color.a > 0.0:
		return special_color
	return Color(0.42, 0.22, 0.12).lerp(
		Color(0.18, 0.72, 0.22), soil.soil_fertility[cell_id]
	)


func _soil_special_surface_color(cell_id: int) -> Color:
	match ecology.biome_id[cell_id]:
		EcologyCatalog.Biome.MARINE:
			return Color(0.03, 0.15, 0.38)
		EcologyCatalog.Biome.LAKE:
			return Color(0.05, 0.42, 0.76)
		EcologyCatalog.Biome.GLACIER:
			return Color(0.86, 0.94, 0.98)
		_:
			return Color(0.0, 0.0, 0.0, 0.0)


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
		ecology = null
		soil = null
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
	started = Time.get_ticks_msec()
	ecology_settings = EcologySettings.new()
	ecology = null if surface_water == null else EcologyGenerator.generate(
		graph,
		terrain,
		climate,
		formal_hydrology,
		hydrology.closed_basin_id,
		geology,
		surface_water,
		ecology_settings,
		surface_water_settings
	)
	_ecology_generation_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	soil_settings = SoilSettings.new()
	soil = null if ecology == null else SoilGenerator.generate(
		graph,
		terrain,
		climate,
		formal_hydrology,
		geology,
		surface_water,
		ecology,
		soil_settings
	)
	_soil_generation_ms = Time.get_ticks_msec() - started
	_statistics = WorldCompositionValidator.statistics(composition)
	_terrain_statistics = _calculate_terrain_statistics()
	_climate_statistics = _calculate_climate_statistics()
	_climate_delta_statistics = _calculate_climate_delta_statistics()
	_formal_hydrology_statistics = _calculate_formal_hydrology_statistics()
	_geology_statistics = _calculate_geology_statistics()
	_surface_water_statistics = _calculate_surface_water_statistics()
	_ecology_statistics = _calculate_ecology_statistics()
	_soil_statistics = _calculate_soil_statistics()
	_print_soil_texture_diagnostics()
	_print_soil_deposition_diagnostics()
	_print_river_network_diagnostics()
	selected_cell_id = -1
	queue_redraw()


func _draw_information() -> void:
	var viewport_width := get_viewport_rect().size.x
	var panel := Rect2(viewport_width - _INFO_WIDTH, 0.0, _INFO_WIDTH, get_viewport_rect().size.y)
	draw_rect(panel, Color(0.055, 0.065, 0.085, 0.97))
	var mode := _view_mode_name()
	var lines := PackedStringArray([
		"Soil Foundation v1.10.1 Debug",
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
		"Ecology: %d ms" % _ecology_generation_ms,
		"Soil: %d ms" % _soil_generation_ms,
		"Mode: " + mode,
		"V Raw / Shift+V Vegetation",
		"H Terrain   L Land/Water",
		"C Temp   P Precip   Shift = Delta",
		"D Conditioning / Shift+D Drainage",
		"F Accum   N River   W Watershed",
		"G Province   M Material / Shift+M Moisture",
		"K Permeability   E Erodibility",
		"O Lake / Shift+O Depth   B Biome",
		"S Soil Depth / Shift+S Texture",
		"U Organic / Shift+U Fertility",
		"T Template   R Seed+1   Click inspect",
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
		elif _is_soil_view():
			lines.append("Terrain Height: %.3f" % terrain.terrain_height[selected_cell_id])
			lines.append(
				"Material: %s"
				% GeologyCatalog.material_name(geology.material_id[selected_cell_id])
			)
			lines.append(
				"Biome: %s"
				% EcologyCatalog.biome_name(ecology.biome_id[selected_cell_id])
			)
			lines.append("Soil Depth: %.4f" % soil.soil_depth[selected_cell_id])
			lines.append(
				"Soil Texture: %s"
				% SoilCatalog.texture_name(soil.soil_texture_id[selected_cell_id])
			)
			lines.append("Organic Matter: %.4f" % soil.organic_matter[selected_cell_id])
			lines.append("Soil Fertility: %.4f" % soil.soil_fertility[selected_cell_id])
		elif _is_ecology_view():
			lines.append("Terrain Height: %.3f" % terrain.terrain_height[selected_cell_id])
			lines.append("Temperature: %.2f °C" % climate.temperature[selected_cell_id])
			lines.append("Precipitation: %.2f" % climate.precipitation[selected_cell_id])
			lines.append("Permeability: %.3f" % geology.permeability[selected_cell_id])
			lines.append(
				"Flow Accumulation: %.3f"
				% formal_hydrology.flow_accumulation[selected_cell_id]
			)
			lines.append("Lake ID: %d" % surface_water.lake_id[selected_cell_id])
			if view_mode == ViewMode.DRAINAGE:
				lines.append("Drainage Index: %.4f" % ecology.drainage_index[selected_cell_id])
			elif view_mode == ViewMode.ECOLOGICAL_MOISTURE:
				lines.append("Drainage Index: %.4f" % ecology.drainage_index[selected_cell_id])
				lines.append(
					"Ecological Moisture: %.4f"
					% ecology.ecological_moisture[selected_cell_id]
				)
			elif view_mode == ViewMode.VEGETATION_POTENTIAL:
				lines.append(
					"Ecological Moisture: %.4f"
					% ecology.ecological_moisture[selected_cell_id]
				)
				lines.append(
					"Vegetation Potential: %.4f"
					% ecology.vegetation_potential[selected_cell_id]
				)
			else:
				lines.append("Drainage Index: %.4f" % ecology.drainage_index[selected_cell_id])
				lines.append(
					"Ecological Moisture: %.4f"
					% ecology.ecological_moisture[selected_cell_id]
				)
				lines.append(
					"Vegetation Potential: %.4f"
					% ecology.vegetation_potential[selected_cell_id]
				)
			lines.append(
				"Biome: %s"
				% EcologyCatalog.biome_name(ecology.biome_id[selected_cell_id])
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
				and not _is_surface_water_view() \
				and not _is_ecology_view() \
				and not _is_soil_view():
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
	var line_height := minf(
		21.0, (get_viewport_rect().size.y - 36.0) / maxf(float(lines.size()), 1.0)
	)
	var font_size := mini(14, maxi(10, floori(line_height - 2.0)))
	for line_index in lines.size():
		draw_string(
			font,
			Vector2(panel.position.x + 16.0, 28.0 + line_index * line_height),
			lines[line_index],
			HORIZONTAL_ALIGNMENT_LEFT,
			_INFO_WIDTH - 32.0,
			font_size
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
			lines.append("All Cells:")
			lines.append("Min Final Precipitation: %.2f" % _climate_statistics.min_precipitation)
			lines.append("Max Final Precipitation: %.2f" % _climate_statistics.max_precipitation)
			lines.append("Mean Final Precipitation: %.2f" % _climate_statistics.mean_precipitation)
			lines.append("P25: %.2f" % _climate_statistics.precipitation_p25)
			lines.append("P50 / Median: %.2f" % _climate_statistics.precipitation_p50)
			lines.append("P75: %.2f" % _climate_statistics.precipitation_p75)
			lines.append("P90: %.2f" % _climate_statistics.precipitation_p90)
			lines.append("")
			lines.append("Land Only:")
			if _climate_statistics.land_precipitation_count > 0:
				lines.append(
					"Land Min Final Precipitation: %.2f"
					% _climate_statistics.land_min_precipitation
				)
				lines.append(
					"Land Max Final Precipitation: %.2f"
					% _climate_statistics.land_max_precipitation
				)
				lines.append(
					"Land Mean Final Precipitation: %.2f"
					% _climate_statistics.land_mean_precipitation
				)
				lines.append("Land P25: %.2f" % _climate_statistics.land_precipitation_p25)
				lines.append(
					"Land P50 / Median: %.2f" % _climate_statistics.land_precipitation_p50
				)
				lines.append("Land P75: %.2f" % _climate_statistics.land_precipitation_p75)
				lines.append("Land P90: %.2f" % _climate_statistics.land_precipitation_p90)
			else:
				lines.append("No land Cells (terrain_height >= 0.0)")
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
			lines.append("Zero-Capacity Basin Count: %d" % surface_water.zero_capacity_basin_count)
			lines.append("Rejected Small Lake Count: %d" % surface_water.rejected_small_lake_count)
			lines.append("No-Lake Basin Count: %d" % surface_water.no_lake_basin_count)
		ViewMode.DRAINAGE:
			_append_continuous_ecology_statistics(lines, _ecology_statistics.drainage)
		ViewMode.ECOLOGICAL_MOISTURE:
			_append_moisture_statistics(lines, _ecology_statistics.moisture)
		ViewMode.VEGETATION_POTENTIAL:
			_append_continuous_ecology_statistics(lines, _ecology_statistics.vegetation)
		ViewMode.BIOME:
			var land_count: int = _ecology_statistics.land_count
			for biome_id in EcologyCatalog.BIOME_COUNT:
				var count: int = _ecology_statistics.biome_counts[biome_id]
				var land_biome_count: int = _ecology_statistics.biome_land_counts[biome_id]
				var land_ratio := (
					float(land_biome_count) / float(land_count) * 100.0
					if land_count > 0 else 0.0
				)
				lines.append(
					"%s: %d / %.2f%% Land"
					% [EcologyCatalog.biome_name(biome_id), count, land_ratio]
				)
			lines.append(
				"Wetland Cell Count: %d"
				% _ecology_statistics.biome_counts[EcologyCatalog.Biome.WETLAND]
			)
		ViewMode.SOIL_DEPTH:
			_append_soil_depth_diagnostics(lines)
		ViewMode.SOIL_TEXTURE:
			var soil_land_count: int = _soil_statistics.land_count
			for texture_id in range(SoilCatalog.TextureType.SANDY, SoilCatalog.TEXTURE_COUNT):
				var texture_count: int = _soil_statistics.texture_counts[texture_id]
				var texture_ratio := (
					float(texture_count) / float(soil_land_count) * 100.0
					if soil_land_count > 0 else 0.0
				)
				lines.append(
					"%s: %d / %.2f%% Land"
					% [SoilCatalog.texture_name(texture_id), texture_count, texture_ratio]
				)
		ViewMode.ORGANIC_MATTER:
			_append_continuous_soil_statistics(lines, _soil_statistics.organic_matter)
		ViewMode.SOIL_FERTILITY:
			_append_continuous_soil_statistics(lines, _soil_statistics.fertility)
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


func _append_continuous_ecology_statistics(lines: PackedStringArray, statistics: Dictionary) -> void:
	lines.append("Min: %.4f" % statistics.min)
	lines.append("Max: %.4f" % statistics.max)
	lines.append("Mean: %.4f" % statistics.mean)
	lines.append("P25: %.4f" % statistics.p25)
	lines.append("P50: %.4f" % statistics.p50)
	lines.append("P75: %.4f" % statistics.p75)


func _append_moisture_statistics(lines: PackedStringArray, statistics: Dictionary) -> void:
	_append_continuous_ecology_statistics(lines, statistics)
	lines.append("P90: %.4f" % statistics.p90)
	lines.append("P95: %.4f" % statistics.p95)
	var land_count: int = statistics.land_count
	for entry in [
		["0.50", statistics.count_ge_050],
		["0.60", statistics.count_ge_060],
		["0.70", statistics.count_ge_070],
		["0.72", statistics.count_ge_072],
	]:
		var count: int = entry[1]
		var land_ratio := float(count) / float(land_count) * 100.0 if land_count > 0 else 0.0
		lines.append("Moisture >= %s: %d / %.2f%% Land" % [entry[0], count, land_ratio])


func _append_continuous_soil_statistics(
		lines: PackedStringArray, statistics: Dictionary
) -> void:
	if int(statistics.count) == 0:
		lines.append("No soil-bearing Land Cells")
		return
	lines.append("Land Only:")
	_append_soil_statistic_values(lines, statistics)


func _append_soil_depth_diagnostics(lines: PackedStringArray) -> void:
	if int(_soil_statistics.depth.count) == 0:
		lines.append("No soil-bearing Land Cells")
		return
	lines.append("Land Only:")
	for entry in [
		["Soil Depth", _soil_statistics.depth],
		["Formation Potential", _soil_statistics.formation_potential],
		["Erosion Pressure", _soil_statistics.erosion_pressure],
		["Deposition Tendency", _soil_statistics.deposition_tendency],
	]:
		lines.append(str(entry[0]) + ":")
		_append_soil_statistic_values(lines, entry[1])


func _append_soil_statistic_values(lines: PackedStringArray, statistics: Dictionary) -> void:
	lines.append("Min: %.4f" % statistics.min)
	lines.append("Mean: %.4f" % statistics.mean)
	lines.append("P25: %.4f" % statistics.p25)
	lines.append("P50 / Median: %.4f" % statistics.p50)
	lines.append("P75: %.4f" % statistics.p75)
	lines.append("P90: %.4f" % statistics.p90)
	lines.append("Max: %.4f" % statistics.max)


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
			"land_precipitation_count": 0,
			"land_min_precipitation": 0.0,
			"land_max_precipitation": 0.0,
			"land_mean_precipitation": 0.0,
			"land_precipitation_p25": 0.0,
			"land_precipitation_p50": 0.0,
			"land_precipitation_p75": 0.0,
			"land_precipitation_p90": 0.0,
		}
	var min_temperature := INF
	var max_temperature := -INF
	var temperature_sum := 0.0
	var min_precipitation := INF
	var max_precipitation := 0.0
	var precipitation_sum := 0.0
	var land_precipitation := PackedFloat32Array()
	var land_precipitation_sum := 0.0
	for cell_id in climate.cell_count():
		var temperature := climate.temperature[cell_id]
		var precipitation := climate.precipitation[cell_id]
		min_temperature = minf(min_temperature, temperature)
		max_temperature = maxf(max_temperature, temperature)
		temperature_sum += temperature
		min_precipitation = minf(min_precipitation, precipitation)
		max_precipitation = maxf(max_precipitation, precipitation)
		precipitation_sum += precipitation
		if terrain != null \
				and cell_id < terrain.terrain_height.size() \
				and terrain.terrain_height[cell_id] >= 0.0:
			land_precipitation.append(precipitation)
			land_precipitation_sum += precipitation
	var sorted_precipitation := climate.precipitation.duplicate()
	sorted_precipitation.sort()
	land_precipitation.sort()
	var count := float(climate.cell_count())
	var land_count := land_precipitation.size()
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
		"land_precipitation_count": land_count,
		"land_min_precipitation": land_precipitation[0] if land_count > 0 else 0.0,
		"land_max_precipitation": land_precipitation[land_count - 1] if land_count > 0 else 0.0,
		"land_mean_precipitation": (
			land_precipitation_sum / float(land_count) if land_count > 0 else 0.0
		),
		"land_precipitation_p25": _percentile(land_precipitation, 0.25),
		"land_precipitation_p50": _percentile(land_precipitation, 0.50),
		"land_precipitation_p75": _percentile(land_precipitation, 0.75),
		"land_precipitation_p90": _percentile(land_precipitation, 0.90),
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


func _print_river_network_diagnostics() -> void:
	if formal_hydrology == null or surface_water == null or terrain == null:
		return
	var network_count := formal_hydrology.river_networks.size()
	var cells_by_network: Array[PackedInt32Array] = []
	for network_id in network_count:
		cells_by_network.append(PackedInt32Array())
	var river_cell_count := 0
	for cell_id in formal_hydrology.cell_count():
		var network_id := formal_hydrology.river_network_id[cell_id]
		if network_id < 0 or network_id >= network_count:
			continue
		var network_cells: PackedInt32Array = cells_by_network[network_id]
		network_cells.append(cell_id)
		cells_by_network[network_id] = network_cells
		river_cell_count += 1
	var network_sizes := PackedFloat32Array()
	var two_cell_network_count := 0
	var four_plus_network_count := 0
	var eight_plus_network_count := 0
	var size_bucket_counts := {
		"1 Cell": 0,
		"2~3 Cells": 0,
		"4~7 Cells": 0,
		"8~15 Cells": 0,
		"16+ Cells": 0,
	}
	var maximum_network_size := 0
	for network_cells in cells_by_network:
		var network_size := network_cells.size()
		network_sizes.append(network_size)
		maximum_network_size = maxi(maximum_network_size, network_size)
		if network_size == 2:
			two_cell_network_count += 1
		if network_size >= 4:
			four_plus_network_count += 1
		if network_size >= 8:
			eight_plus_network_count += 1
		if network_size == 1:
			size_bucket_counts["1 Cell"] += 1
		elif network_size <= 3:
			size_bucket_counts["2~3 Cells"] += 1
		elif network_size <= 7:
			size_bucket_counts["4~7 Cells"] += 1
		elif network_size <= 15:
			size_bucket_counts["8~15 Cells"] += 1
		else:
			size_bucket_counts["16+ Cells"] += 1
	var sorted_network_sizes := network_sizes.duplicate()
	sorted_network_sizes.sort()
	print("River Network diagnostic (%s, Seed %d):" % [template_id, seed])
	print(
		"  Formal Minimum Network Cells: %d"
		% formal_hydrology.settings.formal_river_min_cells
	)
	print("  Total River Network Count: %d" % network_count)
	print("  Total River Cell Count: %d" % river_cell_count)
	print(
		"  Mean Cells per Network: %.4f"
		% (float(river_cell_count) / float(network_count) if network_count > 0 else 0.0)
	)
	print("  Median Cells per Network: %.4f" % _percentile(sorted_network_sizes, 0.50))
	print("  P75 Cells per Network: %.4f" % _percentile(sorted_network_sizes, 0.75))
	print("  P90 Cells per Network: %.4f" % _percentile(sorted_network_sizes, 0.90))
	print("  Max Cells in one Network: %d" % maximum_network_size)
	print("  Network Size Distribution:")
	for label in ["1 Cell", "2~3 Cells", "4~7 Cells", "8~15 Cells", "16+ Cells"]:
		_print_river_diagnostic_count(label, size_bucket_counts[label], network_count)
	_print_river_diagnostic_count("Exact 2 Cell", two_cell_network_count, network_count)
	_print_river_diagnostic_count("4+ Cells", four_plus_network_count, network_count)
	_print_river_diagnostic_count("8+ Cells", eight_plus_network_count, network_count)
	_print_river_diagnostic_count("16+ Cells", size_bucket_counts["16+ Cells"], network_count)

	var outlet_counts := {
		"OCEAN": 0,
		"LAKE": 0,
		"CLOSED_BASIN": 0,
		"LAND_SINK": 0,
		"INVALID / NO_DOWNSTREAM": 0,
	}
	var boundary_outlet_count := 0
	var abnormal_samples: Array[Dictionary] = []
	var abnormal_sample_keys := {}
	for network_id in network_count:
		var network: HydrologyRiverNetwork = formal_hydrology.river_networks[network_id]
		var outlet := _trace_river_network_outlet(network)
		var outlet_type: String = outlet.type
		outlet_counts[outlet_type] += 1
		if bool(outlet.boundary_exit):
			boundary_outlet_count += 1
		if outlet_type == "LAND_SINK" or outlet_type == "INVALID / NO_DOWNSTREAM":
			_append_river_abnormal_sample(
				abnormal_samples,
				abnormal_sample_keys,
				network.mouth_cell,
				network_id,
				outlet_type
			)
	print("  River Network Outlet Type:")
	for outlet_type in [
		"OCEAN", "LAKE", "CLOSED_BASIN", "LAND_SINK", "INVALID / NO_DOWNSTREAM"
	]:
		_print_river_diagnostic_count(outlet_type, outlet_counts[outlet_type], network_count)
	print("    OCEAN formal World Boundary exits: %d" % boundary_outlet_count)
	var abnormal_outlet_count: int = outlet_counts["LAND_SINK"] \
			+ outlet_counts["INVALID / NO_DOWNSTREAM"]
	print("  Abnormal Outlet Count: %d" % abnormal_outlet_count)

	var river_has_upstream := PackedByteArray()
	river_has_upstream.resize(formal_hydrology.cell_count())
	for cell_id in formal_hydrology.cell_count():
		if not formal_hydrology.is_river(cell_id):
			continue
		var downstream_id := formal_hydrology.flow_to[cell_id]
		if downstream_id >= 0 \
				and downstream_id < formal_hydrology.cell_count() \
				and formal_hydrology.is_river(downstream_id):
			river_has_upstream[downstream_id] = 1
	var continuity_counts := {
		"CONTINUES": 0,
		"VALID_OCEAN_EXIT": 0,
		"VALID_LAKE_EXIT": 0,
		"VALID_CLOSED_BASIN_EXIT": 0,
		"RIVER_TO_NON_RIVER_LAND": 0,
		"INVALID_FLOW_END": 0,
	}
	var source_accumulation := PackedFloat32Array()
	for cell_id in formal_hydrology.cell_count():
		if not formal_hydrology.is_river(cell_id):
			continue
		if river_has_upstream[cell_id] == 0:
			source_accumulation.append(formal_hydrology.flow_accumulation[cell_id])
		var continuity_type := _river_continuity_type(cell_id)
		continuity_counts[continuity_type] += 1
		if continuity_type == "RIVER_TO_NON_RIVER_LAND" \
				or continuity_type == "INVALID_FLOW_END":
			_append_river_abnormal_sample(
				abnormal_samples,
				abnormal_sample_keys,
				cell_id,
				formal_hydrology.river_network_id[cell_id],
				continuity_type
			)
	print("  River Continuity Diagnostics:")
	for continuity_type in [
		"CONTINUES",
		"VALID_OCEAN_EXIT",
		"VALID_LAKE_EXIT",
		"VALID_CLOSED_BASIN_EXIT",
		"RIVER_TO_NON_RIVER_LAND",
		"INVALID_FLOW_END",
	]:
		_print_river_diagnostic_count(
			continuity_type, continuity_counts[continuity_type], river_cell_count
		)

	source_accumulation.sort()
	var source_statistics := _soil_continuous_statistics(source_accumulation)
	var river_threshold := formal_hydrology.settings.river_runoff_threshold
	var source_within_110_percent := 0
	var source_within_125_percent := 0
	for accumulation in source_accumulation:
		if accumulation <= river_threshold * 1.10:
			source_within_110_percent += 1
		if accumulation <= river_threshold * 1.25:
			source_within_125_percent += 1
	print("  River Source Diagnostics:")
	print("    River Threshold: %.4f" % river_threshold)
	print("    Source Cell Count: %d" % source_accumulation.size())
	print(
		"    Accumulation: Min %.4f | Mean %.4f | P25 %.4f | P50 %.4f"
		% [
			source_statistics.min,
			source_statistics.mean,
			source_statistics.p25,
			source_statistics.p50,
		]
	)
	print(
		"    Accumulation: P75 %.4f | P90 %.4f | Max %.4f"
		% [source_statistics.p75, source_statistics.p90, source_statistics.max]
	)
	_print_river_diagnostic_count(
		"Sources <= 1.10x Threshold", source_within_110_percent, source_accumulation.size()
	)
	_print_river_diagnostic_count(
		"Sources <= 1.25x Threshold", source_within_125_percent, source_accumulation.size()
	)

	var strahler_one_sizes := PackedFloat32Array()
	var strahler_two_sizes := PackedFloat32Array()
	var strahler_three_plus_sizes := PackedFloat32Array()
	for network_id in network_count:
		var network: HydrologyRiverNetwork = formal_hydrology.river_networks[network_id]
		var network_size := cells_by_network[network_id].size()
		if network.order <= 1:
			strahler_one_sizes.append(network_size)
		elif network.order == 2:
			strahler_two_sizes.append(network_size)
		else:
			strahler_three_plus_sizes.append(network_size)
	print("  Strahler / Network Size:")
	_print_strahler_network_statistics("Strahler 1", strahler_one_sizes)
	_print_strahler_network_statistics("Strahler 2", strahler_two_sizes)
	_print_strahler_network_statistics("Strahler 3+", strahler_three_plus_sizes)
	print("    Max Strahler Order: %d" % _formal_hydrology_statistics.max_river_order)
	_print_river_abnormal_samples(abnormal_samples)
	_print_short_river_network_diagnostics(cells_by_network)


func _print_short_river_network_diagnostics(
		cells_by_network: Array[PackedInt32Array]
) -> void:
	var cell_count := formal_hydrology.cell_count()
	var upstream_by_cell: Array[PackedInt32Array] = []
	for cell_id in cell_count:
		upstream_by_cell.append(PackedInt32Array())
	for cell_id in cell_count:
		var downstream_id := formal_hydrology.flow_to[cell_id]
		if downstream_id < 0 or downstream_id >= cell_count:
			continue
		var upstream_cells: PackedInt32Array = upstream_by_cell[downstream_id]
		upstream_cells.append(cell_id)
		upstream_by_cell[downstream_id] = upstream_cells

	# Reuse Formal Hydrology's watershed assignment instead of rebuilding catchments.
	var watershed_cell_counts := PackedInt32Array()
	watershed_cell_counts.resize(formal_hydrology.watershed_count)
	for cell_id in cell_count:
		if terrain.terrain_height[cell_id] < 0.0:
			continue
		var watershed_id := formal_hydrology.watershed_id[cell_id]
		if watershed_id >= 0 and watershed_id < watershed_cell_counts.size():
			watershed_cell_counts[watershed_id] += 1

	var records_by_size := {
		"1 Cell": [],
		"2~3 Cells": [],
		"4~7 Cells": [],
		"8+ Cells": [],
	}
	var river_threshold := formal_hydrology.settings.river_runoff_threshold
	for network_id in formal_hydrology.river_networks.size():
		var network: HydrologyRiverNetwork = formal_hydrology.river_networks[network_id]
		var network_size := cells_by_network[network_id].size()
		var size_group := _short_river_size_group(network_size)
		var source_cell := network.source_cell
		var mouth_cell := network.mouth_cell
		var non_river_upstream_length := _main_non_river_upstream_length(
			source_cell, upstream_by_cell
		)
		var total_path_length := network_size + non_river_upstream_length
		var source_accumulation := formal_hydrology.flow_accumulation[source_cell]
		var watershed_id := formal_hydrology.watershed_id[mouth_cell]
		var basin_cell_count := watershed_cell_counts[watershed_id] \
				if watershed_id >= 0 and watershed_id < watershed_cell_counts.size() else 0
		var outlet := _trace_river_network_outlet(network)
		records_by_size[size_group].append({
			"network_id": network_id,
			"network_size": network_size,
			"max_strahler": network.order,
			"source_accumulation": source_accumulation,
			"source_threshold_ratio": source_accumulation / river_threshold \
					if river_threshold > 0.0 else 0.0,
			"outlet_accumulation": formal_hydrology.flow_accumulation[mouth_cell],
			"discharge": network.discharge,
			"non_river_upstream_length": non_river_upstream_length,
			"total_path_length": total_path_length,
			"upstream_extension_ratio": float(non_river_upstream_length) \
					/ float(maxi(total_path_length, 1)),
			"basin_cell_count": basin_cell_count,
			"outlet_type": outlet.type,
		})

	print("  Short River Network Diagnostics:")
	print("    Basin Cell Count reuses land-cell counts grouped by formal watershed_id.")
	for size_group in ["1 Cell", "2~3 Cells", "4~7 Cells", "8+ Cells"]:
		_print_short_river_size_group(size_group, records_by_size[size_group])


func _short_river_size_group(network_size: int) -> String:
	if network_size == 1:
		return "1 Cell"
	if network_size <= 3:
		return "2~3 Cells"
	if network_size <= 7:
		return "4~7 Cells"
	return "8+ Cells"


func _main_non_river_upstream_length(
		source_cell: int,
		upstream_by_cell: Array[PackedInt32Array]
) -> int:
	if source_cell < 0 or source_cell >= formal_hydrology.cell_count():
		return 0
	var visited := PackedByteArray()
	visited.resize(formal_hydrology.cell_count())
	visited[source_cell] = 1
	var current_cell := source_cell
	var length := 0
	for step in formal_hydrology.cell_count():
		var predecessor := -1
		var maximum_accumulation := -INF
		for upstream_id in upstream_by_cell[current_cell]:
			var accumulation := formal_hydrology.flow_accumulation[upstream_id]
			if predecessor < 0 or accumulation > maximum_accumulation:
				predecessor = upstream_id
				maximum_accumulation = accumulation
		if predecessor < 0 \
				or terrain.terrain_height[predecessor] < 0.0 \
				or surface_water.lake_id[predecessor] >= 0 \
				or formal_hydrology.is_river(predecessor) \
				or visited[predecessor] != 0:
			break
		visited[predecessor] = 1
		length += 1
		current_cell = predecessor
	return length


func _print_short_river_size_group(size_group: String, records: Array) -> void:
	print("    %s Networks: %d" % [size_group, records.size()])
	var outlet_accumulations := PackedFloat32Array()
	var discharges := PackedFloat32Array()
	var upstream_lengths := PackedFloat32Array()
	var total_lengths := PackedFloat32Array()
	var extension_ratios := PackedFloat32Array()
	var source_threshold_ratios := PackedFloat32Array()
	var basin_cell_counts := PackedFloat32Array()
	var source_ratio_counts := {
		"<= 1.10x": 0,
		"<= 1.25x": 0,
		"<= 1.50x": 0,
		"> 1.50x": 0,
	}
	for record in records:
		outlet_accumulations.append(record.outlet_accumulation)
		discharges.append(record.discharge)
		upstream_lengths.append(record.non_river_upstream_length)
		total_lengths.append(record.total_path_length)
		extension_ratios.append(record.upstream_extension_ratio)
		source_threshold_ratios.append(record.source_threshold_ratio)
		basin_cell_counts.append(record.basin_cell_count)
		if record.source_threshold_ratio <= 1.10:
			source_ratio_counts["<= 1.10x"] += 1
		if record.source_threshold_ratio <= 1.25:
			source_ratio_counts["<= 1.25x"] += 1
		if record.source_threshold_ratio <= 1.50:
			source_ratio_counts["<= 1.50x"] += 1
		else:
			source_ratio_counts["> 1.50x"] += 1
	_print_river_full_statistics("Outlet Accumulation", outlet_accumulations)
	_print_river_full_statistics("Outlet Discharge", discharges)
	_print_river_full_statistics("Non-river Upstream Length", upstream_lengths)
	_print_river_full_statistics("Total Main Drainage Path Length", total_lengths)
	_print_river_ratio_statistics("Upstream Extension Ratio", extension_ratios)
	_print_river_ratio_statistics("Source / Threshold Ratio", source_threshold_ratios)
	for label in ["<= 1.10x", "<= 1.25x", "<= 1.50x", "> 1.50x"]:
		_print_river_diagnostic_count(
			"Source / Threshold %s" % label, source_ratio_counts[label], records.size()
		)
	_print_river_basin_statistics(basin_cell_counts)
	_print_short_river_samples(records)


func _print_river_full_statistics(label: String, values: PackedFloat32Array) -> void:
	var statistics := _soil_continuous_statistics(values)
	print(
		"      %s: Min %.4f | Mean %.4f | P25 %.4f | P50 %.4f | P75 %.4f | P90 %.4f | Max %.4f"
		% [
			label,
			statistics.min,
			statistics.mean,
			statistics.p25,
			statistics.p50,
			statistics.p75,
			statistics.p90,
			statistics.max,
		]
	)


func _print_river_ratio_statistics(label: String, values: PackedFloat32Array) -> void:
	var statistics := _soil_continuous_statistics(values)
	print(
		"      %s: Mean %.4f | P25 %.4f | P50 %.4f | P75 %.4f | P90 %.4f"
		% [
			label,
			statistics.mean,
			statistics.p25,
			statistics.p50,
			statistics.p75,
			statistics.p90,
		]
	)


func _print_river_basin_statistics(values: PackedFloat32Array) -> void:
	var statistics := _soil_continuous_statistics(values)
	print(
		"      Basin Cell Count: Mean %.4f | P50 %.4f | P75 %.4f | P90 %.4f | Max %.4f"
		% [
			statistics.mean,
			statistics.p50,
			statistics.p75,
			statistics.p90,
			statistics.max,
		]
	)


func _print_short_river_samples(records: Array) -> void:
	var sorted_records := records.duplicate()
	sorted_records.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if first.non_river_upstream_length == second.non_river_upstream_length:
			return first.network_id < second.network_id
		return first.non_river_upstream_length < second.non_river_upstream_length
	)
	var sample_count := mini(sorted_records.size(), 5)
	print("      Representative Samples: %d (max 5)" % sample_count)
	for sample_index in sample_count:
		var record_index := 0 if sample_count <= 1 else roundi(
			float(sample_index) * float(sorted_records.size() - 1) / float(sample_count - 1)
		)
		var record: Dictionary = sorted_records[record_index]
		print(
			"        Network %d | River Cells %d | Max Strahler %d | Outlet %s"
			% [record.network_id, record.network_size, record.max_strahler, record.outlet_type]
		)
		print(
			"          Source Acc %.4f | Source/Threshold %.4f | Outlet Acc %.4f"
			% [
				record.source_accumulation,
				record.source_threshold_ratio,
				record.outlet_accumulation,
			]
		)
		print(
			"          Non-river Upstream %d | Total Path %d | Basin Cells %d"
			% [
				record.non_river_upstream_length,
				record.total_path_length,
				record.basin_cell_count,
			]
		)


func _trace_river_network_outlet(network: HydrologyRiverNetwork) -> Dictionary:
	var current_cell := network.mouth_cell
	var visited := PackedByteArray()
	visited.resize(formal_hydrology.cell_count())
	while true:
		if current_cell < 0 or current_cell >= formal_hydrology.cell_count():
			return {
				"type": "INVALID / NO_DOWNSTREAM",
				"terminal_cell": current_cell,
				"boundary_exit": false,
			}
		if visited[current_cell] != 0:
			return {
				"type": "INVALID / NO_DOWNSTREAM",
				"terminal_cell": current_cell,
				"boundary_exit": false,
			}
		visited[current_cell] = 1
		if surface_water.lake_id[current_cell] >= 0:
			return {"type": "LAKE", "terminal_cell": current_cell, "boundary_exit": false}
		if terrain.terrain_height[current_cell] < 0.0:
			return {"type": "OCEAN", "terminal_cell": current_cell, "boundary_exit": false}
		var downstream_id := formal_hydrology.flow_to[current_cell]
		if downstream_id >= 0:
			if downstream_id >= formal_hydrology.cell_count():
				return {
					"type": "INVALID / NO_DOWNSTREAM",
					"terminal_cell": current_cell,
					"boundary_exit": false,
				}
			current_cell = downstream_id
			continue
		if downstream_id == WorldHydrologyLayer.FLOW_TO_CLOSED_BASIN \
				and hydrology.closed_basin_id[current_cell] >= 0:
			return {
				"type": "CLOSED_BASIN",
				"terminal_cell": current_cell,
				"boundary_exit": false,
			}
		if downstream_id == WorldHydrologyLayer.FLOW_TO_BOUNDARY:
			return {"type": "OCEAN", "terminal_cell": current_cell, "boundary_exit": true}
		if downstream_id == HydrologyFlowResult.FLOW_TO_SINK:
			return {"type": "LAND_SINK", "terminal_cell": current_cell, "boundary_exit": false}
		return {
			"type": "INVALID / NO_DOWNSTREAM",
			"terminal_cell": current_cell,
			"boundary_exit": false,
		}
	return {"type": "INVALID / NO_DOWNSTREAM", "terminal_cell": -1, "boundary_exit": false}


func _river_continuity_type(cell_id: int) -> String:
	var downstream_id := formal_hydrology.flow_to[cell_id]
	if downstream_id >= 0:
		if downstream_id >= formal_hydrology.cell_count():
			return "INVALID_FLOW_END"
		if surface_water.lake_id[downstream_id] >= 0:
			return "VALID_LAKE_EXIT"
		if terrain.terrain_height[downstream_id] < 0.0:
			return "VALID_OCEAN_EXIT"
		if formal_hydrology.is_river(downstream_id):
			return "CONTINUES"
		return "RIVER_TO_NON_RIVER_LAND"
	if downstream_id == WorldHydrologyLayer.FLOW_TO_BOUNDARY:
		return "VALID_OCEAN_EXIT"
	if downstream_id == WorldHydrologyLayer.FLOW_TO_CLOSED_BASIN \
			and hydrology.closed_basin_id[cell_id] >= 0:
		return "VALID_CLOSED_BASIN_EXIT"
	return "INVALID_FLOW_END"


func _print_river_diagnostic_count(label: String, count: int, total: int) -> void:
	var ratio := float(count) / float(total) * 100.0 if total > 0 else 0.0
	print("    %s: %d / %.2f%%" % [label, count, ratio])


func _print_strahler_network_statistics(label: String, sizes: PackedFloat32Array) -> void:
	var sorted_sizes := sizes.duplicate()
	sorted_sizes.sort()
	var sum := 0.0
	var maximum := 0
	for size in sizes:
		sum += size
		maximum = maxi(maximum, int(size))
	print(
		"    %s: Networks %d | Mean Cells %.4f | Median Cells %.4f | Max Cells %d"
		% [
			label,
			sizes.size(),
			sum / float(sizes.size()) if not sizes.is_empty() else 0.0,
			_percentile(sorted_sizes, 0.50),
			maximum,
		]
	)


func _append_river_abnormal_sample(
		samples: Array[Dictionary],
		sample_keys: Dictionary,
		cell_id: int,
		network_id: int,
		type: String
) -> void:
	if samples.size() >= 10 or cell_id < 0 or cell_id >= formal_hydrology.cell_count():
		return
	var key := "%s:%d" % [type, cell_id]
	if sample_keys.has(key):
		return
	sample_keys[key] = true
	samples.append({"type": type, "cell_id": cell_id, "network_id": network_id})


func _print_river_abnormal_samples(samples: Array[Dictionary]) -> void:
	print("  Abnormal Endpoint Samples: %d (max 10)" % samples.size())
	for sample in samples:
		var cell_id: int = sample.cell_id
		var downstream_id := formal_hydrology.flow_to[cell_id]
		var has_downstream := downstream_id >= 0 \
				and downstream_id < formal_hydrology.cell_count()
		print(
			"    %s | Cell %d | Network %d"
			% [sample.type, cell_id, sample.network_id]
		)
		print(
			"      Height %.4f | Accumulation %.4f | Closed Basin %s"
			% [
				terrain.terrain_height[cell_id],
				formal_hydrology.flow_accumulation[cell_id],
				"YES" if hydrology.closed_basin_id[cell_id] >= 0 else "NO",
			]
		)
		if not has_downstream:
			print("      Downstream: NONE (flow_to %d)" % downstream_id)
			continue
		print(
			"      Downstream Cell %d | Height %.4f | Accumulation %.4f"
			% [
				downstream_id,
				terrain.terrain_height[downstream_id],
				formal_hydrology.flow_accumulation[downstream_id],
			]
		)
		print(
			"      River %s | Ocean %s | Lake %s"
			% [
				"YES" if formal_hydrology.is_river(downstream_id) else "NO",
				"YES" if terrain.terrain_height[downstream_id] < 0.0 else "NO",
				"YES" if surface_water.lake_id[downstream_id] >= 0 else "NO",
			]
		)


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


func _calculate_ecology_statistics() -> Dictionary:
	var drainage_values := PackedFloat32Array()
	var moisture_values := PackedFloat32Array()
	var vegetation_values := PackedFloat32Array()
	var biome_counts := PackedInt32Array()
	biome_counts.resize(EcologyCatalog.BIOME_COUNT)
	var biome_land_counts := PackedInt32Array()
	biome_land_counts.resize(EcologyCatalog.BIOME_COUNT)
	var land_count := 0
	for cell_id in ecology.cell_count():
		var biome_id := ecology.biome_id[cell_id]
		biome_counts[biome_id] += 1
		var is_terrestrial := terrain.is_land(cell_id) and surface_water.lake_id[cell_id] < 0
		if is_terrestrial:
			land_count += 1
			biome_land_counts[biome_id] += 1
		if is_terrestrial:
			drainage_values.append(ecology.drainage_index[cell_id])
			vegetation_values.append(ecology.vegetation_potential[cell_id])
		if terrain.terrain_height[cell_id] >= 0.0:
			moisture_values.append(ecology.ecological_moisture[cell_id])
	return {
		"drainage": _continuous_statistics(drainage_values),
		"moisture": _moisture_statistics(moisture_values),
		"vegetation": _continuous_statistics(vegetation_values),
		"biome_counts": biome_counts,
		"biome_land_counts": biome_land_counts,
		"land_count": land_count,
	}


func _calculate_soil_statistics() -> Dictionary:
	var depth_values := PackedFloat32Array()
	var formation_values := PackedFloat32Array()
	var erosion_values := PackedFloat32Array()
	var deposition_values := PackedFloat32Array()
	var organic_values := PackedFloat32Array()
	var fertility_values := PackedFloat32Array()
	var texture_counts := PackedInt32Array()
	texture_counts.resize(SoilCatalog.TEXTURE_COUNT)
	var material_texture_counts: Array[PackedInt32Array] = []
	for material_id in GeologyCatalog.MATERIAL_COUNT:
		var counts := PackedInt32Array()
		counts.resize(SoilCatalog.TEXTURE_COUNT)
		material_texture_counts.append(counts)
	if soil != null:
		for cell_id in soil.cell_count():
			if _cell_has_surface_soil(cell_id):
				depth_values.append(soil.soil_depth[cell_id])
				var slope_factor := SoilGenerator.slope_factor_for(
					graph,
					terrain.terrain_height,
					cell_id,
					soil_settings.slope_reference
				)
				var climate_weathering := SoilGenerator.climate_weathering_for(
					climate.temperature[cell_id],
					climate.precipitation[cell_id],
					soil_settings.weathering_precip_reference
				)
				formation_values.append(SoilGenerator.formation_potential_for(
					SoilCatalog.weatherability_for(geology.material_id[cell_id]),
					climate_weathering
				))
				erosion_values.append(SoilGenerator.erosion_pressure_for(
					slope_factor, geology.erodibility[cell_id]
				))
				var valley_position := SoilGenerator.valley_position_for(
					graph, terrain.terrain_height, cell_id
				)
				var flow_strength := EcologyGenerator.river_strength_for(
					formal_hydrology.flow_accumulation[cell_id],
					formal_hydrology.settings.river_runoff_threshold
				)
				deposition_values.append(SoilGenerator.deposition_tendency_for(
					slope_factor, valley_position, flow_strength
				))
				organic_values.append(soil.organic_matter[cell_id])
				fertility_values.append(soil.soil_fertility[cell_id])
				var texture_id := soil.soil_texture_id[cell_id]
				texture_counts[texture_id] += 1
				material_texture_counts[geology.material_id[cell_id]][texture_id] += 1
	return {
		"depth": _soil_continuous_statistics(depth_values),
		"formation_potential": _soil_continuous_statistics(formation_values),
		"erosion_pressure": _soil_continuous_statistics(erosion_values),
		"deposition_tendency": _soil_continuous_statistics(deposition_values),
		"organic_matter": _soil_continuous_statistics(organic_values),
		"fertility": _soil_continuous_statistics(fertility_values),
		"texture_counts": texture_counts,
		"material_texture_counts": material_texture_counts,
		"land_count": depth_values.size(),
	}


func _soil_continuous_statistics(values: PackedFloat32Array) -> Dictionary:
	var statistics := _continuous_statistics(values)
	var sorted_values := values.duplicate()
	sorted_values.sort()
	statistics["p90"] = _percentile(sorted_values, 0.90)
	statistics["count"] = values.size()
	return statistics


func _cell_has_surface_soil(cell_id: int) -> bool:
	var biome_id := ecology.biome_id[cell_id]
	return biome_id != EcologyCatalog.Biome.MARINE \
			and biome_id != EcologyCatalog.Biome.LAKE \
			and biome_id != EcologyCatalog.Biome.GLACIER


func _print_soil_texture_diagnostics() -> void:
	if soil == null or _soil_statistics.is_empty():
		return
	print("Soil Material -> Texture diagnostic (%s, Seed %d):" % [template_id, seed])
	var material_texture_counts: Array = _soil_statistics.material_texture_counts
	for material_id in GeologyCatalog.MATERIAL_COUNT:
		var counts: PackedInt32Array = material_texture_counts[material_id]
		print(
			"  %s: Sandy %d | Loamy %d | Silty %d | Clayey %d"
			% [
				GeologyCatalog.material_name(material_id),
				counts[SoilCatalog.TextureType.SANDY],
				counts[SoilCatalog.TextureType.LOAMY],
				counts[SoilCatalog.TextureType.SILTY],
				counts[SoilCatalog.TextureType.CLAYEY],
			]
		)


func _print_soil_deposition_diagnostics() -> void:
	if soil == null or _soil_statistics.is_empty():
		return
	var actual_depth_values := PackedFloat32Array()
	var depth_without_deposition_values := PackedFloat32Array()
	var depth_gain_values := PackedFloat32Array()
	var actual_texture_counts := PackedInt32Array()
	actual_texture_counts.resize(SoilCatalog.TEXTURE_COUNT)
	var texture_without_deposition_counts := PackedInt32Array()
	texture_without_deposition_counts.resize(SoilCatalog.TEXTURE_COUNT)
	var shifted_finer_count := 0
	var unchanged_count := 0
	var shifted_coarser_count := 0
	for cell_id in soil.cell_count():
		if not _cell_has_surface_soil(cell_id):
			continue
		var slope_factor := SoilGenerator.slope_factor_for(
			graph, terrain.terrain_height, cell_id, soil_settings.slope_reference
		)
		var climate_weathering := SoilGenerator.climate_weathering_for(
			climate.temperature[cell_id],
			climate.precipitation[cell_id],
			soil_settings.weathering_precip_reference
		)
		var valley_position := SoilGenerator.valley_position_for(
			graph, terrain.terrain_height, cell_id
		)
		var flow_strength := EcologyGenerator.river_strength_for(
			formal_hydrology.flow_accumulation[cell_id],
			formal_hydrology.settings.river_runoff_threshold
		)
		var deposition_tendency := SoilGenerator.deposition_tendency_for(
			slope_factor, valley_position, flow_strength
		)
		if deposition_tendency < _HIGH_DEPOSITION_THRESHOLD:
			continue
		var material_id := geology.material_id[cell_id]
		var formation_potential := SoilGenerator.formation_potential_for(
			SoilCatalog.weatherability_for(material_id), climate_weathering
		)
		var erosion_pressure := SoilGenerator.erosion_pressure_for(
			slope_factor, geology.erodibility[cell_id]
		)
		var actual_depth := soil.soil_depth[cell_id]
		var depth_without_deposition := SoilGenerator.soil_depth_for(
			formation_potential, 0.0, erosion_pressure
		)
		actual_depth_values.append(actual_depth)
		depth_without_deposition_values.append(depth_without_deposition)
		depth_gain_values.append(actual_depth - depth_without_deposition)
		var actual_texture := soil.soil_texture_id[cell_id]
		var texture_without_deposition := SoilGenerator.texture_for_fineness(
			SoilGenerator.texture_fineness_for(
				SoilCatalog.parent_fineness_for(material_id), climate_weathering, 0.0
			)
		)
		actual_texture_counts[actual_texture] += 1
		texture_without_deposition_counts[texture_without_deposition] += 1
		if actual_texture > texture_without_deposition:
			shifted_finer_count += 1
		elif actual_texture == texture_without_deposition:
			unchanged_count += 1
		else:
			shifted_coarser_count += 1
	var high_deposition_count := actual_depth_values.size()
	print(
		"Soil Deposition diagnostic (%s, Seed %d, deposition >= %.2f):"
		% [template_id, seed, _HIGH_DEPOSITION_THRESHOLD]
	)
	print("  High Deposition Cell Count: %d" % high_deposition_count)
	if high_deposition_count == 0:
		return
	var actual_depth_statistics := _soil_continuous_statistics(actual_depth_values)
	var depth_without_deposition_statistics := _soil_continuous_statistics(
		depth_without_deposition_values
	)
	var depth_gain_statistics := _soil_continuous_statistics(depth_gain_values)
	_print_soil_deposition_depth_statistics("Actual Depth", actual_depth_statistics, false)
	_print_soil_deposition_depth_statistics(
		"Without Deposition", depth_without_deposition_statistics, false
	)
	_print_soil_deposition_depth_statistics("Depth Gain", depth_gain_statistics, true)
	_print_soil_deposition_texture_statistics(
		"All Land Texture", _soil_statistics.texture_counts, _soil_statistics.land_count
	)
	_print_soil_deposition_texture_statistics(
		"High Deposition Actual Texture", actual_texture_counts, high_deposition_count
	)
	_print_soil_deposition_texture_statistics(
		"High Deposition Without Deposition Texture",
		texture_without_deposition_counts,
		high_deposition_count
	)
	_print_soil_texture_shift("Shifted Finer", shifted_finer_count, high_deposition_count)
	_print_soil_texture_shift("Unchanged", unchanged_count, high_deposition_count)
	_print_soil_texture_shift("Shifted Coarser", shifted_coarser_count, high_deposition_count)
	var all_land_fine_count: int = _soil_statistics.texture_counts[SoilCatalog.TextureType.SILTY] \
			+ _soil_statistics.texture_counts[SoilCatalog.TextureType.CLAYEY]
	var high_deposition_fine_count := actual_texture_counts[SoilCatalog.TextureType.SILTY] \
			+ actual_texture_counts[SoilCatalog.TextureType.CLAYEY]
	print(
		"  All Land SILTY + CLAYEY: %.2f%%"
		% (float(all_land_fine_count) / float(_soil_statistics.land_count) * 100.0)
	)
	print(
		"  High Deposition SILTY + CLAYEY: %.2f%%"
		% (float(high_deposition_fine_count) / float(high_deposition_count) * 100.0)
	)


func _print_soil_deposition_depth_statistics(
		label: String, statistics: Dictionary, include_maximum: bool
) -> void:
	var text := "  %s: Mean %.4f | P50 %.4f | P75 %.4f" % [
		label, statistics.mean, statistics.p50, statistics.p75
	]
	if include_maximum:
		text += " | Max %.4f" % statistics.max
	print(text)


func _print_soil_deposition_texture_statistics(
		label: String, counts: PackedInt32Array, total: int
) -> void:
	print("  %s:" % label)
	for texture_id in range(SoilCatalog.TextureType.SANDY, SoilCatalog.TEXTURE_COUNT):
		print(
			"    %s: %d / %.2f%%"
			% [
				SoilCatalog.texture_name(texture_id),
				counts[texture_id],
				float(counts[texture_id]) / float(total) * 100.0,
			]
		)


func _print_soil_texture_shift(label: String, count: int, total: int) -> void:
	print("  %s: %d / %.2f%%" % [label, count, float(count) / float(total) * 100.0])


func _moisture_statistics(values: PackedFloat32Array) -> Dictionary:
	var statistics := _continuous_statistics(values)
	var sorted_values := values.duplicate()
	sorted_values.sort()
	statistics["p90"] = _percentile(sorted_values, 0.90)
	statistics["p95"] = _percentile(sorted_values, 0.95)
	statistics["land_count"] = values.size()
	statistics["count_ge_050"] = 0
	statistics["count_ge_060"] = 0
	statistics["count_ge_070"] = 0
	statistics["count_ge_072"] = 0
	for value in values:
		if value >= 0.50:
			statistics["count_ge_050"] += 1
		if value >= 0.60:
			statistics["count_ge_060"] += 1
		if value >= 0.70:
			statistics["count_ge_070"] += 1
		if value >= 0.72:
			statistics["count_ge_072"] += 1
	return statistics


func _continuous_statistics(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {"min": 0.0, "max": 0.0, "mean": 0.0, "p25": 0.0, "p50": 0.0, "p75": 0.0}
	var minimum := INF
	var maximum := -INF
	var sum := 0.0
	for value in values:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
		sum += value
	var sorted_values := values.duplicate()
	sorted_values.sort()
	return {
		"min": minimum,
		"max": maximum,
		"mean": sum / float(values.size()),
		"p25": _percentile(sorted_values, 0.25),
		"p50": _percentile(sorted_values, 0.50),
		"p75": _percentile(sorted_values, 0.75),
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
		ViewMode.DRAINAGE:
			return "Drainage"
		ViewMode.ECOLOGICAL_MOISTURE:
			return "Ecological Moisture"
		ViewMode.VEGETATION_POTENTIAL:
			return "Vegetation Potential"
		ViewMode.BIOME:
			return "Biome"
		ViewMode.SOIL_DEPTH:
			return "Soil Depth"
		ViewMode.SOIL_TEXTURE:
			return "Soil Texture"
		ViewMode.ORGANIC_MATTER:
			return "Organic Matter"
		ViewMode.SOIL_FERTILITY:
			return "Soil Fertility"
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


func _is_ecology_view() -> bool:
	return view_mode == ViewMode.DRAINAGE \
			or view_mode == ViewMode.ECOLOGICAL_MOISTURE \
			or view_mode == ViewMode.VEGETATION_POTENTIAL \
			or view_mode == ViewMode.BIOME


func _is_soil_view() -> bool:
	return view_mode == ViewMode.SOIL_DEPTH \
			or view_mode == ViewMode.SOIL_TEXTURE \
			or view_mode == ViewMode.ORGANIC_MATTER \
			or view_mode == ViewMode.SOIL_FERTILITY


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
