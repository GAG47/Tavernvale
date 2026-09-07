class_name ArcaneResourcePotentialSettings
extends RefCounted

var rare_arcane_noise_seed_salt: int = 0x52415245
var rare_arcane_concentration_scale: float = 4.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(rare_arcane_concentration_scale) \
			or rare_arcane_concentration_scale <= 0.0:
		errors.append("rare_arcane_concentration_scale must be finite and positive")
	return errors


func duplicate_settings() -> ArcaneResourcePotentialSettings:
	var result := ArcaneResourcePotentialSettings.new()
	result.rare_arcane_noise_seed_salt = rare_arcane_noise_seed_salt
	result.rare_arcane_concentration_scale = rare_arcane_concentration_scale
	return result
