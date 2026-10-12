extends Node
## Headless behavior gate: actual catch/fade/retry and pause overlay callbacks.
## Visibility checks are renderer eligibility, not a rendered FPS measurement.

class GameFixture:
	extends RunnerGame
	var camera_ticks := 0
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func step(delta: float) -> void: super._process(delta)
	func _settle_camera(_delta: float) -> void: camera_ticks += 1

class PlayerProbe:
	extends RunnerPlayer
	var ticks := 0
	func tick(_delta: float, _speed: float) -> void: ticks += 1

class TrackProbe:
	extends RunnerTrack
	var resets := 0
	func reset(_seed: int, _density: float = -1.0) -> void: resets += 1
	func update_stream(_z: float, _difficulty: float) -> void: pass

class MissionProbe:
	extends RunnerMissions
	func begin_run() -> void: pass
	func rows() -> Array: return []

var _passed := 0
var _failed := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameConfig.force_native_offline_mvp = true
	# This gate exercises real UI/retry callbacks, which can request one-shots.
	# Audio playback has its own gate; avoid mixer-dependent shutdown timing here.
	var library_before := AudioManager._library
	var cache_before := AudioManager._one_shot_cache
	var missing_before := AudioManager._missing_reported
	var pool_cursor_before := AudioManager._sfx_next
	AudioManager._library = {}
	AudioManager._one_shot_cache = {}
	AudioManager._missing_reported = {}
	for reduced: bool in [false, true]:
		await _test_catch_fade_and_retry(reduced)
	await _test_quick_retry_and_replacement()
	await _test_pause_settings_feedback()
	await _test_original_hidden_and_exit()
	await _test_viewport_cover_ownership()
	await get_tree().process_frame
	_check(AudioManager._sfx_next == pool_cursor_before
		and AudioManager._one_shot_cache.is_empty(), "visibility fixture does not start audio")
	AudioManager._library = library_before
	AudioManager._one_shot_cache = cache_before
	AudioManager._missing_reported = missing_before
	print("[runner_covered_world] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)

func _game() -> GameFixture:
	var game := GameFixture.new()
	add_child(game)
	game.build_finished = true
	game._presentation_started = true
	game.track = TrackProbe.new()
	game.add_child(game.track)
	game.player = PlayerProbe.new()
	game.player.state = RunnerPlayer.State.DEAD
	game.add_child(game.player)
	game.chaser = RunnerChaser.new()
	game.add_child(game.chaser)
	game.missions = MissionProbe.new()
	game.hud = RunnerHUD.new()
	game.add_child(game.hud)
	game.hud.setup()
	game.hud.results_cover_changed.connect(game._on_results_cover_changed)
	game.hud.restart_pressed.connect(game.restart)
	var hidden := Node3D.new()
	hidden.name = "OriginallyHidden"
	hidden.visible = false
	game.add_child(hidden)
	var trail := MeshInstance3D.new()
	trail.name = "TopLevelTrail"
	trail.mesh = BoxMesh.new()
	game.add_child(trail)
	trail.top_level = true
	game.camera = Camera3D.new()
	game.add_child(game.camera)
	game.camera.make_current()
	game._world_env = WorldEnvironment.new()
	game._world_env.environment = Environment.new()
	game._world_env.environment.background_mode = Environment.BG_COLOR
	game.add_child(game._world_env)
	return game

func _dispose(game: GameFixture) -> void:
	game.running = false
	game.queue_free()

func _test_catch_fade_and_retry(reduced: bool) -> void:
	var game := _game()
	var tag := "reduced=%s" % reduced
	game.hud._headless = false # Exercise real production Tween completion headlessly.
	game.hud._reduced = reduced
	game._dead = true
	game._pending_results = {"score": 0, "distance": 379.0, "fish": 3}
	game.chaser.overrun(reduced)
	for index: int in 47: game.step(0.05)
	_check(game.visible and not game._world_covered and game.hud._game_over == null,
		"world visible throughout 2.35s catch " + tag)
	_check(game._catch_elapsed >= 2.34 and (game.player as PlayerProbe).ticks == 47,
		"catch/player presentation fully advances " + tag)
	for index: int in 2: game.step(0.05)
	_check(is_instance_valid(game.hud._game_over) and game.visible and not game._world_covered,
		"results starts fade over visible world " + tag)
	await get_tree().create_timer(0.10).timeout
	_check(game.visible and game.hud._game_over.modulate.a < 1.0,
		"partial results fade preserves geometry " + tag)
	await get_tree().create_timer(0.18).timeout
	_check(game._world_covered and not game.visible,
		"opaque results suppress scene geometry " + tag)
	_check(get_viewport().disable_3d, "opaque results suspends entire 3D pass including sky " + tag)
	_check(game.hud._game_over.is_visible_in_tree(), "CanvasLayer results remains visible " + tag)
	_check(not (game.get_node("TopLevelTrail") as Node3D).is_visible_in_tree(),
		"top-level effect follows scene visibility " + tag)
	var old_clock := game._presentation_time
	var old_ticks := (game.player as PlayerProbe).ticks
	var old_camera_ticks := game.camera_ticks
	game.step(0.5)
	_check(game._presentation_time == old_clock and (game.player as PlayerProbe).ticks == old_ticks
		and game.camera_ticks == old_camera_ticks, "covered terminal presentation stops ticking " + tag)
	_check(game._world_env.environment.background_mode == Environment.BG_COLOR and game.camera.current,
		"cover preserves camera/environment " + tag)
	game.hud.restart_pressed.emit()
	_check(game.visible and not game._world_covered and game.running and not game._dead,
		"actual retry restores before gameplay " + tag)
	_check(not get_viewport().disable_3d, "retry restores viewport 3D " + tag)
	_check((game.get_node("TopLevelTrail") as Node3D).is_visible_in_tree()
		and not (game.get_node("OriginallyHidden") as Node3D).visible,
		"retry preserves each child authored visibility " + tag)
	for index: int in 3:
		game._dead = true
		game.hud._headless = true
		game.hud.show_game_over({"score": 0})
		_check(game._world_covered, "repeat result covered %d %s" % [index, tag])
		game.hud.restart_pressed.emit()
		_check(game.visible and not game._world_covered and game.running,
			"repeat retry restored %d %s" % [index, tag])
	_dispose(game)
	await get_tree().process_frame

func _test_quick_retry_and_replacement() -> void:
	var game := _game()
	game._dead = true
	game.hud._headless = false
	game.hud._reduced = true
	game.hud.show_game_over({"score": 0})
	var old_overlay := game.hud._game_over
	game.hud.restart_pressed.emit()
	game.hud._on_results_cover_ready(old_overlay)
	_check(game.visible and not game._world_covered, "quick retry rejects stale cover callback")
	await get_tree().create_timer(0.26).timeout
	_check(game.visible and game.running, "old completed tween cannot hide new run")
	game._dead = true
	game.hud.show_game_over({"score": 0})
	old_overlay = game.hud._game_over
	game.hud.show_game_over({"score": 5})
	game.hud._on_results_cover_ready(old_overlay)
	_check(game.visible and not game._world_covered, "replaced result rejects old overlay identity")
	await get_tree().create_timer(0.26).timeout
	_check(game._world_covered, "current replacement cover still completes")
	game.hud.hide_game_over()
	_check(game.visible and not game._world_covered, "hide results restores before overlay free")
	# Missing art cannot prove an opaque cover.
	game.hud.show_game_over({"score": 0})
	game.hud._game_over.modulate.a = 1.0
	game.hud._results_background.texture = null
	# Check the completion guard synchronously: deferred relayout otherwise
	# restores the real installed texture, correctly making the page opaque.
	game.hud._on_results_cover_ready(game.hud._game_over)
	_check(game.visible and not game._world_covered, "missing results texture keeps scene visible")
	game.hud.hide_game_over()
	_dispose(game)
	await get_tree().process_frame

func _test_pause_settings_feedback() -> void:
	var game := _game()
	game.running = true
	game._toggle_pause()
	_check(get_tree().paused and game._world_covered and not game.visible,
		"actual pause immediately suppresses opaque-covered geometry")
	_check((game._pause_layer.get_child(0) as Control).is_visible_in_tree(),
		"pause controls remain visible while 3D ancestor hidden")
	game._open_runner_settings()
	_check(is_instance_valid(game._runner_settings_panel) and game._world_covered
		and game._runner_settings_panel.is_visible_in_tree(), "pause settings keeps world covered")
	game._close_runner_settings()
	_check(game._world_covered, "settings Back preserves pause cover")
	var feedback = preload("res://scripts/ui/feedback_form.gd").new()
	feedback.open(game._pause_layer)
	_check(game._world_covered and feedback._root.is_visible_in_tree(),
		"feedback over pause preserves cover and visible UI")
	feedback._close()
	await get_tree().process_frame
	_check(game._world_covered and get_tree().paused, "feedback close stays paused/covered")
	var busy := SceneRouter._busy
	SceneRouter._busy = true
	game._close_pause()
	_check(game._world_covered and get_tree().paused, "navigation guard keeps covered world frozen")
	SceneRouter._busy = busy
	game._close_pause()
	_check(game.visible and not game._world_covered and not get_tree().paused,
		"resume restores scene and unpauses")
	_check(not get_viewport().disable_3d, "resume restores viewport rendering")
	_check(not (game.get_node("OriginallyHidden") as Node3D).visible
		and (game.get_node("TopLevelTrail") as Node3D).is_visible_in_tree(),
		"resume restores inherited visibility without altering child flags")
	_dispose(game)
	await get_tree().process_frame

func _test_original_hidden_and_exit() -> void:
	var game := _game()
	game.visible = false
	game.running = true
	game._toggle_pause()
	game._set_world_covered(true)
	game._close_pause()
	_check(not game.visible and not game._world_covered, "idempotent cover retains originally hidden scene")
	game.visible = true
	game._toggle_pause()
	game.running = false
	var environment := game._world_env.environment
	remove_child(game)
	_check(game.visible and not game._world_covered and not get_tree().paused,
		"scene exit restores scene-local visibility and releases pause")
	_check(environment.background_mode == Environment.BG_COLOR,
		"scene exit leaves environment unchanged")
	_check(not get_viewport().disable_3d, "scene exit releases viewport render cover")
	game.free()

func _test_viewport_cover_ownership() -> void:
	var viewport := get_viewport()
	var first := _game()
	var second := _game()
	first._set_world_covered(true)
	second._set_world_covered(true)
	remove_child(first)
	first.free()
	_check(viewport.disable_3d, "old scene exit cannot restore under newer opaque cover")
	second._set_world_covered(false)
	_check(not viewport.disable_3d and not viewport.has_meta(RunnerGame.COVER_RENDER_LEASE),
		"last cover restores original viewport state and clears lease")
	viewport.disable_3d = true
	second._set_world_covered(true)
	second._set_world_covered(true)
	second._set_world_covered(false)
	_check(viewport.disable_3d, "pre-existing disabled 3D state survives idempotent cover")
	viewport.disable_3d = false
	_dispose(second)
	await get_tree().process_frame

func _check(value: bool, label: String) -> void:
	if value:
		_passed += 1
		print("[runner_covered_world] PASS: " + label)
	else:
		_failed += 1
		push_error("[runner_covered_world] FAIL: " + label)
