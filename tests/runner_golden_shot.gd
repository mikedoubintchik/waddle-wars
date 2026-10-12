extends Node
## Fixed 360 m DAY showcase capture. Boots the real mode, replaces only its
## streamed track with the internal golden slice, then photographs all ten
## authored pattern families in five deterministic two-chunk views.
##
##   godot --path . res://tests/runner_golden_shot.tscn -- \
##       out=qa_shots/runner/golden.png w=1600 h=900

const GOLDEN_SEED: int = 20260818
const DISTANCES: PackedFloat32Array = [2.0, 74.0, 146.0, 218.0, 280.0]
const PosedBounds = preload("res://tests/posed_mesh_screen_bounds.gd")

var _out_path: String = "qa_shots/runner/golden.png"
var _capture_distances: PackedFloat32Array = DISTANCES
var _game: RunnerGame = null
var _shot: int = 0
var _started: bool = false
var _capturing: bool = false
var _deadline: float = 0.0
var _save_failed: bool = false
var _framing_failed: bool = false


func _ready() -> void:
	var width := 1600
	var height := 900
	var emulate_touch := false
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", false, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"out": _out_path = parts[1]
			"distance": _capture_distances = PackedFloat32Array([float(parts[1])])
			"w": width = int(parts[1])
			"h": height = int(parts[1])
			"touch": emulate_touch = parts[1].to_lower() in ["1", "true", "yes"]
	# A desktop portrait window is not a phone unless both touch-gated metric
	# paths are enabled: UITheme metrics and SettingsManager's canvas boost.
	# Keep the capture deterministic without persisting either override.
	GameConfig.force_touch = emulate_touch
	var display: Dictionary = SettingsManager.settings.get("display", {}).duplicate(true)
	display["window_mode"] = "windowed"
	display["resolution"] = "%dx%d" % [width, height]
	SettingsManager.settings["display"] = display
	var accessibility: Dictionary = SettingsManager.settings.get(
		"accessibility", {}).duplicate(true)
	accessibility["ui_scale"] = 1.0
	SettingsManager.settings["accessibility"] = accessibility
	SettingsManager.apply_all()
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	if "raster_background=1" not in OS.get_cmdline_user_args():
		DisplayServer.window_move_to_foreground()
	if "foreground_gate=1" in OS.get_cmdline_user_args():
		set_process(false)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
		var focus_deadline := Time.get_ticks_msec() + 20000
		print("[runner-golden] awaiting actual foreground activation before real scene build")
		while not get_window().has_focus() and Time.get_ticks_msec() < focus_deadline:
			await get_tree().process_frame
		if not get_window().has_focus():
			push_error("runner-golden: foreground activation gate expired; no raster acceptance")
			get_tree().quit(2)
			return
		print("[runner-golden] actual foreground activation confirmed")
	var scene := load(Game.SCENE_RUNNER) as PackedScene
	if scene == null:
		push_error("runner_golden_shot: runner scene missing")
		get_tree().quit(1)
		return
	_game = scene.instantiate() as RunnerGame
	add_child(_game)
	_deadline = Time.get_ticks_msec() * 0.001 + 45.0
	set_process(true)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() * 0.001 > _deadline:
		push_error("runner_golden_shot: capture timed out")
		get_tree().quit(1)
		return
	# Keep the deadline live while _capture() awaits process/frame-post-draw.
	# Otherwise a stalled renderer leaves _capturing true forever and this
	# windowed QA harness never exits.
	if _capturing:
		return
	if _game == null or not _game.build_finished:
		return
	if not _started:
		_started = true
		_game.set_process(false)
		_game.track.setup_golden_slice(GOLDEN_SEED, 1)
		_game.running = false
		_game._dead = false
		_game._intro_t = 0.0
		_game.player.set_input_enabled(false)
		if _game.hud != null:
			_game.hud.show_message("")
	if _shot >= _capture_distances.size():
		get_tree().quit(1 if _save_failed or _framing_failed else 0)
		return
	_capturing = true
	_capture(_shot)


func _capture(index: int) -> void:
	var distance := _capture_distances[index]
	var player := _game.player
	player.distance = distance
	player.position = Vector3(0.0, 0.0, -distance)
	player.lane = 1
	player.speed = lerpf(RunnerConfig.START_SPEED, RunnerConfig.MAX_SPEED,
			float(index) / float(maxi(_capture_distances.size() - 1, 1)))
	player._launched = false
	player._vertical = 0.0
	match index:
		0:
			player.state = RunnerPlayer.State.RUN
			player.position.x = RunnerConfig.lane_x(0)
			player.lane = 0
			player._visual.trigger_event(&"recover")
		1:
			player.state = RunnerPlayer.State.SLIDE
			player._visual.trigger_event(RunnerPlayer.PRESENT_SLID)
		2:
			player.state = RunnerPlayer.State.JUMP
			player.position.y = 1.25
			player._vertical = 2.0
			player._visual.trigger_event(RunnerPlayer.PRESENT_JUMPED)
		3:
			player.state = RunnerPlayer.State.RUN
			player.position.x = RunnerConfig.lane_x(0)
			player.lane = 0
			player._visual.trigger_event(&"recover")
		4:
			player.state = RunnerPlayer.State.JUMP
			player.position.y = 2.2
			player._vertical = -2.0
			player._launched = true
			player._visual.trigger_event(RunnerPlayer.PRESENT_RAMP_LAUNCHED)
		_:
			player.state = RunnerPlayer.State.RUN
			player._visual.trigger_event(&"recover")
	# Let procedural pose blending and HUD entrance motion settle before the
	# still. Track animation continues through the ordinary child process path.
	for _frame: int in 14:
		player._drive_visual(1.0 / 60.0)
		await get_tree().process_frame
	_game._place_camera(0.0, true)
	_game._blend_biome(1.0)
	if _game.chaser != null:
		_game.chaser.tick(0.0, distance, 0.0)
	if _game.hud != null:
		_game.hud.set_stats(distance, 24 + index * 11, int(distance * 4.0),
				1 + index, RunnerConfig.MAX_HITS, RunnerConfig.CHASER_BASE_GAP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var fraction := _hero_screen_fraction()
	print("[runner_golden_shot] frame %d distance=%.0fm hero=%.1f%%" % [
			index, distance, fraction * 100.0])
	if fraction < 0.14 or fraction > 0.18:
		_framing_failed = true
		push_warning("runner_golden_shot: hero framing outside 14-18%% (%.1f%%)" % (fraction * 100.0))
	var image := get_viewport().get_texture().get_image()
	var path := "%s_%d.png" % [_out_path.get_basename(), index]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := image.save_png(path)
	print("[runner_golden_shot] saved %s err=%d" % [path, error])
	_save_failed = _save_failed or error != OK
	_shot += 1
	_capturing = false


func _hero_screen_fraction() -> float:
	if _game.camera == null or _game.player == null:
		return 0.0
	var bounds := PosedBounds.measure(_game.player, _game.camera)
	print("[runner_golden_shot] hero bounds meshes=%d vertices=%d skinned=%d morphed=%d hidden=%d scope=%s" % [
		bounds.mesh_count, bounds.vertex_count, bounds.skinned_vertices,
		bounds.morphed_vertices, bounds.hidden_meshes, bounds.scope])
	if not bounds.valid:
		_framing_failed = true
		push_error("runner_golden_shot: hero bounds invalid: %s" % "; ".join(bounds.errors))
		return 0.0
	return bounds.height_fraction
