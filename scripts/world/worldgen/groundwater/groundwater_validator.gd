class_name GroundwaterValidator
extends RefCounted


static func validate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		surface_water: SurfaceWaterLayer,
		groundwater: GroundwaterLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or terrain == null or surface_water == null or groundwater == null:
		errors.append("Spatial, Final Terrain, Surface Water, and Groundwater must not be null")
		return errors
	var count := graph.cell_count()
	if terrain.terrain_height.size() != count \
			or surface_water.lake_id.size() != count \
			or groundwater.groundwater_supply.size() != count \
			or groundwater.water_table_z.size() != count \
			or groundwater.groundwater_salinity_class.size() != count:
		errors.append("all Groundwater arrays must contain one value per Cell")
		return errors
	if groundwater.settings == null:
		errors.append("Groundwater settings must not be null")
		return errors
	var settings_errors := groundwater.settings.validate()
	if not settings_errors.is_empty():
		errors.append_array(settings_errors)
		return errors
	for cell_id in count:
		var supply := groundwater.groundwater_supply[cell_id]
		var water_table_z := groundwater.water_table_z[cell_id]
		var salinity := groundwater.groundwater_salinity_class[cell_id]
		var terrain_z := terrain.terrain_height[cell_id]
		if not is_finite(supply) or supply < 0.0 or supply > 1.0:
			errors.append("groundwater_supply[%d] must be finite and inside [0, 1]" % cell_id)
		if not is_finite(water_table_z) or water_table_z > terrain_z:
			errors.append("water_table_z[%d] must be finite and no higher than Terrain" % cell_id)
		if salinity < 0 or salinity >= GroundwaterLayer.SALINITY_CLASS_COUNT:
			errors.append("groundwater_salinity_class[%d] is invalid" % cell_id)
		if terrain_z < 0.0:
			if supply != 1.0 or water_table_z != terrain_z \
					or salinity != GroundwaterLayer.SalinityClass.SALINE:
				errors.append("Ocean Cell %d must be saturated at Terrain and Saline" % cell_id)
		elif surface_water.lake_id[cell_id] >= 0:
			if supply != 1.0 or water_table_z != terrain_z \
					or salinity != GroundwaterLayer.SalinityClass.FRESH:
				errors.append("Lake Cell %d must be saturated at Terrain and Fresh" % cell_id)
	return errors
