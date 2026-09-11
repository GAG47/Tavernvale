class_name GeologyValidator
extends RefCounted


static func validate(
		graph: SpatialGraph,
		composition: WorldCompositionLayer,
		terrain: TerrainHeightLayer,
		geology: GeologyLayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph == null or composition == null or terrain == null or geology == null:
		errors.append("Spatial, Composition, terrain, and GeologyLayer must not be null")
		return errors
	var count := graph.cell_count()
	if count == 0 \
			or composition.continental_value.size() != count \
			or terrain.cell_count() != count \
			or geology.province_id.size() != count \
			or geology.rock_type_id.size() != count \
			or geology.permeability.size() != count \
			or geology.erodibility.size() != count:
		errors.append("all Geology arrays must contain one value per Cell")
		return errors
	if graph.cell_neighbors.size() != count:
		errors.append("Spatial neighbors must contain one entry per Cell")
		return errors
	var support := GeologyGenerator._components_by_continental_support(graph, composition)
	var support_has_land := PackedByteArray()
	support_has_land.resize(support.components.size())
	for component_id in support.components.size():
		for cell_id in support.components[component_id]:
			if terrain.terrain_height[cell_id] >= 0.0:
				support_has_land[component_id] = 1
				break
	for cell_id in count:
		var province := geology.province_id[cell_id]
		var rock_type := geology.rock_type_id[cell_id]
		var continental_value := composition.continental_value[cell_id]
		if continental_value < 0 or continental_value > 100:
			errors.append("continental_value[%d] must be inside [0, 100]" % cell_id)
		if province < 0 or province >= GeologyCatalog.PROVINCE_COUNT:
			errors.append("province_id[%d] is invalid" % cell_id)
		if not RockCatalog.is_valid_rock_type(rock_type):
			errors.append("rock_type_id[%d] is invalid" % cell_id)
		if continental_value < GeologyGenerator.CONTINENTAL_PROVINCE_SUPPORT_THRESHOLD:
			if province != GeologyCatalog.Province.OCEANIC_CRUST:
				errors.append("Cell %d below Continental Province Support must use Oceanic Crust" % cell_id)
		else:
			var component_id: int = support.component_by_cell[cell_id]
			if component_id < 0:
				errors.append("Cell %d in Continental Province Support has no component" % cell_id)
			elif support_has_land[component_id] != 0 \
					and province == GeologyCatalog.Province.OCEANIC_CRUST:
				errors.append("Cell %d in land-backed Continental Province Support must use a continental Province" % cell_id)
			elif support_has_land[component_id] == 0 \
					and province != GeologyCatalog.Province.OCEANIC_CRUST:
				errors.append("Cell %d in submerged-only support must remain Oceanic Crust" % cell_id)
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
