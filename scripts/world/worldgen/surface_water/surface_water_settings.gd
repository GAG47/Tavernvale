class_name SurfaceWaterSettings
extends RefCounted

## SpatialGraph world-area units. At the standard 2000 x 1000 / 20000 Cell
## resolution this is approximately two average Cells.
var minimum_lake_area: float = 200.0

## Relative long-term loss units per world-area unit.
var minimum_loss_per_area: float = 1.0
var minimum_evaporation_rate: float = 4.0
var maximum_evaporation_rate: float = 24.0
var minimum_infiltration_rate: float = 2.0
var maximum_infiltration_rate: float = 28.0

## Fixed temperature anchors; never derived from a generated world's extrema.
var evaporation_temperature_min: float = -20.0
var evaporation_temperature_max: float = 35.0


func _init(
		minimum_area: float = 200.0,
		minimum_loss: float = 1.0,
		minimum_evaporation: float = 4.0,
		maximum_evaporation: float = 24.0,
		minimum_infiltration: float = 2.0,
		maximum_infiltration: float = 28.0,
		temperature_minimum: float = -20.0,
		temperature_maximum: float = 35.0
) -> void:
	minimum_lake_area = minimum_area
	minimum_loss_per_area = minimum_loss
	minimum_evaporation_rate = minimum_evaporation
	maximum_evaporation_rate = maximum_evaporation
	minimum_infiltration_rate = minimum_infiltration
	maximum_infiltration_rate = maximum_infiltration
	evaporation_temperature_min = temperature_minimum
	evaporation_temperature_max = temperature_maximum


func evaporation_rate(temperature: float) -> float:
	var normalized := clampf(
		(temperature - evaporation_temperature_min)
				/ (evaporation_temperature_max - evaporation_temperature_min),
		0.0,
		1.0
	)
	var smooth := normalized * normalized * (3.0 - 2.0 * normalized)
	return lerpf(minimum_evaporation_rate, maximum_evaporation_rate, smooth)


func infiltration_rate(permeability: float) -> float:
	return lerpf(
		minimum_infiltration_rate,
		maximum_infiltration_rate,
		clampf(permeability, 0.0, 1.0)
	)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(minimum_lake_area) or minimum_lake_area < 0.0:
		errors.append("minimum_lake_area must be finite and non-negative")
	if not is_finite(minimum_loss_per_area) or minimum_loss_per_area <= 0.0:
		errors.append("minimum_loss_per_area must be finite and positive")
	if not is_finite(minimum_evaporation_rate) or minimum_evaporation_rate < 0.0:
		errors.append("minimum_evaporation_rate must be finite and non-negative")
	if not is_finite(maximum_evaporation_rate) \
			or maximum_evaporation_rate < minimum_evaporation_rate:
		errors.append("maximum_evaporation_rate must be finite and at least the minimum")
	if not is_finite(minimum_infiltration_rate) or minimum_infiltration_rate < 0.0:
		errors.append("minimum_infiltration_rate must be finite and non-negative")
	if not is_finite(maximum_infiltration_rate) \
			or maximum_infiltration_rate < minimum_infiltration_rate:
		errors.append("maximum_infiltration_rate must be finite and at least the minimum")
	if not is_finite(evaporation_temperature_min) \
			or not is_finite(evaporation_temperature_max) \
			or evaporation_temperature_max <= evaporation_temperature_min:
		errors.append("evaporation temperature anchors must be finite and strictly increasing")
	return errors


func duplicate_settings() -> SurfaceWaterSettings:
	return SurfaceWaterSettings.new(
		minimum_lake_area,
		minimum_loss_per_area,
		minimum_evaporation_rate,
		maximum_evaporation_rate,
		minimum_infiltration_rate,
		maximum_infiltration_rate,
		evaporation_temperature_min,
		evaporation_temperature_max
	)
