class_name TectonicPlateValidator
extends RefCounted


static func validate(
		graph: SpatialGraph,
		plates: TectonicPlateLayer,
		settings: TectonicPlateSettings
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or plates == null or settings == null:
		errors.append("SpatialGraph, TectonicPlateLayer, and Settings must not be null")
		return errors
	var count := graph.cell_count()
	if count <= 0 or plates.plate_id.size() != count:
		errors.append("plate_id must contain one value per Cell")
		return errors
	if plates.plate_velocity.size() != settings.plate_count:
		errors.append("plate_velocity must contain one value per configured plate")
		return errors
	if graph.cell_neighbors.size() != count:
		errors.append("SpatialGraph must contain neighbors for every Cell")
		return errors
	var cells_by_plate: Array = []
	cells_by_plate.resize(settings.plate_count)
	for plate_id in settings.plate_count:
		cells_by_plate[plate_id] = PackedInt32Array()
		var velocity := plates.plate_velocity[plate_id]
		var speed := velocity.length()
		if not is_finite(velocity.x) or not is_finite(velocity.y):
			errors.append("plate_velocity[%d] must be finite" % plate_id)
		elif speed < settings.velocity_min_final_speed - 0.000001 \
				or speed > settings.velocity_max_final_speed + 0.000001:
			errors.append("plate_velocity[%d] speed is outside the final range" % plate_id)
	for cell_id in count:
		var plate_id := plates.plate_id[cell_id]
		if plate_id < 0 or plate_id >= settings.plate_count:
			errors.append("plate_id[%d] is invalid" % cell_id)
			continue
		cells_by_plate[plate_id].append(cell_id)
	for plate_id in settings.plate_count:
		var cells: PackedInt32Array = cells_by_plate[plate_id]
		if cells.is_empty():
			errors.append("plate %d must contain at least one Cell" % plate_id)
			continue
		if not _cells_are_connected(graph, cells):
			errors.append("plate %d Cells must form one connected component" % plate_id)
	return errors


static func _cells_are_connected(graph: SpatialGraph, cells: PackedInt32Array) -> bool:
	var allowed := {}
	for cell_id in cells:
		allowed[cell_id] = true
	var reached := {cells[0]: true}
	var queue := PackedInt32Array([cells[0]])
	var queue_index := 0
	while queue_index < queue.size():
		var cell_id := queue[queue_index]
		queue_index += 1
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if allowed.has(neighbor_id) and not reached.has(neighbor_id):
				reached[neighbor_id] = true
				queue.append(neighbor_id)
	return reached.size() == cells.size()
