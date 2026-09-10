class_name GroundwaterLayer
extends RefCounted

enum SalinityClass {
	FRESH,
	BRACKISH,
	SALINE,
}

enum AquiferClass {
	NONE,
	LIGHT,
	HEAVY,
}

const SALINITY_CLASS_COUNT := 3
const AQUIFER_CLASS_COUNT := 3

var groundwater_supply := PackedFloat32Array()
var water_table_z := PackedFloat32Array()
var groundwater_salinity_class := PackedInt32Array()
var settings: GroundwaterSettings


func cell_count() -> int:
	return groundwater_supply.size()


func water_table_depth(cell_id: int, terrain: TerrainHeightLayer) -> float:
	if terrain == null or cell_id < 0 or cell_id >= cell_count() \
			or cell_id >= terrain.terrain_height.size():
		return NAN
	return terrain.terrain_height[cell_id] - water_table_z[cell_id]


func is_below_water_table_at_z(cell_id: int, z: float) -> bool:
	return cell_id >= 0 and cell_id < water_table_z.size() \
			and is_finite(z) and z <= water_table_z[cell_id]


func active_groundwater_at_z(cell_id: int, z: float) -> float:
	if settings == null or cell_id < 0 or cell_id >= cell_count() \
			or not is_finite(z) or z > water_table_z[cell_id]:
		return 0.0
	var depth_below_water_table := water_table_z[cell_id] - z
	var depth_factor := pow(
		0.5, depth_below_water_table / settings.active_groundwater_half_depth
	)
	return groundwater_supply[cell_id] * depth_factor


func aquifer_yield_at_z(
		cell_id: int, z: float, strata: SubsurfaceStrataLayer
) -> float:
	if strata == null:
		return 0.0
	var active := active_groundwater_at_z(cell_id, z)
	if active <= 0.0:
		return 0.0
	var material_id := strata.material_at_z(cell_id, z)
	if material_id == SubsurfaceStrataLayer.NO_MATERIAL:
		return 0.0
	return clampf(active * GeologyCatalog.permeability_for(material_id), 0.0, 1.0)


func aquifer_class_at_z(
		cell_id: int, z: float, strata: SubsurfaceStrataLayer
) -> int:
	var aquifer_yield := aquifer_yield_at_z(cell_id, z, strata)
	return aquifer_class_for_yield(aquifer_yield, settings)


static func aquifer_class_for_yield(
		aquifer_yield: float, groundwater_settings: GroundwaterSettings
) -> int:
	if groundwater_settings == null \
			or aquifer_yield < groundwater_settings.light_aquifer_threshold:
		return AquiferClass.NONE
	if aquifer_yield < groundwater_settings.heavy_aquifer_threshold:
		return AquiferClass.LIGHT
	return AquiferClass.HEAVY


static func salinity_class_name(salinity_class: int) -> String:
	match salinity_class:
		SalinityClass.FRESH:
			return "Fresh"
		SalinityClass.BRACKISH:
			return "Brackish"
		SalinityClass.SALINE:
			return "Saline"
	return "Unknown"


static func aquifer_class_name(aquifer_class: int) -> String:
	match aquifer_class:
		AquiferClass.NONE:
			return "None"
		AquiferClass.LIGHT:
			return "Light"
		AquiferClass.HEAVY:
			return "Heavy"
	return "Unknown"
