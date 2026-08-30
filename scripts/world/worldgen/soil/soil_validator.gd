class_name SoilValidator
extends RefCounted


static func validate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		surface_water: SurfaceWaterLayer,
		ecology: EcologyLayer,
		soil: SoilLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or terrain == null or surface_water == null or ecology == null \
			or soil == null:
		errors.append("Soil validation requires all pipeline inputs and a SoilLayer")
		return errors
	var count := graph.cell_count()
	for entry in [
		["soil_depth", soil.soil_depth.size()],
		["soil_texture_id", soil.soil_texture_id.size()],
		["organic_matter", soil.organic_matter.size()],
		["soil_fertility", soil.soil_fertility.size()],
	]:
		if entry[1] != count:
			errors.append("%s must contain one value per Cell" % entry[0])
	if terrain.cell_count() != count \
			or surface_water.lake_id.size() != count \
			or ecology.biome_id.size() != count:
		errors.append("Soil validation inputs must contain one value per Cell")
	if not errors.is_empty():
		return errors
	for cell_id in count:
		for entry in [
			["soil_depth", soil.soil_depth[cell_id]],
			["organic_matter", soil.organic_matter[cell_id]],
			["soil_fertility", soil.soil_fertility[cell_id]],
		]:
			if not is_finite(entry[1]) or entry[1] < 0.0 or entry[1] > 1.0:
				errors.append("%s[%d] must be finite and inside [0, 1]" % [entry[0], cell_id])
		var texture_id := soil.soil_texture_id[cell_id]
		if texture_id < 0 or texture_id >= SoilCatalog.TEXTURE_COUNT:
			errors.append("soil_texture_id[%d] is outside the formal Texture enum" % cell_id)
			continue
		var biome_id := ecology.biome_id[cell_id]
		var has_no_surface_soil := biome_id == EcologyCatalog.Biome.MARINE \
				or biome_id == EcologyCatalog.Biome.LAKE \
				or biome_id == EcologyCatalog.Biome.GLACIER
		if has_no_surface_soil:
			if soil.soil_depth[cell_id] != 0.0 \
					or soil.organic_matter[cell_id] != 0.0 \
					or soil.soil_fertility[cell_id] != 0.0 \
					or texture_id != SoilCatalog.TextureType.NONE:
				errors.append("Marine, Lake, and Glacier Cell %d must have no Surface Soil" % cell_id)
		elif texture_id == SoilCatalog.TextureType.NONE:
			errors.append("ordinary land Cell %d must have a formal Soil Texture" % cell_id)
	return errors
