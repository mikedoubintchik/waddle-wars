extends "res://tests/runner_catch_capture.gd"
## Same real route/catch harness, with one explicitly synthetic 4m gap before
## fatal hits. That frame checks worst live obstruction; no natural danger or
## collision claim. No gameplay clock or frame-draw signal is synthesized.

var _danger_draw: int = -1
var _danger_captured := false
var _next_focus_us: int = 0
var _feedback_checked := false
var _feedback_diagnostics: Dictionary = {}
var _cleanup_pending := false


func _resume_overlay() -> void:
	var game := get_tree().current_scene as RunnerGame
	if game == null:
		_finish(true)
		return
	var before := _snapshot("before_pause_feedback")
	var activated := await _activate_gui_button(game._pause_layer, "Feedback")
	_feedback_diagnostics = {
		"button_activations": int(_gui_activations.get("Feedback", 0)),
		"last_gui_event_handled": get_viewport().is_input_handled(),
		"form_open": game._pause_layer.get_node_or_null("FeedbackForm") != null,
		"tree_paused": get_tree().paused,
	}
	if not activated:
		_finish(true)
		return
	DisplayServer.window_move_to_foreground()
	await get_tree().process_frame
	await get_tree().process_frame
	DisplayServer.window_move_to_foreground()
	await RenderingServer.frame_post_draw
	if _finished:
		return
	var form := game._pause_layer.get_node_or_null("FeedbackForm")
	_check(form != null and get_tree().paused, "pause Feedback opens above still-paused run")
	if form == null:
		_finish(true)
		return
	_capture("pause_feedback", _snapshot("pause_feedback"))
	var back := form.find_child("FeedbackBack", true, false) as Button
	_check(back != null and back.is_visible_in_tree()
		and get_viewport().get_visible_rect().encloses(back.get_global_rect()),
		"pause Feedback Back button remains visible and reachable")
	if back == null:
		_finish(true)
		return
	_gui_activations["FeedbackBack"] = 0
	back.pressed.connect(_on_cycle_gui_pressed.bind("FeedbackBack"))
	var at := back.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.device = InputEvent.DEVICE_ID_EMULATION
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)
	_push_touch(0, at, true)
	_push_mouse(at, true)
	_push_touch(0, at, false)
	_push_mouse(at, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var after := _snapshot("after_pause_feedback")
	_check(int(_gui_activations["FeedbackBack"]) == 1
		and game._pause_layer.get_node_or_null("FeedbackForm") == null
		and get_tree().paused and is_instance_valid(game._pause_layer)
		and is_equal_approx(float(after["elapsed"]), float(before["elapsed"]))
		and is_equal_approx(float(after["distance"]), float(before["distance"]))
		and is_equal_approx(float(after["score"]), float(before["score"])),
		"one GUI Feedback Back returns to pause with gameplay still frozen")
	_feedback_checked = true
	await super._resume_overlay()

func _on_process_frame() -> void:
	super._on_process_frame()
	# A native macOS window stops drawing when occluded. Reacquire the agreed
	# short capture slot; never synthesize frame_post_draw or substitute pixels.
	if _monitor and not _finished and Time.get_ticks_usec() >= _next_focus_us:
		DisplayServer.window_move_to_foreground()
		_next_focus_us = Time.get_ticks_usec() + 1000000

func _advance_overlay_capture(game: RunnerGame, row: Dictionary) -> bool:
	if not super._advance_overlay_capture(game, row):
		return false
	# Observe the steady live chase after the normal opening powder transition.
	if game.elapsed < 3.3:
		return false
	if _danger_draw < 0:
		game.chaser.gap = 4.0
		game.chaser.global_position.z = -game.player.distance + 4.0
		game.chaser._update_wall_visibility()
		game.chaser.set_intro_preview(game.chaser.chase_preview_strength(game.elapsed), game.player.distance, 0.0)
		game.hud.set_stats(game.player.distance, game.fish, int(game._score),
			game._last_multiplier, game.player.hits_left, game.chaser.gap)
		_danger_draw = _draw_serial
		DisplayServer.window_move_to_foreground()
		return false
	if _draw_serial <= _danger_draw + 1:
		return false
	if not _danger_captured:
		_capture("avalanche_close", row)
		_danger_captured = true
	return true

func _snapshot(phase: String) -> Dictionary:
	var row := super._snapshot(phase)
	var game := get_tree().current_scene as RunnerGame
	if game != null and game.chaser != null:
		row["synthetic_near_gap_metres"] = 4.0
		row["wall_body_visible"] = game.chaser._face.visible if game.chaser._face != null else false
		row["wall_puffs_visible"] = game.chaser._puffs.visible if game.chaser._puffs != null else false
		row["powder_front_alpha"] = game.chaser._intro_front.modulate.a if game.chaser._intro_front != null else 0.0
		row["powder_back_alpha"] = game.chaser._intro_back.modulate.a if game.chaser._intro_back != null else 0.0
	return row

func _finish(timed_out: bool) -> void:
	if _cleanup_pending:
		return
	if _catch_complete or timed_out:
		var close_row: Dictionary = _captures.get("avalanche_close", {}).get("snapshot", {})
		_check(_danger_captured and not bool(close_row.get("dead", true))
			and float(close_row.get("chaser_gap", 100.0)) < 6.0,
			"explicitly synthetic near-gap live frame captured")
		_check(not bool(close_row.get("wall_body_visible", true))
			and not bool(close_row.get("wall_puffs_visible", true)),
			"near-gap rear wall cannot fill the chase camera")
		_check(float(close_row.get("powder_front_alpha", 1.0)) < 0.50,
			"near-gap powder remains translucent")
		# Flush silent one-shot playback before the Dummy driver is destroyed.
		# Keep RunnerGame alive through the inherited real-scene identity check.
		_cleanup_pending = true
		for player: Node in AudioManager.get_children():
			if player is AudioStreamPlayer or player is AudioStreamPlayer3D:
				player.stop()
				player.stream = null
		await get_tree().create_timer(0.1).timeout
	super._finish(timed_out)
	if not _finished:
		return
	var report_path := _out.get_basename() + ".json"
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	if report is Dictionary:
		report["readability_fixture"] = {"synthetic_chaser_gap_metres":4.0,
			"natural_close_call_verified":false, "near_miss_semantics":"separate headless real-collider fixture",
			"catch_duration":RunnerGame.CATCH_TIME, "pause_feedback_checked":_feedback_checked,
			"feedback_submission":false, "feedback_diagnostics":_feedback_diagnostics}
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
