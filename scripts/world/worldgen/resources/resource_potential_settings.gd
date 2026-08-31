class_name ResourcePotentialSettings
extends RefCounted

## Stable independent noise channels. Adding another resource must not shift either seed.
var base_metal_noise_seed_salt: int = 0x42415345 # "BASE"
var precious_mineral_noise_seed_salt: int = 0x50524543 # "PREC"

## Number of coherent noise coordinate units across each normalized world axis.
var base_metal_concentration_scale: float = 3.0
var precious_mineral_concentration_scale: float = 4.0


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
	return errors


func duplicate_settings() -> ResourcePotentialSettings:
	var result := ResourcePotentialSettings.new()
	result.base_metal_noise_seed_salt = base_metal_noise_seed_salt
	result.precious_mineral_noise_seed_salt = precious_mineral_noise_seed_salt
	result.base_metal_concentration_scale = base_metal_concentration_scale
	result.precious_mineral_concentration_scale = precious_mineral_concentration_scale
	return result
