class_name GeologyValidator
extends RefCounted


static func validate(
		graph: SpatialGraph,
		terrain: TerrainHeightLayer,
		geology: GeologyLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or terrain == null or geology == null:
		errors.append("Spatial, terrain, and GeologyLayer must not be null")
		return errors
	var count := graph.cell_count()
	if count == 0 \
			or terrain.cell_count() != count \
			or geology.province_id.size() != count \
			or geology.material_id.size() != count \
			or geology.permeability.size() != count \
			or geology.erodibility.size() != count:
		errors.append("all Geology arrays must contain one value per Cell")
		return errors
	for cell_id in count:
		var province := geology.province_id[cell_id]
		var material := geology.material_id[cell_id]
		if province < 0 or province >= GeologyCatalog.PROVINCE_COUNT:
			errors.append("province_id[%d] is invalid" % cell_id)
		if material < 0 or material >= GeologyCatalog.MATERIAL_COUNT:
			errors.append("material_id[%d] is invalid" % cell_id)
		if terrain.terrain_height[cell_id] < 0.0 \
				and province != GeologyCatalog.Province.OCEANIC_CRUST:
			errors.append("Ocean Cell %d must use Oceanic Crust" % cell_id)
		if terrain.terrain_height[cell_id] >= 0.0 \
				and province == GeologyCatalog.Province.OCEANIC_CRUST:
			errors.append("Land Cell %d must use a continental Province" % cell_id)
		var permeability := geology.permeability[cell_id]
		var erodibility := geology.erodibility[cell_id]
		if not is_finite(permeability) or permeability < 0.0 or permeability > 1.0:
			errors.append("permeability[%d] must be finite and inside [0, 1]" % cell_id)
		if not is_finite(erodibility) or erodibility < 0.0 or erodibility > 1.0:
			errors.append("erodibility[%d] must be finite and inside [0, 1]" % cell_id)
		if material >= 0 and material < GeologyCatalog.MATERIAL_COUNT:
			if not is_equal_approx(permeability, GeologyCatalog.permeability_for(material)):
				errors.append("permeability[%d] does not match its Material lookup" % cell_id)
			if not is_equal_approx(erodibility, GeologyCatalog.erodibility_for(material)):
				errors.append("erodibility[%d] does not match its Material lookup" % cell_id)
	return errors
