class_name ArcaneCirculationGenerator
extends RefCounted

## Domain circulation potential models the Arcane Medium's large-scale,
## long-term circulation potential. It is a transient calculation aid—not a
## Debug random value, line-width noise, or ArcaneWebDomain magic property.

const CIRCULATION_SEED_SALT := 0x43495243 # "CIRC"
const CIRCULATION_FEATURE_SCALE := 700.0
const CIRCULATION_OCTAVES := 3
const CIRCULATION_LACUNARITY := 2.0
const CIRCULATION_GAIN := 0.50


static func generate(arcane_web: ArcaneWebLayer) -> ArcaneCirculationLayer:
	if arcane_web == null:
		push_error("ArcaneCirculationGenerator: ArcaneWebLayer is null")
		return null
	var web_errors := ArcaneWebValidator.validate(arcane_web)
	if not web_errors.is_empty():
		push_error("ArcaneCirculationGenerator: invalid Arcane Web: " + "; ".join(web_errors))
		return null

	var noise := _make_circulation_noise(
		DeterministicRng.stable_mix(arcane_web.world_seed, CIRCULATION_SEED_SALT)
	)
	var potentials := PackedFloat64Array()
	potentials.resize(arcane_web.domains.size())
	for domain in arcane_web.domains:
		potentials[domain.id] = noise.get_noise_2d(
			domain.nucleus_position.x, domain.nucleus_position.y
		)

	var circulation := ArcaneCirculationLayer.new()
	circulation.edge_flow.resize(arcane_web.edges.size())
	for edge in arcane_web.edges:
		var sides := domains_for_edge(arcane_web, edge)
		if not bool(sides.get("valid", false)):
			push_error(
				"ArcaneCirculationGenerator: could not resolve domains for Edge %d" % edge.id
			)
			return null
		# Relative long-term Arcane Current: magnitude is relative strength with
		# no absolute mana unit; sign is canonical node_a -> node_b direction.
		circulation.edge_flow[edge.id] = float(
			potentials[int(sides.left_domain_id)] - potentials[int(sides.right_domain_id)]
		)

	var validation_errors := ArcaneCirculationValidator.validate(
		arcane_web, circulation
	)
	if not validation_errors.is_empty():
		push_error("Arcane Circulation validation failed: " + "; ".join(validation_errors))
		return null
	return circulation


static func circulation_potential_for(
		arcane_web: ArcaneWebLayer, domain: ArcaneWebDomain
) -> float:
	var noise := _make_circulation_noise(
		DeterministicRng.stable_mix(arcane_web.world_seed, CIRCULATION_SEED_SALT)
	)
	return noise.get_noise_2d(domain.nucleus_position.x, domain.nucleus_position.y)


static func expected_flow_for_edge(
		arcane_web: ArcaneWebLayer, edge: ArcaneWebEdge
) -> Dictionary:
	var sides := domains_for_edge(arcane_web, edge)
	if not bool(sides.get("valid", false)):
		return {"valid": false}
	var left_domain: ArcaneWebDomain = arcane_web.domains[int(sides.left_domain_id)]
	var right_domain: ArcaneWebDomain = arcane_web.domains[int(sides.right_domain_id)]
	return {
		"valid": true,
		"left_domain_id": left_domain.id,
		"right_domain_id": right_domain.id,
		"flow": circulation_potential_for(arcane_web, left_domain)
				- circulation_potential_for(arcane_web, right_domain),
	}


static func domains_for_edge(
		arcane_web: ArcaneWebLayer, edge: ArcaneWebEdge
) -> Dictionary:
	if arcane_web == null or edge == null \
			or edge.node_a_id < 0 or edge.node_b_id >= arcane_web.nodes.size():
		return {"valid": false}
	var start := arcane_web.nodes[edge.node_a_id].world_position
	var end := arcane_web.nodes[edge.node_b_id].world_position
	var direction := end - start
	if direction.length_squared() <= 0.0 or arcane_web.domains.size() < 2:
		return {"valid": false}
	var midpoint := (start + end) * 0.5
	var closest := _two_closest_domains(arcane_web.domains, midpoint)
	if closest.size() != 2:
		return {"valid": false}
	var first: ArcaneWebDomain = closest[0]
	var second: ArcaneWebDomain = closest[1]
	var left_normal := Vector2(-direction.y, direction.x).normalized()
	var epsilon := SpatialGeometry.epsilon_for_size(
		arcane_web.world_width, arcane_web.world_height
	)
	var probe_distance := maxf(epsilon * 4.0, minf(edge.length * 0.01, 0.1))
	var left_probe := midpoint + left_normal * probe_distance
	var right_probe := midpoint - left_normal * probe_distance
	var containment_epsilon := epsilon * 0.25
	var first_on_left := SpatialGeometry.point_in_polygon(
		left_probe, first.polygon, containment_epsilon
	)
	var second_on_left := SpatialGeometry.point_in_polygon(
		left_probe, second.polygon, containment_epsilon
	)
	var first_on_right := SpatialGeometry.point_in_polygon(
		right_probe, first.polygon, containment_epsilon
	)
	var second_on_right := SpatialGeometry.point_in_polygon(
		right_probe, second.polygon, containment_epsilon
	)
	if first_on_left and not second_on_left and second_on_right and not first_on_right:
		return {
			"valid": true,
			"left_domain_id": first.id,
			"right_domain_id": second.id,
		}
	if second_on_left and not first_on_left and first_on_right and not second_on_right:
		return {
			"valid": true,
			"left_domain_id": second.id,
			"right_domain_id": first.id,
		}

	# Very short edges can put an epsilon-aware containment probe close to a
	# vertex. The same geometric probe still has an unambiguous lower-power side.
	var first_left_power := _power_distance(left_probe, first)
	var second_left_power := _power_distance(left_probe, second)
	var first_right_power := _power_distance(right_probe, first)
	var second_right_power := _power_distance(right_probe, second)
	if first_left_power < second_left_power and second_right_power < first_right_power:
		return {
			"valid": true,
			"left_domain_id": first.id,
			"right_domain_id": second.id,
		}
	if second_left_power < first_left_power and first_right_power < second_right_power:
		return {
			"valid": true,
			"left_domain_id": second.id,
			"right_domain_id": first.id,
		}
	return {"valid": false}


static func _make_circulation_noise(seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = CIRCULATION_OCTAVES
	noise.fractal_lacunarity = CIRCULATION_LACUNARITY
	noise.fractal_gain = CIRCULATION_GAIN
	noise.fractal_weighted_strength = 0.0
	noise.frequency = 1.0 / CIRCULATION_FEATURE_SCALE
	noise.domain_warp_enabled = false
	return noise


static func _two_closest_domains(
		domains: Array[ArcaneWebDomain], point: Vector2
) -> Array[ArcaneWebDomain]:
	var first: ArcaneWebDomain
	var second: ArcaneWebDomain
	var first_power := INF
	var second_power := INF
	for domain in domains:
		var power := _power_distance(point, domain)
		if _domain_candidate_less(power, domain.id, first_power, first.id if first != null else -1):
			second = first
			second_power = first_power
			first = domain
			first_power = power
		elif _domain_candidate_less(
			power, domain.id, second_power, second.id if second != null else -1
		):
			second = domain
			second_power = power
	var result: Array[ArcaneWebDomain] = []
	if first != null:
		result.append(first)
	if second != null:
		result.append(second)
	return result


static func _domain_candidate_less(
		power: float, domain_id: int, current_power: float, current_id: int
) -> bool:
	return power < current_power or (power == current_power and domain_id < current_id)


static func _power_distance(point: Vector2, domain: ArcaneWebDomain) -> float:
	return point.distance_squared_to(domain.nucleus_position) - domain.power_weight
