extends "res://tests/runner_presentation_capture.gd"
## Dedicated actual-window catch sequence. Inherits the shipped-route loader,
## countdown and raster evidence checks. Three explicit synthetic take_hit()
## calls exercise life/death authority; no claim of OS input or collisions.
## Before death, synthetic grants show all three live power-up chips plus a
## mission banner, followed by the shipped pause panel and synthetic GUI resume.
## Run with tests/capture_runner_catch.py, never against the player's save.

const CATCH_CAPTURE_IDS: PackedStringArray = [
	"overlays_active", "overlays_live", "overlays_countdown", "overlays_paused", "overlays_resumed",
	"catch_impact", "catch_engulf", "catch_snow", "catch_caught", "catch_results", "catch_retry",
]

var _catch_armed: bool = false
var _catch_started: bool = false
var _catch_complete: bool = false
var _catch_reduced: bool = false
var _death_us: int = 0
var _results_first_us: int = 0
var _death_snapshot: Dictionary = {}
var _overlay_stage: String = "waiting"
var _overlay_started_elapsed: float = 0.0
var _pause_draw_serial: int = 0
var _overlay_events: Dictionary = {}
var _retry_requested := false
var _retry_activated := false
var _catch_retry_evidence: Dictionary = {}
var _allow_unfocused_raster := false


func _ready() -> void:
	if _monitor:
		_allow_unfocused_raster = "raster_background=1" in OS.get_cmdline_user_args()
		_catch_reduced = "catch_reduced=1" in OS.get_cmdline_user_args()
		if "touch=1" in OS.get_cmdline_user_args():
			GameConfig.force_touch = true
			SettingsManager._apply_ui_scale(float(SettingsManager.get_setting("accessibility", "ui_scale")))
		# Isolated fixture settings only. No account request or live save.
		GameConfig.force_native_offline_mvp = true
		SettingsManager.settings["accessibility"]["reduced_flashing"] = _catch_reduced
	super._ready()


func _snapshot(phase: String) -> Dictionary:
	var row := super._snapshot(phase)
	var game := get_tree().current_scene as RunnerGame
	if game == null:
		return row
	row.merge({
		"dead": game._dead, "score": game._score, "fish": game.fish,
		"hits_left": game.player.hits_left if game.player != null else -1,
		"player_state": game.player.state if game.player != null else -1,
		"catch_elapsed": game._catch_elapsed,
		"results_present": game.hud != null and is_instance_valid(game.hud._game_over),
		"catch_reduced": _catch_reduced,
		"catch_wall_seconds": float(Time.get_ticks_usec() - _death_us) / 1000000.0 if _death_us > 0 else 0.0,
		"death_authority": "three synthetic RunnerPlayer.take_hit calls with explicit iframe resets",
		"natural_collision_verified": false,
		"overlay_stage": _overlay_stage,
		"pause_overlay_present": is_instance_valid(game._pause_layer),
		"achievement_toast_count": SceneRouter._toast_layer.get_child_count(),
	})
	var toast_rects: Array[Dictionary] = []
	for toast: Control in SceneRouter._toast_layer.get_children():
		toast_rects.append({"x":toast.position.x, "y":toast.position.y,
			"width":toast.size.x, "height":toast.size.y})
	row["achievement_toast_rects"] = toast_rects
	if game.player != null:
		row["powerup_ids"] = game.player.powerups.keys()
		row["powerup_remaining"] = game.player.powerups.duplicate(true)
		row["player_visual_pose"] = game.player._visual.pose if game.player._visual != null else -1
	if game.hud != null:
		var exclusion_rects: Array[Dictionary] = []
		var exclusion_nodes: Array[Control] = [game.hud._mission_panel, game.hud._headline_column]
		exclusion_nodes.append_array(game.hud._powerup_slots)
		for control: Control in exclusion_nodes:
			if is_instance_valid(control) and control.is_visible_in_tree():
				var rect := control.get_global_rect()
				exclusion_rects.append({"name":str(control.name), "x":rect.position.x, "y":rect.position.y,
					"width":rect.size.x, "height":rect.size.y})
		row["hud_toast_exclusion_rects"] = exclusion_rects
		var mission_labels: Array[Dictionary] = []
		for label: Label in game.hud._mission_labels:
			mission_labels.append({"text": label.text, "width": label.size.x,
				"height": label.size.y, "lines": label.get_line_count(),
				"visible_lines": label.get_visible_line_count()})
		row["mission_labels"] = mission_labels
		var active_chips := 0
		for slot: Control in game.hud._powerup_slots:
			if slot.is_visible_in_tree() and slot.modulate.a >= 0.90:
				active_chips += 1
		row["powerup_chips_visible_count"] = active_chips
		row["mission_banner_visible"] = is_instance_valid(game.hud._banner) \
			and game.hud._banner.is_visible_in_tree() and game.hud._banner.modulate.a >= 0.90
		row["mission_banner_present"] = is_instance_valid(game.hud._banner) \
			and game.hud._banner.is_visible_in_tree() and game.hud._banner.modulate.a > 0.01
	if game.camera != null:
		row["camera_position"] = [game.camera.position.x, game.camera.position.y, game.camera.position.z]
	if game.chaser != null:
		row["chaser_gap"] = game.chaser.gap
		row["catch_snow_visible"] = is_instance_valid(game.chaser._catch_canvas) and game.chaser._catch_canvas.visible
		row["catch_snow_alpha"] = game.chaser._catch_snow.modulate.a if is_instance_valid(game.chaser._catch_snow) else 0.0
		row["catch_illustration_alpha"] = game.chaser._catch_illustration.modulate.a \
			if is_instance_valid(game.chaser._catch_illustration) else 0.0
		row["catch_title_alpha"] = game.chaser._catch_title.modulate.a \
			if is_instance_valid(game.chaser._catch_title) else 0.0
		row["catch_title_visible"] = is_instance_valid(game.chaser._catch_title) \
			and game.chaser._catch_title.is_visible_in_tree()
	return row


func _on_frame_post_draw() -> void:
	super._on_frame_post_draw()
	if _finished or not _catch_armed:
		return
	var row := _snapshot("catch_post_draw")
	var game := get_tree().current_scene as RunnerGame
	if game == null or not bool(row.get("presentation_started", false)):
		return
	if not bool(row["window_visible"]) or (not _allow_unfocused_raster and not bool(row["window_focused"])):
		_violation("catch observation lost required visible/foreground window state", row)
		_finish(true)
		return
	if _retry_requested:
		if not _retry_activated or game.elapsed < 0.15:
			return
		row["cloud_evidence"] = _cloud_evidence(game)
		_check(int(row["cloud_evidence"]["mesh_count"]) == 2
			and int(row["cloud_evidence"]["material_count"]) == 1
			and row["cloud_evidence"]["texture_paths"] == [RunnerPaintedClouds.CLOUD_TEXTURE],
			"real GUI retry retains exactly two clouds sharing one material and texture")
		_check(not game._dead and game.running and game.player._input_enabled
			and game.player.hits_left == 3 and game.hud._game_over == null
			and game.player.distance > 0.0 and not bool(row["catch_snow_visible"])
			and is_zero_approx(float(row["catch_title_alpha"])),
			"real GUI retry renders fresh running hero without catch or result residue")
		_capture("catch_retry", row)
		_catch_complete = true
		_finish(false)
		return
	if not _catch_started:
		if not _advance_overlay_capture(game, row):
			return
		_check(game.player.hits_left == RunnerConfig.MAX_HITS and not game._dead,
			"synthetic catch starts with three lives and live runner")
		for index: int in RunnerConfig.MAX_HITS:
			game.player.invulnerable_for = 0.0
			game.player.take_hit()
			_check(game.player.hits_left == RunnerConfig.MAX_HITS - index - 1
				and game._dead == (index == RunnerConfig.MAX_HITS - 1),
				"synthetic hit %d spends one life; only third starts catch" % (index + 1))
		_death_us = Time.get_ticks_usec()
		_catch_started = true
		_death_snapshot = _snapshot("after_third_synthetic_hit")
		_check(not bool(_death_snapshot["results_present"]) and not game.player._input_enabled,
			"third hit freezes input before any results panel")
		return
	if not is_equal_approx(float(row["distance"]), float(_death_snapshot["distance"])) \
			or not is_equal_approx(float(row["score"]), float(_death_snapshot["score"])):
		_violation("distance or score changed after third hit", row)
	if bool(row["results_present"]) and float(row["catch_elapsed"]) < RunnerGame.CATCH_TIME:
		_violation("results covered catch before its full presentation interval", row)
	for moment: Dictionary in [
		{"id": "catch_impact", "time": 0.25},
		{"id": "catch_engulf", "time": 1.20},
		{"id": "catch_snow", "time": 2.10},
		{"id": "catch_caught", "time": 2.32},
	]:
		if float(row["catch_elapsed"]) >= float(moment["time"]) and not _captures.has(moment["id"]):
			_capture(String(moment["id"]), row)
	if bool(row["results_present"]):
		if _results_first_us == 0:
			_results_first_us = Time.get_ticks_usec()
		if Time.get_ticks_usec() - _results_first_us >= 1500000:
			_capture("catch_results", row)
			_retry_requested = true
			call_deferred("_retry_after_catch", game.get_instance_id(), game.player.get_instance_id())


func _retry_after_catch(game_id: int, player_id: int) -> void:
	var game := get_tree().current_scene as RunnerGame
	if game == null:
		_finish(true)
		return
	_run_index = 1
	if not await _activate_gui_button(game.hud._game_over, "Run Again"):
		_finish(true)
		return
	_catch_retry_evidence = _snapshot("after_gui_retry")
	_previous_process_end = _catch_retry_evidence.duplicate(true)
	_check(game.get_instance_id() == game_id and game.player.get_instance_id() != player_id
		and not game._dead and game.running and game.player._input_enabled
		and is_zero_approx(game.elapsed) and is_zero_approx(game.player.distance)
		and is_zero_approx(game._score) and game.fish == 0 and game.hud._game_over == null,
		"Run Again GUI performs one real in-place retry with a fresh player and zeroed run")
	_retry_activated = true


func _advance_overlay_capture(game: RunnerGame, row: Dictionary) -> bool:
	if _overlay_stage == "waiting":
		if game.elapsed < 0.15:
			return false
		for id: StringName in RunnerConfig.POWERUP_IDS:
			game.player.grant_powerup(id)
		game.hud.show_mission_complete("Collect 60 fish")
		_overlay_started_elapsed = game.elapsed
		_overlay_stage = "powers_settling"
		_overlay_events["powerup_grants"] = {
			"authority": "RunnerPlayer.grant_powerup", "calls": 3,
			"ids": RunnerConfig.POWERUP_IDS, "synthetic": true, "elapsed": game.elapsed}
		_overlay_events["mission_banner"] = {
			"authority": "RunnerHUD.show_mission_complete", "calls": 1,
			"text": "Collect 60 fish", "synthetic": true,
			"mission_completion_verified": false}
		return false
	if _overlay_stage == "powers_settling":
		if game.elapsed - _overlay_started_elapsed < 0.55:
			return false
		_check(int(row.get("powerup_chips_visible_count", 0)) == 3
			and bool(row.get("mission_banner_visible", false)),
			"three active powerup chips and synthetic mission banner visibly settled")
		var toast_bounded := true
		for rect: Dictionary in row["achievement_toast_rects"]:
			toast_bounded = toast_bounded and float(rect["height"]) <= 128.0 \
				and float(rect["width"]) <= 600.0
		_check(toast_bounded, "live achievement notification retains bounded painted panel")
		var toast_unobstructed := true
		for rect: Dictionary in row["achievement_toast_rects"]:
			var toast := Rect2(float(rect["x"]), float(rect["y"]), float(rect["width"]), float(rect["height"]))
			for excluded: Dictionary in row["hud_toast_exclusion_rects"]:
				var occupied := Rect2(float(excluded["x"]), float(excluded["y"]), float(excluded["width"]), float(excluded["height"]))
				toast_unobstructed = toast_unobstructed and not toast.intersects(occupied)
		_check(toast_unobstructed, "every live achievement toast avoids powerup slots, challenges and headline")
		_capture("overlays_active", row)
		_overlay_stage = "powers_draining"
		return false
	if _overlay_stage == "powers_draining":
		# Let GO, real pickup floaters, achievement toast and mission banner
		# finish naturally, including a real mission earned during these frames.
		# Keep actual simulation running; do not hide any live notification.
		if game.elapsed - _overlay_started_elapsed < 4.30 \
				or int(row["achievement_toast_count"]) > 0 \
				or bool(row["mission_banner_present"]) \
				or not game.hud._message_label.text.is_empty():
			return false
		var magnet := RunnerConfig.POWERUP_IDS.find(RunnerConfig.POWERUP_MAGNET)
		var remaining := float(game.player.powerups.get(RunnerConfig.POWERUP_MAGNET, 0.0))
		_check(remaining > 0.0 and remaining < RunnerConfig.POWERUP_TIME - 2.0
			and is_equal_approx(game.hud._powerup_rings[magnet].value, remaining / RunnerConfig.POWERUP_TIME),
			"rendered magnet countdown drains with normal gameplay time")
		_capture("overlays_countdown", row)
		_check(int(row["achievement_toast_count"]) == 0 and not bool(row["mission_banner_present"])
			and game.hud._message_label.text.is_empty(),
			"clean live HUD waits for real GO banner and achievement notice expiry")
		row["course_material_evidence"] = _course_material_evidence(game)
		row["cloud_evidence"] = _cloud_evidence(game)
		_check(int(row["cloud_evidence"]["mesh_count"]) == 2
			and int(row["cloud_evidence"]["material_count"]) == 1
			and row["cloud_evidence"]["texture_paths"] == [RunnerPaintedClouds.CLOUD_TEXTURE],
			"actual course has exactly two cloud meshes sharing one material and texture")
		_check("res://assets/art/runner/textures/runner_crystal_ice_v2.webp"
			in row["course_material_evidence"]["texture_paths"],
			"actual visible course binds reference crystal ice texture")
		_capture("overlays_live", row)
		_overlay_stage = "pause_settling"
		_pause_draw_serial = _draw_serial
		game._on_hud_pause_pressed()
		_overlay_events["pause"] = {
			"authority": "RunnerGame._on_hud_pause_pressed", "calls": 1,
			"synthetic": true, "before": row.duplicate(true)}
		_check(get_tree().paused and is_instance_valid(game._pause_layer),
			"synthetic pause request opened shipped pause overlay")
		return false
	if _overlay_stage == "pause_settling":
		if _draw_serial < _pause_draw_serial + 2:
			return false
		var before: Dictionary = _overlay_events["pause"]["before"]
		_check(bool(row["paused"]) and bool(row["pause_overlay_present"])
			and is_equal_approx(float(row["elapsed"]), float(before["elapsed"]))
			and is_equal_approx(float(row["distance"]), float(before["distance"]))
			and is_equal_approx(float(row["score"]), float(before["score"])),
			"rendered pause overlay keeps gameplay distance score and clock frozen")
		_check(row["powerup_remaining"] == before["powerup_remaining"],
			"rendered pause retains exact magnet and shield durations")
		_capture("overlays_paused", row)
		var wordmark := game._pause_layer.find_child("PausedWordmark", true, false) as TextureRect
		_check(wordmark != null and wordmark.is_visible_in_tree()
			and wordmark.texture == RunnerHUDArt.paused_wordmark(),
			"pause displays generated sculpted PAUSED artwork")
		_overlay_stage = "resuming_gui"
		_resume_overlay.call_deferred()
		return false
	if _overlay_stage == "resuming_gui":
		return false
	if _overlay_stage == "resumed":
		_check(not bool(row["paused"]) and not bool(row["pause_overlay_present"])
			and game.running and game.player._input_enabled,
			"resumed frame shows live runner after one synthetic GUI Resume")
		_capture("overlays_resumed", row)
		# Retire the fixture-only powerups through their real expiry authority.
		# In particular, the shield must not eat one of the three damage hits.
		game.player._advance_powerups(RunnerConfig.POWERUP_TIME + 1.0)
		_overlay_events["powerup_expiry"] = {
			"authority": "RunnerPlayer._advance_powerups", "calls": 1,
			"delta": RunnerConfig.POWERUP_TIME + 1.0, "synthetic": true,
			"gameplay_clock_unchanged": true}
		_check(game.player.powerups.is_empty() and game.player.hits_left == RunnerConfig.MAX_HITS,
			"fixture powerups expire before three-hit catch without spending life")
		_overlay_stage = "complete"
		return true
	return _overlay_stage == "complete"


func _cloud_evidence(root_node: Node) -> Dictionary:
	var materials: Dictionary = {}
	var textures: Dictionary = {}
	var mesh_count := 0
	for bank: Node in root_node.find_children("*", "Node3D", true, false):
		if not bank is RunnerPaintedClouds:
			continue
		for node: Node in bank.get_children():
			if node is MeshInstance3D:
				mesh_count += 1
				var material := (node as MeshInstance3D).material_override as StandardMaterial3D
				if material != null:
					materials[material.get_instance_id()] = true
					if material.albedo_texture != null:
						textures[material.albedo_texture.resource_path] = true
	return {"mesh_count":mesh_count, "material_count":materials.size(),
		"texture_paths":textures.keys()}


func _course_material_evidence(root_node: Node) -> Dictionary:
	var shaders: Dictionary = {}
	var textures: Dictionary = {}
	var painted_instances := 0
	for node: Node in root_node.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree():
			continue
		var material := geometry.material_override as ShaderMaterial
		if material == null or material.shader == null:
			continue
		shaders[material.shader.resource_path] = true
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(uniform["name"])
			if value is Texture2D:
				textures[(value as Texture2D).resource_path] = true
				if String(uniform["name"]) == "painted_albedo":
					painted_instances += 1
	return {"visible_painted_instances": painted_instances,
		"shader_paths": shaders.keys(), "texture_paths": textures.keys(),
		"scope": "actual visible GeometryInstance3D material bindings at live capture; not a 3D-library regeneration"}


func _resume_overlay() -> void:
	var game := get_tree().current_scene as RunnerGame
	if game == null or not await _activate_gui_button(game._pause_layer, "Resume"):
		_finish(true)
		return
	_overlay_events["resume"] = {"authority": "synthetic viewport GUI touch/emulated-mouse Resume",
		"calls": int(_gui_activations.get("Resume", 0)), "synthetic": true,
		"os_input_verified": false}
	_overlay_stage = "resumed"


func _required_capture_ids() -> PackedStringArray:
	var ids := super._required_capture_ids()
	ids.append_array(CATCH_CAPTURE_IDS)
	return ids


func _finish(timed_out: bool) -> void:
	# The base fixture normally stops at its first moving frame. Keep that
	# evidence, then continue through the explicitly labeled catch sequence.
	if not timed_out and not _catch_complete:
		_catch_armed = true
		return
	_check(_catch_complete, "third-hit catch and delayed results visibly completed")
	if "raster_nonactivating_visible=1" in OS.get_cmdline_user_args():
		var actual_flags := true
		for capture: Dictionary in _captures.values():
			var frame: Dictionary = capture.get("snapshot", {})
			actual_flags = actual_flags and bool(frame.get("window_no_focus", false)) \
				and bool(frame.get("window_always_on_top", false))
		_check(actual_flags, "nonactivating visible raster retained actual no-focus and floating flags")
	_check(_overlay_stage == "complete" and _overlay_events.size() == 5
		and int(_gui_activations.get("Resume", 0)) == 1,
		"one synthetic powerup/banner pause/resume sequence completed before catch")
	for id: String in ["catch_impact", "catch_engulf", "catch_snow", "catch_caught"]:
		var frame: Dictionary = _captures.get(id, {}).get("snapshot", {})
		_check(not frame.is_empty() and not bool(frame.get("results_present", true))
			and bool(frame.get("catch_snow_visible", false)), id + " retains snow/world without results")
	var final_frame: Dictionary = _captures.get("catch_results", {}).get("snapshot", {})
	_check(bool(final_frame.get("results_present", false))
		and is_equal_approx(float(final_frame.get("catch_elapsed", -1.0)), RunnerGame.CATCH_TIME),
		"results follow the completed 2.4 second catch")
	_check(is_equal_approx(float(final_frame.get("catch_illustration_alpha", 0.0)), 1.0),
		"full caught-in-snow illustration precedes results controls")
	for id: String in ["catch_engulf", "catch_snow"]:
		var frame: Dictionary = _captures.get(id, {}).get("snapshot", {})
		_check(bool(frame.get("catch_title_visible", false)) and float(frame.get("catch_title_alpha", 0.0)) >= 0.95,
			id + " retains full avalanche headline beyond transient HUD toast duration")
		_check(int(frame.get("player_visual_pose", -1)) == PenguinVisual.Pose.SLIDE
			and int(frame.get("player_state", -1)) == RunnerPlayer.State.DEAD,
			id + " uses prone visual pose while gameplay remains dead")
	_check(int(_gui_activations.get("Run Again", 0)) == 1 and _retry_activated,
		"exactly one synthetic GUI Run Again completes native retry authority")
	if _catch_reduced:
		var snow_frame: Dictionary = _captures.get("catch_snow", {}).get("snapshot", {})
		_check(snow_frame.get("camera_position") == _death_snapshot.get("camera_position"),
			"reduced motion catch preserves camera position")
	super._finish(timed_out)
	# The inherited report includes unchanged loader checks. Replace its generic
	# no-input limitation with the exact synthetic authority used by this scene.
	var report_path := _out.get_basename() + ".json"
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	if report is Dictionary:
		report["kind"] = "runner_third_hit_avalanche_catch"
		report["raster_focus_policy"] = "visible submitted raster; keyboard focus recorded but not required" if _allow_unfocused_raster else "visible and focused submitted raster"
		report["allow_unfocused_raster"] = _allow_unfocused_raster
		report["nonactivating_visible_raster"] = "raster_nonactivating_visible=1" in OS.get_cmdline_user_args()
		report["overlay_presentation"] = _overlay_events
		report["retry"] = {"authority":"one synthetic viewport GUI Run Again", "snapshot":_catch_retry_evidence,
			"activation_count":int(_gui_activations.get("Run Again", 0)), "physical_input_verified":false}
		report["catch"] = {"reduced_motion": _catch_reduced, "duration": RunnerGame.CATCH_TIME,
			"synthetic_hit_calls": 3 if _catch_started else 0,
			"iframe_resets": 3 if _catch_started else 0,
			"death_snapshot": _death_snapshot, "physical_input_verified": false,
			"natural_collision_verified": false, "visual_review_required": true}
		report["limitations"] = "Real SceneRouter/countdown/gameplay rendered in a desktop window. Synthetic grant_powerup for all three powers and direct mission banner call exercise presentation, not natural collection or mission completion. Production pause authority and one synthetic viewport GUI Resume are followed by explicit powerup expiry; gameplay clocks remain normal. Three synthetic take_hit calls with explicit iframe resets trigger shipped death authority. No natural collision, OS input, browser, native device or performance acceptance. PNG readbacks perturb wall time. Layout and snow coverage require image review."
		if report["nonactivating_visible_raster"]:
			report["limitations"] += " Capture-only documented no-focus and floating window flags keep pixels visible without keyboard activation; this is not ordinary unfocused/occluded application performance evidence."
		if _allow_unfocused_raster:
			report["limitations"] += " Explicit background-raster mode permits missing keyboard focus; each frame records actual focus. Visible window, real post-draw capture, state/GUI authority and bounded deadlines remain required. This is not foreground interaction or performance acceptance."
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t") + "\n")
			file.close()
