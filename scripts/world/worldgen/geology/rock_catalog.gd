class_name RockCatalog
extends RefCounted

enum RockCategory {
	IGNEOUS_EXTRUSIVE,
	IGNEOUS_INTRUSIVE,
	METAMORPHIC,
	SEDIMENTARY,
}

enum IgneousComposition {
	NONE,
	FELSIC,
	INTERMEDIATE,
	MAFIC,
}

enum RockType {
	GRANITE,
	DIORITE,
	GABBRO,
	RHYOLITE,
	ANDESITE,
	DACITE,
	BASALT,
	SANDSTONE,
	SHALE,
	CLAYSTONE,
	CONGLOMERATE,
	LIMESTONE,
	DOLOMITE,
	CHALK,
	CHERT,
	SLATE,
	PHYLLITE,
	SCHIST,
	GNEISS,
	MARBLE,
	QUARTZITE,
}

const ROCK_TYPE_COUNT := 21
const ROCK_CATEGORY_COUNT := 4


static func category_for(rock_type: int) -> int:
	match rock_type:
		RockType.GRANITE, RockType.DIORITE, RockType.GABBRO:
			return RockCategory.IGNEOUS_INTRUSIVE
		RockType.RHYOLITE, RockType.ANDESITE, RockType.DACITE, RockType.BASALT:
			return RockCategory.IGNEOUS_EXTRUSIVE
		RockType.SLATE, RockType.PHYLLITE, RockType.SCHIST, RockType.GNEISS, \
				RockType.MARBLE, RockType.QUARTZITE:
			return RockCategory.METAMORPHIC
		RockType.SANDSTONE, RockType.SHALE, RockType.CLAYSTONE, \
				RockType.CONGLOMERATE, RockType.LIMESTONE, RockType.DOLOMITE, \
				RockType.CHALK, RockType.CHERT:
			return RockCategory.SEDIMENTARY
	return -1


static func igneous_composition_for(rock_type: int) -> int:
	match rock_type:
		RockType.GRANITE, RockType.RHYOLITE:
			return IgneousComposition.FELSIC
		RockType.DIORITE, RockType.ANDESITE, RockType.DACITE:
			return IgneousComposition.INTERMEDIATE
		RockType.GABBRO, RockType.BASALT:
			return IgneousComposition.MAFIC
	return IgneousComposition.NONE


## Baseline effective water-transmission capacity of ordinary rock masses at World scale.
## It does not represent exceptional fracture zones or established large karst conduits.
static func permeability_for(rock_type: int) -> float:
	match rock_type:
		RockType.GRANITE: return 0.12
		RockType.DIORITE: return 0.10
		RockType.GABBRO: return 0.10
		RockType.RHYOLITE: return 0.15
		RockType.ANDESITE: return 0.20
		RockType.DACITE: return 0.18
		RockType.BASALT: return 0.45
		RockType.SANDSTONE: return 0.60
		RockType.SHALE: return 0.04
		RockType.CLAYSTONE: return 0.03
		RockType.CONGLOMERATE: return 0.50
		RockType.LIMESTONE: return 0.30
		RockType.DOLOMITE: return 0.32
		RockType.CHALK: return 0.30
		RockType.CHERT: return 0.05
		RockType.SLATE: return 0.07
		RockType.PHYLLITE: return 0.08
		RockType.SCHIST: return 0.12
		RockType.GNEISS: return 0.12
		RockType.MARBLE: return 0.20
		RockType.QUARTZITE: return 0.05
	return 0.0


## Relative ease of weathering, erosion, and scouring under equal external conditions.
static func erodibility_for(rock_type: int) -> float:
	match rock_type:
		RockType.GRANITE: return 0.18
		RockType.DIORITE: return 0.17
		RockType.GABBRO: return 0.20
		RockType.RHYOLITE: return 0.25
		RockType.ANDESITE: return 0.23
		RockType.DACITE: return 0.24
		RockType.BASALT: return 0.20
		RockType.SANDSTONE: return 0.55
		RockType.SHALE: return 0.82
		RockType.CLAYSTONE: return 0.88
		RockType.CONGLOMERATE: return 0.48
		RockType.LIMESTONE: return 0.48
		RockType.DOLOMITE: return 0.40
		RockType.CHALK: return 0.88
		RockType.CHERT: return 0.10
		RockType.SLATE: return 0.30
		RockType.PHYLLITE: return 0.38
		RockType.SCHIST: return 0.34
		RockType.GNEISS: return 0.20
		RockType.MARBLE: return 0.36
		RockType.QUARTZITE: return 0.08
	return 0.0


## General mechanical robustness of the rock or rock mass. It is not excavation time,
## cavern stability, construction quality, or Mohs hardness.
static func rock_strength_for(rock_type: int) -> float:
	match rock_type:
		RockType.GRANITE: return 0.82
		RockType.DIORITE: return 0.85
		RockType.GABBRO: return 0.88
		RockType.RHYOLITE: return 0.75
		RockType.ANDESITE: return 0.80
		RockType.DACITE: return 0.78
		RockType.BASALT: return 0.88
		RockType.SANDSTONE: return 0.45
		RockType.SHALE: return 0.28
		RockType.CLAYSTONE: return 0.20
		RockType.CONGLOMERATE: return 0.55
		RockType.LIMESTONE: return 0.55
		RockType.DOLOMITE: return 0.62
		RockType.CHALK: return 0.15
		RockType.CHERT: return 0.90
		RockType.SLATE: return 0.55
		RockType.PHYLLITE: return 0.48
		RockType.SCHIST: return 0.62
		RockType.GNEISS: return 0.80
		RockType.MARBLE: return 0.60
		RockType.QUARTZITE: return 0.95
	return 0.0


## Whether this lithology permits karst formation; true does not mean karst exists here.
static func karst_capable(rock_type: int) -> bool:
	return rock_type == RockType.LIMESTONE \
			or rock_type == RockType.DOLOMITE \
			or rock_type == RockType.CHALK \
			or rock_type == RockType.MARBLE


static func name_for(rock_type: int) -> String:
	match rock_type:
		RockType.GRANITE: return "Granite"
		RockType.DIORITE: return "Diorite"
		RockType.GABBRO: return "Gabbro"
		RockType.RHYOLITE: return "Rhyolite"
		RockType.ANDESITE: return "Andesite"
		RockType.DACITE: return "Dacite"
		RockType.BASALT: return "Basalt"
		RockType.SANDSTONE: return "Sandstone"
		RockType.SHALE: return "Shale"
		RockType.CLAYSTONE: return "Claystone"
		RockType.CONGLOMERATE: return "Conglomerate"
		RockType.LIMESTONE: return "Limestone"
		RockType.DOLOMITE: return "Dolomite"
		RockType.CHALK: return "Chalk"
		RockType.CHERT: return "Chert"
		RockType.SLATE: return "Slate"
		RockType.PHYLLITE: return "Phyllite"
		RockType.SCHIST: return "Schist"
		RockType.GNEISS: return "Gneiss"
		RockType.MARBLE: return "Marble"
		RockType.QUARTZITE: return "Quartzite"
	return "Unknown Rock"


static func is_valid_rock_type(rock_type: int) -> bool:
	return rock_type >= 0 and rock_type < ROCK_TYPE_COUNT
