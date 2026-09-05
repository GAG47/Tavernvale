extends SceneTree

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	# Exercise the actual standard Debug pipeline: Seed 1, 2000 x 1000, 20000 Cells.
	var view := WorldCompositionDebugView.new()
	root.add_child(view)
	if view.arcane_ecology == null:
		printerr("FAIL: standard Debug pipeline did not generate Arcane Ecology")
		view.queue_free()
		quit(1)
		return
	var errors := ArcaneEcologyValidator.validate(view.graph.cell_count(), view.arcane_ecology)
	_failures.append_array(errors)
	print("Seed 1 Arcane Ecology diagnostics: ", JSON.stringify(view._arcane_ecology_statistics))
	view.debug_page = WorldCompositionDebugView.DebugPage.ARCANE_ECOLOGY
	view.selected_cell_id = 0
	for index in 3:
		view._select_current_page_view(index)
		var lines := PackedStringArray()
		view._append_mode_statistics(lines)
		view._append_cell_inspector_header(lines, 0)
		view._append_arcane_ecology_cell_inspection(lines, 0)
		var text := "\n".join(lines)
		for label in ["Arcane Ecology Potential", "State:", "Response:", "Mana Concentration",
			"Mana Flowability", "Mana Stability", "Biome:", "Ecological Moisture", "Vegetation Potential"]:
			if not text.contains(label):
				_failures.append("Debug inspection missing " + label)
		view.queue_redraw()
		await process_frame
		await process_frame
	view.reference_view = WorldCompositionDebugView.ReferenceView.BIOME
	if view._cell_color(0) != view._biome_color(view.ecology.biome_id[0]):
		_failures.append("Biome reference should remain available on Arcane Ecology page")
	view.reference_view = WorldCompositionDebugView.ReferenceView.HEIGHT
	if view._cell_color(0) != view._terrain_height_color(view.terrain.terrain_height[0]):
		_failures.append("Height reference should remain available on Arcane Ecology page")
	view.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Arcane Ecology Debug Pipeline: Seed 1 and all three maps passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		quit(1)
