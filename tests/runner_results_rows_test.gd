extends Node
## Full completed-mission labels survive responsive results layout.

var _passes := 0
var _failures := 0

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var hud := RunnerHUD.new()
	viewport.add_child(hud)
	hud.setup()
	var missions := PackedStringArray(["Run 250 m at x2 or better in one run", "Collect 60 fish in one run"])
	hud.show_game_over({"distance":363.0, "fish":27, "score":1038,
		"best":6692, "missions":missions})
	var original: Array[Label] = hud._results_mission_labels.duplicate()
	for shape: Vector2i in [Vector2i(1920,1080), Vector2i(1080,1920), Vector2i(792,1408)]:
		viewport.size = shape
		hud._relayout()
		for frame: int in 3:
			await get_tree().process_frame
		var tag := "%dx%d_" % [shape.x, shape.y]
		_check(hud._results_mission_labels == original, tag + "rotation_preserves_mission_nodes")
		_check(hud._results_mission_labels.size() == missions.size(), tag + "one_label_per_completed_mission")
		for i: int in missions.size():
			var label := hud._results_mission_labels[i]
			# Results typography scales against the authored 1080-unit canvas.
			# Fixed 34px rejects the accepted 28-unit face and smaller touch canvas.
			var result_unit := float(shape.x if shape.y >= shape.x else shape.y) / 1080.0
			_check(label.text == missions[i]
				and label.get_theme_font_size("font_size") >= roundi(28.0 * result_unit)
				and label.get_theme_font_size("font_size") >= 20,
				tag + "full_readable_label_%d" % i)
			_check(label.get_visible_line_count() == label.get_line_count()
				and label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING,
				tag + "all_wrapped_lines_visible_%d" % i)
			var row := label.get_parent().get_parent().get_parent() as Control
			_check(row.get_global_rect().encloses(label.get_global_rect()), tag + "label_inside_row_%d" % i)
			_check(row.find_children("CompletionCheck*", "PanelContainer", true, false).size() == 1,
				tag + "checked_completion_row_%d" % i)
			var bars := row.find_children("*", "ProgressBar", true, false)
			_check(bars.size() == 1 and is_equal_approx((bars[0] as ProgressBar).value, 1.0),
				tag + "true_completion_bar_%d" % i)
		for child: Node in hud._game_over_buttons.get_children():
			var button := child as Button
			_check(Rect2(Vector2.ZERO, Vector2(shape)).encloses(button.get_global_rect()),
				tag + "action_visible_" + button.text)
	hud.show_game_over({"score":100, "missions":[]})
	_check(hud._results_mission_labels.is_empty(), "empty_summary_has_no_false_completed_rows")
	hud.hide_game_over()
	_check(hud._results_mission_labels.is_empty(), "retry_clears_result_label_references")
	viewport.free()
	await get_tree().process_frame
	print("[runner_results_rows] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	if ok:
		_passes += 1
	else:
		_failures += 1
	print("[runner_results_rows] %s %s" % ["PASS" if ok else "FAIL", message])
