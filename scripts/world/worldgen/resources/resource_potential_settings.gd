class_name ResourcePotentialSettings
extends RefCounted

## Stable independent noise channels. Adding another resource must not shift either seed.
var base_metal_noise_seed_salt: int = 0x42415345 # "BASE"
var precious_mineral_noise_seed_salt: int = 0x50524543 # "PREC"

## Number of coherent noise coordinate units across each normalized world axis.
var base_metal_concentration_scale: float = 3.0
var precious_mineral_concentration_scale: float = 4.0

## Resource-specific transfer scales; these do not change upstream Terrain or Ecology.
var coastal_shallow_shelf_depth: float = 20.0
var coastal_deep_shelf_depth: float = 60.0
var forage_vegetation_low: float = 0.10
var forage_vegetation_full: float = 0.50


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if base_metal_noise_seed_salt == precious_mineral_noise_seed_salt:
		errors.append("Base Metal and Precious Mineral noise salts must be distinct")
	if not is_finite(base_metal_concentration_scale) \
			or base_metal_concentration_scale <= 0.0:
		errors.append("base_metal_concentration_scale must be finite and positive")
	if not is_finite(precious_mineral_concentration_scale) \
			or precious_mineral_concentration_scale <= 0.0:
		errors.append("precious_mineral_concentration_scale must be finite and positive")
	if not is_finite(coastal_shallow_shelf_depth) or coastal_shallow_shelf_depth < 0.0:
		errors.append("coastal_shallow_shelf_depth must be finite and non-negative")
	if not is_finite(coastal_deep_shelf_depth) \
			or coastal_deep_shelf_depth <= coastal_shallow_shelf_depth:
		errors.append("coastal_deep_shelf_depth must be finite and greater than shallow depth")
	if not is_finite(forage_vegetation_low) or forage_vegetation_low < 0.0 \
			or forage_vegetation_low >= 1.0:
		errors.append("forage_vegetation_low must be finite and inside [0, 1)")
	if not is_finite(forage_vegetation_full) \
			or forage_vegetation_full <= forage_vegetation_low \
			or forage_vegetation_full > 1.0:
		errors.append("forage_vegetation_full must be greater than low and at most 1")
	return errors


func duplicate_settings() -> ResourcePotentialSettings:
	var result := ResourcePotentialSettings.new()
	result.base_metal_noise_seed_salt = base_metal_noise_seed_salt
	result.precious_mineral_noise_seed_salt = precious_mineral_noise_seed_salt
	result.base_metal_concentration_scale = base_metal_concentration_scale
	result.precious_mineral_concentration_scale = precious_mineral_concentration_scale
	result.coastal_shallow_shelf_depth = coastal_shallow_shelf_depth
	result.coastal_deep_shelf_depth = coastal_deep_shelf_depth
	result.forage_vegetation_low = forage_vegetation_low
	result.forage_vegetation_full = forage_vegetation_full
	return result
