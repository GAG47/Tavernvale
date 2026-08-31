class_name ResourcePotentialValidator
extends RefCounted


static func validate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		surface_water: SurfaceWaterLayer,
		resources: ResourcePotentialLayer,
		settings: ResourcePotentialSettings = null
) -> PackedStringArray:
	var errors := PackedStringArray()
	var actual_settings := settings if settings != null else ResourcePotentialSettings.new()
	if graph == null or terrain == null or surface_water == null or resources == null:
		errors.append("Resource Potential validation requires all pipeline inputs and a ResourcePotentialLayer")
		return errors
	var count := graph.cell_count()
	var arrays := _named_arrays(resources)
	for entry in arrays:
		if entry[1].size() != count:
			errors.append("%s must contain one value per Cell" % entry[0])
	if terrain.terrain_height.size() != count \
			or surface_water.lake_id.size() != count \
			or graph.cell_neighbors.size() != count:
		errors.append("Resource Potential validation inputs must contain one value per Cell")
	errors.append_array(actual_settings.validate())
	if not errors.is_empty():
		return errors
	for cell_id in count:
		for entry in arrays:
			var value: float = entry[1][cell_id]
			if not is_finite(value) or value < 0.0 or value > 1.0:
				errors.append("%s[%d] must be finite and inside [0, 1]" % [entry[0], cell_id])
		var is_ocean := terrain.terrain_height[cell_id] < 0.0
		var is_lake := surface_water.lake_id[cell_id] >= 0
		if is_ocean or is_lake:
			for land_entry in arrays.slice(0, 6):
				if land_entry[1][cell_id] != 0.0:
					errors.append("Ocean and Lake Cell %d must have no terrestrial Resource Potential" % cell_id)
					break
		if is_ocean and resources.freshwater_aquatic_potential[cell_id] != 0.0:
			errors.append("Ocean Cell %d must have no Freshwater Aquatic Potential" % cell_id)
		if not is_ocean and resources.coastal_aquatic_potential[cell_id] != 0.0:
			errors.append("Non-ocean Cell %d must have no Coastal Aquatic Potential" % cell_id)
		elif is_ocean \
				and not ResourcePotentialGenerator.is_coastal_ocean_cell(graph, terrain, cell_id) \
				and resources.coastal_aquatic_potential[cell_id] != 0.0:
			errors.append("Non-coastal Ocean Cell %d must have no Coastal Aquatic Potential" % cell_id)
		if is_ocean and ResourcePotentialGenerator.is_coastal_ocean_cell(graph, terrain, cell_id):
			var shelf_suitability := ResourcePotentialGenerator.shelf_suitability_for(
				terrain.terrain_height[cell_id], actual_settings
			)
			if not is_finite(shelf_suitability) \
					or shelf_suitability < 0.0 or shelf_suitability > 1.0:
				errors.append("Coastal Ocean Cell %d has invalid shelf suitability" % cell_id)
	return errors


static func _named_arrays(resources: ResourcePotentialLayer) -> Array:
	return [
		["agriculture_potential", resources.agriculture_potential],
		["timber_potential", resources.timber_potential],
		["forage_potential", resources.forage_potential],
		["construction_stone_potential", resources.construction_stone_potential],
		["base_metal_potential", resources.base_metal_potential],
		["precious_mineral_potential", resources.precious_mineral_potential],
		["freshwater_aquatic_potential", resources.freshwater_aquatic_potential],
		["coastal_aquatic_potential", resources.coastal_aquatic_potential],
	]
