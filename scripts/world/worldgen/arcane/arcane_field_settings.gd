class_name ArcaneFieldSettings
extends RefCounted

var mana_feature_scale: float = 800.0
var stability_feature_scale: float = 500.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(mana_feature_scale) or mana_feature_scale <= 0.0:
		errors.append("mana_feature_scale must be finite and positive")
	if not is_finite(stability_feature_scale) or stability_feature_scale <= 0.0:
		errors.append("stability_feature_scale must be finite and positive")
	return errors


func duplicate_settings() -> ArcaneFieldSettings:
	var result := ArcaneFieldSettings.new()
	result.mana_feature_scale = mana_feature_scale
	result.stability_feature_scale = stability_feature_scale
	return result
