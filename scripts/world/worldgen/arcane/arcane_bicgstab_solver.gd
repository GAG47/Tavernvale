class_name ArcaneBiCGSTABSolver
extends RefCounted

const RELATIVE_RESIDUAL_TOLERANCE := 0.0000001
const ABSOLUTE_RESIDUAL_TOLERANCE := 0.000000001
const MAX_ITERATIONS := 500
const BREAKDOWN_THRESHOLD := 1.0e-30


static func solve(
		operator: ArcaneSteadyStateOperator,
		initial_guess: PackedFloat64Array
) -> Dictionary:
	var count := operator.cell_count()
	var x := initial_guess.duplicate()
	var r := PackedFloat64Array()
	var r_hat := PackedFloat64Array()
	var p := PackedFloat64Array()
	var v := PackedFloat64Array()
	var s := PackedFloat64Array()
	var t := PackedFloat64Array()
	var p_hat := PackedFloat64Array()
	var s_hat := PackedFloat64Array()
	r.resize(count)
	r_hat.resize(count)
	p.resize(count)
	v.resize(count)
	s.resize(count)
	t.resize(count)
	p_hat.resize(count)
	s_hat.resize(count)
	operator.residual_into(x, r)
	for cell_id in count:
		r_hat[cell_id] = r[cell_id]

	var rhs_norm := _norm_l2(operator.rhs)
	var residual_norm := _norm_l2(r)
	var residual_l_inf := _norm_l_inf(r)
	var target := maxf(
		ABSOLUTE_RESIDUAL_TOLERANCE,
		RELATIVE_RESIDUAL_TOLERANCE * rhs_norm
	)
	if residual_norm <= target:
		return _result(x, 0, residual_norm, residual_l_inf, rhs_norm, true, "")

	var rho_previous := 1.0
	var alpha := 1.0
	var omega := 1.0
	for iteration in MAX_ITERATIONS:
		var rho := _dot(r_hat, r)
		if not is_finite(rho) or absf(rho) <= BREAKDOWN_THRESHOLD:
			return _result(
				x, iteration, residual_norm, residual_l_inf, rhs_norm, false,
				"rho breakdown"
			)
		if iteration == 0:
			for cell_id in count:
				p[cell_id] = r[cell_id]
		else:
			if not is_finite(omega) or absf(omega) <= BREAKDOWN_THRESHOLD:
				return _result(
					x, iteration, residual_norm, residual_l_inf, rhs_norm, false,
					"omega breakdown"
				)
			var beta := (rho / rho_previous) * (alpha / omega)
			if not is_finite(beta):
				return _result(
					x, iteration, residual_norm, residual_l_inf, rhs_norm, false,
					"non-finite beta"
				)
			for cell_id in count:
				p[cell_id] = r[cell_id] + beta * (
					p[cell_id] - omega * v[cell_id]
				)

		operator.jacobi_into(p, p_hat)
		operator.apply_into(p_hat, v)
		var alpha_denominator := _dot(r_hat, v)
		if not is_finite(alpha_denominator) \
				or absf(alpha_denominator) <= BREAKDOWN_THRESHOLD:
			return _result(
				x, iteration, residual_norm, residual_l_inf, rhs_norm, false,
				"alpha denominator breakdown"
			)
		alpha = rho / alpha_denominator
		if not is_finite(alpha):
			return _result(
				x, iteration, residual_norm, residual_l_inf, rhs_norm, false,
				"non-finite alpha"
			)
		for cell_id in count:
			s[cell_id] = r[cell_id] - alpha * v[cell_id]
		var s_norm := _norm_l2(s)
		if s_norm <= target:
			for cell_id in count:
				x[cell_id] += alpha * p_hat[cell_id]
			operator.residual_into(x, r)
			residual_norm = _norm_l2(r)
			residual_l_inf = _norm_l_inf(r)
			return _result(
				x, iteration + 1, residual_norm, residual_l_inf, rhs_norm,
				residual_norm <= target, ""
			)

		operator.jacobi_into(s, s_hat)
		operator.apply_into(s_hat, t)
		var omega_denominator := _dot(t, t)
		if not is_finite(omega_denominator) \
				or absf(omega_denominator) <= BREAKDOWN_THRESHOLD:
			return _result(
				x, iteration, residual_norm, residual_l_inf, rhs_norm, false,
				"omega denominator breakdown"
			)
		omega = _dot(t, s) / omega_denominator
		if not is_finite(omega) or absf(omega) <= BREAKDOWN_THRESHOLD:
			return _result(
				x, iteration, residual_norm, residual_l_inf, rhs_norm, false,
				"omega breakdown"
			)
		for cell_id in count:
			x[cell_id] += alpha * p_hat[cell_id] + omega * s_hat[cell_id]
			r[cell_id] = s[cell_id] - omega * t[cell_id]
		residual_norm = _norm_l2(r)
		residual_l_inf = _norm_l_inf(r)
		if not is_finite(residual_norm) or not is_finite(residual_l_inf):
			return _result(
				x, iteration + 1, residual_norm, residual_l_inf, rhs_norm, false,
				"non-finite residual"
			)
		if residual_norm <= target:
			return _result(
				x, iteration + 1, residual_norm, residual_l_inf, rhs_norm, true, ""
			)
		rho_previous = rho

	operator.residual_into(x, r)
	residual_norm = _norm_l2(r)
	residual_l_inf = _norm_l_inf(r)
	return _result(
		x, MAX_ITERATIONS, residual_norm, residual_l_inf, rhs_norm, false,
		"maximum iterations reached"
	)


static func _result(
		x: PackedFloat64Array,
		iterations: int,
		residual_norm: float,
		residual_l_inf: float,
		rhs_norm: float,
		converged: bool,
		breakdown_reason: String
) -> Dictionary:
	return {
		"concentration": x,
		"report": {
			"iterations": iterations,
			"relative_residual": (
				residual_norm / rhs_norm if rhs_norm > BREAKDOWN_THRESHOLD else residual_norm
			),
			"absolute_residual": residual_norm,
			"l_inf_residual": residual_l_inf,
			"converged": converged,
			"breakdown": not breakdown_reason.is_empty()
					and breakdown_reason != "maximum iterations reached",
			"breakdown_reason": breakdown_reason,
			"finite": is_finite(residual_norm) and is_finite(residual_l_inf),
		},
	}


static func _dot(first: PackedFloat64Array, second: PackedFloat64Array) -> float:
	var result := 0.0
	for index in first.size():
		result += first[index] * second[index]
	return result


static func _norm_l2(values: PackedFloat64Array) -> float:
	return sqrt(maxf(_dot(values, values), 0.0))


static func _norm_l_inf(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, absf(value))
	return result
