class_name RunnerGame
extends Node3D
## Waddle Run: the endless-runner half of the game.
##
## This is the whole mode's orchestrator — world, player, camera, avalanche,
## HUD, scoring, death and restart. It shares the racing game's ART and save
## data and nothing else: no RaceManager, no CourseBase, no PathGuide. That
## separation is the point. The racing game is a simulation with surfaces,
## rubberbanding and AI; a runner is a rhythm game on rails, and every attempt
## to make one out of the other ends up compromising both.
##
## Restart never reloads the scene: the track resets, the player resets, and
## the run starts again. Reloading would pay the whole shader-compile and
## build cost again, which on the web build is seconds — unacceptable for the
## "die, retry immediately" loop this mode lives on.

const COUNTDOWN_TIME: float = 1.6

var track: RunnerTrack = null
var player: RunnerPlayer = null
var chaser: RunnerChaser = null
var hud: RunnerHUD = null
var camera: Camera3D = null

var running: bool = false
var elapsed: float = 0.0
var fish: int = 0
var hits_taken: int = 0
## Distance since the last hit, which is what the score multiplier keys off.
var clean_metres: float = 0.0
var _score: float = 0.0
var _countdown: float = COUNTDOWN_TIME
var _dead: bool = false
var _camera_shake: float = 0.0
var _fov_kick: float = 0.0
## False until the world is assembled. The loading overlay watches this so its
## animation keeps running while the track builds — on the single-threaded web
## build, a synchronous build freezes every frame including the spinner.
var build_finished: bool = false
var _near_snow: GPUParticles3D = null
var _world_env: WorldEnvironment = null
var _sun: DirectionalLight3D = null
var _rng := RandomNumberGenerator.new()
var _pause_layer: CanvasLayer = null
var _touch: RunnerTouch = null
var missions: RunnerMissions = null
var _last_multiplier: int = 1
## Ramps hit and near misses survived, both reported to the mission system and
## shown to the player, because a runner has to reward style as well as
## survival or it is just a dodging drill.
var ramps_hit: int = 0
var near_misses: int = 0
## Sim hook: ends the run after this many seconds when > 0.
static var auto_quit_after: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_build_environment()
	await _stage()

	missions = RunnerMissions.new()
	missions.load_state()
	missions.completed.connect(_on_mission_complete)
	missions.set_cleared.connect(func(star_count: int) -> void:
		if hud != null:
			hud.show_mission_complete("SET COMPLETE — %d ★" % star_count)
		AudioManager.play_sfx("sfx_unlock"))

	track = RunnerTrack.new()
	track.name = "RunnerTrack"
	add_child(track)
	track.setup(_rng.randi())
	await _stage()

	player = RunnerPlayer.new()
	player.name = "RunnerPlayer"
	add_child(player)
	player.setup(_player_visual_config())
	player.set_input_enabled(false)
	_connect_player()

	chaser = RunnerChaser.new()
	chaser.name = "RunnerChaser"
	add_child(chaser)
	chaser.setup()
	await _stage()
	chaser.caught.connect(func() -> void:
		if player != null:
			player.kill())

	if not GameConfig.is_headless():
		camera = Camera3D.new()
		camera.fov = 74.0
		camera.far = 900.0
		add_child(camera)
		camera.make_current()
		_place_camera(0.0, true)

		hud = RunnerHUD.new()
		add_child(hud)
		hud.setup()
		hud.restart_pressed.connect(restart)
		hud.menu_pressed.connect(func() -> void: SceneRouter.go_to(Game.SCENE_MAIN_MENU))
		if hud != null:
			hud.set_missions(missions.rows())
		if SettingsManager.touch_controls_enabled():
			_touch = RunnerTouch.new()
			_touch.name = "RunnerTouch"
			add_child(_touch)
			_touch.setup(player)
		AudioManager.play_music("music_race")

	build_finished = true
	ShaderWarmup.warm(self)


## Yields a frame so the loading overlay can draw. Headless has no overlay and
## no renderer, so it builds straight through.
func _stage() -> void:
	if GameConfig.is_headless():
		return
	var tree := get_tree()
	if tree != null:
		await tree.process_frame


func _connect_player() -> void:
	player.hit_taken.connect(_on_hit_taken)
	player.fish_collected.connect(_on_fish_collected)
	player.died.connect(_on_death)
	player.powerup_gained.connect(_on_powerup_gained)
	player.shield_spent.connect(_on_shield_spent)
	player.near_miss.connect(_on_near_miss)
	player.ramp_launched.connect(_on_ramp)
	player.jumped.connect(func() -> void: missions.note_jump())
	player.slid.connect(func() -> void: missions.note_slide())
	player.lane_changed.connect(func() -> void: missions.note_lane_change())


func _player_visual_config() -> Dictionary:
	# The runner wears whatever the player has equipped in the racing game:
	# one penguin, one wardrobe, both modes.
	var equipped := Progression.equipped()
	var body_info := CosmeticsDB.get_item(String(equipped.get("body", "body_classic")))
	var config := {
		"body_color": body_info.get("body_color", Color(0.13, 0.16, 0.22)),
		"belly_color": body_info.get("belly_color", Color(0.95, 0.94, 0.9)),
		"hat": equipped.get("hat", ""),
		"scarf": equipped.get("scarf", ""),
		"goggles": equipped.get("goggles", ""),
	}
	if body_info.has("crest_color"):
		config["crest_color"] = body_info["crest_color"]
	return config


func _process(delta: float) -> void:
	if _dead:
		_settle_camera(delta)
		return
	if not running:
		_countdown -= delta
		if hud != null:
			var count := int(ceil(_countdown / COUNTDOWN_TIME * 3.0))
			hud.show_message("GO!" if count <= 0 else str(count))
		if _countdown <= 0.0:
			running = true
			missions.begin_run()
			player.set_input_enabled(true)
			if hud != null:
				hud.show_message("GO!")
		_settle_camera(delta)
		return

	elapsed += delta
	var speed := RunnerConfig.speed_at(elapsed) - float(hits_taken) * RunnerConfig.HIT_SPEED_LOSS \
		* maxf(0.0, 1.0 - clean_metres / 180.0)
	speed = maxf(speed, RunnerConfig.START_SPEED * 0.6)

	var before := player.distance
	player.tick(delta, speed)
	var gained := player.distance - before
	clean_metres += gained
	var multiplier := RunnerConfig.multiplier_for(clean_metres)
	if player.has_powerup(RunnerConfig.POWERUP_DOUBLE):
		multiplier *= 2
	_score += gained * RunnerConfig.POINTS_PER_METRE * float(multiplier)
	missions.note_distance(player.distance)

	# Difficulty is distance-driven rather than time-driven: a player who dies
	# early and restarts should always see the same gentle opening, however
	# long they have had the mode open.
	track.update_stream(player.position.z, clampf(player.distance / 2600.0, 0.0, 1.0))
	chaser.tick(delta, player.distance, float(hits_taken))
	_place_camera(delta, false)
	_blend_biome(delta)
	if _near_snow != null:
		_near_snow.global_position = Vector3(player.position.x * 0.5, 3.4,
			player.position.z - 4.0)

	if hud != null:
		hud.set_stats(player.distance, fish, int(_score), multiplier,
			player.hits_left, chaser.gap)
		hud.set_powerups(player.powerups)
		hud.set_speed_ratio(clampf((player.speed - RunnerConfig.START_SPEED)
			/ maxf(RunnerConfig.MAX_SPEED - RunnerConfig.START_SPEED, 0.001), 0.0, 1.0))
		hud.set_combo(multiplier, multiplier > _last_multiplier)
		if multiplier > _last_multiplier:
			hud.add_floater("x%d" % multiplier, &"score")
			AudioManager.play_sfx("sfx_checkpoint")
	_last_multiplier = multiplier

	if auto_quit_after > 0.0 and elapsed >= auto_quit_after:
		_on_death()


## --- Camera -----------------------------------------------------------------

## Chase camera: behind and above, easing toward the player's lane so a lane
## change reads as movement rather than as the world sliding. FOV opens with
## speed, which is most of what makes 38 m/s feel different from 15.
func _place_camera(delta: float, snap: bool) -> void:
	if camera == null or player == null:
		return
	# Close, and just high enough. The first pass sat 8.4 m back and 3.35 m up
	# and the penguin read as a distant speck. Pulling it to 5.9 m back fixed
	# that, but at 2.55 m up the camera skimmed the 2.0 m tunnel beams closely
	# enough that one filled the frame on the way through — 2.95 m keeps the
	# penguin large and clears the arches.
	# Height tracking is deliberately partial — following a hop one-for-one
	# makes the whole world bounce — but it has to open up for a ramp launch or
	# the penguin flies out of the top of the frame, which is exactly the
	# moment the mode looks best.
	var lift := 0.32 if player.position.y < 1.6 else 0.72
	var target := Vector3(player.position.x * 0.55, 2.95 + player.position.y * lift,
		player.position.z + 5.9)
	if snap:
		camera.position = target
	else:
		camera.position = camera.position.lerp(target, clampf(delta * 9.0, 0.0, 1.0))
	if _camera_shake > 0.0:
		_camera_shake = maxf(0.0, _camera_shake - delta * 2.4)
		camera.position += Vector3(
			_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), 0.0) * _camera_shake * 0.5
	# The aim point rises with the penguin too, so a launch is framed rather
	# than merely kept on screen.
	var look := Vector3(player.position.x * 0.5, 1.35 + player.position.y * 0.45,
		player.position.z - 11.0)
	camera.look_at(look, Vector3.UP)
	var speed_ratio := clampf((player.speed - RunnerConfig.START_SPEED)
		/ maxf(RunnerConfig.MAX_SPEED - RunnerConfig.START_SPEED, 0.001), 0.0, 1.0)
	# The kick is what makes a ramp or a power-up land as an EVENT rather than
	# as a number changing: the whole picture widens for a beat and settles.
	_fov_kick = maxf(0.0, _fov_kick - delta * 14.0)
	camera.fov = lerpf(74.0, 88.0, speed_ratio) + _fov_kick
	# Roll with the penguin's bank. A camera that stays level through a lane
	# change makes the world look like it slid sideways under a static player.
	camera.rotation.z = lerp_angle(camera.rotation.z, player.rotation.z * 0.45,
		clampf(delta * 8.0, 0.0, 1.0))


## After death the camera keeps drifting and looking at the wreck, so the
## game-over panel is not slapped over a frozen frame.
func _settle_camera(delta: float) -> void:
	if camera == null or player == null:
		return
	camera.position = camera.position.lerp(
		Vector3(player.position.x * 0.5, 3.2, player.position.z + 7.0),
		clampf(delta * 2.4, 0.0, 1.0))
	camera.look_at(Vector3(player.position.x, 1.1, player.position.z), Vector3.UP)


## --- Run events -------------------------------------------------------------

func _on_fish_collected(value: int) -> void:
	fish += value
	var worth := RunnerConfig.POINTS_PER_FISH * value
	if player != null and player.has_powerup(RunnerConfig.POWERUP_DOUBLE):
		worth *= 2
	_score += float(worth)
	missions.note_fish(value)
	if hud != null:
		hud.add_floater("+%d" % worth, &"fish")
	AudioManager.play_sfx("sfx_fish")


func _on_powerup_gained(id: StringName) -> void:
	missions.note_powerup(id)
	_fov_kick = 5.0
	if hud != null:
		var label := "MAGNET"
		if id == RunnerConfig.POWERUP_SHIELD:
			label = "SHIELD"
		elif id == RunnerConfig.POWERUP_DOUBLE:
			label = "DOUBLE POINTS"
		hud.add_floater(label, &"powerup")
	AudioManager.play_sfx("sfx_powerup")


func _on_shield_spent() -> void:
	# Spending the shield is a save, not a hit: it gets the celebration and the
	# multiplier survives.
	_camera_shake = 0.5
	if hud != null:
		hud.add_floater("SHIELD SAVED YOU", &"powerup")
	AudioManager.play_sfx("sfx_powerup")


func _on_near_miss() -> void:
	near_misses += 1
	_score += 15.0
	missions.note_near_miss()
	if hud != null:
		hud.add_floater("CLOSE!", &"near_miss")


func _on_ramp() -> void:
	ramps_hit += 1
	_fov_kick = 7.0
	missions.note_ramp()
	if hud != null:
		hud.add_floater("AIRBORNE", &"score")
	AudioManager.play_sfx("sfx_go")


func _on_mission_complete(text: String) -> void:
	if hud != null:
		hud.show_mission_complete(text)
		hud.set_missions(missions.rows())
		hud.add_floater("MISSION", &"mission")
	AudioManager.play_sfx("sfx_unlock")


func _on_hit_taken(hits_left: int) -> void:
	hits_taken += 1
	clean_metres = 0.0
	_camera_shake = 1.0
	missions.note_hit()
	AudioManager.play_sfx("sfx_bump")
	if hud != null:
		hud.flash_hit()
		if hits_left > 0:
			hud.show_message("%d left" % hits_left)


func _on_death() -> void:
	if _dead:
		return
	_dead = true
	running = false
	if player != null:
		player.set_input_enabled(false)
	AudioManager.play_sfx("sfx_crash")
	var score := int(_score)
	missions.note_run_ended(player.distance if player != null else 0.0, fish, score)
	if hud != null:
		hud.set_missions(missions.rows())
	var previous := Progression.runner_high_score()
	var is_best := Progression.submit_runner_score(score, player.distance if player != null else 0.0)
	if fish > 0:
		Progression.add_fish(fish)
	if hud != null:
		hud.show_game_over({
			"distance": player.distance if player != null else 0.0,
			"fish": fish,
			"score": score,
			"best": previous,
			"is_new_best": is_best,
		})


## Restarts in place — no scene reload, so a retry is instant even on the web
## build where a fresh scene would pay the whole build and shader cost again.
func restart() -> void:
	if hud != null:
		hud.hide_game_over()
	_dead = false
	running = false
	elapsed = 0.0
	fish = 0
	hits_taken = 0
	clean_metres = 0.0
	_score = 0.0
	_countdown = COUNTDOWN_TIME
	_camera_shake = 0.0
	_last_multiplier = 1
	ramps_hit = 0
	near_misses = 0
	missions.begin_run()
	if hud != null:
		hud.set_missions(missions.rows())
	track.reset(_rng.randi())
	remove_child(player)
	player.queue_free()
	player = RunnerPlayer.new()
	player.name = "RunnerPlayer"
	add_child(player)
	player.setup(_player_visual_config())
	player.set_input_enabled(false)
	_connect_player()
	if _touch != null and is_instance_valid(_touch):
		_touch.setup(player)
	chaser.reset()
	_place_camera(0.0, true)


## --- World ------------------------------------------------------------------

## A compact polar daylight set. The racing courses build their environments
## through CourseBase; the runner is not a course, and copying the eight lines
## that matter is cheaper and clearer than inheriting a thousand-line base for
## a sky.
func _build_environment() -> void:
	if GameConfig.is_headless():
		return
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.26, 0.68)
	sky_mat.sky_horizon_color = Color(0.66, 0.83, 0.98)
	sky_mat.ground_bottom_color = Color(0.44, 0.62, 0.85)
	sky_mat.ground_horizon_color = Color(0.66, 0.83, 0.98)
	sky_mat.sun_angle_max = 22.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.74
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.66, 0.86)
	env.fog_density = 0.0022
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.08
	if SettingsManager.glow_allowed():
		env.glow_enabled = true
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_hdr_threshold = 1.45
		env.glow_intensity = 0.45
	world_env.environment = env
	add_child(world_env)
	_world_env = world_env

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.32
	# Raked from the front-left so obstacles throw their shadows toward the
	# player: in a runner the shadow arrives before the object does, and that
	# is a real readability aid at 38 m/s.
	sun.rotation_degrees = Vector3(-38.0, 152.0, 0.0)
	sun.shadow_enabled = String(SettingsManager.get_setting("display", "shadow_quality")) != "off"
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.6
	add_child(sun)
	_sun = sun

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.74, 0.95)
	fill.light_energy = 0.14
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-36.0, -28.0, 0.0)
	add_child(fill)

	_add_weather()
	if String(SettingsManager.get_setting("display", "quality_preset")) != "low":
		var shafts := SunShafts.new()
		shafts.name = "SunShafts"
		add_child(shafts)
		shafts.configure(sun, Color(1.0, 0.97, 0.9).lerp(Color.WHITE, 0.5), 0.34, 13, 99)


## Eases the sky, sun and fog toward the band the player is currently running
## through. The track authors the bands and publishes what each should look
## like; doing the blend here keeps one WorldEnvironment for the whole run
## (swapping environments per band would restart the sky and re-link its
## shader mid-run, which on web is a visible hitch).
func _blend_biome(delta: float) -> void:
	if _world_env == null or track == null or player == null:
		return
	var want := RunnerTrack.biome_environment(track.biome_at_z(player.position.z))
	if want.is_empty():
		return
	var env := _world_env.environment
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	var k := clampf(delta * 0.9, 0.0, 1.0)
	if sky_mat != null:
		sky_mat.sky_top_color = sky_mat.sky_top_color.lerp(
			want.get("sky_top", sky_mat.sky_top_color), k)
		sky_mat.sky_horizon_color = sky_mat.sky_horizon_color.lerp(
			want.get("sky_horizon", sky_mat.sky_horizon_color), k)
		sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	env.fog_light_color = env.fog_light_color.lerp(want.get("fog", env.fog_light_color), k)
	env.ambient_light_energy = lerpf(env.ambient_light_energy,
		float(want.get("ambient", env.ambient_light_energy)), k)
	if _sun != null:
		_sun.light_color = _sun.light_color.lerp(want.get("sun", _sun.light_color), k)
		_sun.light_energy = lerpf(_sun.light_energy,
			float(want.get("sun_energy", _sun.light_energy)), k)


## Snow around the lens. The racing courses get this through CourseBase; the
## runner is not a course, and the parallax of a few large out-of-focus flakes
## crossing close to the camera is the cheapest depth cue available to a
## renderer with no depth of field — at 38 m/s it is also most of what sells
## the speed.
func _add_weather() -> void:
	if String(SettingsManager.get_setting("display", "particle_quality")) == "low":
		return
	var near := GPUParticles3D.new()
	near.name = "NearSnow"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(9.0, 3.0, 6.0)
	mat.direction = Vector3(0.15, -1.0, 0.6)
	mat.spread = 18.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.5
	# Blown backward as well as down: the flakes have to move with the run or
	# they read as a static screen effect pasted over a moving world.
	mat.gravity = Vector3(0.6, -3.4, 9.0)
	mat.scale_min = 0.5
	mat.scale_max = 2.0
	near.process_material = mat
	var flake := QuadMesh.new()
	flake.size = Vector2(0.26, 0.26)
	flake.material = VisualLibrary.billboard_puff_material(
		Color(0.97, 0.99, 1.0, 0.5), 32, 0.85)
	near.draw_pass_1 = flake
	near.amount = 54
	near.lifetime = 2.6
	near.preprocess = 2.0
	near.visibility_aabb = AABB(Vector3(-20, -16, -20), Vector3(40, 32, 40))
	add_child(near)
	_near_snow = near


## --- Pause ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if GameConfig.is_headless() or _dead:
		return
	if event.is_action_pressed(&"pause"):
		_toggle_pause()


func _toggle_pause() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if tree.paused:
		_close_pause()
		return
	tree.paused = true
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 90
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.06, 0.12, 0.82)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(scrim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	scrim.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	box.add_child(title)
	var resume := UITheme.make_button("Resume", Vector2(280, 64), 28)
	resume.pressed.connect(_close_pause)
	box.add_child(resume)
	var quit := UITheme.make_button("Main Menu", Vector2(280, 64), 28)
	quit.pressed.connect(func() -> void:
		get_tree().paused = false
		SceneRouter.go_to(Game.SCENE_MAIN_MENU))
	box.add_child(quit)
	add_child(_pause_layer)
	resume.grab_focus()


func _close_pause() -> void:
	get_tree().paused = false
	if _pause_layer != null and is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
	_pause_layer = null


func _exit_tree() -> void:
	# A mode that can be left while paused must never hand the next scene a
	# paused tree.
	var tree := get_tree()
	if tree != null:
		tree.paused = false
