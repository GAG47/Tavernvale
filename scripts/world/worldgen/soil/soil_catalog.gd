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


static func parent_fineness_for(rock_type: int) -> float:
	return _parent_properties_for(rock_type).x


static func weatherability_for(rock_type: int) -> float:
	return _parent_properties_for(rock_type).y


static func parent_nutrient_for(rock_type: int) -> float:
	return _parent_properties_for(rock_type).z


static func _parent_properties_for(rock_type: int) -> Vector3:
	match rock_type:
		RockCatalog.RockType.GRANITE, RockCatalog.RockType.DIORITE, RockCatalog.RockType.GABBRO:
			return Vector3(0.25, 0.25, 0.35)
		RockCatalog.RockType.RHYOLITE, RockCatalog.RockType.ANDESITE, \
				RockCatalog.RockType.DACITE, RockCatalog.RockType.BASALT:
			return Vector3(0.55, 0.70, 0.80)
		RockCatalog.RockType.SANDSTONE, RockCatalog.RockType.CONGLOMERATE:
			return Vector3(0.15, 0.45, 0.20)
		RockCatalog.RockType.SHALE, RockCatalog.RockType.CLAYSTONE:
			return Vector3(0.80, 0.75, 0.65)
		RockCatalog.RockType.LIMESTONE, RockCatalog.RockType.DOLOMITE, \
				RockCatalog.RockType.CHALK, RockCatalog.RockType.CHERT:
			return Vector3(0.50, 0.70, 0.65)
		RockCatalog.RockType.SLATE, RockCatalog.RockType.PHYLLITE, \
				RockCatalog.RockType.SCHIST, RockCatalog.RockType.GNEISS, \
				RockCatalog.RockType.MARBLE, RockCatalog.RockType.QUARTZITE:
			return Vector3(0.35, 0.35, 0.50)
	return Vector3.ZERO
