extends Node
## Optical/pose checks on the real player and camera. Not raster acceptance.
const Bounds := preload("res://tests/posed_mesh_screen_bounds.gd")

class Fixture:
	extends RunnerGame
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var passed := 0
var failed := 0

func _ready() -> void:
	for size: Vector2i in [Vector2i(1672,941), Vector2i(941,1672),
		Vector2i(1080,2400), Vector2i(1600,1200)]:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var game := Fixture.new()
		viewport.add_child(game)
		game._intro_t = 0.0
		game._layout = LayoutProfile.for_view_size(Vector2(size))
		game.camera = Camera3D.new()
		game.add_child(game.camera)
		game.camera.make_current()
		for species: String in PenguinVisual.SPECIES:
			game.player = RunnerPlayer.new()
			game.add_child(game.player)
			game.player.setup({"species":species})
			game.player.set_input_enabled(false)
			_check(not game.player._visual.is_authored_backend_active(), "production species backend " + species)
			for speed: float in [RunnerConfig.START_SPEED, RunnerConfig.MAX_SPEED]:
				game.player.position = Vector3.ZERO
				game.player.speed = speed
				game.player.state = RunnerPlayer.State.RUN
				game.player._visual.set_pose(PenguinVisual.Pose.RUN)
				for frame: int in 30: game.player._drive_visual(1.0/60.0)
				var body_transform := game.player.transform
				var shape_transform := game.player._shape.transform
				var shape_height := game.player._capsule.height
				var rng_state := game._rng.state
				game._place_camera(0.0,true)
				var label := "%s %s speed%.0f" % [size,species,speed]
				_check(game.player.transform.is_equal_approx(body_transform)
					and game.player._shape.transform.is_equal_approx(shape_transform)
					and game.player._capsule.height == shape_height
					and game._rng.state == rng_state, "camera preserves gameplay " + label)
				var portrait := size.y >= size.x
				var sole := game.camera.unproject_position(Vector3.ZERO).y / size.y
				var horizon := game.camera.unproject_position(Vector3(0,0,-100000)).y / size.y
				_check(absf(sole - (0.71 if portrait else 0.73)) < 0.001,
					"ground contact at reference anchor " + label)
				_check(absf(horizon - (0.375 if portrait else 0.41)) < 0.001,
					"reference horizon " + label)
				_check(game.camera.position.y >= 2.95, "tunnel clearance " + label)
				var view := Bounds.measure(game.player._visual,game.camera)
				_check(view.valid and Rect2(Vector2.ZERO,Vector2(size)).encloses(view.screen_rect),
					"whole species visible " + label)
				_check(view.height_fraction >= 0.065 and view.height_fraction <= 0.16,
					"grounded reference scale without speed over-zoom " + label)
				if species == "emperor":
					print("[reference-pose] grounded ",JSON.stringify({"viewport":str(size),
						"speed":speed,"height_fraction":view.height_fraction,"sole":sole,
						"horizon":horizon,"fov":game.camera.fov,"camera":str(game.camera.position)}))
					_test_lane_readability(game,size)
			_test_jump(game,size,species)
			if species == "emperor": _test_slide_and_ramp(game,size)
			game.player.free()
			game.player = null
		viewport.queue_free()
		await get_tree().process_frame
	print("[reference-pose] %d/%d passed" % [passed,passed+failed])
	get_tree().quit(1 if failed else 0)


func _test_lane_readability(game: RunnerGame,size: Vector2i) -> void:
	for lane: int in 3:
		game.player.position.x = RunnerConfig.lane_x(lane)
		game._place_camera(0.0,true)
		for distance: float in [20.0,55.0,70.0]:
			for edge: float in [-4.65,4.65]:
				var point := Vector3(edge,0.0,-distance)
				var screen := game.camera.unproject_position(point)
				_check(not game.camera.is_position_behind(point)
					and Rect2(Vector2.ZERO,Vector2(size)).has_point(screen),
					"decision lanes visible %s lane%d %.0fm" % [size,lane,distance])
	game.player.position.x = 0.0


func _test_jump(game: RunnerGame,size: Vector2i,species: String) -> void:
	var player := game.player
	player.position = Vector3.ZERO
	player.speed = RunnerConfig.START_SPEED
	player.state = RunnerPlayer.State.RUN
	player._visual.set_pose(PenguinVisual.Pose.RUN)
	var visual := player._visual
	var node_count := visual.find_children("*","",true,false).size()
	var initial_shape := player._shape.transform
	var initial_height := player._capsule.height
	var accepted := {"count":0}
	player.jumped.connect(func() -> void: accepted.count += 1)
	player.jump()
	_check(accepted.count == 1 and player.state == RunnerPlayer.State.JUMP,
		"real jump accepted " + species)
	var largest_step := 0.0
	var previous_pitch := visual._foot_l.rotation.x
	for frame: int in 60:
		player.tick(1.0/60.0,RunnerConfig.START_SPEED)
		game._place_camera(1.0/60.0,true)
		largest_step = maxf(largest_step,absf(visual._foot_l.rotation.x - previous_pitch))
		previous_pitch = visual._foot_l.rotation.x
		if frame in [9,20]:
			var label := "%s %s jump-frame%d" % [size,species,frame]
			_check(player.state == RunnerPlayer.State.JUMP and visual.pose == PenguinVisual.Pose.AIR,
				"real airborne state " + label)
			for foot: MeshInstance3D in [visual._foot_l,visual._foot_r]:
				var heel := foot.global_transform * Vector3(0,0.014,0.065)
				var toe := foot.global_transform * Vector3(0,0.008,-0.13)
				_check(toe.y < heel.y - 0.10 and (-foot.global_basis.z.normalized()).y < -0.65,
					"both feet hang toes-down " + label)
			var view := Bounds.measure(visual,game.camera)
			_check(view.valid and Rect2(Vector2.ZERO,Vector2(size)).encloses(view.screen_rect),
				"airborne hero inside viewport " + label)
			_check(view.screen_rect.get_center().y / size.y >= 0.45
				and view.screen_rect.end.y / size.y < 0.76,
				"jump readable between HUD and gauge " + label)
			if species == "emperor":
				print("[reference-pose] jump ",JSON.stringify({"viewport":str(size),"frame":frame,
					"height_fraction":view.height_fraction,"rect":str(view.screen_rect),
					"ankle_pitch":rad_to_deg(visual._foot_l.rotation.x),"body_pitch":rad_to_deg(visual._root.rotation.x)}))
	_check(player.state == RunnerPlayer.State.RUN and player.position.y == 0.0,
		"unchanged jump returns to ground " + species)
	_check(player._shape.transform.is_equal_approx(initial_shape) and player._capsule.height == initial_height,
		"jump pose never changes collider " + species)
	_check(visual.find_children("*","",true,false).size() == node_count,
		"no per-jump meshes or nodes " + species)
	_check(largest_step < deg_to_rad(19), "continuous ankle blend " + species)
	visual.set_pose(PenguinVisual.Pose.IDLE)
	for frame: int in 60: visual.tick(1.0/60.0,0.0)
	_check(absf(visual._foot_l.rotation.x) < deg_to_rad(1.0)
		and absf(visual._foot_r.rotation.x) < deg_to_rad(1.0),"ground-flat feet restored " + species)


func _test_slide_and_ramp(game: RunnerGame,size: Vector2i) -> void:
	var player := game.player
	player.position = Vector3.ZERO
	player.set_input_enabled(true)
	player.slide()
	var slide_height := player._capsule.height
	for frame: int in 12: player.tick(1.0/60.0,RunnerConfig.START_SPEED)
	game._place_camera(0.0,true)
	var slide := Bounds.measure(player._visual,game.camera)
	_check(player.state == RunnerPlayer.State.SLIDE and player._height == RunnerConfig.SLIDE_HEIGHT
		and player._capsule.height == slide_height and slide_height < RunnerConfig.STAND_HEIGHT,
		"real slide/collider retained " + str(size))
	_check(slide.valid and Rect2(Vector2.ZERO,Vector2(size)).encloses(slide.screen_rect)
		and slide.screen_rect.end.y / size.y < 0.84,"slide fits above gauge " + str(size))
	player.launch(RunnerConfig.RAMP_LAUNCH)
	for frame: int in 90:
		player.tick(1.0/60.0,RunnerConfig.START_SPEED)
		game._place_camera(1.0/60.0,false)
		if frame % 12 == 0:
			var launch := Bounds.measure(player._visual,game.camera)
			_check(launch.valid and Rect2(Vector2.ZERO,Vector2(size)).encloses(launch.screen_rect),
				"real ramp roll stays in frame %s %d" % [size,frame])
	_check(player.state == RunnerPlayer.State.RUN and not player._launched,
		"ramp returns to unchanged ground authority " + str(size))


func _check(ok: bool,label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("[reference-pose] FAIL ",label)
