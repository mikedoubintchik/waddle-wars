extends Node
## Real runner/camera/collision route, not a benchmark or fixed-clock replay.

var _game: RunnerGame
var _output: String
var _duration := 2.5
var _started := false
var _deadline := 0
var _play := false
var _preflight := false
const CandidateSession := preload("res://tests/hero_candidate_session.gd")
var _candidate_session := CandidateSession.new()
var _candidate_facade: PenguinVisual
var _candidate_report: Dictionary = {}
var _candidate_ready := false
var _candidate_failed := false
var _previous_autopilot := false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "mode=play":
			_play = true
		elif arg == "mode=preflight":
			_preflight = true
		elif arg.begins_with("output="):
			_output = arg.trim_prefix("output=")
		elif arg.begins_with("seconds="):
			_duration = float(arg.trim_prefix("seconds="))
	if (GameConfig.is_headless() and not _preflight) or (_play and _preflight) \
			or (not _play and (_output.is_empty() or _duration < 0.5 or _duration > 6.0)):
		push_error("Runner candidate capture requires a window and 0.5..6 seconds")
		get_tree().quit(2)
		return
	if not GameConfig.is_headless():
		DisplayServer.window_set_size(Vector2i(540, 960))
		DisplayServer.window_set_title("Waddle Wars — QA penguin (unapproved geometry review)")
	Engine.max_fps = 60
	_previous_autopilot = RunnerPlayer.autopilot
	RunnerPlayer.autopilot = not _play
	_game = (load(Game.SCENE_RUNNER) as PackedScene).instantiate() as RunnerGame
	_game.generation_seed = 20260907
	# Runner startup yields before player creation. Scope selection precisely
	# around the existing synchronous player.setup, including later retries.
	_game.child_entered_tree.connect(_on_game_child_entered)
	add_child(_game)
	_deadline = Time.get_ticks_msec() + 90_000


func _on_game_child_entered(child: Node) -> void:
	if not child is RunnerPlayer:
		return
	_candidate_ready = false
	_candidate_facade = null
	if not _candidate_session.begin():
		_reject_candidate("Actual runner could not enter the bound candidate session")
		return
	child.child_entered_tree.connect(_on_player_child_entered)


func _on_player_child_entered(child: Node) -> void:
	if not child is PenguinVisual:
		return
	# RunnerPlayer.setup constructs the complete facade before attaching it.
	_candidate_session.restore()
	_candidate_facade = child as PenguinVisual
	# child_entered_tree fires before the facade's descendants enter. Inspect
	# the complete scene below, after runner setup has finished.


func _reject_candidate(message: String) -> void:
	_candidate_session.restore()
	_candidate_failed = true
	_candidate_ready = false
	if _game != null:
		_game.process_mode = Node.PROCESS_MODE_DISABLED
		if _game.player != null:
			_game.player.set_input_enabled(false)
	push_error(message)
	get_tree().quit(2)


func _exit_tree() -> void:
	_candidate_session.restore()
	RunnerPlayer.autopilot = _previous_autopilot


func _process(_delta: float) -> void:
	if _candidate_failed:
		return
	if _candidate_session.is_active():
		_reject_candidate("Candidate setup did not complete synchronously")
		return
	if not _candidate_ready and _candidate_facade != null and _game.running:
		_candidate_report = _candidate_session.inspect(_candidate_facade)
		_candidate_ready = _candidate_report.get("passed", false) == true
		if not _candidate_ready:
			_reject_candidate("Actual runner did not select the bound model and materials")
			return
	if _candidate_ready and _play:
		return
	if Time.get_ticks_msec() > _deadline:
		push_error("Runner candidate capture timed out")
		get_tree().quit(2)
		return
	if not _started and _game != null and _game.running:
		if not _candidate_ready:
			_reject_candidate("Actual runner became playable without its bound candidate")
			return
		_started = true
		if _preflight:
			_preflight_report()
		else:
			_capture()


func _preflight_report() -> void:
	var report := _candidate_session.inspect(_candidate_facade)
	report.merge({"headless": GameConfig.is_headless(), "pixels_captured": 0,
		"actual_runner_started": _game.running, "performance_measured": false,
		"material_parity_verified": false, "input_mode": "autopilot"}, true)
	DirAccess.make_dir_recursive_absolute(_output)
	var file := FileAccess.open(_output.path_join("candidate_runner_review.json"), FileAccess.WRITE)
	if file == null:
		_reject_candidate("Could not save runner preflight receipt")
		return
	file.store_string(JSON.stringify(report, "\t"))
	print("[v12-runner] HEADLESS PREFLIGHT ", "PASS" if report.passed else "FAIL", "; no pixels captured")
	call_deferred("_finish_capture", 0 if report.passed else 1)


func _capture() -> void:
	var report := _candidate_session.inspect(_candidate_facade)
	if not report.get("passed", false):
		_reject_candidate("Actual runner candidate changed before capture")
		return
	var rig := _game.player.find_child("AuthoredHeroPenguin", true, false) as HeroPenguinRig
	if rig == null or not rig.has_method("qa_material_report"):
		push_error("Actual runner did not select the QA candidate backend")
		get_tree().quit(2)
		return
	var start := _game.elapsed
	var samples: Array[Dictionary] = []
	var next_sample := 0.0
	DirAccess.make_dir_recursive_absolute(_output)
	while _game.elapsed - start < _duration and _game.running:
		await get_tree().process_frame
		if _game.elapsed - start < next_sample:
			continue
		await RenderingServer.frame_post_draw
		if not _candidate_session.inspect(_candidate_facade, rig).get("passed", false):
			_reject_candidate("Actual runner candidate changed during capture")
			return
		var filename := "runner_%04d.png" % samples.size()
		var image := get_viewport().get_texture().get_image()
		if image == null or image.save_png(_output.path_join(filename)) != OK:
			push_error("Could not save real runner candidate frame")
			get_tree().quit(2)
			return
		var row: Dictionary = rig.call("qa_motion_snapshot")
		row.merge({"file": filename, "elapsed": _game.elapsed - start,
			"distance": _game.player.distance, "state": int(_game.player.state),
			"camera_transform": str(_game.camera.global_transform), "camera_fov": _game.camera.fov,
			"collider_radius": _game.player._capsule.radius, "collider_height": _game.player._capsule.height})
		samples.append(row)
		next_sample = _game.elapsed - start + 0.12
	report.merge({"clock": "real_runner_process_with_existing_autopilot", "samples": samples,
		"normal_runner_camera": true, "gameplay_code_changed": false,
		"collision_code_changed": false, "performance_measured": false,
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"renderer": RenderingServer.get_current_rendering_method(),
		"input_mode": "autopilot" if RunnerPlayer.autopilot else "interactive",
		"duration_elapsed": _game.elapsed - start})
	report["passed"] = report.passed and samples.size() >= 5 and _game.running
	var file := FileAccess.open(_output.path_join("candidate_runner_review.json"), FileAccess.WRITE)
	if file == null:
		_reject_candidate("Could not save real runner candidate receipt")
		return
	file.store_string(JSON.stringify(report, "\t"))
	print("[v12-runner] ", "PASS" if report.passed else "FAIL", " screenshots=", samples.size())
	# Let this coroutine release rig/material references before deferred scene
	# teardown, then allow queued frees to complete before shutting down Godot.
	call_deferred("_finish_capture", 0 if report.passed else 1)


func _finish_capture(code: int) -> void:
	set_process(false)
	_game.queue_free()
	_game = null
	for frame: int in 4:
		await get_tree().process_frame
	get_tree().quit(code)
