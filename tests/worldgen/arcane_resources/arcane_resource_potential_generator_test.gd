extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_layer_and_settings()
	_test_energy_exact_formula()
	_test_material_exact_formula()
	_test_geology_factor_tables()
	_test_bioresource_exact_formula()
	_test_rare_exact_formula()
	_test_rare_deterministic_coherent_field()
	_test_generation_validation_and_input_preservation()
	_finish()


func _test_layer_and_settings() -> void:
	var layer := ArcaneResourcePotentialLayer.new()
	_expect(layer.arcane_energy_potential is PackedFloat32Array,
		"Layer should expose Arcane Energy Potential")
	_expect(layer.arcane_material_potential is PackedFloat32Array,
		"Layer should expose Arcane Material Potential")
	_expect(layer.arcane_bioresource_potential is PackedFloat32Array,
		"Layer should expose Arcane Bioresource Potential")
	_expect(layer.rare_arcane_resource_potential is PackedFloat32Array,
		"Layer should expose Rare Arcane Resource Potential")
	_expect(not "total_arcane_resource_potential" in layer,
		"Layer must not expose a total Arcane Resource field")
	_expect(not "magical_resource_score" in layer,
		"Layer must not expose a universal magical resource score")
	var settings := ArcaneResourcePotentialSettings.new()
	_expect(settings.rare_arcane_noise_seed_salt == 0x52415245,
		"Rare Arcane salt should default to RARE")
	_expect(settings.rare_arcane_concentration_scale == 4.0,
		"Rare Arcane concentration scale should default to 4.0")
	var copy := settings.duplicate_settings()
	_expect(copy != settings
			and copy.rare_arcane_noise_seed_salt == settings.rare_arcane_noise_seed_salt
			and copy.rare_arcane_concentration_scale == settings.rare_arcane_concentration_scale,
		"duplicate_settings should preserve formal settings")
	for invalid_scale in [0.0, -1.0, NAN, INF]:
		settings.rare_arcane_concentration_scale = invalid_scale
		_expect(not settings.validate().is_empty(), "Invalid Rare scale should be rejected")


func _test_energy_exact_formula() -> void:
	_expect(is_equal_approx(
		ArcaneResourcePotentialGenerator.arcane_energy_potential_for(0.8, 0.0), 0.56
	), "Energy should equal C * 0.70 at zero Flowability")
	_expect(is_equal_approx(
		ArcaneResourcePotentialGenerator.arcane_energy_potential_for(0.8, 1.0), 0.8
	), "Energy should equal C at full Flowability")
	var low_concentration := ArcaneResourcePotentialGenerator.arcane_energy_potential_for(0.2, 0.5)
	var high_concentration := ArcaneResourcePotentialGenerator.arcane_energy_potential_for(0.8, 0.5)
	var low_flow := ArcaneResourcePotentialGenerator.arcane_energy_potential_for(0.8, 0.1)
	var high_flow := ArcaneResourcePotentialGenerator.arcane_energy_potential_for(0.8, 0.9)
	_expect(high_concentration >= low_concentration,
		"Increasing Concentration must not lower Energy")
	_expect(high_flow >= low_flow, "Increasing Flowability must not lower Energy")
	_expect(ArcaneResourcePotentialGenerator.arcane_energy_potential_for(1.0, 0.0) > 0.0,
		"Zero Flowability must not erase high-Mana Energy")
	var first := _fixture()
	var second := _fixture()
	second.arcane_field.background_arcane_potential.fill(0.0)
	second.geology.province_id.fill(GeologyCatalog.Province.OCEANIC_CRUST)
	second.arcane_ecology.arcane_manifestation_type.fill(
		ArcaneEcologyLayer.ManifestationType.NONE
	)
	var first_result := _generate(first)
	var second_result := _generate(second)
	_expect(first_result != null and second_result != null
			and first_result.arcane_energy_potential == second_result.arcane_energy_potential,
		"Energy must not depend on Potential, Manifestation, or Geology")


func _test_material_exact_formula() -> void:
	var province := GeologyCatalog.Province.OROGENIC_BELT
	var material := GeologyCatalog.MaterialType.VOLCANIC_ROCK
	var geological_host := sqrt(1.0 * 0.9)
	var expected := sqrt(0.64) * (0.60 + 0.40 * geological_host)
	var none_value := ArcaneResourcePotentialGenerator.arcane_material_potential_for(
		0.64, province, material, ArcaneEcologyLayer.ManifestationType.NONE
	)
	_expect(is_equal_approx(none_value, expected * 0.75),
		"Material should use sqrt Mana, geological host, and 0.75 NONE support")
	var mana_value := ArcaneResourcePotentialGenerator.arcane_material_potential_for(
		0.64, province, material, ArcaneEcologyLayer.ManifestationType.MANA_DOMINANT
	)
	var mixed_value := ArcaneResourcePotentialGenerator.arcane_material_potential_for(
		0.64, province, material, ArcaneEcologyLayer.ManifestationType.MIXED
	)
	var ecology_value := ArcaneResourcePotentialGenerator.arcane_material_potential_for(
		0.64, province, material, ArcaneEcologyLayer.ManifestationType.ECOLOGY_DOMINANT
	)
	_expect(mana_value > mixed_value and mixed_value > ecology_value
			and ecology_value > none_value,
		"Material Manifestation support should order Mana > Mixed > Ecology > None")
	_expect(is_equal_approx(mana_value / expected, 1.0)
			and is_equal_approx(mixed_value / expected, 0.95)
			and is_equal_approx(ecology_value / expected, 0.8125),
		"Material Manifestation support values should be exact")
	_expect(none_value > 0.0, "NONE Manifestation must not gate positive-Mana Material")
	var strong_geology := ArcaneResourcePotentialGenerator.arcane_material_potential_for(
		0.64, province, material, ArcaneEcologyLayer.ManifestationType.NONE
	)
	var weak_geology := ArcaneResourcePotentialGenerator.arcane_material_potential_for(
		0.64, GeologyCatalog.Province.OCEANIC_CRUST,
		GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK,
		ArcaneEcologyLayer.ManifestationType.NONE
	)
	_expect(strong_geology > weak_geology and weak_geology > 0.0,
		"Better Geology should enrich Material without turning weak Geology into a gate")


func _test_geology_factor_tables() -> void:
	var province_factors := {
		GeologyCatalog.Province.OROGENIC_BELT: 1.00,
		GeologyCatalog.Province.VOLCANIC_PROVINCE: 0.90,
		GeologyCatalog.Province.CRATON: 0.65,
		GeologyCatalog.Province.SEDIMENTARY_BASIN: 0.45,
		GeologyCatalog.Province.PASSIVE_MARGIN: 0.25,
		GeologyCatalog.Province.OCEANIC_CRUST: 0.20,
	}
	for province_id in province_factors:
		_expect(ArcaneResourcePotentialGenerator.arcane_material_province_factor_for(
			province_id
		) == province_factors[province_id], "Province factor should match the formal table")
	var material_factors := {
		GeologyCatalog.MaterialType.VOLCANIC_ROCK: 0.90,
		GeologyCatalog.MaterialType.METAMORPHIC_ROCK: 0.85,
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK: 0.75,
		GeologyCatalog.MaterialType.SHALE_MUDSTONE: 0.45,
		GeologyCatalog.MaterialType.CARBONATE_ROCK: 0.35,
		GeologyCatalog.MaterialType.SANDSTONE: 0.25,
		GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK: 0.20,
	}
	for material_id in material_factors:
		_expect(ArcaneResourcePotentialGenerator.arcane_material_material_factor_for(
			material_id
		) == material_factors[material_id], "Material factor should match the formal table")
	_expect(ArcaneResourcePotentialGenerator.arcane_material_province_factor_for(99) == 0.0,
		"Unknown Province should have zero factor")
	_expect(ArcaneResourcePotentialGenerator.arcane_material_material_factor_for(99) == 0.0,
		"Unknown Material should have zero factor")


func _test_bioresource_exact_formula() -> void:
	_expect(is_equal_approx(
		ArcaneResourcePotentialGenerator.biological_host_for(0.81, 0.4, 0.2), 0.9
	), "Terrestrial host should use sqrt vegetation and may dominate B")
	_expect(is_equal_approx(
		ArcaneResourcePotentialGenerator.biological_host_for(0.16, 0.8, 0.2), 0.8
	), "Freshwater host may dominate B")
	_expect(is_equal_approx(
		ArcaneResourcePotentialGenerator.biological_host_for(0.16, 0.2, 0.9), 0.9
	), "Coastal host may dominate B")
	_expect(is_equal_approx(
		ArcaneResourcePotentialGenerator.biological_host_support_for(0.0), 0.20
	), "Zero Biological Host should retain the formal 0.20 baseline")
	_expect(is_equal_approx(
		ArcaneResourcePotentialGenerator.biological_host_support_for(1.0), 1.0
	), "Full Biological Host should provide full support")
	_expect(ArcaneResourcePotentialGenerator.manifestation_bioresource_factor_for(
		ArcaneEcologyLayer.ManifestationType.ECOLOGY_DOMINANT
	) == 1.0, "Ecology-dominant Bioresource factor should be 1.00")
	_expect(ArcaneResourcePotentialGenerator.manifestation_bioresource_factor_for(
		ArcaneEcologyLayer.ManifestationType.MIXED
	) == 0.85, "Mixed Bioresource factor should be 0.85")
	_expect(ArcaneResourcePotentialGenerator.manifestation_bioresource_factor_for(
		ArcaneEcologyLayer.ManifestationType.MANA_DOMINANT
	) == 0.25, "Mana-dominant Bioresource factor should be 0.25")
	_expect(ArcaneResourcePotentialGenerator.manifestation_bioresource_factor_for(
		ArcaneEcologyLayer.ManifestationType.NONE
	) == 0.0, "NONE Bioresource factor should be zero")
	var barren_ecology := ArcaneResourcePotentialGenerator.arcane_bioresource_potential_for(
		0.8, 0.8, 0.0, ArcaneEcologyLayer.ManifestationType.ECOLOGY_DOMINANT
	)
	_expect(barren_ecology > 0.0,
		"Strong Arcane Ecology may form Bioresources with zero natural host")
	_expect(ArcaneResourcePotentialGenerator.arcane_bioresource_potential_for(
		0.8, 0.8, 1.0, ArcaneEcologyLayer.ManifestationType.NONE
	) == 0.0, "NONE Manifestation should produce zero Arcane Bioresource")


func _test_rare_exact_formula() -> void:
	_expect(ArcaneResourcePotentialGenerator.rare_host_for(0.4, 0.7, 0.5) == 0.7,
		"Rare host should be the maximum common Potential")
	_expect(ArcaneResourcePotentialGenerator.rare_arcane_resource_potential_for(
		0.8, 0.0
	) == 0.0, "Zero Rare concentration must produce zero Rare Potential")
	_expect(ArcaneResourcePotentialGenerator.rare_arcane_resource_potential_for(
		0.8, 1.0
	) == 0.8, "Full Rare concentration should preserve Rare host")
	_expect(ArcaneResourcePotentialGenerator.rare_concentration_for(-1.0) == 0.0,
		"Rare concentration must have no baseline")


func _test_rare_deterministic_coherent_field() -> void:
	var graph := SpatialGenerator.generate(SpatialConfig.new(123, 300.0, 200.0, 900, 0.9))
	_expect(graph != null, "Rare coherence graph should generate")
	if graph == null:
		return
	var settings := ArcaneResourcePotentialSettings.new()
	var first := PackedFloat32Array()
	var repeated := PackedFloat32Array()
	var other_seed := PackedFloat32Array()
	var base := PackedFloat32Array()
	var precious := PackedFloat32Array()
	for cell_id in graph.cell_count():
		first.append(ArcaneResourcePotentialGenerator.rare_raw_concentration_at(
			graph, cell_id, settings
		))
		repeated.append(ArcaneResourcePotentialGenerator.rare_raw_concentration_at(
			graph, cell_id, settings
		))
		base.append(ResourcePotentialGenerator.base_metal_raw_concentration_at(
			graph, cell_id, ResourcePotentialSettings.new()
		))
		precious.append(ResourcePotentialGenerator.precious_mineral_raw_concentration_at(
			graph, cell_id, ResourcePotentialSettings.new()
		))
	var second_graph := SpatialGenerator.generate(SpatialConfig.new(124, 300.0, 200.0, 900, 0.9))
	for cell_id in second_graph.cell_count():
		other_seed.append(ArcaneResourcePotentialGenerator.rare_raw_concentration_at(
			second_graph, cell_id, settings
		))
	_expect(first == repeated, "Fixed world seed and graph should be bit-identical")
	_expect(first != other_seed, "Changing world seed should change the Rare channel")
	_expect(first != base and first != precious,
		"Rare channel should differ from both v1 mineral channels")
	var arcane_field := ArcaneFieldGenerator.generate(graph, graph.config.seed)
	_expect(arcane_field != null and first != arcane_field.background_mana
			and first != arcane_field.background_stability
			and first != arcane_field.background_arcane_potential,
		"Rare channel should differ from all Background Arcane fields")
	var neighbor_delta_sum := 0.0
	var neighbor_count := 0
	for cell_id in graph.cell_count():
		for neighbor_id in graph.cell_neighbors[cell_id]:
			if neighbor_id > cell_id:
				neighbor_delta_sum += absf(first[cell_id] - first[neighbor_id])
				neighbor_count += 1
	var neighbor_delta := neighbor_delta_sum / float(neighbor_count)
	_expect(neighbor_count > 0 and neighbor_delta < 0.20,
		"Rare channel should be spatially coherent rather than per-Cell salt-and-pepper")


func _test_generation_validation_and_input_preservation() -> void:
	var fixture := _fixture()
	var before := _formal_input_hash(fixture)
	var result := _generate(fixture)
	_expect(result != null, "Valid Arcane Resource Potential fixture should generate")
	if result == null:
		return
	_expect(result.cell_count() == fixture.graph.cell_count(),
		"All four result arrays should be Cell-aligned")
	_expect(ArcaneResourcePotentialValidator.validate(fixture.graph, result).is_empty(),
		"Generated Arcane Resource Potential should validate")
	_expect(ArcaneResourcePotentialValidator.statistics(result).size() == 4,
		"Validator should expose statistics for all four outputs")
	_expect(_formal_input_hash(fixture) == before,
		"Generator must not mutate any formal upstream input")
	var repeated := _generate(fixture)
	_expect(repeated != null
			and result.arcane_energy_potential == repeated.arcane_energy_potential
			and result.arcane_material_potential == repeated.arcane_material_potential
			and result.arcane_bioresource_potential == repeated.arcane_bioresource_potential
			and result.rare_arcane_resource_potential == repeated.rare_arcane_resource_potential,
		"Full generation should be bit-identical")
	var invalid := ArcaneResourcePotentialLayer.new()
	invalid.arcane_energy_potential = PackedFloat32Array([0.5])
	_expect(not ArcaneResourcePotentialValidator.validate(fixture.graph, invalid).is_empty(),
		"Validator should reject invalid array sizes")
	invalid.arcane_energy_potential.resize(fixture.graph.cell_count())
	invalid.arcane_material_potential.resize(fixture.graph.cell_count())
	invalid.arcane_bioresource_potential.resize(fixture.graph.cell_count())
	invalid.rare_arcane_resource_potential.resize(fixture.graph.cell_count())
	invalid.arcane_energy_potential[0] = NAN
	_expect(not ArcaneResourcePotentialValidator.validate(fixture.graph, invalid).is_empty(),
		"Validator should reject non-finite results")


func _generate(fixture: Dictionary) -> ArcaneResourcePotentialLayer:
	return ArcaneResourcePotentialGenerator.generate(
		fixture.graph,
		fixture.geology,
		fixture.ecology,
		fixture.resource_potential,
		fixture.arcane_field,
		fixture.arcane_environment,
		fixture.arcane_ecology
	)


func _fixture() -> Dictionary:
	var graph := SpatialGraph.new()
	graph.config = SpatialConfig.new(123, 60.0, 20.0, 6, 0.9)
	graph.cell_centers = PackedVector2Array([
		Vector2(5, 5), Vector2(15, 5), Vector2(25, 5),
		Vector2(35, 15), Vector2(45, 15), Vector2(55, 15),
	])
	var geology := GeologyLayer.new()
	geology.province_id = PackedInt32Array([
		GeologyCatalog.Province.OROGENIC_BELT,
		GeologyCatalog.Province.VOLCANIC_PROVINCE,
		GeologyCatalog.Province.CRATON,
		GeologyCatalog.Province.SEDIMENTARY_BASIN,
		GeologyCatalog.Province.PASSIVE_MARGIN,
		GeologyCatalog.Province.OCEANIC_CRUST,
	])
	geology.material_id = PackedInt32Array([
		GeologyCatalog.MaterialType.VOLCANIC_ROCK,
		GeologyCatalog.MaterialType.METAMORPHIC_ROCK,
		GeologyCatalog.MaterialType.CRYSTALLINE_ROCK,
		GeologyCatalog.MaterialType.SHALE_MUDSTONE,
		GeologyCatalog.MaterialType.SANDSTONE,
		GeologyCatalog.MaterialType.MARINE_SEDIMENTARY_ROCK,
	])
	geology.permeability = PackedFloat32Array([0.4, 0.12, 0.15, 0.12, 0.65, 0.45])
	geology.erodibility = PackedFloat32Array([0.3, 0.18, 0.15, 0.75, 0.55, 0.6])
	var ecology := EcologyLayer.new()
	ecology.vegetation_potential = PackedFloat32Array([0.81, 0.16, 0.0, 1.0, 0.25, 0.0])
	var resources := ResourcePotentialLayer.new()
	resources.freshwater_aquatic_potential = PackedFloat32Array([0.1, 0.8, 0.0, 0.0, 0.2, 0.0])
	resources.coastal_aquatic_potential = PackedFloat32Array([0.0, 0.0, 0.9, 0.0, 0.4, 0.7])
	var field := ArcaneFieldLayer.new()
	field.background_arcane_potential = PackedFloat32Array([0.8, 0.7, 0.9, 0.6, 0.5, 0.4])
	var environment := ArcaneEnvironmentLayer.new()
	environment.mana_concentration = PackedFloat32Array([0.8, 0.7, 0.9, 0.6, 0.5, 0.4])
	environment.mana_flowability = PackedFloat32Array([0.0, 1.0, 0.5, 0.7, 0.2, 0.9])
	var arcane_ecology := ArcaneEcologyLayer.new()
	arcane_ecology.arcane_manifestation_type = PackedInt32Array([
		ArcaneEcologyLayer.ManifestationType.MANA_DOMINANT,
		ArcaneEcologyLayer.ManifestationType.ECOLOGY_DOMINANT,
		ArcaneEcologyLayer.ManifestationType.MIXED,
		ArcaneEcologyLayer.ManifestationType.NONE,
		ArcaneEcologyLayer.ManifestationType.ECOLOGY_DOMINANT,
		ArcaneEcologyLayer.ManifestationType.MANA_DOMINANT,
	])
	return {
		"graph": graph,
		"geology": geology,
		"ecology": ecology,
		"resource_potential": resources,
		"arcane_field": field,
		"arcane_environment": environment,
		"arcane_ecology": arcane_ecology,
	}


func _formal_input_hash(fixture: Dictionary) -> int:
	return hash([
		fixture.graph.cell_centers,
		fixture.geology.province_id,
		fixture.geology.material_id,
		fixture.geology.permeability,
		fixture.geology.erodibility,
		fixture.ecology.vegetation_potential,
		fixture.resource_potential.freshwater_aquatic_potential,
		fixture.resource_potential.coastal_aquatic_potential,
		fixture.arcane_field.background_arcane_potential,
		fixture.arcane_environment.mana_concentration,
		fixture.arcane_environment.mana_flowability,
		fixture.arcane_ecology.arcane_manifestation_type,
	])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Arcane Resource Potential: all 8 targeted test groups passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	printerr("Arcane Resource Potential: %d failures" % _failures.size())
	quit(1)
