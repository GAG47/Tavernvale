class_name SubsurfaceStrataLayer
extends RefCounted

## World-scale major subsurface materials stored in CSR-like PackedArrays.
const NO_MATERIAL := -1

var cell_offsets := PackedInt32Array()
var material_ids := PackedInt32Array()
var top_z := PackedFloat32Array()


func cell_count() -> int:
	return maxi(0, cell_offsets.size() - 1)


func record_range_for_cell(cell_id: int) -> Vector2i:
	if cell_id < 0 or cell_id + 1 >= cell_offsets.size():
		return Vector2i(-1, -1)
	var begin := cell_offsets[cell_id]
	var end := cell_offsets[cell_id + 1]
	if begin < 0 or end < begin or end > material_ids.size() or end > top_z.size():
		return Vector2i(-1, -1)
	return Vector2i(begin, end)


func material_at_z(cell_id: int, z: float) -> int:
	var local_index := layer_index_at_z(cell_id, z)
	if local_index < 0:
		return NO_MATERIAL
	var record_range := record_range_for_cell(cell_id)
	return material_ids[record_range.x + local_index]


func layer_index_at_z(cell_id: int, z: float) -> int:
	if not is_finite(z):
		return -1
	var record_range := record_range_for_cell(cell_id)
	if record_range.x < 0 or record_range.x == record_range.y:
		return -1
	if z > top_z[record_range.x]:
		return -1
	for record_index in range(record_range.x, record_range.y - 1):
		if z > top_z[record_index + 1]:
			return record_index - record_range.x
	return record_range.y - record_range.x - 1


func layer_bounds(cell_id: int, local_layer_index: int) -> Vector2:
	var record_range := record_range_for_cell(cell_id)
	if record_range.x < 0 or local_layer_index < 0 \
			or record_range.x + local_layer_index >= record_range.y:
		return Vector2(NAN, NAN)
	var record_index := record_range.x + local_layer_index
	var bottom_z := -INF if record_index + 1 == record_range.y else top_z[record_index + 1]
	return Vector2(top_z[record_index], bottom_z)
