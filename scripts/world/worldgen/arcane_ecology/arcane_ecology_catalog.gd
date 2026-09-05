class_name ArcaneEcologyCatalog
extends RefCounted

enum State { NORMAL = 0, INFLUENCED = 1, DOMINANT = 2 }
enum ResponseProfile { STABLE_ACCUMULATION = 0, CIRCULATING_EXCHANGE = 1, FLUCTUATION_ADAPTATION = 2 }
enum NaturalEcologyGroup { WOODLAND, OPEN_VEGETATION, WETLAND, BARREN_EXTREME, AQUATIC }
enum Band { LOW, MEDIUM, HIGH }

const NO_RESPONSE_PROFILE := -1
const GROUP_COUNT := 5
const PROFILE_COUNT := 3
const STATE_COUNT := 3


static func natural_group_for_biome(biome_id: int) -> int:
	match biome_id:
		EcologyCatalog.Biome.TAIGA, EcologyCatalog.Biome.TEMPERATE_FOREST, \
		EcologyCatalog.Biome.TEMPERATE_RAINFOREST, EcologyCatalog.Biome.TROPICAL_SEASONAL_FOREST, \
		EcologyCatalog.Biome.TROPICAL_RAINFOREST:
			return NaturalEcologyGroup.WOODLAND
		EcologyCatalog.Biome.TUNDRA, EcologyCatalog.Biome.GRASSLAND, EcologyCatalog.Biome.SAVANNA:
			return NaturalEcologyGroup.OPEN_VEGETATION
		EcologyCatalog.Biome.WETLAND:
			return NaturalEcologyGroup.WETLAND
		EcologyCatalog.Biome.GLACIER, EcologyCatalog.Biome.COLD_DESERT, EcologyCatalog.Biome.HOT_DESERT:
			return NaturalEcologyGroup.BARREN_EXTREME
		EcologyCatalog.Biome.LAKE, EcologyCatalog.Biome.MARINE:
			return NaturalEcologyGroup.AQUATIC
	return -1


static func state_name(state: int) -> String:
	return State.keys()[state] if state >= 0 and state < STATE_COUNT else "Unknown"


static func response_profile_name(profile: int) -> String:
	if profile == NO_RESPONSE_PROFILE:
		return "NO_RESPONSE_PROFILE"
	return ResponseProfile.keys()[profile] if profile >= 0 and profile < PROFILE_COUNT else "Unknown"


static func natural_group_name(group: int) -> String:
	return NaturalEcologyGroup.keys()[group] if group >= 0 and group < GROUP_COUNT else "Unknown"
