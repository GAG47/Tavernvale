class_name SubsurfaceStrataSettings
extends RefCounted

var max_layers: int = 4
var sequence_feature_scale: float = 450.0
var thickness_feature_scale: float = 300.0
var deep_crust_feature_scale: float = 800.0
var deep_crust_noise_amplitude: float = 4.0
var deep_continental_threshold: float = 14.0
var min_layer_thickness: float = 12.0
var max_layer_thickness: float = 55.0
var province_base_thickness := PackedFloat32Array([20.0, 24.0, 30.0, 36.0, 34.0, 30.0])


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if max_layers != 4:
		errors.append("max_layers must equal 4 for the v3.0.1 transition rules")
	if not is_finite(sequence_feature_scale) or sequence_feature_scale <= 0.0:
		errors.append("sequence_feature_scale must be finite and positive")
	if not is_finite(thickness_feature_scale) or thickness_feature_scale <= 0.0:
		errors.append("thickness_feature_scale must be finite and positive")
	if not is_finite(deep_crust_feature_scale) or deep_crust_feature_scale <= 0.0:
		errors.append("deep_crust_feature_scale must be finite and positive")
	if not is_finite(deep_crust_noise_amplitude) or deep_crust_noise_amplitude < 0.0:
		errors.append("deep_crust_noise_amplitude must be finite and non-negative")
	if not is_finite(deep_continental_threshold):
		errors.append("deep_continental_threshold must be finite")
	if not is_finite(min_layer_thickness) or min_layer_thickness <= 0.0:
		errors.append("min_layer_thickness must be finite and positive")
	if not is_finite(max_layer_thickness) \
			or max_layer_thickness < min_layer_thickness:
		errors.append("max_layer_thickness must be finite and at least the minimum")
	if province_base_thickness.size() != GeologyCatalog.PROVINCE_COUNT:
		errors.append("province_base_thickness must contain one value per Province")
	else:
		for province_id in GeologyCatalog.PROVINCE_COUNT:
			var thickness := province_base_thickness[province_id]
			if not is_finite(thickness) or thickness <= 0.0:
				errors.append("province_base_thickness[%d] must be finite and positive" % province_id)
	return errors


func base_thickness_for(province_id: int) -> float:
	if province_id < 0 or province_id >= province_base_thickness.size():
		return 0.0
	return province_base_thickness[province_id]


func duplicate_settings() -> SubsurfaceStrataSettings:
	var result := SubsurfaceStrataSettings.new()
	result.max_layers = max_layers
	result.sequence_feature_scale = sequence_feature_scale
	result.thickness_feature_scale = thickness_feature_scale
	result.deep_crust_feature_scale = deep_crust_feature_scale
	result.deep_crust_noise_amplitude = deep_crust_noise_amplitude
	result.deep_continental_threshold = deep_continental_threshold
	result.min_layer_thickness = min_layer_thickness
	result.max_layer_thickness = max_layer_thickness
	result.province_base_thickness = province_base_thickness.duplicate()
	return result
