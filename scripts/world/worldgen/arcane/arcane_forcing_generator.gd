class_name ArcaneForcingGenerator
extends RefCounted

const FORCING_SEED_SALT := 0x46524345 # "FRCE"
const _TWO_PI := PI * 2.0

static var _last_generation_diagnostics := {}


static func generate(
		graph: SpatialGraph,
		world_seed: int,
		settings: ArcaneForcingSettings = null
) -> ArcaneForcingLayer:
	_last_generation_diagnostics = {}
	var actual_settings := settings if settings != null else ArcaneForcingSettings.new()
	if graph == null or graph.config == null:
		push_error("ArcaneForcingGenerator: SpatialGraph/config is null")
		return null
	var settings_errors := actual_settings.validate()
	if not settings_errors.is_empty():
		push_error("ArcaneForcingGenerator: invalid settings: " + "; ".join(settings_errors))
		return null
	var world_width := graph.config.world_width
	var world_height := graph.config.world_height
	var generation_rect := Rect2(
		Vector2(
			-actual_settings.forcing_generation_margin,
			-actual_settings.forcing_generation_margin
		),
		Vector2(
			world_width + actual_settings.forcing_generation_margin * 2.0,
			world_height + actual_settings.forcing_generation_margin * 2.0
		)
	)
	var sampling_started := Time.get_ticks_usec()
	var sampled_positions := sample_positions(
		world_seed,
		generation_rect,
		actual_settings.forcing_min_separation,
		actual_settings.forcing_poisson_k
	)
	var sites := build_sites(
		world_seed,
		sampled_positions,
		world_width,
		world_height,
		actual_settings
	)
	var sampling_ms := _elapsed_ms(sampling_started)
	var projection_started := Time.get_ticks_usec()
	var layer := ArcaneForcingLayer.new()
	layer.sites = sites
	project_rates(graph, layer, actual_settings)
	var projection_ms := _elapsed_ms(projection_started)
	var validation_errors := ArcaneForcingValidator.validate(graph, layer)
	if not validation_errors.is_empty():
		push_error("Arcane Forcing validation failed: " + "; ".join(validation_errors))
		return null
	_last_generation_diagnostics = ArcaneForcingValidator.statistics(graph, layer)
	_last_generation_diagnostics["performance"] = {
		"sampling_ms": sampling_ms,
		"projection_ms": projection_ms,
		"total_ms": sampling_ms + projection_ms,
	}
	_last_generation_diagnostics["parameters"] = {
		"forcing_min_separation": actual_settings.forcing_min_separation,
		"forcing_poisson_k": actual_settings.forcing_poisson_k,
		"forcing_generation_margin": actual_settings.forcing_generation_margin,
		"forcing_core_radius": actual_settings.forcing_core_radius,
		"forcing_total_power": actual_settings.forcing_total_power,
	}
	return layer


static func last_generation_diagnostics() -> Dictionary:
	return _last_generation_diagnostics.duplicate(true)


static func sample_positions(
		world_seed: int,
		generation_rect: Rect2,
		minimum_separation: float,
		candidate_count: int
) -> Array[Vector2]:
	var forcing_seed := DeterministicRng.stable_mix(world_seed, FORCING_SEED_SALT)
	var rng := DeterministicRng.new(forcing_seed)
	var cell_size := minimum_separation / sqrt(2.0)
	var columns := maxi(1, ceili(generation_rect.size.x / cell_size))
	var rows := maxi(1, ceili(generation_rect.size.y / cell_size))
	var grid := PackedInt32Array()
	grid.resize(columns * rows)
	grid.fill(-1)
	var positions := PackedVector2Array()
	var active := PackedInt32Array()
	var first := generation_rect.position + Vector2(
		rng.next_float() * generation_rect.size.x,
		rng.next_float() * generation_rect.size.y
	)
	_add_position(first, positions, active, grid, columns, cell_size, generation_rect)
	var separation_squared := minimum_separation * minimum_separation
	while not active.is_empty():
		var active_slot := mini(floori(rng.next_float() * active.size()), active.size() - 1)
		var source := positions[active[active_slot]]
		var accepted := false
		for attempt in candidate_count:
			var angle := rng.next_float() * _TWO_PI
			var radius := minimum_separation * (1.0 + rng.next_float())
			var candidate := source + Vector2(cos(angle), sin(angle)) * radius
			if not generation_rect.has_point(candidate):
				continue
			if not _candidate_is_clear(
				candidate, positions, grid, columns, rows, cell_size,
				generation_rect, separation_squared
			):
				continue
			_add_position(
				candidate, positions, active, grid, columns, cell_size, generation_rect
			)
			accepted = true
			break
		if not accepted:
			active.remove_at(active_slot)
	var sorted_positions: Array[Vector2] = []
	for position in positions:
		sorted_positions.append(position)
	sorted_positions.sort_custom(_position_less)
	return sorted_positions


static func build_sites(
		world_seed: int,
		sampled_positions: Array[Vector2],
		world_width: float,
		world_height: float,
		settings: ArcaneForcingSettings
) -> Array[ArcaneForcingSite]:
	var sites: Array[ArcaneForcingSite] = []
	var forcing_seed := DeterministicRng.stable_mix(world_seed, FORCING_SEED_SALT)
	for sampled_id in sampled_positions.size():
		var position := sampled_positions[sampled_id]
		if not circle_intersects_world(
			position, settings.forcing_core_radius, world_width, world_height
		):
			continue
		var identity_seed := DeterministicRng.stable_mix(forcing_seed, sampled_id + 1)
		identity_seed = DeterministicRng.stable_mix(
			identity_seed, roundi(position.x * 1000.0)
		)
		identity_seed = DeterministicRng.stable_mix(
			identity_seed, roundi(position.y * 1000.0)
		)
		var polarity_rng := DeterministicRng.new(identity_seed)
		var kind := ArcaneForcingSite.Kind.SOURCE \
				if polarity_rng.next_float() < 0.5 else ArcaneForcingSite.Kind.SINK
		sites.append(ArcaneForcingSite.new(
			sites.size(), position, kind,
			settings.forcing_core_radius, settings.forcing_total_power
		))
	return sites


static func project_rates(
		graph: SpatialGraph,
		layer: ArcaneForcingLayer,
		_settings: ArcaneForcingSettings
) -> void:
	layer.source_rate.resize(graph.cell_count())
	layer.sink_rate.resize(graph.cell_count())
	for site in layer.sites:
		for cell_id in graph.cell_count():
			var distance := graph.cell_centers[cell_id].distance_to(site.world_position)
			var density := site_rate_density(distance, site.core_radius, site.total_power)
			if density <= 0.0:
				continue
			if site.kind == ArcaneForcingSite.Kind.SOURCE:
				layer.source_rate[cell_id] += density
			else:
				layer.sink_rate[cell_id] += density


static func site_influence(distance: float, radius: float) -> float:
	if distance >= radius:
		return 0.0
	var u := clampf(1.0 - distance / radius, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


static func kernel_normalization(core_radius: float) -> float:
	return 0.3 * PI * core_radius * core_radius


static func site_rate_density(
		distance: float, core_radius: float, total_power: float
) -> float:
	return total_power * site_influence(distance, core_radius) \
			/ kernel_normalization(core_radius)


static func projected_base_power(
		graph: SpatialGraph, site: ArcaneForcingSite
) -> float:
	var power := 0.0
	for cell_id in graph.cell_count():
		power += graph.cell_areas[cell_id] * site_rate_density(
			graph.cell_centers[cell_id].distance_to(site.world_position),
			site.core_radius,
			site.total_power
		)
	return power


static func circle_intersects_world(
		center: Vector2, radius: float, world_width: float, world_height: float
) -> bool:
	var closest := Vector2(
		clampf(center.x, 0.0, world_width),
		clampf(center.y, 0.0, world_height)
	)
	return center.distance_squared_to(closest) <= radius * radius


static func _add_position(
		position: Vector2,
		positions: PackedVector2Array,
		active: PackedInt32Array,
		grid: PackedInt32Array,
		columns: int,
		cell_size: float,
		generation_rect: Rect2
) -> void:
	var position_id := positions.size()
	positions.append(position)
	active.append(position_id)
	var coordinate := _grid_coordinate(position, cell_size, generation_rect)
	grid[coordinate.y * columns + coordinate.x] = position_id


static func _candidate_is_clear(
		candidate: Vector2,
		positions: PackedVector2Array,
		grid: PackedInt32Array,
		columns: int,
		rows: int,
		cell_size: float,
		generation_rect: Rect2,
		separation_squared: float
) -> bool:
	var coordinate := _grid_coordinate(candidate, cell_size, generation_rect)
	for y in range(maxi(0, coordinate.y - 2), mini(rows - 1, coordinate.y + 2) + 1):
		for x in range(maxi(0, coordinate.x - 2), mini(columns - 1, coordinate.x + 2) + 1):
			var position_id := grid[y * columns + x]
			if position_id >= 0 and candidate.distance_squared_to(
				positions[position_id]
			) < separation_squared:
				return false
	return true


static func _grid_coordinate(
		position: Vector2, cell_size: float, generation_rect: Rect2
) -> Vector2i:
	var relative := position - generation_rect.position
	return Vector2i(
		floori(relative.x / cell_size),
		floori(relative.y / cell_size)
	)


static func _position_less(first: Vector2, second: Vector2) -> bool:
	return first.x < second.x or (first.x == second.x and first.y < second.y)


static func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0
