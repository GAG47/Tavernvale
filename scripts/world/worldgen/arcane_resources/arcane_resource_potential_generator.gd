class_name ArcaneResourcePotentialGenerator
extends RefCounted


static func generate(
		graph: SpatialGraph,
		geology: GeologyLayer,
		ecology: EcologyLayer,
		resource_potential: ResourcePotentialLayer,
		arcane_field: ArcaneFieldLayer,
		arcane_environment: ArcaneEnvironmentLayer,
		arcane_ecology: ArcaneEcologyLayer,
		settings: ArcaneResourcePotentialSettings = null
) -> ArcaneResourcePotentialLayer:
	var actual_settings := (
		settings if settings != null else ArcaneResourcePotentialSettings.new()
	)
	if not _inputs_are_valid(
		graph, geology, ecology, resource_potential, arcane_field,
		arcane_environment, arcane_ecology, actual_settings
	):
		return null

	var result := ArcaneResourcePotentialLayer.new()
	var count := graph.cell_count()
	for values in _resource_arrays(result):
		values.resize(count)
	var rare_noise := _make_rare_noise(_channel_seed(
		graph.config.seed, actual_settings.rare_arcane_noise_seed_salt
	))
	for cell_id in count:
		var concentration := arcane_environment.mana_concentration[cell_id]
		var potential := arcane_field.background_arcane_potential[cell_id]
		var manifestation := arcane_ecology.arcane_manifestation_type[cell_id]
		var energy := arcane_energy_potential_for(
			concentration, arcane_environment.mana_flowability[cell_id]
		)
		var material := arcane_material_potential_for(
			concentration,
			geology.province_id[cell_id],
			geology.rock_type_id[cell_id],
			manifestation
		)
		var biological_host := biological_host_for(
			ecology.vegetation_potential[cell_id],
			resource_potential.freshwater_aquatic_potential[cell_id],
			resource_potential.coastal_aquatic_potential[cell_id]
		)
		var bioresource := arcane_bioresource_potential_for(
			concentration, potential, biological_host, manifestation
		)
		result.arcane_energy_potential[cell_id] = energy
		result.arcane_material_potential[cell_id] = material
		result.arcane_bioresource_potential[cell_id] = bioresource
		var rare_host := rare_host_for(energy, material, bioresource)
		var raw_noise := _rare_raw_noise_at(
			graph, cell_id, rare_noise, actual_settings.rare_arcane_concentration_scale
		)
		result.rare_arcane_resource_potential[cell_id] = rare_arcane_resource_potential_for(
			rare_host, rare_concentration_for(raw_noise)
		)

	var errors := ArcaneResourcePotentialValidator.validate(graph, result)
	if not errors.is_empty():
		push_error("Arcane Resource Potential validation failed: " + "; ".join(errors))
		return null
	return result


static func arcane_energy_potential_for(concentration: float, flowability: float) -> float:
	var clamped_concentration := clampf(concentration, 0.0, 1.0)
	var clamped_flowability := clampf(flowability, 0.0, 1.0)
	return clampf(
		clamped_concentration * (0.70 + 0.30 * clamped_flowability), 0.0, 1.0
	)


static func arcane_material_potential_for(
		concentration: float, province_id: int, rock_type: int, manifestation: int
) -> float:
	var mana_support := sqrt(clampf(concentration, 0.0, 1.0))
	var geological_host := arcane_material_geology_host_for(province_id, rock_type)
	var geology_support := 0.60 + 0.40 * geological_host
	var manifestation_support := 0.75 + 0.25 * manifestation_material_factor_for(
		manifestation
	)
	return clampf(mana_support * geology_support * manifestation_support, 0.0, 1.0)


static func arcane_material_geology_host_for(province_id: int, rock_type: int) -> float:
	return sqrt(
		arcane_material_province_factor_for(province_id)
		* arcane_material_rock_factor_for(rock_type)
	)


static func arcane_material_province_factor_for(province_id: int) -> float:
	match province_id:
		GeologyCatalog.Province.OROGENIC_BELT:
			return 1.00
		GeologyCatalog.Province.VOLCANIC_PROVINCE:
			return 0.90
		GeologyCatalog.Province.CRATON:
			return 0.65
		GeologyCatalog.Province.SEDIMENTARY_BASIN:
			return 0.45
		GeologyCatalog.Province.PASSIVE_MARGIN:
			return 0.25
		GeologyCatalog.Province.OCEANIC_CRUST:
			return 0.20
		_:
			return 0.0


static func arcane_material_rock_factor_for(rock_type: int) -> float:
	match RockCatalog.category_for(rock_type):
		RockCatalog.RockCategory.IGNEOUS_EXTRUSIVE:
			return 0.90
		RockCatalog.RockCategory.METAMORPHIC:
			return 0.85
		RockCatalog.RockCategory.IGNEOUS_INTRUSIVE:
			return 0.75
		RockCatalog.RockCategory.SEDIMENTARY:
			return 0.30
	return 0.0


static func manifestation_material_factor_for(manifestation: int) -> float:
	match manifestation:
		ArcaneEcologyLayer.ManifestationType.MANA_DOMINANT:
			return 1.00
		ArcaneEcologyLayer.ManifestationType.ECOLOGY_DOMINANT:
			return 0.25
		ArcaneEcologyLayer.ManifestationType.MIXED:
			return 0.80
		_:
			return 0.0


static func terrestrial_biological_host_for(vegetation_potential: float) -> float:
	return sqrt(clampf(vegetation_potential, 0.0, 1.0))


static func biological_host_for(
		vegetation_potential: float,
		freshwater_aquatic_potential: float,
		coastal_aquatic_potential: float
) -> float:
	return maxf(
		terrestrial_biological_host_for(vegetation_potential),
		maxf(
			clampf(freshwater_aquatic_potential, 0.0, 1.0),
			clampf(coastal_aquatic_potential, 0.0, 1.0)
		)
	)


static func arcane_ecology_support_for(concentration: float, potential: float) -> float:
	return sqrt(clampf(
		clampf(concentration, 0.0, 1.0) * clampf(potential, 0.0, 1.0), 0.0, 1.0
	))


static func biological_host_support_for(biological_host: float) -> float:
	return 0.20 + 0.80 * clampf(biological_host, 0.0, 1.0)


static func manifestation_bioresource_factor_for(manifestation: int) -> float:
	match manifestation:
		ArcaneEcologyLayer.ManifestationType.MANA_DOMINANT:
			return 0.25
		ArcaneEcologyLayer.ManifestationType.ECOLOGY_DOMINANT:
			return 1.00
		ArcaneEcologyLayer.ManifestationType.MIXED:
			return 0.85
		_:
			return 0.0


static func arcane_bioresource_potential_for(
		concentration: float, potential: float, biological_host: float, manifestation: int
) -> float:
	return clampf(
		arcane_ecology_support_for(concentration, potential)
		* biological_host_support_for(biological_host)
		* manifestation_bioresource_factor_for(manifestation),
		0.0,
		1.0
	)


static func rare_host_for(energy: float, material: float, bioresource: float) -> float:
	return maxf(
		clampf(energy, 0.0, 1.0),
		maxf(clampf(material, 0.0, 1.0), clampf(bioresource, 0.0, 1.0))
	)


static func rare_unit_noise_for(raw_noise: float) -> float:
	return clampf((raw_noise + 1.0) * 0.5, 0.0, 1.0)


static func rare_concentration_for(raw_noise: float) -> float:
	return smoothstep(0.60, 0.92, rare_unit_noise_for(raw_noise))


static func rare_arcane_resource_potential_for(
		rare_host: float, rare_concentration: float
) -> float:
	return clampf(
		clampf(rare_host, 0.0, 1.0) * clampf(rare_concentration, 0.0, 1.0), 0.0, 1.0
	)


static func rare_raw_concentration_at(
		graph: SpatialGraph, cell_id: int, settings: ArcaneResourcePotentialSettings
) -> float:
	var noise := _make_rare_noise(_channel_seed(
		graph.config.seed, settings.rare_arcane_noise_seed_salt
	))
	return _rare_raw_noise_at(
		graph, cell_id, noise, settings.rare_arcane_concentration_scale
	)


static func _rare_raw_noise_at(
		graph: SpatialGraph, cell_id: int, noise: FastNoiseLite, scale: float
) -> float:
	var position: Vector2 = graph.cell_centers[cell_id]
	return noise.get_noise_2d(
		position.x / graph.config.world_width * scale,
		position.y / graph.config.world_height * scale
	)


static func _make_rare_noise(seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.50
	noise.fractal_lacunarity = 2.0
	noise.frequency = 1.0
	noise.domain_warp_enabled = false
	return noise


static func _channel_seed(world_seed: int, salt: int) -> int:
	return DeterministicRng.stable_mix(world_seed, salt)


static func _resource_arrays(resources: ArcaneResourcePotentialLayer) -> Array:
	return [
		resources.arcane_energy_potential,
		resources.arcane_material_potential,
		resources.arcane_bioresource_potential,
		resources.rare_arcane_resource_potential,
	]


static func _inputs_are_valid(
		graph: SpatialGraph,
		geology: GeologyLayer,
		ecology: EcologyLayer,
		resource_potential: ResourcePotentialLayer,
		arcane_field: ArcaneFieldLayer,
		arcane_environment: ArcaneEnvironmentLayer,
		arcane_ecology: ArcaneEcologyLayer,
		settings: ArcaneResourcePotentialSettings
) -> bool:
	if graph == null or geology == null or ecology == null or resource_potential == null \
			or arcane_field == null or arcane_environment == null or arcane_ecology == null:
		push_error("Arcane Resource Potential requires all formal upstream layers")
		return false
	var count := graph.cell_count()
	if count <= 0 or graph.config == null \
			or not is_finite(graph.config.world_width) \
			or not is_finite(graph.config.world_height) \
			or graph.config.world_width <= 0.0 or graph.config.world_height <= 0.0 \
			or graph.cell_centers.size() != count \
			or geology.province_id.size() != count or geology.rock_type_id.size() != count \
			or ecology.vegetation_potential.size() != count \
			or resource_potential.freshwater_aquatic_potential.size() != count \
			or resource_potential.coastal_aquatic_potential.size() != count \
			or arcane_field.background_arcane_potential.size() != count \
			or arcane_environment.mana_concentration.size() != count \
			or arcane_environment.mana_flowability.size() != count \
			or arcane_ecology.arcane_manifestation_type.size() != count:
		push_error("Arcane Resource Potential input arrays must contain one value per Cell")
		return false
	var settings_errors := settings.validate()
	if not settings_errors.is_empty():
		push_error("Invalid Arcane Resource Potential settings: " + "; ".join(settings_errors))
		return false
	for cell_id in count:
		var named_values := [
			["mana_concentration", arcane_environment.mana_concentration[cell_id]],
			["mana_flowability", arcane_environment.mana_flowability[cell_id]],
			["background_arcane_potential", arcane_field.background_arcane_potential[cell_id]],
			["vegetation_potential", ecology.vegetation_potential[cell_id]],
			["freshwater_aquatic_potential", resource_potential.freshwater_aquatic_potential[cell_id]],
			["coastal_aquatic_potential", resource_potential.coastal_aquatic_potential[cell_id]],
		]
		for entry in named_values:
			var value: float = entry[1]
			if not is_finite(value) or value < 0.0 or value > 1.0:
				push_error("%s[%d] must be finite and inside [0, 1]" % [entry[0], cell_id])
				return false
		if arcane_ecology.arcane_manifestation_type[cell_id] not in [
			ArcaneEcologyLayer.ManifestationType.NONE,
			ArcaneEcologyLayer.ManifestationType.MANA_DOMINANT,
			ArcaneEcologyLayer.ManifestationType.ECOLOGY_DOMINANT,
			ArcaneEcologyLayer.ManifestationType.MIXED,
		]:
			push_error("arcane_manifestation_type[%d] is invalid" % cell_id)
			return false
	return true
