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
var _rng := RandomNumberGenerator.new()
var _pause_layer: CanvasLayer = null
var _touch: RunnerTouch = null
## Sim hook: ends the run after this many seconds when > 0.
static var auto_quit_after: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_build_environment()

	track = RunnerTrack.new()
	track.name = "RunnerTrack"
	add_child(track)
	track.setup(_rng.randi())

	player = RunnerPlayer.new()
	player.name = "RunnerPlayer"
	add_child(player)
	player.setup(_player_visual_config())
	player.set_input_enabled(false)
	player.hit_taken.connect(_on_hit_taken)
	player.fish_collected.connect(_on_fish_collected)
	player.died.connect(_on_death)

	chaser = RunnerChaser.new()
	chaser.name = "RunnerChaser"
	add_child(chaser)
	chaser.setup()
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
		if SettingsManager.touch_controls_enabled():
			_touch = RunnerTouch.new()
			_touch.name = "RunnerTouch"
			add_child(_touch)
			_touch.setup(player)
		AudioManager.play_music("music_race")

	ShaderWarmup.warm(self)


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
	clean_metres += player.distance - before
	_score += (player.distance - before) * RunnerConfig.POINTS_PER_METRE \
		* float(RunnerConfig.multiplier_for(clean_metres))

	# Difficulty is distance-driven rather than time-driven: a player who dies
	# early and restarts should always see the same gentle opening, however
	# long they have had the mode open.
	track.update_stream(player.position.z, clampf(player.distance / 2600.0, 0.0, 1.0))
	chaser.tick(delta, player.distance, float(hits_taken))
	_place_camera(delta, false)

	if hud != null:
		hud.set_stats(player.distance, fish, int(_score),
			RunnerConfig.multiplier_for(clean_metres), player.hits_left, chaser.gap)

	if auto_quit_after > 0.0 and elapsed >= auto_quit_after:
		_on_death()


## --- Camera -----------------------------------------------------------------

## Chase camera: behind and above, easing toward the player's lane so a lane
## change reads as movement rather than as the world sliding. FOV opens with
## speed, which is most of what makes 38 m/s feel different from 15.
func _place_camera(delta: float, snap: bool) -> void:
	if camera == null or player == null:
		return
	# Close and low. The first pass sat 8.4 m back and 3.35 m up and the penguin
	# read as a distant speck — in a runner the character is the thing you are
	# reading every frame, and it has to be big enough to see a slide start.
	var target := Vector3(player.position.x * 0.55, 2.55 + player.position.y * 0.32,
		player.position.z + 5.9)
	if snap:
		camera.position = target
	else:
		camera.position = camera.position.lerp(target, clampf(delta * 9.0, 0.0, 1.0))
	if _camera_shake > 0.0:
		_camera_shake = maxf(0.0, _camera_shake - delta * 2.4)
		camera.position += Vector3(
			_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), 0.0) * _camera_shake * 0.5
	var look := Vector3(player.position.x * 0.5, 1.35, player.position.z - 11.0)
	camera.look_at(look, Vector3.UP)
	var speed_ratio := clampf((player.speed - RunnerConfig.START_SPEED)
		/ maxf(RunnerConfig.MAX_SPEED - RunnerConfig.START_SPEED, 0.001), 0.0, 1.0)
	camera.fov = lerpf(74.0, 88.0, speed_ratio)


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
	_score += float(RunnerConfig.POINTS_PER_FISH * value)
	AudioManager.play_sfx("sfx_fish")


func _on_hit_taken(hits_left: int) -> void:
	hits_taken += 1
	clean_metres = 0.0
	_camera_shake = 1.0
	AudioManager.play_sfx("sfx_bump")
	if hud != null and hits_left > 0:
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
	track.reset(_rng.randi())
	remove_child(player)
	player.queue_free()
	player = RunnerPlayer.new()
	player.name = "RunnerPlayer"
	add_child(player)
	player.setup(_player_visual_config())
	player.set_input_enabled(false)
	player.hit_taken.connect(_on_hit_taken)
	player.fish_collected.connect(_on_fish_collected)
	player.died.connect(_on_death)
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

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.74, 0.95)
	fill.light_energy = 0.14
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-36.0, -28.0, 0.0)
	add_child(fill)

	if String(SettingsManager.get_setting("display", "quality_preset")) != "low":
		var shafts := SunShafts.new()
		shafts.name = "SunShafts"
		add_child(shafts)
		shafts.configure(sun, Color(1.0, 0.97, 0.9).lerp(Color.WHITE, 0.5), 0.34, 13, 99)


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
