class_name GeologyCatalog
extends RefCounted

enum Province {
	OCEANIC_CRUST,
	CRATON,
	OROGENIC_BELT,
	SEDIMENTARY_BASIN,
	PASSIVE_MARGIN,
	VOLCANIC_PROVINCE,
}

enum MaterialType {
	CRYSTALLINE_ROCK,
	METAMORPHIC_ROCK,
	SANDSTONE,
	SHALE_MUDSTONE,
	CARBONATE_ROCK,
	VOLCANIC_ROCK,
	MARINE_SEDIMENTARY_ROCK,
}

const PROVINCE_COUNT := 6
const MATERIAL_COUNT := 7


static func province_name(province_id: int) -> String:
	match province_id:
		Province.OCEANIC_CRUST:
			return "Oceanic Crust"
		Province.CRATON:
			return "Craton"
		Province.OROGENIC_BELT:
			return "Orogenic Belt"
		Province.SEDIMENTARY_BASIN:
			return "Sedimentary Basin"
		Province.PASSIVE_MARGIN:
			return "Passive Margin"
		Province.VOLCANIC_PROVINCE:
			return "Volcanic Province"
		_:
			return "Unknown Province"


static func material_name(material_id: int) -> String:
	match material_id:
		MaterialType.CRYSTALLINE_ROCK:
			return "Crystalline Rock"
		MaterialType.METAMORPHIC_ROCK:
			return "Metamorphic Rock"
		MaterialType.SANDSTONE:
			return "Sandstone"
		MaterialType.SHALE_MUDSTONE:
			return "Shale / Mudstone"
		MaterialType.CARBONATE_ROCK:
			return "Carbonate Rock"
		MaterialType.VOLCANIC_ROCK:
			return "Volcanic Rock"
		MaterialType.MARINE_SEDIMENTARY_ROCK:
			return "Marine Sedimentary Rock"
		_:
			return "Unknown Material"


static func material_weights(province_id: int) -> PackedFloat32Array:
	match province_id:
		Province.OCEANIC_CRUST:
			return PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.70, 0.30])
		Province.CRATON:
			return PackedFloat32Array([0.60, 0.25, 0.08, 0.04, 0.03, 0.0, 0.0])
		Province.OROGENIC_BELT:
			return PackedFloat32Array([0.30, 0.40, 0.08, 0.07, 0.0, 0.15, 0.0])
		Province.SEDIMENTARY_BASIN:
			return PackedFloat32Array([0.05, 0.0, 0.40, 0.35, 0.20, 0.0, 0.0])
		Province.PASSIVE_MARGIN:
			return PackedFloat32Array([0.05, 0.0, 0.35, 0.30, 0.25, 0.05, 0.0])
		Province.VOLCANIC_PROVINCE:
			return PackedFloat32Array([0.20, 0.10, 0.05, 0.05, 0.0, 0.60, 0.0])
		_:
			return PackedFloat32Array()


static func permeability_for(material_id: int) -> float:
	match material_id:
		MaterialType.CRYSTALLINE_ROCK:
			return 0.15
		MaterialType.METAMORPHIC_ROCK:
			return 0.12
		MaterialType.SANDSTONE:
			return 0.65
		MaterialType.SHALE_MUDSTONE:
			return 0.12
		MaterialType.CARBONATE_ROCK:
			return 0.80
		MaterialType.VOLCANIC_ROCK:
			return 0.40
		MaterialType.MARINE_SEDIMENTARY_ROCK:
			return 0.45
		_:
			return 0.0


static func erodibility_for(material_id: int) -> float:
	match material_id:
		MaterialType.CRYSTALLINE_ROCK:
			return 0.15
		MaterialType.METAMORPHIC_ROCK:
			return 0.18
		MaterialType.SANDSTONE:
			return 0.55
		MaterialType.SHALE_MUDSTONE:
			return 0.75
		MaterialType.CARBONATE_ROCK:
			return 0.45
		MaterialType.VOLCANIC_ROCK:
			return 0.30
		MaterialType.MARINE_SEDIMENTARY_ROCK:
			return 0.60
		_:
			return 0.0
