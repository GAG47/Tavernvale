class_name ArcaneFieldGenerator
extends RefCounted

const ARCANE_MANA_SEED_SALT := 0x4D414E41 # "MANA"
const ARCANE_STABILITY_SEED_SALT := 0x53544142 # "STAB"

const MANA_OCTAVES := 3
const MANA_LACUNARITY := 2.0
const MANA_GAIN := 0.40
const STABILITY_OCTAVES := 3
const STABILITY_LACUNARITY := 2.0
const STABILITY_GAIN := 0.50


static func generate(
		graph: SpatialGraph,
		world_seed: int,
		settings: ArcaneFieldSettings = null
) -> ArcaneFieldLayer:
	var actual_settings := settings if settings != null else ArcaneFieldSettings.new()
	if graph == null:
		push_error("ArcaneFieldGenerator: SpatialGraph is null")
		return null
	if graph.cell_count() <= 0 or graph.cell_centers.size() != graph.cell_count():
		push_error("ArcaneFieldGenerator: SpatialGraph is incomplete")
		return null
	var settings_errors := actual_settings.validate()
	if not settings_errors.is_empty():
		push_error("ArcaneFieldGenerator: invalid settings: " + "; ".join(settings_errors))
		return null

	var mana_noise := _make_noise(
		DeterministicRng.stable_mix(world_seed, ARCANE_MANA_SEED_SALT),
		actual_settings.mana_feature_scale,
		MANA_OCTAVES,
		MANA_LACUNARITY,
		MANA_GAIN
	)
	var stability_noise := _make_noise(
		DeterministicRng.stable_mix(world_seed, ARCANE_STABILITY_SEED_SALT),
		actual_settings.stability_feature_scale,
		STABILITY_OCTAVES,
		STABILITY_LACUNARITY,
		STABILITY_GAIN
	)
	var arcane_field := ArcaneFieldLayer.new()
	var count := graph.cell_count()
	arcane_field.background_mana.resize(count)
	arcane_field.background_stability.resize(count)
	for cell_id in count:
		var position := graph.cell_centers[cell_id]
		arcane_field.background_mana[cell_id] = _unit_value(
			mana_noise.get_noise_2d(position.x, position.y)
		)
		arcane_field.background_stability[cell_id] = _unit_value(
			stability_noise.get_noise_2d(position.x, position.y)
		)

	var validation_errors := ArcaneFieldValidator.validate(graph, arcane_field)
	if not validation_errors.is_empty():
		push_error("Arcane Field validation failed: " + "; ".join(validation_errors))
		return null
	return arcane_field


static func _make_noise(
		seed: int, feature_scale: float, octaves: int, lacunarity: float, gain: float
) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = lacunarity
	noise.fractal_gain = gain
	noise.fractal_weighted_strength = 0.0
	noise.frequency = 1.0 / feature_scale
	noise.domain_warp_enabled = false
	return noise


static func _unit_value(raw_noise: float) -> float:
	return clampf((raw_noise + 1.0) * 0.5, 0.0, 1.0)
