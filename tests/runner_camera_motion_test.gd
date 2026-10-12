extends Node
## Real forward motion must not silently widen the authored chase-camera fit.
const Bounds := preload("res://tests/posed_mesh_screen_bounds.gd")

class Fixture:
	extends RunnerGame
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var passed := 0
var failed := 0
var diagnostic := false

func _ready() -> void:
	diagnostic = "--diagnostic-baseline" in OS.get_cmdline_user_args()
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(480, 854)]:
		for fps: float in [30.0, 60.0, 120.0]:
			for speed: float in [RunnerConfig.START_SPEED, RunnerConfig.MAX_SPEED]:
				await _check_motion(size, fps, speed)
	print("[camera-motion] %d/%d passed%s" % [passed, passed + failed,
		" (baseline diagnostic only)" if diagnostic else ""])
	get_tree().quit(1 if failed else 0)


func _check_motion(size: Vector2i, fps: float, speed: float) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var game := Fixture.new()
	viewport.add_child(game)
	game._intro_t = 0.0
	game._layout = LayoutProfile.for_view_size(Vector2(size))
	game.player = RunnerPlayer.new()
	game.add_child(game.player)
	game.player.setup({"species": "emperor"})
	game.player.set_input_enabled(false)
	game.player.speed = speed
	game.camera = Camera3D.new()
	game.add_child(game.camera)
	game.camera.make_current()
	game._place_camera(0.0, true)
	var initial_offset := game.camera.position.z - game.player.position.z
	var rng_before := game._rng.state
	var shape_before := game.player._shape.transform
	var height_before := game.player._capsule.height
	for frame: int in int(fps * 3.0):
		game.player.tick(1.0 / fps, speed)
		game._place_camera(1.0 / fps, false)
	var running_position := game.camera.position
	var moving_bounds := Bounds.measure(game.player._visual, game.camera)
	var sole := game.camera.unproject_position(game.player.global_position).y / size.y
	var horizon := game.camera.unproject_position(game.player.global_position
		+ Vector3(0, 0, -100000)).y / size.y
	game._place_camera(0.0, true)
	var target_bounds := Bounds.measure(game.player._visual, game.camera)
	print("[camera-motion] sample ", JSON.stringify({"viewport": [size.x, size.y],
		"fps": fps, "speed": speed, "intended_offset_m": initial_offset,
		"actual_offset_m": running_position.z - game.player.position.z,
		"excess_trailing_m": running_position.z - game.camera.position.z,
		"moving_hero_height_fraction": moving_bounds.height_fraction,
		"intended_hero_height_fraction": target_bounds.height_fraction,
		"moving_sole_fraction": sole, "horizon_fraction": horizon}))
	var label := "%s %.0ffps %.0fm/s" % [size, fps, speed]
	if not diagnostic:
		_check(absf(running_position.z - game.camera.position.z) < 0.003,
			"forward motion preserves intended distance " + label)
		_check(absf(moving_bounds.height_fraction - target_bounds.height_fraction) < 0.0001,
			"moving hero retains target scale " + label)
		_check(absf(sole - (0.71 if size.y > size.x else 0.73)) < 0.001,
			"real moving sole anchor " + label)
		_check(absf(horizon - (0.375 if size.y > size.x else 0.41)) < 0.001,
			"reference horizon retained " + label)
	_check(game.player._shape.transform.is_equal_approx(shape_before)
		and game.player._capsule.height == height_before
		and game._rng.state == rng_before, "camera leaves collider and RNG alone " + label)
	_check(game.camera.position.y >= 2.95, "safe roof clearance " + label)
	# Lateral and vertical response must still ease, including a real jump.
	game.player.position.x = RunnerConfig.lane_x(2)
	game._place_camera(1.0 / fps, false)
	_check(game.camera.position.x > 0.0
		and game.camera.position.x < game.player.position.x * 0.55,
		"lane follow still eases " + label)
	game.player.jump()
	game.player.tick(1.0 / fps, speed)
	var previous_height := game.camera.position.y
	game._place_camera(1.0 / fps, false)
	_check(game.camera.position.y > previous_height
		and game.camera.position.y < previous_height + game.player.position.y * 0.32,
		"jump height still eases " + label)
	# A resize/retry snap starts a new forward reference without stale travel.
	game.player.position = Vector3.ZERO
	game.player.state = RunnerPlayer.State.RUN
	game.player._vertical = 0.0
	game._place_camera(0.0, true)
	game.player.tick(1.0 / fps, speed)
	game._place_camera(1.0 / fps, false)
	if not diagnostic:
		_check(absf(game.camera.position.z - game.player.position.z - initial_offset) < 0.003,
			"retry/snap resets forward reference " + label)
	viewport.queue_free()
	await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("[camera-motion] FAIL ", label)
