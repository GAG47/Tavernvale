class_name SoilCatalog
extends RefCounted

enum TextureType {
	NONE,
	SANDY,
	LOAMY,
	SILTY,
	CLAYEY,
}

const TEXTURE_COUNT := 5

const _PARENT_FINENESS := [0.25, 0.35, 0.15, 0.80, 0.50, 0.55, 0.70]
const _WEATHERABILITY := [0.25, 0.35, 0.45, 0.75, 0.70, 0.70, 0.60]
const _PARENT_NUTRIENT := [0.35, 0.50, 0.20, 0.65, 0.65, 0.80, 0.55]


static func texture_name(texture_id: int) -> String:
	match texture_id:
		TextureType.NONE:
			return "None"
		TextureType.SANDY:
			return "Sandy"
		TextureType.LOAMY:
			return "Loamy"
		TextureType.SILTY:
			return "Silty"
		TextureType.CLAYEY:
			return "Clayey"
		_:
			return "Unknown Texture"


static func parent_fineness_for(material_id: int) -> float:
	return _property_for(_PARENT_FINENESS, material_id)


static func weatherability_for(material_id: int) -> float:
	return _property_for(_WEATHERABILITY, material_id)


static func parent_nutrient_for(material_id: int) -> float:
	return _property_for(_PARENT_NUTRIENT, material_id)


static func _property_for(values: Array, material_id: int) -> float:
	if material_id < 0 or material_id >= GeologyCatalog.MATERIAL_COUNT:
		return 0.0
	return float(values[material_id])
