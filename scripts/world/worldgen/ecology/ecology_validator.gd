class_name EcologyValidator
extends RefCounted


static func validate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		climate: WorldClimateLayer,
		surface_water: SurfaceWaterLayer,
		ecology: EcologyLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or terrain == null or climate == null or surface_water == null \
			or ecology == null:
		errors.append("Ecology validation requires all pipeline inputs and an EcologyLayer")
		return errors
	var count := graph.cell_count()
	for entry in [
		["drainage_index", ecology.drainage_index.size()],
		["ecological_moisture", ecology.ecological_moisture.size()],
		["vegetation_potential", ecology.vegetation_potential.size()],
		["biome_id", ecology.biome_id.size()],
	]:
		if entry[1] != count:
			errors.append("%s must contain one value per Cell" % entry[0])
	if not errors.is_empty():
		return errors
	for cell_id in count:
		for entry in [
			["drainage_index", ecology.drainage_index[cell_id]],
			["ecological_moisture", ecology.ecological_moisture[cell_id]],
			["vegetation_potential", ecology.vegetation_potential[cell_id]],
		]:
			if not is_finite(entry[1]) or entry[1] < 0.0 or entry[1] > 1.0:
				errors.append("%s[%d] must be finite and inside [0, 1]" % [entry[0], cell_id])
		var biome := ecology.biome_id[cell_id]
		if biome < 0 or biome >= EcologyCatalog.BIOME_COUNT:
			errors.append("biome_id[%d] is outside the formal Biome enum" % cell_id)
			continue
		var is_ocean := terrain.terrain_height[cell_id] < 0.0
		var is_lake := surface_water.lake_id[cell_id] >= 0
		if (is_ocean or is_lake) and ecology.drainage_index[cell_id] != 0.0:
			errors.append("Ocean and Lake Cells must have drainage_index 0")
		if (is_ocean or is_lake) and ecology.vegetation_potential[cell_id] != 0.0:
			errors.append("Ocean and Lake Cells must have vegetation_potential 0")
		if is_ocean and biome != EcologyCatalog.Biome.MARINE:
			errors.append("Ocean Cells must use the Marine Biome")
		elif is_lake and biome != EcologyCatalog.Biome.LAKE:
			errors.append("Lake Cells must use the Lake Biome")
		elif not is_ocean and not is_lake \
				and climate.temperature[cell_id] <= -10.0 \
				and biome != EcologyCatalog.Biome.GLACIER:
			errors.append("Land Cells at or below -10 C must use the Glacier Biome")
	return errors
