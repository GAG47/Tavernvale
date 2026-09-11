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
			or geology.rock_type_id.size() != count \
			or geology.permeability.size() != count \
			or geology.erodibility.size() != count:
		errors.append("all Geology arrays must contain one value per Cell")
		return errors
	for cell_id in count:
		var province := geology.province_id[cell_id]
		var rock_type := geology.rock_type_id[cell_id]
		if province < 0 or province >= GeologyCatalog.PROVINCE_COUNT:
			errors.append("province_id[%d] is invalid" % cell_id)
		if not RockCatalog.is_valid_rock_type(rock_type):
			errors.append("rock_type_id[%d] is invalid" % cell_id)
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
		if RockCatalog.is_valid_rock_type(rock_type):
			if not is_equal_approx(permeability, RockCatalog.permeability_for(rock_type)):
				errors.append("permeability[%d] does not match its RockType lookup" % cell_id)
			if not is_equal_approx(erodibility, RockCatalog.erodibility_for(rock_type)):
				errors.append("erodibility[%d] does not match its RockType lookup" % cell_id)
	return errors
