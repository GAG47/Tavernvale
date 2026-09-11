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

const PROVINCE_COUNT := 6


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
