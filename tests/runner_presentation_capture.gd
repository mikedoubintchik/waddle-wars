extends Node
## Actual-window SceneRouter -> RunnerGame handoff proof. Run ONLY through
## run_frontend_qa.sh runner_handoff, which provides a copied project/user://.
## Default: no router overrides, synthetic draw signals, clocks or injected input.
## Optional cycle=1 adds synthetic GUI input and one explicitly forced death;
## gameplay clocks, loader and retry authority remain the shipped ones.
## Optional chase=1 instead continues real gameplay to 6 seconds, recording
## the snow front at 4 and 6 seconds without input, forced death or clock edits.
## chase=1 chase_actions=1 adds one direct jump() and take_hit() after the 4s
## baseline, with midair/post-hit captures. This is synthetic action coverage,
## not physical input or natural-collision proof; gameplay clocks stay real.
## Readbacks perturb frame time: this is ordering/visibility QA, not a benchmark.
## native_trace=1 is a separately labeled, baked-in native QA derivative only:
## it logs existing warmup events without screenshots/input or a watchdog change.
## This fixture remains excluded from production exports.

const TIMEOUT_SECONDS: float = 60.0
const MAX_SAMPLES: int = 30000
const MAX_VIOLATIONS: int = 32
const EPSILON: float = 0.00001
const CAPTURE_IDS: PackedStringArray = [
	"loader", "clear", "countdown_3", "countdown_2", "countdown_1", "go", "moving",
]
const CYCLE_CAPTURE_IDS: PackedStringArray = [
	"pause", "resumed", "results", "retry_go", "retry_moving",
]

var _monitor: bool = false
var _out: String = ""
var _size: Vector2i = Vector2i(540, 960)
var _started: bool = false
var _finished: bool = false
var _start_us: int = 0
var _process_serial: int = 0
var _draw_serial: int = 0
var _samples: Array[Dictionary] = []
var _sample_drops: int = 0
var _violations: Array[Dictionary] = []
var _violation_count: int = 0
var _checks: Array[Dictionary] = []
var _captures: Dictionary = {}
var _first_clear_draw: Dictionary = {}
var _first_presentation: Dictionary = {}
var _first_running: Dictionary = {}
var _first_countdown_draw: Dictionary = {}
var _numerals: Array[String] = []
var _scene_events: Array[Dictionary] = []
var _guarded_runner_samples: int = 0
var _guarded_runner_draws: int = 0
var _previous_process_end: Dictionary = {}
var _countdown_delta_sum: float = 0.0
var _countdown_delta_last: float = 0.0
var _countdown_steps: int = 0
var _cycle: bool = false
var _chase: bool = false
var _chase_actions: bool = false
var _chase_action_events: Dictionary = {}
var _cycle_stage: String = "initial"
var _run_index: int = 0
var _cycle_game_id: int = 0
var _forced_deaths: int = 0
var _gui_activations: Dictionary = {}
var _retry_baseline: Dictionary = {}
var _retry_first_running: Dictionary = {}
var _retry_first_countdown_draw: Dictionary = {}
var _retry_numerals: Array[String] = []
var _retry_guarded_samples: int = 0
var _retry_delta_sum: float = 0.0
var _retry_delta_last: float = 0.0
var _retry_steps: int = 0
var _native_trace: bool = false
var _warmup_events: Array[Dictionary] = []
var _trace_state: String = ""
var _trace_last_us: int = 0
var _trace_previous_initial: bool = false
var _trace_previous_shader: bool = false
var _native_recovery_us: int = 0
var _native_recovery_snapshot: Dictionary = {}


func _ready() -> void:
	# --check-only --script does not register project autoload identifiers.
	# Load this real scene normally for a parser-only headless gate; never
	# present that gate as a rendered handoff or mutate gameplay/save state.
	if not _monitor and GameConfig.is_headless() and "parse_only=1" in OS.get_cmdline_user_args():
		print("[runner-handoff-parse] PASS: capture scene and project autoload references compile; no visual checks run")
		get_tree().quit(0)
		return
	if not _monitor:
		# The current scene will be deleted by the real scene swap. Its sibling
		# monitor stays alive without becoming an autoload or replacing a manager.
		call_deferred("_install_monitor")
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100000
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			match parts[0]:
				"out": _out = parts[1].simplify_path()
				"w": _size.x = int(parts[1])
				"h": _size.y = int(parts[1])
				"cycle": _cycle = parts[1] == "1"
				"chase": _chase = parts[1] == "1"
				"chase_actions": _chase_actions = parts[1] == "1"
				"native_trace": _native_trace = parts[1] == "1"
	if _native_trace:
		_out = ProjectSettings.globalize_path("user://runner-native-trace.png")
	if not _validate_environment():
		get_tree().quit(2)
		return
	if _native_trace:
		_size = Vector2i(get_viewport().get_visible_rect().size)
		ShaderWarmup.clear_perf_trace()
		InitialVisualWarmup.clear_perf_trace()
		ShaderWarmup.perf_trace_enabled = true
		InitialVisualWarmup.perf_trace_enabled = true
		print("[runner-native-trace] " + JSON.stringify({
			"kind": "diagnostic_only", "build_id": GameConfig.BUILD_ID,
			"renderer": RenderingServer.get_current_rendering_method(),
			"viewport": [_size.x, _size.y], "route": Game.SCENE_RUNNER,
			"watchdog_msec": SceneRouter.WARMUP_TIMEOUT_MSEC,
			"qa_feature": OS.has_feature("waddle_native_trace_qa"),
			"debug_build": OS.is_debug_build(),
			"screenshots": false, "synthetic_input": false,
			"boot_menu_route_verified": false, "acceptance": false,
		}))
	else:
		DisplayServer.window_set_size(_size)
		if "raster_nonactivating_visible=1" in OS.get_cmdline_user_args():
			# Documented macOS window flags keep a submitted-raster fixture
			# visible without taking keyboard focus. Never used by performance QA.
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
			var usable := DisplayServer.screen_get_usable_rect()
			DisplayServer.window_set_position(usable.position + Vector2i(maxi(20, usable.size.x - _size.x - 20), 40))
		if _chase:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
		if "raster_background=1" not in OS.get_cmdline_user_args():
			DisplayServer.window_move_to_foreground()
	if _cycle:
		# Existing QA-only hooks model phone layout/input and disable native
		# services; these are not actual mobile OS/build feature declarations.
		GameConfig.force_touch = true
		GameConfig.force_native_offline_mvp = true
		LayoutProfile.forced_insets = Vector4(24.0, 24.0, 24.0, 24.0)
		SettingsManager._apply_ui_scale(float(SettingsManager.get_setting("accessibility", "ui_scale")))
	get_tree().process_frame.connect(_on_process_frame)
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	SceneRouter.scene_changed.connect(_on_scene_changed)
	await get_tree().process_frame
	await get_tree().process_frame
	if "foreground_gate=1" in OS.get_cmdline_user_args():
		DisplayServer.window_set_position(Vector2i(40,60))
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
		DisplayServer.window_move_to_foreground()
		var focus_deadline := Time.get_ticks_msec() + 20000
		print("[runner-handoff] awaiting actual foreground activation before production route")
		while not get_window().has_focus() and Time.get_ticks_msec() < focus_deadline:
			await get_tree().process_frame
		if not get_window().has_focus():
			push_error("runner-handoff: foreground activation gate expired; no gameplay acceptance")
			get_tree().quit(2)
			return
		print("[runner-handoff] actual foreground activation confirmed")
	get_tree().create_timer(TIMEOUT_SECONDS, true, false, true).timeout.connect(_on_timeout)
	_start_us = Time.get_ticks_usec()
	_started = true
	# Production entry point sets mode/course and invokes
	# SceneRouter.go_to(Game.SCENE_RUNNER); the ResourceLoader and swap are real.
	Game.start_runner()


func _install_monitor() -> void:
	var monitor: Node = get_script().new()
	monitor.name = "RunnerPresentationMonitor"
	monitor.set("_monitor", true)
	get_tree().root.add_child(monitor)
	set_process(false)


func _validate_environment() -> bool:
	if _chase_actions and not _chase:
		push_error("[runner-handoff] chase_actions=1 requires chase=1")
		return false
	if _chase and (_cycle or _native_trace):
		push_error("[runner-handoff] chase=1 requires standalone visual observation")
		return false
	var custom_name := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) \
			or not custom_name.begins_with("waddle-wars-frontend-"):
		push_error("[runner-handoff] Run through run_frontend_qa.sh; isolated user:// is required")
		return false
	if GameConfig.is_headless():
		push_error("[runner-handoff] Actual-window proof requires a rendering device; no headless pass")
		return false
	if _native_trace:
		if _cycle or OS.is_debug_build() or not (OS.has_feature("android") or OS.has_feature("ios")) \
				or not OS.has_feature("waddle_native_trace_qa") \
				or not custom_name.begins_with("waddle-wars-frontend-native-"):
			push_error("[runner-native-trace] Requires dedicated native QA export marker and no cycle")
			return false
		if FileAccess.file_exists(_out.get_basename() + ".json"):
			push_error("[runner-native-trace] Existing report; use fresh isolated QA data")
			return false
		return true
	if _size.x < 240 or _size.y < 240 or _size.x > 4096 or _size.y > 4096:
		push_error("[runner-handoff] w/h must be between 240 and 4096")
		return false
	var project_path := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var user_path := ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	if _out.is_empty() or not _out.is_absolute_path() or not _out.ends_with(".png") \
			or _out.begins_with(project_path + "/") or _out.begins_with(user_path + "/"):
		push_error("[runner-handoff] out must be an absolute .png outside copied project and user://")
		return false
	for id: String in _required_capture_ids():
		if FileAccess.file_exists(_capture_path(id)):
			push_error("[runner-handoff] Choose a fresh output prefix; screenshot exists: " + id)
			return false
	if FileAccess.file_exists(_out.get_basename() + ".json"):
		push_error("[runner-handoff] Choose a fresh output prefix; JSON report exists")
		return false
	if DirAccess.make_dir_recursive_absolute(_out.get_base_dir()) != OK:
		push_error("[runner-handoff] Cannot create output directory")
		return false
	return true


func _on_process_frame() -> void:
	_process_serial += 1
	_observe("process_begin")


func _process(delta: float) -> void:
	if _monitor:
		if _native_trace and _started and not _finished:
			_drain_native_warmup_trace()
		# High priority samples after normal gameplay nodes. Tween updates may
		# follow this callback; frame_post_draw supplies the final submitted state.
		var row := _observe("process_end")
		if row.is_empty():
			return
		row["process_delta"] = delta
		if bool(row.get("runner_present", false)) \
				and bool(_previous_process_end.get("presentation_started", false)) \
				and not bool(_previous_process_end.get("running", true)) \
				and not bool(_previous_process_end.get("dead", false)) \
				and not bool(row.get("dead", false)) \
				and not bool(_previous_process_end.get("paused", true)) \
				and not bool(row["paused"]) \
				and int(_previous_process_end.get("run_index", 0)) == _run_index:
			# Same engine process delta received by RunnerGame, rather than wall
			# time inflated by PNG readbacks. First latch frame charges no delta.
			if _run_index == 0:
				_countdown_delta_sum += delta
				_countdown_delta_last = delta
				_countdown_steps += 1
			else:
				_retry_delta_sum += delta
				_retry_delta_last = delta
				_retry_steps += 1
			var consumed := float(_previous_process_end["countdown"]) - float(row["countdown"])
			if absf(consumed - delta) > 0.0001:
				_violation("visible countdown did not consume exactly its process delta", row)
		_previous_process_end = row


func _on_scene_changed(path: String) -> void:
	_scene_events.append({"path": path, "process_serial": _process_serial,
		"draw_serial": _draw_serial, "time_us": Time.get_ticks_usec()})


func _snapshot(phase: String) -> Dictionary:
	var game := get_tree().current_scene as RunnerGame
	var row := {
		"phase": phase, "time_us": Time.get_ticks_usec(),
		"process_serial": _process_serial, "draw_serial": _draw_serial,
		"engine_process_frame": Engine.get_process_frames(),
		"paused": get_tree().paused,
		"window_focused": get_window().has_focus(),
		"window_visible": get_window().visible and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED,
		"window_mode": DisplayServer.window_get_mode(),
		"router_busy": SceneRouter.is_busy(), "router_presenting": SceneRouter.is_presenting(),
		"router_swap_busy": SceneRouter._busy,
		"fade_visible": SceneRouter._fade_rect.is_visible_in_tree(),
		"fade_alpha": SceneRouter._fade_rect.modulate.a,
		"loading_box_visible": SceneRouter._loading_box.is_visible_in_tree(),
		"loading_box_alpha": SceneRouter._loading_box.modulate.a,
		"loading_stage": SceneRouter._loading_label.text,
		"loading_progress": SceneRouter._loading_progress.value,
		"runner_present": game != null,
		"window_no_focus": DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS),
		"window_always_on_top": DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP),
	}
	if game == null:
		return row
	row.merge({
		"scene_path": game.scene_file_path, "build_finished": game.build_finished,
		"warmup_alive": is_instance_valid(game._startup_warmup),
		"presentation_started": game._presentation_started,
		"countdown": game._countdown, "running": game.running,
		"elapsed": game.elapsed, "player_present": game.player != null,
		"camera_present": game.camera != null,
		"hud_text": "", "hud_visible": false, "hud_alpha": 0.0,
	})
	if game.player != null:
		row.merge({"distance": game.player.distance, "input_enabled": game.player._input_enabled,
			"player_position": [game.player.position.x, game.player.position.y, game.player.position.z]})
		if _chase_actions:
			row.merge({"player_height": game.player.position.y, "player_state": game.player.state,
				"hits_left": game.player.hits_left, "invulnerable_for": game.player.invulnerable_for,
				"shielded": game.player.has_powerup(RunnerConfig.POWERUP_SHIELD)})
	if _chase and game.chaser != null:
		row.merge({"dead": game._dead, "chaser_gap": game.chaser.gap,
			"chaser_clock": game.chaser._time, "wave_clock": game.chaser._wave_time,
			"wave_visible": is_instance_valid(game.chaser._intro_wave) \
				and game.chaser._intro_wave.is_visible_in_tree(),
			"wave_alpha": game.chaser._intro_front.modulate.a \
				if is_instance_valid(game.chaser._intro_front) else 0.0})
		if is_instance_valid(game.chaser._intro_wave):
			row["spray_gap"] = game.chaser._intro_wave.global_position.z + game.player.distance
	var initial_warmup := game.get_node_or_null("InitialVisualWarmup") as InitialVisualWarmup
	row["initial_warmup_present"] = initial_warmup != null
	if _native_trace:
		# Diagnostic-only readback distinguishes a skipped cover guard from a
		# slow draw after it engaged. Never modifies renderer/workload settings.
		row["opaque_loading_cover"] = SceneRouter.has_opaque_loading_cover(game)
		row["covered_background_active"] = game._covered_warmup_environment != null
		if is_instance_valid(game._world_env) and game._world_env.environment != null:
			var environment := game._world_env.environment
			row["environment_background_mode"] = environment.background_mode
			row["environment_reflection_source"] = environment.reflected_light_source
			row["environment_ambient_source"] = environment.ambient_light_source
	if initial_warmup != null:
		row["initial_warmup_cursor"] = initial_warmup._cursor
		row["initial_warmup_awaiting_draw"] = initial_warmup._awaiting_draw
		if _native_trace:
			row["initial_warmup_total"] = initial_warmup._visible_queue.size()
			row["initial_warmup_pending_name"] = initial_warmup._pending_name
			row["initial_warmup_processing"] = initial_warmup.is_processing()
			row["initial_warmup_recovery_suspended"] = initial_warmup._recovery_suspended
			row["initial_warmup_draw_connected"] = RenderingServer.frame_post_draw.is_connected(initial_warmup._on_frame_post_draw)
	if _native_trace and is_instance_valid(game._startup_warmup):
		row["shader_warmup_cursor"] = game._startup_warmup._queue_cursor
		row["shader_warmup_total"] = game._startup_warmup._queue.size()
		row["shader_warmup_awaiting_draw"] = game._startup_warmup._awaiting_draw
		row["shader_warmup_render_serial"] = game._startup_warmup._render_serial
		row["shader_warmup_processing"] = game._startup_warmup.is_processing()
		row["shader_warmup_recovery_suspended"] = game._startup_warmup._recovery_suspended
		row["shader_warmup_draw_connected"] = RenderingServer.frame_post_draw.is_connected(game._startup_warmup._on_frame_post_draw)
	if game.hud != null and game.hud._message_label != null:
		row["hud_text"] = game.hud._message_label.text
		row["hud_visible"] = game.hud._message_label.is_visible_in_tree()
		row["hud_alpha"] = game.hud._message_label.modulate.a
	if _cycle:
		row.merge({"run_index": _run_index, "cycle_stage": _cycle_stage,
			"dead": game._dead, "game_instance_id": game.get_instance_id(),
			"score": game._score, "fish": game.fish,
			"player_instance_id": game.player.get_instance_id() if game.player != null else 0,
			"player_state": game.player.state if game.player != null else -1,
			"lane": game.player.lane if game.player != null else -1,
			"touch_present": is_instance_valid(game._touch),
			"pause_overlay_present": is_instance_valid(game._pause_layer),
			"results_present": game.hud != null and is_instance_valid(game.hud._game_over),
			"pause_button_visible": game.hud != null and game.hud._pause_button.is_visible_in_tree(),
		})
	return row


func _observe(phase: String) -> Dictionary:
	if not _started or _finished:
		return {}
	var row := _snapshot(phase)
	if _native_trace and phase == "process_end":
		_trace_native_state(row)
	if _samples.size() < MAX_SAMPLES:
		_samples.append(row)
	else:
		_sample_drops += 1
	if not bool(row["runner_present"]):
		return row
	var covered := bool(row["fade_visible"]) and float(row["fade_alpha"]) > EPSILON
	var guarded := bool(row["router_busy"]) or bool(row["router_presenting"]) or covered
	if guarded:
		_guarded_runner_samples += 1
		if phase == "post_draw":
			_guarded_runner_draws += 1
		if _run_index == 1:
			_retry_guarded_samples += 1
		if bool(row["presentation_started"]) or bool(row["running"]) \
				or absf(float(row["countdown"]) - RunnerGame.COUNTDOWN_TIME) > EPSILON:
			_violation("countdown or presentation advanced while loader guarded gameplay", row)
		if float(row["elapsed"]) > EPSILON or float(row.get("distance", 0.0)) > EPSILON \
				or bool(row.get("input_enabled", false)):
			_violation("movement or input enabled underneath loading presentation", row)
	if not bool(row["running"]) and not bool(row.get("dead", false)) \
			and (float(row.get("distance", 0.0)) > EPSILON \
			or bool(row.get("input_enabled", false))):
		_violation("movement or input enabled before GO", row)
	if _run_index == 0 and bool(row["presentation_started"]) and _first_presentation.is_empty():
		_first_presentation = row.duplicate(true)
		if _first_clear_draw.is_empty() or _process_serial <= int(_first_clear_draw.get("process_serial", _process_serial)):
			_violation("presentation started before a cleared draw and following process frame", row)
		if absf(float(row["countdown"]) - RunnerGame.COUNTDOWN_TIME) > EPSILON:
			_violation("first presentation frame consumed countdown time", row)
	if _run_index == 0 and bool(row["running"]) and _first_running.is_empty():
		_first_running = row.duplicate(true)
	elif _run_index == 1 and bool(row["running"]) and _retry_first_running.is_empty():
		_retry_first_running = row.duplicate(true)
	return row


func _on_frame_post_draw() -> void:
	_draw_serial += 1
	var row := _observe("post_draw")
	if row.is_empty():
		return
	if _native_trace:
		_drain_native_warmup_trace()
		if bool(row.get("runner_present", false)) and bool(row.get("build_finished", false)) \
				and not bool(row["fade_visible"]) and not bool(row["loading_box_visible"]) \
				and _first_clear_draw.is_empty():
			_first_clear_draw = row.duplicate(true)
			if not bool(row["router_presenting"]):
				_violation("router released presentation before the first cleared draw", row)
			if bool(row["warmup_alive"]) or bool(row["presentation_started"]):
				_violation("first cleared draw did not retain a ready, stationary runner", row)
		if bool(row.get("running", false)) and float(row.get("distance", 0.0)) > 0.01:
			_finish_native_trace("first_movement")
		return
	if not _captures.has("loader") and bool(row["fade_visible"]) \
			and float(row["fade_alpha"]) >= 0.999 and bool(row["loading_box_visible"]) \
			and SceneRouter._loading_mascot != null and SceneRouter._loading_mascot.is_visible_in_tree():
		_capture("loader", row)
	if not bool(row["runner_present"]) or not bool(row.get("build_finished", false)):
		return
	var clear := not bool(row["fade_visible"]) and not bool(row["loading_box_visible"])
	if clear and _first_clear_draw.is_empty():
		_first_clear_draw = row.duplicate(true)
		_capture("clear", row)
		if not bool(row["router_presenting"]):
			_violation("router released presentation before the first cleared draw", row)
		if bool(row["warmup_alive"]) or bool(row["presentation_started"]):
			_violation("first cleared draw did not retain a ready, stationary runner", row)
	if not clear:
		return
	var text := str(row["hud_text"])
	if _chase and bool(row.get("dead", false)):
		_violation("runner died before requested avalanche observation completed", row)
		_finish(false)
		return
	if _chase and bool(row["running"]):
		if _chase_actions and (not bool(row["window_focused"]) or not bool(row["window_visible"])):
			_violation("synthetic chase action observation lost the foreground window", row)
			_finish(false)
			return
		for second: int in [4, 6]:
			var capture_id := "chase_%ds" % second
			if float(row["elapsed"]) >= float(second) and not _captures.has(capture_id):
				_capture(capture_id, row)
		if _chase_actions:
			_advance_chase_actions(row)
			if _finished:
				return
		if _captures.has("chase_6s") and (not _chase_actions or _captures.has("chase_post_hit")):
			_finish(false)
			return
	if _cycle and _run_index == 1:
		if _cycle_stage != "retry_running":
			return
		if bool(row["hud_visible"]) and float(row["hud_alpha"]) > 0.05:
			if text == "GO!" and bool(row["running"]) and not _captures.has("retry_go"):
				_capture("retry_go", row)
		if bool(row["running"]) and float(row.get("distance", 0.0)) > 0.01 \
				and not _captures.has("retry_moving"):
			_capture("retry_moving", row)
			_cycle_stage = "complete"
			_finish(false)
		return
	if bool(row["hud_visible"]) and float(row["hud_alpha"]) > 0.05:
		if text in ["3", "2", "1"] and not _numerals.has(text):
			if _first_countdown_draw.is_empty():
				_first_countdown_draw = row.duplicate(true)
			_numerals.append(text)
			_capture("countdown_" + text, row)
		elif text == "GO!" and bool(row["running"]) and not _captures.has("go"):
			_capture("go", row)
	if bool(row["running"]) and float(row.get("distance", 0.0)) > 0.01 \
			and not _captures.has("moving"):
		_capture("moving", row)
		if _cycle:
			_cycle_stage = "pause_entry"
			call_deferred("_run_cycle")
		elif not _chase:
			_finish(false)


func _advance_chase_actions(row: Dictionary) -> void:
	var elapsed := float(row["elapsed"])
	if elapsed >= 8.0:
		_violation("synthetic chase actions did not complete before eight seconds of real gameplay", row)
		_finish(false)
		return
	if not _captures.has("chase_4s"):
		return
	var game := get_tree().current_scene as RunnerGame
	if not _chase_action_events.has("jump") and elapsed >= 4.25:
		if int(row["player_state"]) != RunnerPlayer.State.RUN or float(row["player_height"]) > 0.01:
			return
		# Direct shipped action authority; never change clocks, position, lives,
		# invulnerability, RNG or hazard placement to make a fixture succeed.
		var before := _snapshot("before_synthetic_jump")
		game.player.jump()
		_chase_action_events["jump"] = {"authority": "RunnerPlayer.jump", "call_count": 1,
			"before": before, "after": _snapshot("after_synthetic_jump")}
		return
	if _chase_action_events.has("jump") and not _captures.has("chase_midair"):
		var jump_before: Dictionary = _chase_action_events["jump"]["before"]
		if elapsed >= float(jump_before["elapsed"]) + 0.2 \
				and int(row["player_state"]) == RunnerPlayer.State.JUMP and float(row["player_height"]) > 0.3:
			_capture("chase_midair", row)
	if _captures.has("chase_midair") and not _chase_action_events.has("hit") and elapsed >= 5.5:
		if int(row["player_state"]) != RunnerPlayer.State.RUN or float(row["player_height"]) > 0.01 \
				or int(row["hits_left"]) != RunnerConfig.MAX_HITS \
				or float(row["invulnerable_for"]) > 0.0 or bool(row["shielded"]):
			return
		var before := _snapshot("before_synthetic_hit")
		game.player.take_hit()
		_chase_action_events["hit"] = {"authority": "RunnerPlayer.take_hit -> hit_taken -> RunnerGame._on_hit_taken",
			"call_count": 1, "before": before, "after": _snapshot("after_synthetic_hit")}
		return
	if _chase_action_events.has("hit") and not _captures.has("chase_post_hit"):
		var hit_before: Dictionary = _chase_action_events["hit"]["before"]
		if elapsed >= float(hit_before["elapsed"]) + 0.2:
			_capture("chase_post_hit", row)


func _run_cycle() -> void:
	var game := get_tree().current_scene as RunnerGame
	if not _cycle_require(game != null and game.running and not game._dead \
			and game.hud != null and is_instance_valid(game._touch),
			"cycle starts with the real live runner, HUD and touch recognizer"):
		return
	_cycle_game_id = game.get_instance_id()
	var before := _snapshot("before_synthetic_pause")
	var at := game.hud._pause_button.get_global_rect().get_center()
	_push_touch(1, at, true)
	if not _cycle_require(get_tree().paused and get_viewport().is_input_handled() \
			and is_instance_valid(game._pause_layer) and not game._touch._tracking,
			"raw pause-origin finger opened the real pause overlay and canceled gestures"):
		return
	_cycle_stage = "paused"
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if _finished:
		return
	var paused := _snapshot("cycle_post_draw")
	_capture("pause", paused)
	if not _cycle_require(is_equal_approx(float(paused["elapsed"]), float(before["elapsed"])) \
			and is_equal_approx(float(paused["distance"]), float(before["distance"])) \
			and is_equal_approx(float(paused["score"]), float(before["score"])) \
			and paused["lane"] == before["lane"] and paused["player_state"] == before["player_state"],
			"intentional pause froze gameplay clocks, score and movement"):
		return
	_cycle_stage = "resume_gui"
	if not await _activate_gui_button(game._pause_layer, "Resume"):
		return
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = at + Vector2(-180.0, 130.0)
	get_viewport().push_input(drag, true)
	var drag_consumed := get_viewport().is_input_handled()
	_push_touch(1, drag.position, false)
	if not _cycle_require(not get_tree().paused and game._pause_layer == null \
			and drag_consumed and get_viewport().is_input_handled() \
			and game.player.lane == int(before["lane"]) \
			and game.player.state == int(before["player_state"]),
			"GUI Resume activated once; held pause drag/release did not jump or change lane"):
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if _finished:
		return
	_capture("resumed", _snapshot("cycle_post_draw"))
	_cycle_stage = "forced_death"
	_forced_deaths += 1
	# Shipped authority: kill -> player.died -> RunnerGame._on_death. This
	# intentionally does not claim a natural collision or physical input.
	game.player.kill()
	if not _cycle_require(game._dead and not game.running and not game.player._input_enabled \
			and not is_instance_valid(game.hud._game_over) and not get_tree().paused,
			"one forced player.kill reached the shipped catch/save authority before results"):
		return
	while not is_instance_valid(game.hud._game_over) and not _finished:
		await get_tree().process_frame
	if _finished:
		return
	_cycle_stage = "results"
	await get_tree().create_timer(0.4, true, false, true).timeout
	await RenderingServer.frame_post_draw
	if _finished:
		return
	_capture("results", _snapshot("cycle_post_draw"))
	var previous_player_id := game.player.get_instance_id()
	_cycle_stage = "retry_gui"
	_run_index = 1
	if not await _activate_gui_button(game.hud._game_over, "Run Again"):
		return
	_retry_baseline = _snapshot("after_gui_retry")
	_previous_process_end = _retry_baseline.duplicate(true)
	if not _cycle_require(game.get_instance_id() == _cycle_game_id \
			and game.player.get_instance_id() != previous_player_id \
			and not game._dead and game.running and game.player._input_enabled \
			and game._presentation_started and not is_instance_valid(game._startup_warmup) \
			and game._countdown <= 0.0 \
			and is_zero_approx(game.elapsed) and is_zero_approx(game.player.distance) \
			and is_zero_approx(game._score) and game.fish == 0 \
			and game.hud._game_over == null and game.hud._pause_button.visible \
			and not SceneRouter.is_busy(),
			"GUI Run Again restarted in place with fresh player, reset result and live input"):
		return
	_cycle_stage = "retry_running"


func _activate_gui_button(container: Node, text: String) -> bool:
	await get_tree().process_frame
	await get_tree().process_frame
	if _finished:
		return false
	if not _cycle_require(is_instance_valid(container), "GUI " + text + " overlay still exists"):
		return false
	var target: Button = null
	for node: Node in container.find_children("*", "Button", true, false):
		if (node as Button).text.to_lower().contains(text.to_lower()) \
				or (node as Button).accessibility_name.to_lower() == text.to_lower():
			target = node as Button
			break
	if not _cycle_require(target != null and target.is_visible_in_tree() and not target.disabled,
			"GUI " + text + " is an enabled shipped button"):
		return false
	var rect := target.get_global_rect()
	if not _cycle_require(rect.has_area() \
			and get_viewport().get_visible_rect().encloses(rect), "GUI " + text + " fits the actual viewport"):
		return false
	_gui_activations[text] = 0
	target.pressed.connect(_on_cycle_gui_pressed.bind(text))
	var at := rect.get_center()
	var motion := InputEventMouseMotion.new()
	motion.device = InputEvent.DEVICE_ID_EMULATION
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)
	_push_touch(0, at, true)
	_push_mouse(at, true)
	_push_touch(0, at, false)
	_push_mouse(at, false)
	return _cycle_require(int(_gui_activations[text]) == 1 and get_viewport().is_input_handled(),
		"synthetic touch/emulated-mouse GUI " + text + " activated exactly once")


func _on_cycle_gui_pressed(text: String) -> void:
	_gui_activations[text] = int(_gui_activations.get(text, 0)) + 1


func _push_touch(index: int, at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = down
	get_viewport().push_input(event, true)


func _push_mouse(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.position = at
	event.global_position = at
	event.pressed = down
	get_viewport().push_input(event, true)


func _cycle_require(condition: bool, message: String) -> bool:
	_check(condition, message)
	if not condition:
		_finish(false)
	return condition


func _required_capture_ids() -> PackedStringArray:
	var ids := CAPTURE_IDS.duplicate()
	if _cycle:
		ids.append_array(CYCLE_CAPTURE_IDS)
	if _chase:
		ids.append_array(PackedStringArray(["chase_4s", "chase_6s"]))
	if _chase_actions:
		ids.append_array(PackedStringArray(["chase_midair", "chase_post_hit"]))
	return ids


func _capture_path(id: String) -> String:
	return _out if id == "loader" else _out.get_basename() + "_" + id + ".png"


func _capture(id: String, row: Dictionary) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := _capture_path(id)
	var error := ERR_INVALID_DATA
	var actual_size := Vector2i.ZERO
	if image != null and not image.is_empty():
		actual_size = image.get_size()
		error = image.save_png(path)
	_captures[id] = {"path": path, "png_error": error,
		"actual_size": [actual_size.x, actual_size.y], "snapshot": row.duplicate(true)}
	if error != OK or actual_size != _size:
		_violation("failed or incorrectly sized actual viewport capture: " + id, row)


func _violation(message: String, row: Dictionary) -> void:
	_violation_count += 1
	if _violations.size() < MAX_VIOLATIONS:
		_violations.append({"message": message, "snapshot": row.duplicate(true)})


func _on_timeout() -> void:
	if not _finished:
		if _native_trace:
			_finish_native_trace("fixture_timeout")
		else:
			_finish(true)


func _drain_native_warmup_trace() -> void:
	for event: Dictionary in InitialVisualWarmup.drain_perf_trace_events():
		event["source"] = "initial_visual"
		_record_native_warmup_event(event)
	for event: Dictionary in ShaderWarmup.drain_perf_trace_events():
		event["source"] = "shader_probe"
		_record_native_warmup_event(event)


func _record_native_warmup_event(event: Dictionary) -> void:
	event["observed_us"] = Time.get_ticks_usec()
	_warmup_events.append(event)
	print("[runner-native-warmup] " + JSON.stringify(event))


func _trace_native_state(row: Dictionary) -> void:
	var initial := bool(row.get("initial_warmup_present", false))
	var shader := bool(row.get("warmup_alive", false))
	var state := "loading_resource"
	if bool(row.get("runner_present", false)):
		state = "initial_visual" if initial else "building"
		if shader:
			state = "shader_probe"
		elif bool(row.get("build_finished", false)):
			state = "presentation"
		if bool(row.get("presentation_started", false)):
			state = "countdown"
		if bool(row.get("running", false)):
			state = "running"
	if SceneRouter._recovery_active:
		state = "router_recovery"
	var now := Time.get_ticks_usec()
	if state == "router_recovery" and _native_recovery_us == 0:
		_native_recovery_us = now
		_native_recovery_snapshot = row.duplicate(true)
	# Log stage boundaries immediately and one heartbeat per second otherwise.
	# A probe's wall duration includes normal drawing; it is not compile timing.
	if state != _trace_state or initial != _trace_previous_initial \
			or shader != _trace_previous_shader or now - _trace_last_us >= 1000000:
		var pulse := row.duplicate(true)
		pulse["stage"] = state
		pulse["wall_seconds"] = float(now - _start_us) / 1000000.0
		print("[runner-native-stage] " + JSON.stringify(pulse))
		_trace_state = state
		_trace_last_us = now
		_trace_previous_initial = initial
		_trace_previous_shader = shader
	# Diagnostic only: retain one post-recovery second to observe the terminal
	# helper latch and cursor. Do not change the production watchdog or Retry.
	if state == "router_recovery" and now - _native_recovery_us >= 1000000:
		_finish_native_trace("router_recovery")


func _finish_native_trace(outcome: String) -> void:
	if _finished:
		return
	_finished = true
	_drain_native_warmup_trace()
	ShaderWarmup.perf_trace_enabled = false
	InitialVisualWarmup.perf_trace_enabled = false
	var report := {
		"schema_version": 1, "kind": "native_runner_route_diagnostic",
		"outcome": outcome, "acceptance": false, "performance_acceptance": false,
		"build_id": GameConfig.BUILD_ID, "route": Game.SCENE_RUNNER,
		"watchdog_msec": SceneRouter.WARMUP_TIMEOUT_MSEC,
		"isolated_user_name": ProjectSettings.get_setting("application/config/custom_user_dir_name", ""),
		"wall_seconds": float(Time.get_ticks_usec() - _start_us) / 1000000.0,
		"process_count": _process_serial, "draw_count": _draw_serial,
		"samples": _samples, "sample_drops": _sample_drops,
		"violation_count": _violation_count, "violation_examples": _violations,
		"first_clear_draw": _first_clear_draw,
		"warmup_events": _warmup_events, "scene_events": _scene_events,
		"recovery_snapshot": _native_recovery_snapshot,
		"recovery_observation_seconds": float(Time.get_ticks_usec() - _native_recovery_us) / 1000000.0 if _native_recovery_us > 0 else 0.0,
		"last_snapshot": _snapshot("diagnostic_end"),
		"screenshots": false, "synthetic_input": false,
		"limitations": "QA main scene bypasses boot/menu; real Game.start_runner and SceneRouter remain unchanged. The custom user-directory string is an intent marker, not native OS sandbox proof; staging must verify a distinct QA package and fresh app data. Probe wall times include frame work, not isolated shader compilation. No natural collision, responsiveness, FPS or shipping-build acceptance claim.",
	}
	var file := FileAccess.open(_out.get_basename() + ".json", FileAccess.WRITE)
	if file == null:
		push_error("[runner-native-trace] Could not write diagnostic report")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	print("[runner-native-end] " + JSON.stringify({"outcome": outcome,
		"report": _out.get_basename() + ".json", "write_error": error,
		"acceptance": false}))
	get_tree().quit(0 if error == OK and outcome == "first_movement" else 1)


func _exit_tree() -> void:
	if _monitor and _native_trace:
		ShaderWarmup.perf_trace_enabled = false
		InitialVisualWarmup.perf_trace_enabled = false
		ShaderWarmup.clear_perf_trace()
		InitialVisualWarmup.clear_perf_trace()


func _finish(timed_out: bool) -> void:
	if _finished:
		return
	_finished = true
	_check(not timed_out, "real runner completed requested handoff/cycle before the 60-second deadline" \
		if _cycle or _chase else "real runner reached first movement before the 60-second deadline")
	_check(_violation_count == 0, "all process and submitted-draw handoff invariants held")
	_check(_sample_drops == 0, "complete bounded trace retained without dropped samples")
	_check(get_parent() == get_tree().root and get_tree().current_scene is RunnerGame,
		"root-child monitor survived the real scene swap into RunnerGame")
	_check(_scene_events.size() == 1 and str(_scene_events[0].get("path", "")) == Game.SCENE_RUNNER,
		"one real SceneRouter transition targeted the production runner scene")
	_check(_guarded_runner_samples > 0 and _guarded_runner_draws > 0,
		"real runner observed underneath guarded loader in process and rendered frames")
	_check(not _first_clear_draw.is_empty() and not _first_presentation.is_empty(),
		"cleared draw and subsequent presentation start both observed")
	_check(_numerals == ["3", "2", "1"], "all three countdown numerals rendered in order without loader")
	_check(not _first_countdown_draw.is_empty() \
		and float(_first_countdown_draw.get("countdown", 0.0)) > RunnerGame.COUNTDOWN_TIME * 2.0 / 3.0,
		"first visible numeral retained the beginning of the full countdown")
	var visible_duration := -1.0
	if not _first_presentation.is_empty() and not _first_running.is_empty():
		visible_duration = float(int(_first_running["time_us"]) - int(_first_presentation["time_us"])) / 1000000.0
	_check(_countdown_steps > 0 and _countdown_delta_sum >= RunnerGame.COUNTDOWN_TIME \
		and _countdown_delta_sum <= RunnerGame.COUNTDOWN_TIME + _countdown_delta_last + EPSILON,
		"full countdown charged to visible gameplay process deltas before GO")
	_check(not _first_running.is_empty() and absf(_countdown_delta_sum \
		- (RunnerGame.COUNTDOWN_TIME - float(_first_running.get("countdown", 0.0)))) < 0.0001,
		"observed countdown decrement matches actual process-delta sum")
	if _cycle:
		_check(_cycle_stage == "complete" and _forced_deaths == 1 \
			and int(_gui_activations.get("Resume", 0)) == 1 \
			and int(_gui_activations.get("Run Again", 0)) == 1,
			"exactly one synthetic pause/resume, forced death and GUI retry completed")
		_check(not _retry_baseline.is_empty() and _retry_guarded_samples == 0,
			"retry retained the warm scene and never advanced beneath a loader guard")
		_check(bool(_retry_baseline.get("running", false))
			and bool(_retry_baseline.get("input_enabled", false))
			and float(_retry_baseline.get("countdown", 1.0)) <= 0.0,
			"retry was playable before its GUI activation callback returned")
		_check(_retry_numerals.is_empty() and _retry_steps == 0
			and is_zero_approx(_retry_delta_sum),
			"retry did not charge a second countdown")
		_check(not _retry_first_running.is_empty(), "retry submitted live gameplay")
	if _chase:
		var earlier: Dictionary = _captures.get("chase_4s", {}).get("snapshot", {})
		var later: Dictionary = _captures.get("chase_6s", {}).get("snapshot", {})
		_check(bool(earlier.get("wave_visible", false)) and bool(later.get("wave_visible", false)) \
			and float(earlier.get("wave_alpha", 0.0)) > 0.85 \
			and float(later.get("wave_alpha", 0.0)) > 0.85,
			"snow front remains submitted at four and six seconds after GO")
		_check(float(later.get("distance", 0.0)) > float(earlier.get("distance", 0.0)) \
			and float(later.get("wave_clock", 0.0)) > float(earlier.get("wave_clock", 0.0)),
			"real player movement and snow animation continue between chase captures")
	if _chase_actions:
		var jump: Dictionary = _chase_action_events.get("jump", {})
		var hit: Dictionary = _chase_action_events.get("hit", {})
		var jump_before: Dictionary = jump.get("before", {})
		var hit_before: Dictionary = hit.get("before", {})
		var hit_after: Dictionary = hit.get("after", {})
		var midair: Dictionary = _captures.get("chase_midair", {}).get("snapshot", {})
		var post_hit: Dictionary = _captures.get("chase_post_hit", {}).get("snapshot", {})
		_check(int(jump.get("call_count", 0)) == 1 and int(hit.get("call_count", 0)) == 1 \
			and _chase_action_events.size() == 2 and float(jump_before.get("elapsed", 0.0)) >= 4.25 \
			and float(hit_before.get("elapsed", 0.0)) >= 5.5,
			"exactly one synthetic jump and hit invoked after the four-second baseline")
		_check(int(midair.get("player_state", -1)) == RunnerPlayer.State.JUMP \
			and float(midair.get("player_height", 0.0)) > 0.3 \
			and int(midair.get("draw_serial", 0)) > int(jump_before.get("draw_serial", 0)),
			"midair submitted frame shows real jump height above 0.3 metres")
		_check(int(hit_before.get("hits_left", -1)) == RunnerConfig.MAX_HITS \
			and int(hit_after.get("hits_left", -1)) == RunnerConfig.MAX_HITS - 1 \
			and int(post_hit.get("hits_left", -1)) == RunnerConfig.MAX_HITS - 1,
			"direct take_hit consumed exactly one life and submitted the result")
		_check(not post_hit.is_empty() and float(hit_before.get("chaser_gap", 0.0)) \
			- float(post_hit.get("chaser_gap", 0.0)) >= RunnerConfig.CHASER_GAP_PER_HIT * 0.9 \
			and int(post_hit.get("draw_serial", 0)) > int(hit_before.get("draw_serial", 0)),
			"real chaser tick closed at least 90 percent of the per-hit gap in the post-hit frame")
		_check(float(_snapshot("chase_actions_end").get("elapsed", 9.0)) < 8.0,
			"synthetic chase action observation completed within eight gameplay seconds")
	for id: String in _required_capture_ids():
		_check(_captures.has(id) and int(_captures.get(id, {}).get("png_error", ERR_INVALID_DATA)) == OK,
			"saved actual submitted viewport: " + id)
	var failed := 0
	for check: Dictionary in _checks:
		if not bool(check["passed"]):
			failed += 1
	var report := {
		"schema_version": 1, "kind": "real_scene_router_runner_handoff",
		"status": "PASS" if failed == 0 else "FAIL", "check_count": _checks.size(), "failed_count": failed,
		"renderer": RenderingServer.get_current_rendering_method(), "display_server": DisplayServer.get_name(),
		"isolated_user_name": ProjectSettings.get_setting("application/config/custom_user_dir_name", ""),
		"requested_window_size": [_size.x, _size.y], "destination": Game.SCENE_RUNNER,
		"elapsed_wall_seconds": float(Time.get_ticks_usec() - _start_us) / 1000000.0,
		"countdown_seconds": RunnerGame.COUNTDOWN_TIME, "visible_countdown_wall_seconds": visible_duration,
		"visible_countdown_process_delta_sum": _countdown_delta_sum,
		"countdown_process_steps": _countdown_steps, "countdown_last_process_delta": _countdown_delta_last,
		"process_count": _process_serial, "draw_count": _draw_serial,
		"guarded_runner_samples": _guarded_runner_samples, "guarded_runner_draws": _guarded_runner_draws,
		"sample_limit": MAX_SAMPLES, "sample_drops": _sample_drops, "samples": _samples,
		"violation_count": _violation_count, "violation_examples": _violations,
		"violation_examples_dropped": maxi(0, _violation_count - _violations.size()),
		"scene_events": _scene_events, "captures": _captures, "checks": _checks,
		"first_clear_draw": _first_clear_draw, "first_presentation": _first_presentation,
		"first_countdown_draw": _first_countdown_draw, "first_running": _first_running,
		"limitations": "Actual-window submitted frames only, not browser compositor proof. Screenshot readbacks perturb frame time; this is not a performance measurement. No input was injected. Destination loads through unmodified production managers and is not a recreated scene.",
	}
	if _cycle:
		report["cycle"] = {"enabled": true, "stage": _cycle_stage,
			"synthetic_gui_input": true, "forced_death_count": _forced_deaths,
			"death_authority": "RunnerPlayer.kill -> died -> RunnerGame._on_death",
			"gui_activations": _gui_activations, "retry_baseline": _retry_baseline,
			"retry_first_running": _retry_first_running,
			"retry_first_countdown_draw": _retry_first_countdown_draw,
			"retry_numerals": _retry_numerals, "retry_guarded_samples": _retry_guarded_samples,
			"retry_process_delta_sum": _retry_delta_sum, "retry_process_steps": _retry_steps,
			"qa_force_touch": true, "qa_force_native_offline_mvp": true,
			"qa_safe_insets_logical": [24, 24, 24, 24],
			"physical_device_input_verified": false, "natural_collision_verified": false,
			"performance_claim": false, "signed_mobile_build_verified": false}
		report["limitations"] = "Actual desktop rendering window with simulated phone layout/native-offline policy. Synthetic viewport GUI touch/emulated-mouse events and one forced RunnerPlayer.kill; not OS/physical-device input or natural-collision proof. Loader, gameplay clocks and in-place retry use shipped authorities. PNG readbacks perturb timing; no performance or signed-mobile acceptance."
	if _chase:
		report["chase"] = {"enabled": true, "observed_seconds": [4, 6],
			"synthetic_input": false, "forced_death_count": 0,
			"visual_occlusion_requires_image_review": true, "performance_claim": false}
	if _chase_actions:
		report["chase"]["synthetic_actions"] = true
		report["chase"]["action_events"] = _chase_action_events
		report["chase"]["physical_input_verified"] = false
		report["chase"]["natural_collision_verified"] = false
		report["limitations"] = "Actual foreground desktop submitted frames with one direct RunnerPlayer.jump and one direct RunnerPlayer.take_hit after the four-second baseline. These synthetic actions bypass OS input and collision detection; neither physical input nor natural collision is verified. Loader, RNG, hazard placement and gameplay clocks remain unchanged. PNG readbacks perturb timing; no browser, performance or signed-mobile acceptance claim. Visual occlusion still requires image review."
	var file := FileAccess.open(_out.get_basename() + ".json", FileAccess.WRITE)
	if file == null:
		push_error("[runner-handoff] Could not write JSON report")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		push_error("[runner-handoff] Could not finish JSON report (%d)" % error)
		get_tree().quit(1)
		return
	print("[runner-handoff] %s: %d checks, %d failures, %d violations; %s" % [
		report["status"], _checks.size(), failed, _violation_count, _out.get_basename() + ".json"])
	get_tree().quit(1 if failed > 0 else 0)


func _check(condition: bool, message: String) -> void:
	_checks.append({"passed": condition, "message": message})
	if not condition:
		push_error("[runner-handoff] FAIL: " + message)
