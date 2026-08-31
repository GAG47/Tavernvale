class_name EcologyCatalog
extends RefCounted

enum Biome {
	MARINE,
	LAKE,
	GLACIER,
	TUNDRA,
	COLD_DESERT,
	HOT_DESERT,
	GRASSLAND,
	SAVANNA,
	TAIGA,
	TEMPERATE_FOREST,
	TEMPERATE_RAINFOREST,
	TROPICAL_SEASONAL_FOREST,
	TROPICAL_RAINFOREST,
	WETLAND,
}

enum TemperatureBand {
	VERY_COLD,
	COOL,
	TEMPERATE,
	WARM,
	HOT,
}

enum MoistureBand {
	ARID,
	DRY,
	MODERATE,
	HUMID,
	WET,
}

const BIOME_COUNT := 14

const BIOME_NAMES := [
	"Marine",
	"Lake",
	"Glacier",
	"Tundra",
	"Cold Desert",
	"Hot Desert",
	"Grassland",
	"Savanna",
	"Taiga",
	"Temperate Forest",
	"Temperate Rainforest",
	"Tropical Seasonal Forest",
	"Tropical Rainforest",
	"Wetland",
]

## Rows are TemperatureBand; columns are MoistureBand.
const BIOME_MATRIX := [
	[Biome.COLD_DESERT, Biome.TUNDRA, Biome.TUNDRA, Biome.TUNDRA, Biome.TUNDRA],
	[Biome.COLD_DESERT, Biome.GRASSLAND, Biome.TAIGA, Biome.TAIGA, Biome.TAIGA],
	[
		Biome.COLD_DESERT,
		Biome.GRASSLAND,
		Biome.TEMPERATE_FOREST,
		Biome.TEMPERATE_FOREST,
		Biome.TEMPERATE_RAINFOREST,
	],
	[
		Biome.HOT_DESERT,
		Biome.SAVANNA,
		Biome.TROPICAL_SEASONAL_FOREST,
		Biome.TROPICAL_SEASONAL_FOREST,
		Biome.TROPICAL_RAINFOREST,
	],
	[
		Biome.HOT_DESERT,
		Biome.SAVANNA,
		Biome.SAVANNA,
		Biome.TROPICAL_SEASONAL_FOREST,
		Biome.TROPICAL_RAINFOREST,
	],
]


static func temperature_band(temperature: float) -> int:
	if temperature < 2.0:
		return TemperatureBand.VERY_COLD
	if temperature < 8.0:
		return TemperatureBand.COOL
	if temperature < 20.0:
		return TemperatureBand.TEMPERATE
	if temperature < 28.0:
		return TemperatureBand.WARM
	return TemperatureBand.HOT


static func moisture_band(moisture: float) -> int:
	if moisture < 0.15:
		return MoistureBand.ARID
	if moisture < 0.30:
		return MoistureBand.DRY
	if moisture < 0.50:
		return MoistureBand.MODERATE
	if moisture < 0.67:
		return MoistureBand.HUMID
	return MoistureBand.WET


static func matrix_biome(temperature: float, moisture: float) -> int:
	return BIOME_MATRIX[temperature_band(temperature)][moisture_band(moisture)]


static func biome_name(biome_id: int) -> String:
	if biome_id < 0 or biome_id >= BIOME_COUNT:
		return "Unknown"
	return BIOME_NAMES[biome_id]
