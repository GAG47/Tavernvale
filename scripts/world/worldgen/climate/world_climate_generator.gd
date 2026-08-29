class_name WorldClimateGenerator
extends RefCounted

## Azgaar's relative precipitation modifier for each absolute 5-degree band.
const _LATITUDE_MODIFIER := [
	4.0, 2.0, 2.0, 2.0, 1.0, 1.0, 2.0, 2.0, 2.0,
	2.0, 3.0, 3.0, 2.0, 2.0, 1.0, 1.0, 1.0, 0.5,
]
const _MAX_PASSABLE_AZGAAR_HEIGHT := 85.0
const _CLIMATE_SALT := 0x434c494d # "CLIM"


static func generate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		settings: WorldClimateSettings = null
) -> WorldClimateLayer:
	if graph == null or graph.config == null:
		push_error("WorldClimateGenerator: SpatialGraph is null or incomplete")
		return null
	if terrain == null:
		push_error("WorldClimateGenerator: TerrainHeightLayer is null")
		return null
	if terrain.cell_count() != graph.cell_count():
		push_error(
			"WorldClimateGenerator: terrain_height length %d does not match Cell Count %d"
			% [terrain.cell_count(), graph.cell_count()]
		)
		return null
	if graph.columns <= 0 or graph.rows <= 0 or graph.columns * graph.rows != graph.cell_count():
		push_error("WorldClimateGenerator: SpatialGraph row-major dimensions are incomplete")
		return null

	var resolved_settings := WorldClimateSettings.new() if settings == null else settings
	var setting_errors := resolved_settings.validate()
	if not setting_errors.is_empty():
		push_error("WorldClimateGenerator: invalid settings: " + "; ".join(setting_errors))
		return null

	var layer := WorldClimateLayer.new()
	layer.settings = resolved_settings.duplicate_settings()
	layer.temperature.resize(graph.cell_count())
	for cell_id in graph.cell_count():
		var latitude := latitude_at(cell_id, graph, resolved_settings)
		layer.temperature[cell_id] = temperature_at(
			latitude, terrain.terrain_height[cell_id], resolved_settings
		)
	layer.precipitation = _generate_precipitation(
		graph,
		terrain,
		resolved_settings,
		DeterministicRng.new(_climate_seed(graph.config.seed))
	)
	return layer


static func latitude_at(
		cell_id: int, graph: SpatialGraph, settings: WorldClimateSettings
) -> float:
	return latitude_at_y(
		graph.cell_centers[cell_id].y, graph.config.world_height, settings
	)


static func latitude_at_y(
		y: float, world_height: float, settings: WorldClimateSettings
) -> float:
	var normalized_y := clampf(y / world_height, 0.0, 1.0)
	return lerpf(settings.latitude_north, settings.latitude_south, normalized_y)


static func temperature_at(
		latitude: float, terrain_height: float, settings: WorldClimateSettings
) -> float:
	var sea_level_temperature := _sea_level_temperature(latitude, settings)
	var altitude_drop := 0.0
	if terrain_height >= 0.0:
		var azgaar_height := _azgaar_height_from_terrain(terrain_height)
		var virtual_altitude := pow(azgaar_height - 18.0, settings.height_exponent)
		altitude_drop = virtual_altitude / 1000.0 * 6.5
	return clampf(sea_level_temperature - altitude_drop, -128.0, 127.0)


static func _sea_level_temperature(
		latitude: float, settings: WorldClimateSettings
) -> float:
	const NORTH_TROPIC := 16.0
	const SOUTH_TROPIC := -20.0
	const TROPICAL_GRADIENT := 0.15
	var north_tropic_temperature := (
		settings.equator_temperature - NORTH_TROPIC * TROPICAL_GRADIENT
	)
	var northern_gradient := (
		(north_tropic_temperature - settings.north_pole_temperature)
		/ (90.0 - NORTH_TROPIC)
	)
	var south_tropic_temperature := (
		settings.equator_temperature + SOUTH_TROPIC * TROPICAL_GRADIENT
	)
	var southern_gradient := (
		(south_tropic_temperature - settings.south_pole_temperature)
		/ (90.0 + SOUTH_TROPIC)
	)
	if latitude <= NORTH_TROPIC and latitude >= SOUTH_TROPIC:
		return settings.equator_temperature - absf(latitude) * TROPICAL_GRADIENT
	if latitude > 0.0:
		return north_tropic_temperature - (latitude - NORTH_TROPIC) * northern_gradient
	return south_tropic_temperature + (latitude - SOUTH_TROPIC) * southern_gradient


static func _generate_precipitation(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		settings: WorldClimateSettings,
		rng: DeterministicRng
) -> PackedFloat32Array:
	var precipitation := PackedFloat32Array()
	precipitation.resize(graph.cell_count())
	var cell_count_modifier := pow(float(graph.cell_count()) / 10000.0, 0.25)
	var modifier := cell_count_modifier * settings.precipitation_modifier
	if modifier <= 0.0:
		return precipitation

	var winds := _get_winds(graph, settings)
	var westerly: Array = winds.westerly
	var easterly: Array = winds.easterly
	if not westerly.is_empty():
		_pass_wind(
			westerly, 120.0 * modifier, 1, graph.columns,
			terrain, precipitation, modifier, rng
		)
	if not easterly.is_empty():
		_pass_wind(
			easterly, 120.0 * modifier, -1, graph.columns,
			terrain, precipitation, modifier, rng
		)

	var northerly := int(winds.northerly)
	var southerly := int(winds.southerly)
	var vertical_total := northerly + southerly
	if northerly > 0:
		var north_modifier := _edge_latitude_modifier(
			settings.latitude_north, settings.latitude_north - settings.latitude_south
		)
		var north_max := float(northerly) / vertical_total * 60.0 * modifier * north_modifier
		var north_sources: Array = []
		for column in graph.columns:
			north_sources.append(column)
		_pass_wind(
			north_sources, north_max, graph.columns, graph.rows,
			terrain, precipitation, modifier, rng
		)
	if southerly > 0:
		var south_modifier := _edge_latitude_modifier(
			settings.latitude_south, settings.latitude_north - settings.latitude_south
		)
		var south_max := float(southerly) / vertical_total * 60.0 * modifier * south_modifier
		var south_sources: Array = []
		var last_row_start := graph.cell_count() - graph.columns
		for column in graph.columns:
			south_sources.append(last_row_start + column)
		_pass_wind(
			south_sources, south_max, -graph.columns, graph.rows,
			terrain, precipitation, modifier, rng
		)
	return precipitation


static func _get_winds(graph: SpatialGraph, settings: WorldClimateSettings) -> Dictionary:
	var westerly: Array = []
	var easterly: Array = []
	var northerly := 0
	var southerly := 0
	for row in graph.rows:
		var first_cell_id := row * graph.columns
		var latitude := latitude_at(first_cell_id, graph, settings)
		var latitude_modifier := _latitude_modifier(latitude)
		var tier := clampi(int(absf(latitude - 89.0) / 30.0), 0, 5)
		var angle := fposmod(settings.wind_bands[tier], 360.0)
		if angle > 40.0 and angle < 140.0:
			westerly.append({"first": first_cell_id, "latitude_modifier": latitude_modifier})
		if angle > 220.0 and angle < 320.0:
			easterly.append({
				"first": first_cell_id + graph.columns - 1,
				"latitude_modifier": latitude_modifier,
			})
		if angle > 100.0 and angle < 260.0:
			northerly += 1
		if angle > 280.0 or angle < 80.0:
			southerly += 1
	return {
		"westerly": westerly,
		"easterly": easterly,
		"northerly": northerly,
		"southerly": southerly,
	}


static func _pass_wind(
		sources: Array,
		initial_max_precipitation: float,
		next_offset: int,
		steps: int,
		terrain: TerrainHeightLayer,
		precipitation: PackedFloat32Array,
		modifier: float,
		rng: DeterministicRng
) -> void:
	for source in sources:
		var first: int
		var max_precipitation := initial_max_precipitation
		if source is Dictionary:
			first = int(source.first)
			# Preserve Azgaar's legacy behavior for a horizontal band starting at Cell 0.
			if first == 0:
				continue
			max_precipitation = minf(
				initial_max_precipitation * float(source.latitude_modifier), 255.0
			)
		else:
			first = int(source)

		var humidity := max_precipitation - _azgaar_height_from_terrain(
			terrain.terrain_height[first]
		)
		if humidity <= 0.0:
			continue
		for step in steps:
			var current := first + step * next_offset
			if current < 0 or current >= terrain.cell_count():
				break
			var has_next := step + 1 < steps
			var next_cell := current + next_offset if has_next else -1
			if not terrain.is_land(current):
				if has_next and terrain.is_land(next_cell):
					var coastal_divisor := float(_random_integer(rng, 10, 20))
					precipitation[next_cell] += maxf(humidity / coastal_divisor, 1.0)
				else:
					humidity = minf(humidity + 5.0 * modifier, max_precipitation)
					precipitation[current] += 5.0 * modifier
				continue

			var is_passable := (
				has_next
				and _azgaar_height_from_terrain(terrain.terrain_height[next_cell])
					<= _MAX_PASSABLE_AZGAAR_HEIGHT
			)
			var precipitation_amount := humidity
			if is_passable:
				precipitation_amount = _land_precipitation(
					humidity,
					terrain.terrain_height[current],
					terrain.terrain_height[next_cell],
					modifier
				)
			precipitation[current] += precipitation_amount
			var evaporation := 1.0 if precipitation_amount > 1.5 else 0.0
			humidity = (
				clampf(humidity - precipitation_amount + evaporation, 0.0, max_precipitation)
				if is_passable else 0.0
			)


static func _land_precipitation(
		humidity: float,
		current_terrain_height: float,
		next_terrain_height: float,
		modifier: float
) -> float:
	var current_height := _azgaar_height_from_terrain(current_terrain_height)
	var next_height := _azgaar_height_from_terrain(next_terrain_height)
	var normal_loss := maxf(humidity / (10.0 * modifier), 1.0)
	var height_difference := maxf(next_height - current_height, 0.0)
	var orographic_modifier := pow(next_height / 70.0, 2.0)
	return minf(maxf(normal_loss + height_difference * orographic_modifier, 1.0), humidity)


static func _azgaar_height_from_terrain(terrain_height: float) -> float:
	if terrain_height < 0.0:
		return 20.0 + terrain_height / 5.0
	return 20.0 + terrain_height / 1.25


static func _latitude_modifier(latitude: float) -> float:
	var band := clampi(int((absf(latitude) - 1.0) / 5.0), 0, _LATITUDE_MODIFIER.size() - 1)
	return _LATITUDE_MODIFIER[band]


static func _edge_latitude_modifier(latitude: float, latitude_span: float) -> float:
	if latitude_span <= 60.0:
		return _latitude_modifier(latitude)
	var sum := 0.0
	for modifier in _LATITUDE_MODIFIER:
		sum += modifier
	return sum / _LATITUDE_MODIFIER.size()


static func _random_integer(rng: DeterministicRng, minimum: int, maximum: int) -> int:
	return minimum + mini(int(rng.next_float() * float(maximum - minimum + 1)), maximum - minimum)


static func _climate_seed(world_seed: int) -> int:
	const MASK := 0x7fffffff
	var value := (world_seed & MASK) ^ _CLIMATE_SALT
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & MASK
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & MASK
	value = (value ^ (value >> 16)) & MASK
	return value if value != 0 else 1
