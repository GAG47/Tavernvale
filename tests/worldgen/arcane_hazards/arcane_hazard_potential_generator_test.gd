extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_layer_structure()
	_test_activity_exact_formula()
	_test_severity_exact_formula()
	_test_propagation_exact_formula()
	_test_semantic_independence()
	_test_no_random_dependency()
	_test_invalid_input_and_validator()
	_test_upstream_immutability()
	_finish()


func _test_layer_structure() -> void:
	var layer := ArcaneHazardPotentialLayer.new()
	_expect(layer.arcane_hazard_activity_potential is PackedFloat32Array,
		"Layer should expose Hazard Activity Potential")
	_expect(layer.arcane_hazard_severity_potential is PackedFloat32Array,
		"Layer should expose Hazard Severity Potential")
	_expect(layer.arcane_hazard_propagation_potential is PackedFloat32Array,
		"Layer should expose Hazard Propagation Potential")
	for forbidden_field in [
		"total_hazard", "arcane_hazard_score", "disaster_type", "event_probability",
		"event_rate", "event_id", "disaster_damage",
	]:
		_expect(not forbidden_field in layer, "Layer must not expose " + forbidden_field)
	layer.arcane_hazard_activity_potential = PackedFloat32Array([0.1, 0.2])
	_expect(layer.cell_count() == 2, "cell_count should use the Activity array")


func _test_activity_exact_formula() -> void:
	_expect(ArcaneHazardPotentialGenerator.activity_potential_for(1.0, 1.0) == 0.0,
		"Full Stability must produce zero Activity at full Flowability")
	_expect(is_equal_approx(
		ArcaneHazardPotentialGenerator.activity_potential_for(0.0, 0.0), 0.70
	), "Full instability at zero Flowability should produce 0.70 Activity")
	_expect(ArcaneHazardPotentialGenerator.activity_potential_for(0.0, 1.0) == 1.0,
		"Full instability and Flowability should produce full Activity")
	_expect(is_equal_approx(
		ArcaneHazardPotentialGenerator.activity_potential_for(0.5, 0.5), 0.425
	), "Half Stability and Flowability should produce 0.425 Activity")
	_expect(ArcaneHazardPotentialGenerator.activity_potential_for(0.4, 0.9)
			>= ArcaneHazardPotentialGenerator.activity_potential_for(0.4, 0.1),
		"Flowability must not lower Activity at fixed Stability")
	var first := _fixture()
	var second := _fixture()
	second.environment.mana_concentration.fill(0.0)
	second.field.background_arcane_potential.fill(0.0)
	var first_result := _generate(first)
	var second_result := _generate(second)
	_expect(first_result != null and second_result != null
			and first_result.arcane_hazard_activity_potential
			== second_result.arcane_hazard_activity_potential,
		"Concentration and Potential must not affect Activity")


func _test_severity_exact_formula() -> void:
	_expect(is_equal_approx(
		ArcaneHazardPotentialGenerator.severity_potential_for(0.8, 0.0), 0.56
	), "Severity should retain 70% of high Mana at zero Potential")
	_expect(is_equal_approx(
		ArcaneHazardPotentialGenerator.severity_potential_for(0.8, 1.0), 0.8
	), "Full Potential should preserve Mana Concentration in Severity")
	_expect(ArcaneHazardPotentialGenerator.severity_potential_for(0.0, 1.0) == 0.0,
		"Zero Mana Concentration should produce zero Severity")
	_expect(ArcaneHazardPotentialGenerator.severity_potential_for(0.8, 0.9)
			>= ArcaneHazardPotentialGenerator.severity_potential_for(0.8, 0.1),
		"Potential must not lower Severity at fixed Concentration")
	var first := _fixture()
	var second := _fixture()
	second.environment.mana_stability.fill(0.0)
	second.environment.mana_flowability.fill(0.0)
	var first_result := _generate(first)
	var second_result := _generate(second)
	_expect(first_result != null and second_result != null
			and first_result.arcane_hazard_severity_potential
			== second_result.arcane_hazard_severity_potential,
		"Stability and Flowability must not affect Severity")


func _test_propagation_exact_formula() -> void:
	_expect(is_equal_approx(
		ArcaneHazardPotentialGenerator.propagation_potential_for(0.8, 0.0), 0.48
	), "Propagation should retain 60% of high Flowability at zero Mana")
	_expect(is_equal_approx(
		ArcaneHazardPotentialGenerator.propagation_potential_for(0.8, 1.0), 0.8
	), "Full Mana should preserve Flowability in Propagation")
	_expect(ArcaneHazardPotentialGenerator.propagation_potential_for(0.0, 1.0) == 0.0,
		"Zero Flowability should produce zero Propagation")
	_expect(ArcaneHazardPotentialGenerator.propagation_potential_for(0.8, 0.9)
			>= ArcaneHazardPotentialGenerator.propagation_potential_for(0.8, 0.1),
		"Concentration must not lower Propagation at fixed Flowability")
	var first := _fixture()
	var second := _fixture()
	second.environment.mana_stability.fill(0.0)
	second.field.background_arcane_potential.fill(0.0)
	var first_result := _generate(first)
	var second_result := _generate(second)
	_expect(first_result != null and second_result != null
			and first_result.arcane_hazard_propagation_potential
			== second_result.arcane_hazard_propagation_potential,
		"Stability and Potential must not affect Propagation")


func _test_semantic_independence() -> void:
	var stable_extreme := _single_cell_result(1.0, 1.0, 1.0, 1.0)
	_expect(stable_extreme != null
			and stable_extreme.arcane_hazard_activity_potential[0] == 0.0
			and stable_extreme.arcane_hazard_severity_potential[0] == 1.0
			and stable_extreme.arcane_hazard_propagation_potential[0] == 1.0,
		"Stable high-Mana environment should support low Activity and high other axes")
	var frequent_small := _single_cell_result(0.0, 0.1, 0.0, 0.5)
	_expect(frequent_small != null
			and frequent_small.arcane_hazard_activity_potential[0] > 0.8
			and frequent_small.arcane_hazard_severity_potential[0] < 0.1
			and frequent_small.arcane_hazard_propagation_potential[0] > 0.25
			and frequent_small.arcane_hazard_propagation_potential[0] < 0.5,
		"Low Stability and low Mana should express frequent small disturbances")
	var severe_local := _single_cell_result(0.05, 0.9, 0.8, 0.05)
	_expect(severe_local != null
			and severe_local.arcane_hazard_activity_potential[0] > 0.65
			and severe_local.arcane_hazard_severity_potential[0] > 0.8
			and severe_local.arcane_hazard_propagation_potential[0] < 0.1,
		"Low Stability, high Mana, and low Flowability should express severe local hazard")


func _test_no_random_dependency() -> void:
	var fixture := _fixture()
	var first := _generate(fixture)
	var second := _generate(fixture)
	_expect(first != null and second != null
			and first.arcane_hazard_activity_potential
			== second.arcane_hazard_activity_potential
			and first.arcane_hazard_severity_potential
			== second.arcane_hazard_severity_potential
			and first.arcane_hazard_propagation_potential
			== second.arcane_hazard_propagation_potential,
		"Identical formal inputs should produce bit-identical Hazard arrays")


func _test_invalid_input_and_validator() -> void:
	var fixture := _fixture()
	_expect(ArcaneHazardPotentialGenerator.generate(null, fixture.environment) == null,
		"Null Arcane Field should be rejected")
	_expect(ArcaneHazardPotentialGenerator.generate(fixture.field, null) == null,
		"Null Arcane Environment should be rejected")
	var empty_environment := ArcaneEnvironmentLayer.new()
	_expect(ArcaneHazardPotentialGenerator.generate(fixture.field, empty_environment) == null,
		"Empty formal arrays should be rejected")
	var mismatch := _fixture()
	mismatch.environment.mana_flowability.resize(2)
	_expect(_generate(mismatch) == null, "Mismatched formal arrays should be rejected")
	for invalid_value in [NAN, -0.01, 1.01]:
		var invalid := _fixture()
		invalid.environment.mana_concentration[0] = invalid_value
		_expect(_generate(invalid) == null,
			"Non-finite and out-of-range formal inputs should be rejected")
	var invalid_layer := ArcaneHazardPotentialLayer.new()
	_expect(not ArcaneHazardPotentialValidator.validate(invalid_layer).is_empty(),
		"Validator should reject empty result arrays")
	invalid_layer.arcane_hazard_activity_potential = PackedFloat32Array([0.5])
	invalid_layer.arcane_hazard_severity_potential = PackedFloat32Array([0.5, 0.5])
	invalid_layer.arcane_hazard_propagation_potential = PackedFloat32Array([0.5])
	_expect(not ArcaneHazardPotentialValidator.validate(invalid_layer).is_empty(),
		"Validator should reject mismatched result arrays")
	invalid_layer.arcane_hazard_severity_potential.resize(1)
	invalid_layer.arcane_hazard_activity_potential[0] = INF
	_expect(not ArcaneHazardPotentialValidator.validate(invalid_layer).is_empty(),
		"Validator should reject invalid result values")


func _test_upstream_immutability() -> void:
	var fixture := _fixture()
	var before := hash([
		fixture.field.background_mana,
		fixture.field.background_stability,
		fixture.field.background_arcane_potential,
		fixture.environment.mana_concentration,
		fixture.environment.mana_flowability,
		fixture.environment.mana_stability,
	])
	var result := _generate(fixture)
	var after := hash([
		fixture.field.background_mana,
		fixture.field.background_stability,
		fixture.field.background_arcane_potential,
		fixture.environment.mana_concentration,
		fixture.environment.mana_flowability,
		fixture.environment.mana_stability,
	])
	_expect(result != null and before == after,
		"Hazard generation must not mutate Arcane Field or Arcane Environment")
	_expect(result != null and ArcaneHazardPotentialValidator.validate(result).is_empty(),
		"Generated Hazard Potential should validate")
	_expect(result != null and ArcaneHazardPotentialValidator.statistics(result).size() == 3,
		"Validator should provide statistics for all three outputs")


func _single_cell_result(
		stability: float, concentration: float, potential: float, flowability: float
) -> ArcaneHazardPotentialLayer:
	var field := ArcaneFieldLayer.new()
	field.background_arcane_potential = PackedFloat32Array([potential])
	var environment := ArcaneEnvironmentLayer.new()
	environment.mana_concentration = PackedFloat32Array([concentration])
	environment.mana_flowability = PackedFloat32Array([flowability])
	environment.mana_stability = PackedFloat32Array([stability])
	return ArcaneHazardPotentialGenerator.generate(field, environment)


func _generate(fixture: Dictionary) -> ArcaneHazardPotentialLayer:
	return ArcaneHazardPotentialGenerator.generate(fixture.field, fixture.environment)


func _fixture() -> Dictionary:
	var field := ArcaneFieldLayer.new()
	field.background_mana = PackedFloat32Array([0.1, 0.2, 0.3, 0.4])
	field.background_stability = PackedFloat32Array([0.4, 0.5, 0.6, 0.7])
	field.background_arcane_potential = PackedFloat32Array([0.0, 0.4, 0.8, 1.0])
	var environment := ArcaneEnvironmentLayer.new()
	environment.mana_concentration = PackedFloat32Array([0.1, 0.4, 0.8, 1.0])
	environment.mana_flowability = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	environment.mana_stability = PackedFloat32Array([1.0, 0.8, 0.4, 0.0])
	return {"field": field, "environment": environment}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Arcane Hazard Potential: all 8 targeted test groups passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	printerr("Arcane Hazard Potential: %d failures" % _failures.size())
	quit(1)
