class_name ArcaneSteadyStateOperator
extends RefCounted

## Matrix-free sparse representation of the v2.3.3 affine transport equation.
## The steady state satisfies A*C=b, while the original amount-rate RHS is b-A*C.

var diagonal := PackedFloat64Array()
var rhs := PackedFloat64Array()

var internal_a := PackedInt32Array()
var internal_b := PackedInt32Array()
var internal_diffusion := PackedFloat64Array()
var internal_velocity_length := PackedFloat64Array()

var boundary_face_count: int = 0


func cell_count() -> int:
	return diagonal.size()


func internal_face_count() -> int:
	return internal_a.size()


func apply_into(x: PackedFloat64Array, output: PackedFloat64Array) -> void:
	var count := diagonal.size()
	for cell_id in count:
		output[cell_id] = diagonal[cell_id] * x[cell_id]
	for face_index in internal_a.size():
		var cell_a := internal_a[face_index]
		var cell_b := internal_b[face_index]
		var diffusion := internal_diffusion[face_index]
		var velocity_length := internal_velocity_length[face_index]
		output[cell_a] -= diffusion * x[cell_b]
		output[cell_b] -= diffusion * x[cell_a]
		if velocity_length >= 0.0:
			output[cell_b] -= velocity_length * x[cell_a]
		else:
			output[cell_a] += velocity_length * x[cell_b]


func residual_into(x: PackedFloat64Array, output: PackedFloat64Array) -> void:
	apply_into(x, output)
	for cell_id in diagonal.size():
		output[cell_id] = rhs[cell_id] - output[cell_id]


func jacobi_into(input: PackedFloat64Array, output: PackedFloat64Array) -> void:
	for cell_id in diagonal.size():
		output[cell_id] = input[cell_id] / diagonal[cell_id]
