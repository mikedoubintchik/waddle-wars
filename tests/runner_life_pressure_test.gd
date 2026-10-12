extends Node
## Active-time behavior and live signal/camera/resource contracts. No screenshot
## or performance acceptance is inferred from this headless fixture.
const Effect = preload("res://scripts/runner/runner_hit_distortion.gd")
const Birds = preload("res://scripts/runner/runner_sky_birds.gd")
class QuietGame:
	extends RunnerGame
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
var passed := 0
var failed := 0

func _ready() -> void:
	_test_clock()
	_test_real_hits()
	await _test_camera_and_birds()
	_test_water()
	# AudioServer retires stopped real-hit Dummy playbacks on its own mix
	# thread; allow one bounded drain before process shutdown.
	await get_tree().create_timer(0.1).timeout
	_check(passed + failed == 144, "all clock, signal, projection and resource cases reached")
	print("[runner_life_pressure] %d/%d passed" % [passed, passed + failed])
	get_tree().quit(1 if failed else 0)

func _test_clock() -> void:
	for fps: int in [30, 60, 120]:
		var effect := Effect.new()
		add_child(effect)
		effect.setup()
		effect.finish_warmup()
		_check(not effect.visible, "zero-cost normal play after warmup %d" % fps)
		effect.lost_life(2)
		for frame: int in fps: effect.advance(1.0 / fps, true, false, "full")
		var first_strength := effect.strength
		_check(is_equal_approx(effect.seconds_left, 14.0) and first_strength > 0.0,
			"first lost life uses active time %d" % fps)
		effect.advance(300.0, false, false, "full")
		_check(is_equal_approx(effect.seconds_left, 14.0) and is_equal_approx(effect.active_seconds, 1.0),
			"pause/menu time cannot spend effect %d" % fps)
		effect.lost_life(1)
		for frame: int in fps: effect.advance(1.0 / fps, true, false, "full")
		_check(is_equal_approx(effect.seconds_left, 14.0) and effect.strength > first_strength
			and effect.strength <= first_strength * 1.51, "second loss refreshes15s at bounded extra strength %d" % fps)
		effect.advance(0.0, true, true, "full")
		_check(effect.motion_scale == 0.0 and effect.visible, "reduced motion retains static cue %d" % fps)
		effect.advance(0.0, true, false, "off")
		_check(effect.motion_scale == 0.0, "comfort motion off disables displacement %d" % fps)
		effect.advance(0.0, true, false, "reduced")
		_check(is_equal_approx(effect.motion_scale, 0.35), "comfort reduced scales movement %d" % fps)
		for frame: int in fps * 13: effect.advance(1.0 / fps, true, false, "full")
		_check(effect.visible and effect.strength > 0.0 and effect.strength < first_strength,
			"final second eases toward normal %d" % fps)
		for frame: int in fps: effect.advance(1.0 / fps, true, false, "full")
		_check(effect.seconds_left == 0.0 and effect.strength == 0.0 and not effect.visible,
			"exact15 active seconds removes entire pass %d" % fps)
		effect.lost_life(2)
		effect.lost_life(0)
		_check(not effect.visible and effect.seconds_left == 0.0, "fatal catch clears live distortion %d" % fps)
		effect.lost_life(1)
		effect.reset()
		_check(effect.lost_lives == 0 and not effect.visible, "retry clears all effect state %d" % fps)
		effect.free()

func _test_real_hits() -> void:
	var game := QuietGame.new()
	add_child(game)
	game.player = RunnerPlayer.new()
	game.add_child(game.player)
	game.player.setup({})
	game.missions = RunnerMissions.new()
	game._hit_distortion = Effect.new()
	game.add_child(game._hit_distortion)
	game.player.hit_taken.connect(game._on_hit_taken)
	game.player.powerups[RunnerConfig.POWERUP_SHIELD] = 3.0
	game.player.take_hit()
	_check(game.player.hits_left == 3 and game._hit_distortion.seconds_left == 0.0,
		"real shield absorption does not arm lost-life effect")
	game.player.invulnerable_for = 0.0
	game.player.take_hit()
	_check(game.player.hits_left == 2 and game._hit_distortion.seconds_left == 15.0,
		"real accepted life loss arms effect")
	game.running = true
	game._presentation_started = true
	game._advance_hit_distortion(2.0)
	game.player.take_hit()
	_check(game.player.hits_left == 2 and game._hit_distortion.seconds_left == 13.0,
		"iframe rejected hit cannot refresh effect")
	for state: String in ["countdown", "covered", "dead", "paused"]:
		game.running = state != "countdown"
		game._world_covered = state == "covered"
		game._dead = state == "dead"
		get_tree().paused = state == "paused"
		game._advance_hit_distortion(50.0)
		_check(game._hit_distortion.seconds_left == 13.0, "owner excludes " + state)
	get_tree().paused = false
	game._world_covered = false
	game._dead = false
	game.player.invulnerable_for = 0.0
	game.player.take_hit()
	_check(game.player.hits_left == 1 and game._hit_distortion.lost_lives == 2
		and game._hit_distortion.seconds_left == 15.0, "real second lost life refreshes whole interval")
	game.player.invulnerable_for = 0.0
	game.player.take_hit()
	_check(game.player.state == RunnerPlayer.State.DEAD and not game._hit_distortion.visible,
		"third real hit still kills and ends nonfatal effect")
	game.free()
	# Real hit callbacks started pooled SFX. Stop those Dummy playbacks before
	# this fast fixture exits, as normal game lifetime would outlive them.
	for audio_player: AudioStreamPlayer in AudioManager._sfx_pool:
		audio_player.stop()
		audio_player.stream = null

func _test_camera_and_birds() -> void:
	for shape: Vector2i in [Vector2i(1920,1080), Vector2i(800,1422),Vector2i(2400,1080),Vector2i(1200,1600)]:
		var viewport := SubViewport.new()
		viewport.size = shape
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var game := QuietGame.new()
		viewport.add_child(game)
		game.player = RunnerPlayer.new()
		game.add_child(game.player)
		game.player.setup({})
		game.player.set_input_enabled(false)
		game.camera = Camera3D.new()
		game.add_child(game.camera)
		game.camera.make_current()
		game._layout = LayoutProfile.for_view_size(Vector2(shape))
		game._intro_t = 0.0
		var rng_state := game._rng.state
		var player_start := game.player.transform
		for speed: float in [RunnerConfig.START_SPEED,RunnerConfig.MAX_SPEED]:
			game.player.speed = speed
			game._place_camera(0.0,true)
			var zoomed := _bounds(game.player._visual,game.camera)
			game.camera.fov += 8.0
			var wider := _bounds(game.player._visual,game.camera)
			game.camera.fov -= 8.0
			_check(zoomed.size.y > wider.size.y * 1.10 and zoomed.size.y < wider.size.y * 1.30,
				"closer lens enlarges actual hero10-30percent %s speed%.0f" % [shape,speed])
			_check(Rect2(Vector2.ZERO,Vector2(shape)).encloses(zoomed) and game.camera.position.y >= 2.95,
				"whole hero and tunnel clearance preserved %s" % shape)
			for lane: int in 3:
				var point := game.camera.unproject_position(Vector3(RunnerConfig.lane_x(lane),0,-20)) / Vector2(shape)
				_check(point.x > 0.0 and point.x < 1.0 and point.y > 0.0 and point.y < 1.0,
					"all three20m lane choices remain visible %s" % shape)
		_check(game.player.transform == player_start and game._rng.state == rng_state,
			"camera never changes collision root/RNG %s" % shape)
		var birds := Birds.new()
		game.add_child(birds)
		birds.setup()
		birds.present(game.camera,1.0,false,true)
		var batch := birds._birds.multimesh
		_check(birds.get_child_count() == 1 and batch.instance_count == 6 and batch.mesh == Birds.bird_mesh()
			and batch.mesh.surface_get_array_len(0) == 36, "six birds share one72-triangle draw %s" % shape)
		for index: int in 6:
			var center := birds._birds.global_transform * birds._placements[index].origin
			var projected := game.camera.unproject_position(center) / Vector2(shape)
			_check(not game.camera.is_position_behind(center) and projected.x > 0.20 and projected.x < 0.40
				and projected.y > 0.18 and projected.y < 0.37, "small flock stays in reference sky gap %s bird%d" % [shape,index])
		var clock := birds._clock
		birds.present(game.camera,100.0,true,true)
		_check(birds._clock == clock and birds._material.get_shader_parameter("wing_motion") == 0.0,
			"reduced motion freezes distant wings %s" % shape)
		birds.present(game.camera,1.0,false,false)
		_check(not birds.visible, "cave/night have no outdoor birds %s" % shape)
		birds.reset()
		_check(birds._clock == 0.0 and birds._birds.multimesh == batch, "retry reuses entire flock %s" % shape)
		viewport.queue_free()
		await get_tree().process_frame

func _test_water() -> void:
	for biome: int in [RunnerTrack.Biome.DAY,RunnerTrack.Biome.DUSK,RunnerTrack.Biome.CAVE,RunnerTrack.Biome.NIGHT]:
		var env := RunnerTrack.biome_environment(biome)
		var water := RunnerPaintedSea.reference_water_tint(env.ground_horizon,env.ground_bottom)
		_check(water.r >= 0.0 and water.g <= 1.0 and water.b <= 1.0,
			"biome water palette remains bounded %d" % biome)
		if biome == RunnerTrack.Biome.DAY:
			_check(water.g > 0.38 and water.b > 0.64 and water.r < 0.05,
				"DAY water is reference cyan blue rather than dark navy")


	# Exercise production DAY inputs and the same material interpolation used by
	# a live run, without requiring a renderer in this behavioral fixture.
	var game := QuietGame.new()
	var sea := RunnerPaintedSea.new()
	sea._water_material = ShaderMaterial.new()
	sea._water_material.shader = RunnerPaintedSea.SURFACE_SHADER
	var day := game._runner_environment(RunnerTrack.Biome.DAY)
	_check(is_equal_approx(float(day.sun_energy), 0.25), "reviewed DAY sun reaches gameplay")
	_check(day.water_tint == Color(0.008, 0.44, 0.75), "reviewed DAY water reaches gameplay")
	sea.blend_environment(day, 1.0)
	_check(is_equal_approx(sea._detail_weight, 1.0), "DAY enables painted facets")
	_check(sea._water_material.get_shader_parameter("day_detail_weight") == 1.0,
		"DAY detail reaches actual material")
	_check(sea._water_tint == day.water_tint, "DAY applies saturated palette without postprocessing")
	_check(sea._haze_distances == Vector2(110.0, 600.0), "reviewed haze endpoints retained")
	_check(sea._crest_tint.is_equal_approx(Vector3(0.08, 0.75, 1.0)), "reviewed crest color applied")
	for biome: int in [RunnerTrack.Biome.DUSK, RunnerTrack.Biome.CAVE, RunnerTrack.Biome.NIGHT]:
		sea.blend_environment(day, 1.0)
		var next := game._runner_environment(biome)
		sea.blend_environment(next, 0.5)
		_check(is_equal_approx(sea._detail_weight, 0.5), "DAY detail interpolates on exit %d" % biome)
		sea.blend_environment(next, 1.0)
		_check(is_zero_approx(sea._detail_weight)
			and sea._crest_tint.is_equal_approx(Vector3(0.70, 0.91, 1.0))
			and sea._water_tint.is_equal_approx(RunnerPaintedSea.reference_water_tint(next.ground_horizon, next.ground_bottom)),
			"other biome restores its original water palette and detail %d" % biome)
	sea.free()
	game.free()

func _bounds(visual: Node3D, camera: Camera3D) -> Rect2:
	var points := PackedVector2Array()
	for node: Node in visual.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		for corner: int in 8: points.append(camera.unproject_position(mesh.global_transform * mesh.mesh.get_aabb().get_endpoint(corner)))
	if points.is_empty(): return Rect2()
	var rect := Rect2(points[0],Vector2.ZERO)
	for point: Vector2 in points: rect = rect.expand(point)
	return rect

func _check(ok: bool,label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("[runner_life_pressure] FAIL ",label)
