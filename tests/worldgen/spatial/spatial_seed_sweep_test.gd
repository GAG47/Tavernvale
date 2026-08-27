extends SceneTree

const FIRST_SEED := 1
const LAST_SEED := 100


func _init() -> void:
	call_deferred("_run_sweep")


func _run_sweep() -> void:
	var failed_seeds := PackedInt32Array()
	var passed := 0
	var started := Time.get_ticks_msec()
	for seed in range(FIRST_SEED, LAST_SEED + 1):
		var graph := SpatialGenerator.generate(SpatialConfig.new(seed))
		var errors := PackedStringArray(["generator returned null"]) if graph == null \
			else SpatialValidator.validate(graph)
		if errors.is_empty():
			passed += 1
		else:
			failed_seeds.append(seed)
			printerr("Seed %d failed: %s" % [seed, "; ".join(errors)])
		if seed % 10 == 0:
			print("Spatial seed sweep progress: %d/%d" % [seed, LAST_SEED])
	var total_ms := Time.get_ticks_msec() - started
	var total := LAST_SEED - FIRST_SEED + 1
	print(
		"Spatial seed sweep: passed=%d/%d failed=%s total=%d ms average=%.2f ms/seed"
		% [passed, total, failed_seeds, total_ms, float(total_ms) / total]
	)
	quit(0 if failed_seeds.is_empty() else 1)
