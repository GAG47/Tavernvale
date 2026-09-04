class_name ArcaneForcingValidator
extends RefCounted


static func validate(
		graph: SpatialGraph, forcing: ArcaneForcingLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or forcing == null:
		errors.append("Arcane Forcing validation requires a SpatialGraph and ArcaneForcingLayer")
		return errors
	var count := graph.cell_count()
	if forcing.source_rate.size() != count:
		errors.append("source_rate must contain one value per Cell")
	if forcing.sink_rate.size() != count:
		errors.append("sink_rate must contain one value per Cell")
	if forcing.source_rate.size() == count:
		_validate_rates("source_rate", forcing.source_rate, errors)
	if forcing.sink_rate.size() == count:
		_validate_rates("sink_rate", forcing.sink_rate, errors)
	for site_id in forcing.sites.size():
		var site := forcing.sites[site_id]
		if site == null:
			errors.append("forcing Site %d is null" % site_id)
			continue
		if site.id != site_id:
			errors.append("forcing Site IDs must be stable and continuous")
		if not is_finite(site.world_position.x) or not is_finite(site.world_position.y):
			errors.append("forcing Site %d position must be finite" % site_id)
		if site.kind != ArcaneForcingSite.Kind.SOURCE \
				and site.kind != ArcaneForcingSite.Kind.SINK:
			errors.append("forcing Site %d kind is invalid" % site_id)
		if not is_finite(site.core_radius) or site.core_radius <= 0.0:
			errors.append("forcing Site %d core_radius must be finite and positive" % site_id)
		if not is_finite(site.total_power) or site.total_power <= 0.0:
			errors.append("forcing Site %d total_power must be finite and positive" % site_id)
		if graph.config != null and not ArcaneForcingGenerator.circle_intersects_world(
			site.world_position, site.core_radius,
			graph.config.world_width, graph.config.world_height
		):
			errors.append("forcing Site %d does not influence the formal World Extent" % site_id)
	return errors


static func statistics(
		graph: SpatialGraph, forcing: ArcaneForcingLayer
) -> Dictionary:
	if graph == null or forcing == null:
		return {}
	var source_count := 0
	var sink_count := 0
	var inside_count := 0
	var outside_count := 0
	var fully_inside_site_power := []
	for site in forcing.sites:
		if site.kind == ArcaneForcingSite.Kind.SOURCE:
			source_count += 1
		else:
			sink_count += 1
		if _is_inside_formal_world(
			site.world_position, graph.config.world_width, graph.config.world_height
		):
			inside_count += 1
		else:
			outside_count += 1
		if _core_is_fully_inside_world(
			site, graph.config.world_width, graph.config.world_height
		):
			var projected_power := ArcaneForcingGenerator.projected_base_power(graph, site)
			fully_inside_site_power.append({
				"site_id": site.id,
				"kind": site.kind,
				"projected_base_power": projected_power,
				"total_power": site.total_power,
				"error": projected_power - site.total_power,
				"relative_error": (projected_power - site.total_power) / site.total_power,
			})
	var source_affected := 0
	var sink_affected := 0
	var both_affected := 0
	for cell_id in graph.cell_count():
		var has_source := forcing.source_rate[cell_id] > 0.0
		var has_sink := forcing.sink_rate[cell_id] > 0.0
		if has_source:
			source_affected += 1
		if has_sink:
			sink_affected += 1
		if has_source and has_sink:
			both_affected += 1
	return {
		"total_sites": forcing.sites.size(),
		"sources": source_count,
		"sinks": sink_count,
		"inside_world": inside_count,
		"outside_influencing_world": outside_count,
		"core_radius": forcing.sites[0].core_radius if not forcing.sites.is_empty() else 0.0,
		"total_power": forcing.sites[0].total_power if not forcing.sites.is_empty() else 0.0,
		"source_rate": _rate_statistics(forcing.source_rate),
		"sink_rate": _rate_statistics(forcing.sink_rate),
		"source_affected_cells": _count_statistics(source_affected, graph.cell_count()),
		"sink_affected_cells": _count_statistics(sink_affected, graph.cell_count()),
		"both_affected_cells": _count_statistics(both_affected, graph.cell_count()),
		"directly_forced_cells": _count_statistics(
			source_affected + sink_affected - both_affected, graph.cell_count()
		),
		"fully_inside_site_power": fully_inside_site_power,
	}


static func _validate_rates(
		field_name: String, values: PackedFloat32Array, errors: PackedStringArray
) -> void:
	for cell_id in values.size():
		if not is_finite(values[cell_id]) or values[cell_id] < 0.0:
			errors.append("%s[%d] must be finite and non-negative" % [field_name, cell_id])


static func _is_inside_formal_world(
		position: Vector2, world_width: float, world_height: float
) -> bool:
	return position.x >= 0.0 and position.x <= world_width \
			and position.y >= 0.0 and position.y <= world_height


static func _core_is_fully_inside_world(
		site: ArcaneForcingSite, world_width: float, world_height: float
) -> bool:
	return site.world_position.x - site.core_radius >= 0.0 \
			and site.world_position.x + site.core_radius <= world_width \
			and site.world_position.y - site.core_radius >= 0.0 \
			and site.world_position.y + site.core_radius <= world_height


static func _rate_statistics(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {"min": 0.0, "mean": 0.0, "max": 0.0}
	var minimum := INF
	var maximum := -INF
	var sum := 0.0
	for value in values:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
		sum += value
	return {
		"min": minimum,
		"mean": sum / float(values.size()),
		"max": maximum,
	}


static func _count_statistics(count: int, total: int) -> Dictionary:
	return {
		"count": count,
		"percentage": 100.0 * float(count) / float(total) if total > 0 else 0.0,
	}
