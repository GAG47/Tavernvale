extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_output_sizes_and_enum_validity()
	_test_settings_validation()
	_test_exact_band_boundaries()
	_test_complete_rule_table()
	_test_determinism()
	_test_potential_change_and_input_preservation()
	_test_mana_change_and_input_preservation()
	_test_flowability_and_stability_independence()
	_test_natural_ecology_is_not_an_input()
	_test_validator_semantics()
	_finish()


func _test_output_sizes_and_enum_validity() -> void:
	var field := _field(PackedFloat32Array([0.2, 0.65, 0.8]))
	var environment := _environment(PackedFloat32Array([0.2, 0.65, 0.8]))
	var result := ArcaneEcologyGenerator.generate(field, environment)
	_expect(result != null, "Arcane Ecology fixture should generate")
	if result == null:
		return
	_expect(result.arcane_ecology_state.size() == 3,
		"Arcane Ecology State should contain one value per input Cell")
	_expect(result.arcane_manifestation_type.size() == 3,
		"Manifestation Type should contain one value per input Cell")
	_expect(ArcaneEcologyValidator.validate(field, environment, result).is_empty(),
		"generated Arcane Ecology should pass its Validator")


func _test_settings_validation() -> void:
	var settings := ArcaneEcologySettings.new()
	_expect(settings.validate().is_empty(), "default Arcane Ecology Settings should validate")
	_expect(settings.mana_medium_threshold == 0.60
			and settings.mana_high_threshold == 0.70
			and settings.potential_medium_threshold == 0.60
			and settings.potential_high_threshold == 0.70,
		"default thresholds should be fixed at 0.60 and 0.70")
	var copied := settings.duplicate_settings()
	_expect(copied.mana_medium_threshold == settings.mana_medium_threshold
			and copied.mana_high_threshold == settings.mana_high_threshold
			and copied.potential_medium_threshold == settings.potential_medium_threshold
			and copied.potential_high_threshold == settings.potential_high_threshold,
		"duplicate_settings should preserve all four thresholds")
	settings.mana_medium_threshold = NAN
	settings.potential_medium_threshold = 0.8
	settings.potential_high_threshold = 0.7
	_expect(settings.validate().size() == 2,
		"Settings should reject non-finite and unordered threshold pairs")


func _test_exact_band_boundaries() -> void:
	var settings := ArcaneEcologySettings.new()
	var values := PackedFloat32Array([0.599999, 0.600000, 0.699999, 0.700000])
	var expected := PackedInt32Array([
		ArcaneEcologyGenerator.Band.LOW,
		ArcaneEcologyGenerator.Band.MEDIUM,
		ArcaneEcologyGenerator.Band.MEDIUM,
		ArcaneEcologyGenerator.Band.HIGH,
	])
	for index in values.size():
		_expect(ArcaneEcologyGenerator.classify_mana(values[index], settings) == expected[index],
			"Mana boundary value %.6f should enter the exact specified Band" % values[index])
		_expect(ArcaneEcologyGenerator.classify_potential(values[index], settings)
				== expected[index],
			"Potential boundary value %.6f should enter the exact specified Band" % values[index])


func _test_complete_rule_table() -> void:
	var mana := PackedFloat32Array()
	var potential := PackedFloat32Array()
	for mana_value in [0.50, 0.65, 0.80]:
		for potential_value in [0.50, 0.65, 0.80]:
			mana.append(mana_value)
			potential.append(potential_value)
	var result := ArcaneEcologyGenerator.generate(_field(potential), _environment(mana))
	_expect(result != null, "complete 3x3 classification fixture should generate")
	if result == null:
		return
	var expected_states := PackedInt32Array([
		0, 0, 0,
		0, 1, 1,
		0, 1, 2,
	])
	var expected_manifestations := PackedInt32Array([
		0, 0, 0,
		1, 3, 2,
		1, 3, 3,
	])
	_expect(result.arcane_ecology_state == expected_states,
		"all nine Mana-Potential cells must match the Ecology State rule table")
	_expect(result.arcane_manifestation_type == expected_manifestations,
		"all nine Mana-Potential cells must match the Manifestation rule table")


func _test_determinism() -> void:
	var field := _field(PackedFloat32Array([0.3, 0.62, 0.71, 0.9]))
	var environment := _environment(PackedFloat32Array([0.8, 0.65, 0.2, 0.9]))
	var first := ArcaneEcologyGenerator.generate(field, environment)
	var repeat := ArcaneEcologyGenerator.generate(field, environment)
	_expect(first != null and repeat != null, "determinism fixtures should generate")
	if first != null and repeat != null:
		_expect(first.arcane_ecology_state == repeat.arcane_ecology_state
				and first.arcane_manifestation_type == repeat.arcane_manifestation_type,
			"identical formal inputs should reproduce Arcane Ecology exactly")


func _test_potential_change_and_input_preservation() -> void:
	var environment := _environment(PackedFloat32Array([0.65]))
	var low_field := _field(PackedFloat32Array([0.50]))
	var high_field := _field(PackedFloat32Array([0.80]))
	var mana_before := environment.mana_concentration.duplicate()
	var low_before := low_field.background_arcane_potential.duplicate()
	var high_before := high_field.background_arcane_potential.duplicate()
	var low_result := ArcaneEcologyGenerator.generate(low_field, environment)
	var high_result := ArcaneEcologyGenerator.generate(high_field, environment)
	_expect(low_result != null and high_result != null,
		"Potential-change fixtures should generate")
	if low_result != null and high_result != null:
		_expect(low_result.arcane_manifestation_type[0]
				== ArcaneEcologyLayer.ManifestationType.CRYSTALLINE
				and high_result.arcane_manifestation_type[0]
				== ArcaneEcologyLayer.ManifestationType.ECOLOGICAL,
			"changing Potential may change only the downstream classification")
	_expect(environment.mana_concentration == mana_before
			and low_field.background_arcane_potential == low_before
			and high_field.background_arcane_potential == high_before,
		"Potential classification must not mutate either formal input Layer")


func _test_mana_change_and_input_preservation() -> void:
	var field := _field(PackedFloat32Array([0.80]))
	var low_environment := _environment(PackedFloat32Array([0.50]))
	var high_environment := _environment(PackedFloat32Array([0.80]))
	var potential_before := field.background_arcane_potential.duplicate()
	var low_before := low_environment.mana_concentration.duplicate()
	var high_before := high_environment.mana_concentration.duplicate()
	var low_result := ArcaneEcologyGenerator.generate(field, low_environment)
	var high_result := ArcaneEcologyGenerator.generate(field, high_environment)
	_expect(low_result != null and high_result != null, "Mana-change fixtures should generate")
	if low_result != null and high_result != null:
		_expect(low_result.arcane_ecology_state[0]
				== ArcaneEcologyLayer.EcologyState.NORMAL
				and high_result.arcane_ecology_state[0]
				== ArcaneEcologyLayer.EcologyState.DOMINANT,
			"changing Mana Concentration may change only the downstream classification")
	_expect(field.background_arcane_potential == potential_before
			and low_environment.mana_concentration == low_before
			and high_environment.mana_concentration == high_before,
		"Mana classification must not mutate either formal input Layer")


func _test_flowability_and_stability_independence() -> void:
	var field := _field(PackedFloat32Array([0.65, 0.80]))
	var first_environment := _environment(PackedFloat32Array([0.65, 0.80]))
	var second_environment := _environment(PackedFloat32Array([0.65, 0.80]))
	first_environment.mana_flowability = PackedFloat32Array([0.0, 1.0])
	first_environment.mana_stability = PackedFloat32Array([1.0, 0.0])
	second_environment.mana_flowability = PackedFloat32Array([1.0, 0.0])
	second_environment.mana_stability = PackedFloat32Array([0.0, 1.0])
	field.background_mana = PackedFloat32Array([0.0, 1.0])
	field.background_stability = PackedFloat32Array([1.0, 0.0])
	var first := ArcaneEcologyGenerator.generate(field, first_environment)
	field.background_mana = PackedFloat32Array([1.0, 0.0])
	field.background_stability = PackedFloat32Array([0.0, 1.0])
	var second := ArcaneEcologyGenerator.generate(field, second_environment)
	_expect(first != null and second != null, "irrelevant Arcane-input fixtures should generate")
	if first != null and second != null:
		_expect(first.arcane_ecology_state == second.arcane_ecology_state
				and first.arcane_manifestation_type == second.arcane_manifestation_type,
			"Flowability, Stability, Background Mana, and Background Stability must not affect v2.4")


func _test_natural_ecology_is_not_an_input() -> void:
	var result := ArcaneEcologyGenerator.generate(
		_field(PackedFloat32Array([0.80])),
		_environment(PackedFloat32Array([0.65]))
	)
	_expect(result != null,
		"Arcane Ecology classification should require no graph or natural-geography Layer")
	if result != null:
		_expect(result.arcane_manifestation_type[0]
				== ArcaneEcologyLayer.ManifestationType.ECOLOGICAL,
			"classification without natural ecology should follow the formal two-axis table")


func _test_validator_semantics() -> void:
	var field := _field(PackedFloat32Array([0.5, 0.5]))
	var environment := _environment(PackedFloat32Array([0.5, 0.5]))
	var invalid := ArcaneEcologyLayer.new()
	invalid.arcane_ecology_state = PackedInt32Array([99, 1])
	invalid.arcane_manifestation_type = PackedInt32Array([0, 99])
	_expect(ArcaneEcologyValidator.validate(field, environment, invalid).size() == 2,
		"Validator should reject invalid Ecology State and Manifestation enums")
	invalid.arcane_ecology_state = PackedInt32Array([1, 2])
	invalid.arcane_manifestation_type = PackedInt32Array([0, 2])
	_expect(ArcaneEcologyValidator.validate(field, environment, invalid).size() == 2,
		"Validator should enforce NONE-NORMAL and DOMINANT-MIXED implications")


func _field(potential: PackedFloat32Array) -> ArcaneFieldLayer:
	var field := ArcaneFieldLayer.new()
	field.background_arcane_potential = potential.duplicate()
	field.background_mana.resize(potential.size())
	field.background_stability.resize(potential.size())
	field.background_mana.fill(0.5)
	field.background_stability.fill(0.5)
	return field


func _environment(mana: PackedFloat32Array) -> ArcaneEnvironmentLayer:
	var environment := ArcaneEnvironmentLayer.new()
	environment.mana_concentration = mana.duplicate()
	environment.mana_flowability.resize(mana.size())
	environment.mana_stability.resize(mana.size())
	environment.mana_flowability.fill(0.5)
	environment.mana_stability.fill(0.5)
	return environment


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Arcane Ecology & Manifestation: all 10 targeted test groups passed")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
