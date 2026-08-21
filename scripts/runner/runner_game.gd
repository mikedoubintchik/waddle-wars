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
const RUNNER_ART_SET_PATH: String = "res://data/art/runner_art_set_foundation.tres"
const RUNNER_DAY_PREVIEW_FRAGMENT_PATH: String = \
		"res://data/art/fragments/runner_day_kit_v1.json"
const BIOME_IDS: PackedStringArray = ["day", "dusk", "cave", "night"]

var track: RunnerTrack = null
var player: RunnerPlayer = null
var chaser: RunnerChaser = null
var hud: RunnerHUD = null
var camera: Camera3D = null
var vfx: RunnerVfx = null

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
var _shake_roll: float = 0.0
var _fov_kick: float = 0.0
## 1.0 during the countdown, 0.0 by GO. The camera starts wide and high and
## eases into the run framing, so the run opens on a move instead of on a cut.
var _intro_t: float = 1.0
## Downward camera punch on touchdown, and the airborne latch that fires it.
var _land_dip: float = 0.0
var _ramp_airborne: bool = false
var _presentation_time: float = 0.0
## False until the world is assembled. The loading overlay watches this so its
## animation keeps running while the track builds — on the single-threaded web
## build, a synchronous build freezes every frame including the spinner.
var build_finished: bool = false
var _near_snow: GPUParticles3D = null
## Low, fast, lateral snow. Falling flakes read as weather; flakes blowing
## ACROSS the corridor at deck height read as speed, which is the thing this
## mode is actually selling.
var _spindrift: GPUParticles3D = null
var _snow_mat: StandardMaterial3D = null
var _drift_mat: StandardMaterial3D = null
var _world_env: WorldEnvironment = null
var _sun: DirectionalLight3D = null
var _fill: DirectionalLight3D = null
## The shaft fan's material, reached through its MeshInstance3D rather than
## through SunShafts' own private field. Its RGB is the per-band tint AND the
## per-band strength in one: the fan blends additively, so a darker colour is a
## weaker shaft. (SunShafts owns the alpha channel — it rewrites it every frame
## for the glare window — so only RGB is ours to touch.)
var _shaft_mat: StandardMaterial3D = null
## Rim light on the player. From a chase camera the penguin only ever shows its
## dorsal, which is the one surface authored to be featureless, so without a
## dedicated edge light it is a hole punched in the picture at any deck value.
var _rim: OmniLight3D = null
var _rng := RandomNumberGenerator.new()
var _pause_layer: CanvasLayer = null
var _touch: RunnerTouch = null
var _layout: LayoutProfile = null
## Foundation resources are advisory while procedural fallback is enabled.
## They give authored production assets one stable seam without making a
## schema fixture or a failed manifest capable of blanking a playable run.
var _runner_art_set: RunnerArtSet = null
var _art_catalog: ArtCatalog = null
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
	_refresh_layout()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_refresh_layout):
		viewport.size_changed.connect(_refresh_layout)
	await _initialize_art_foundation()
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
	track.setup(_rng.randi(), _runner_dressing_density(RunnerTrack.Biome.DAY))
	await _stage()

	player = RunnerPlayer.new()
	player.name = "RunnerPlayer"
	add_child(player)
	player.setup(_player_visual_config())
	player.set_input_enabled(false)
	_connect_player()

	if not GameConfig.is_headless():
		vfx = RunnerVfx.new()
		vfx.name = "RunnerVfx"
		add_child(vfx)
		vfx.setup()

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
		camera.fov = _layout.runner_base_fov if _layout != null else 74.0
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


## Loads and validates the contract before any runner art is built. The DAY
## review kit is requested behind this staged loader; incomplete biomes and
## roles remain on their explicit procedural fallback until their authored
## assets pass visual, gameplay and performance gates.
func _initialize_art_foundation() -> void:
	var loaded := load(RUNNER_ART_SET_PATH)
	var candidate := loaded as RunnerArtSet
	if candidate == null:
		push_warning("Runner art set unavailable; using procedural fallback")
		return
	var errors := candidate.validation_errors()
	if not errors.is_empty():
		push_warning("Runner art set invalid; using procedural fallback: %s" % [errors])
		return
	if not candidate.production_ready and not candidate.allow_procedural_fallback:
		push_warning("Runner art set is incomplete and forbids fallback; keeping playable procedural art")
		return
	_runner_art_set = candidate
	_art_catalog = ArtCatalog.new()
	var manifest_error := _art_catalog.reload_manifest()
	if manifest_error != OK:
		push_warning("Runner art catalog unavailable; profiles remain active, procedural geometry stays authoritative")
		_art_catalog = null
		return
	# Local/debug builds consume the honest production_ready=false fragment so
	# ordinary Waddle Run shows the DAY review kit before catalog promotion.
	# Release exports never enter this branch and therefore keep the strict,
	# production-only central manifest unchanged.
	if ArtCatalog.preview_overlay_allowed(OS.is_debug_build(), OS.has_feature("editor")):
		var preview_error := _apply_runner_day_preview(_art_catalog)
		if preview_error == OK and _art_catalog.preview_overlay_active():
			push_warning("Runner DAY review preview enabled (production_ready=false); release catalog unchanged")
		elif preview_error != OK:
			push_warning("Runner DAY review preview rejected (%d); procedural fallback remains active: %s"
					% [preview_error, _art_catalog.manifest_errors()])
	var ids := _runner_art_set.collect_preload_ids("day")
	if ids.is_empty():
		return
	var request_error := _art_catalog.begin_preload(ids)
	if request_error != OK:
		push_warning("Some runner preload requests failed (%d); procedural fallback remains active" % request_error)
	while true:
		var status := _art_catalog.poll_preload()
		if bool(status.get("complete", true)):
			if int(status.get("failed", 0)) > 0:
				push_warning("Runner art preload incomplete; procedural fallback remains active: %s"
						% [status.get("failures", {})])
			return
		await _stage()
		# _stage() deliberately does not yield in headless mode. Future catalog
		# fixtures can still complete without turning this polling loop into a
		# busy wait in CI.
		if GameConfig.is_headless() and get_tree() != null:
			await get_tree().process_frame


## Small synchronous seam used by contract tests to prove RunnerGame consumes
## the real fragment, not the legacy capture-only fixture manifest.
func _apply_runner_day_preview(catalog: ArtCatalog) -> Error:
	if catalog == null:
		return ERR_INVALID_PARAMETER
	return catalog.apply_preview_fragment(RUNNER_DAY_PREVIEW_FRAGMENT_PATH)


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
	player.presentation_event.connect(_on_presentation_event)


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
	_presentation_time += delta
	if _dead:
		if player != null:
			player.tick(delta, player.speed)
		_update_follow_fx(0.0)
		if vfx != null:
			vfx.tick(delta)
		_settle_camera(delta)
		return
	if not running:
		_countdown -= delta
		_intro_t = clampf(_countdown / COUNTDOWN_TIME, 0.0, 1.0)
		if hud != null:
			var count := int(ceil(_countdown / COUNTDOWN_TIME * 3.0))
			hud.show_message("GO!" if count <= 0 else str(count))
		if _countdown <= 0.0:
			running = true
			missions.begin_run()
			player.set_input_enabled(true)
			if hud != null:
				hud.show_message("GO!")
		_place_camera(delta, false)
		_blend_biome(delta)
		_update_follow_fx(0.0)
		if vfx != null:
			vfx.tick(delta)
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
	_update_runner_presentation(delta)

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

## Shared viewport profile. Camera and HUD now classify the same geometry, so
## a phone resize cannot leave gameplay composed for one aspect and UI for
## another. Safe to call before camera/player construction and from size_changed.
func _refresh_layout() -> void:
	var viewport := get_viewport()
	_layout = LayoutProfile.for_viewport(viewport) if viewport != null \
		else LayoutProfile.for_view_size(Vector2(1920.0, 1080.0))
	if camera != null:
		camera.fov = _layout.runner_base_fov
		_place_camera(0.0, true)

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
	var chase_distance := _layout.runner_chase_distance if _layout != null else 5.9
	var chase_height := _layout.runner_chase_height if _layout != null else 2.95
	var base_fov := _layout.runner_base_fov if _layout != null else 74.0
	var look_ahead := _layout.runner_look_ahead if _layout != null else 11.0
	var lift := 0.32 if player.position.y < 1.6 else 0.72
	var intro := smoothstep(0.0, 1.0, _intro_t)
	_land_dip = move_toward(_land_dip, 0.0, delta * 2.8)
	var speed_ratio := clampf((player.speed - RunnerConfig.START_SPEED)
		/ maxf(RunnerConfig.MAX_SPEED - RunnerConfig.START_SPEED, 0.001), 0.0, 1.0)
	# FOV opens with speed, but an FOV-only zoom shrinks the hero from ~14% to
	# ~10% of frame height. Dolly toward the player by the matching tangent
	# ratio, keeping the authored chase HEIGHT (and tunnel clearance) intact.
	var speed_fov := lerpf(base_fov, base_fov + 14.0, speed_ratio)
	var fov_ratio := tan(deg_to_rad(base_fov * 0.5)) \
			/ maxf(tan(deg_to_rad(speed_fov * 0.5)), 0.001)
	var vertical_offset := chase_height - player.position.y * (1.0 - lift)
	var base_radius := Vector2(chase_distance, vertical_offset).length()
	# LayoutProfile's semantic target stays inside the 14-18% readability
	# band. The procedural hero calibrates to ~14% at the raw camera values;
	# pull in enough to reach a restrained 15-16%, with a small pose allowance
	# because slide/tuck animations shorten the visible silhouette.
	var frame_target := clampf(_layout.hero_frame_height if _layout != null else 0.15,
			0.15, 0.16)
	var hero_scale := 0.14 / frame_target
	if player.state == RunnerPlayer.State.JUMP or player.state == RunnerPlayer.State.SLIDE:
		hero_scale *= 0.92
		# Legacy tucks lose projected height, so the camera moves closer. The
		# authored rig keeps fuller bounds in slide/takeoff (especially its wings)
		# and needs the neutral radius instead. Ramp launch retains the closer air
		# treatment so its apex remains at the lower edge of the 14-18% band.
		if player._visual != null and player._visual.is_authored_backend_active() \
				and not player._launched:
			hero_scale /= 0.92
	# Tall projections leave the procedural penguin smaller than the semantic
	# target after pose bounds are projected. A narrow touch canvas needs the
	# stronger correction; keep both camera-only and class-scoped so landscape
	# composition stays exact.
	if _layout != null:
		if _layout.view_class == LayoutProfile.ViewClass.PORTRAIT_NARROW:
			hero_scale *= 0.86
		elif _layout.view_class == LayoutProfile.ViewClass.PORTRAIT_TABLET:
			hero_scale *= 0.965
		elif _layout.view_class == LayoutProfile.ViewClass.LANDSCAPE_COMPACT:
			# Perspective makes the speed-FOV dolly slightly over-correct on a
			# touch-scaled compact canvas. Ease back with speed so the hero never
			# crowds out the lane decision window late in a grounded run. Airborne
			# poses already have enough breathing room from height tracking.
			if player.state != RunnerPlayer.State.JUMP:
				hero_scale *= lerpf(1.0, 1.095, speed_ratio)
	var framed_radius := base_radius * fov_ratio * hero_scale
	# The ordinary half-chase floor protects arches in grounded play. At the
	# apex of a ramp launch it overrides the portrait framing correction, so a
	# narrow canvas may use a slightly closer presentation-only floor.
	var minimum_distance_scale := 0.44 if _layout != null \
			and _layout.view_class == LayoutProfile.ViewClass.PORTRAIT_NARROW \
			and player._launched else 0.5
	var framed_distance := sqrt(maxf(framed_radius * framed_radius
			- vertical_offset * vertical_offset,
			chase_distance * chase_distance * minimum_distance_scale * minimum_distance_scale))
	var target := Vector3(player.position.x * 0.55, chase_height + player.position.y * lift,
		player.position.z + framed_distance)
	# Countdown starts on a wider establishing view, then settles behind the
	# penguin by GO. A landing punch moves only the camera, never the player.
	target += Vector3(0.0, intro * chase_height * 0.75 - _land_dip,
			intro * chase_distance * 0.42)
	if snap:
		camera.position = target
	else:
		camera.position = camera.position.lerp(target, clampf(delta * 9.0, 0.0, 1.0))
	if _camera_shake > 0.0:
		_camera_shake = maxf(0.0, _camera_shake - delta * 2.4)
		# Analytic noise keeps camera juice out of the seeded gameplay RNG. A
		# different frame rate may change the picture, never the next run seed.
		var phase := _presentation_time * 47.0
		camera.position += Vector3(sin(phase), sin(phase * 1.37 + 1.1), 0.0) \
			* _camera_shake * 0.42
		_shake_roll = sin(phase * 0.73) * _camera_shake * 0.035
	else:
		_shake_roll = move_toward(_shake_roll, 0.0, delta * 0.18)
	# The aim point rises with the penguin too, so a launch is framed rather
	# than merely kept on screen.
	var look := Vector3(player.position.x * 0.5, 1.35 + player.position.y * 0.45,
		player.position.z - look_ahead)
	camera.look_at(look, Vector3.UP)
	# The kick is what makes a ramp or a power-up land as an EVENT rather than
	# as a number changing: the whole picture widens for a beat and settles.
	_fov_kick = maxf(0.0, _fov_kick - delta * 14.0)
	var intro_fov := intro * (3.0 if UITheme.reduced_motion() else 8.0)
	camera.fov = speed_fov + _fov_kick + intro_fov
	# Roll with the penguin's bank. A camera that stays level through a lane
	# change makes the world look like it slid sideways under a static player.
	camera.rotation.z += player.rotation.z * 0.34 + _shake_roll


## After death the camera keeps drifting and looking at the wreck, so the
## game-over panel is not slapped over a frozen frame.
func _settle_camera(delta: float) -> void:
	if camera == null or player == null:
		return
	var chase_distance := _layout.runner_chase_distance if _layout != null else 5.9
	var chase_height := _layout.runner_chase_height if _layout != null else 2.95
	camera.position = camera.position.lerp(
		Vector3(player.position.x * 0.5, chase_height + 0.25,
				player.position.z + chase_distance + 1.1),
		clampf(delta * 2.4, 0.0, 1.0))
	if _camera_shake > 0.0:
		_camera_shake = maxf(0.0, _camera_shake - delta * 1.8)
		var phase := _presentation_time * 39.0
		camera.position += Vector3(sin(phase), sin(phase * 1.41), 0.0) \
			* _camera_shake * 0.32
	camera.look_at(Vector3(player.position.x, 1.1, player.position.z), Vector3.UP)


## --- Run events -------------------------------------------------------------

## One presentation consumer, independent from gameplay/HUD signals. Keeping
## effects here means adding the typed seam cannot double-fire any legacy path.
func _on_presentation_event(event_id: StringName, context: Dictionary) -> void:
	var fallback := player.global_position if player != null else Vector3.ZERO
	var at: Vector3 = context.get("world_position", fallback)
	var strength := float(context.get("strength", 1.0))
	match event_id:
		RunnerPlayer.PRESENT_FISH_COLLECTED:
			if vfx != null:
				vfx.pickup(at)
		RunnerPlayer.PRESENT_POWERUP_GAINED:
			_fov_kick = 2.5 if UITheme.reduced_motion() else 5.0
			if vfx != null:
				var item_id: StringName = context.get("item_id", &"")
				vfx.powerup(at, _powerup_vfx_color(item_id))
		RunnerPlayer.PRESENT_SHIELD_SPENT:
			_add_camera_shake(0.5)
			if vfx != null:
				vfx.impact(at + Vector3.UP * 0.85, true)
		RunnerPlayer.PRESENT_NEAR_MISS:
			if vfx != null:
				vfx.whoosh(at + Vector3.UP * 0.75, float(context.get("side", 0.0)))
		RunnerPlayer.PRESENT_RAMP_LAUNCHED:
			_ramp_airborne = true
			_fov_kick = 3.0 if UITheme.reduced_motion() else 7.0
			if vfx != null:
				vfx.launch(at + Vector3(0.0, 0.08, 0.45))
		RunnerPlayer.PRESENT_LANDED:
			_land_dip = maxf(_land_dip,
					(0.14 if UITheme.reduced_motion() else lerpf(0.28, 0.48, strength)))
			if vfx != null:
				vfx.land(at + Vector3.UP * 0.03, strength)
			_ramp_airborne = false
		RunnerPlayer.PRESENT_HIT_TAKEN:
			_add_camera_shake(strength)
			if vfx != null:
				vfx.impact(at + Vector3.UP * 0.85,
						bool(context.get("shielded", false)))


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
	if chaser != null:
		chaser.overrun()
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
	_shake_roll = 0.0
	_fov_kick = 0.0
	_intro_t = 1.0
	_land_dip = 0.0
	_ramp_airborne = false
	_last_multiplier = 1
	ramps_hit = 0
	near_misses = 0
	missions.begin_run()
	if hud != null:
		hud.set_missions(missions.rows())
	track.reset(_rng.randi(), _runner_dressing_density(RunnerTrack.Biome.DAY))
	remove_child(player)
	player.queue_free()
	player = RunnerPlayer.new()
	player.name = "RunnerPlayer"
	add_child(player)
	player.setup(_player_visual_config())
	player.set_input_enabled(false)
	_connect_player()
	if vfx != null:
		vfx.clear()
	if _touch != null and is_instance_valid(_touch):
		_touch.setup(player)
	chaser.reset()
	_place_camera(0.0, true)


## Presentation consumes the player's already-resolved state. It never feeds
## positions, timings or random values back into the runner simulation.
func _update_runner_presentation(delta: float) -> void:
	if player == null:
		return
	var airborne := player.state == RunnerPlayer.State.JUMP

	var pace := clampf((player.speed - RunnerConfig.START_SPEED)
			/ maxf(RunnerConfig.MAX_SPEED - RunnerConfig.START_SPEED, 0.001), 0.0, 1.0)
	_update_follow_fx(pace)
	if vfx == null:
		return
	var emit_delta := delta * (0.42 if UITheme.reduced_motion() else 1.0)
	if player.position.y <= 0.05 \
			and (player.state == RunnerPlayer.State.RUN or player.state == RunnerPlayer.State.SLIDE):
		vfx.ground_spray(player.global_position + Vector3(0.0, 0.03, 0.35), pace,
				emit_delta, player.state == RunnerPlayer.State.SLIDE)
	if _ramp_airborne and airborne:
		vfx.launch_trail(player.global_transform * Vector3(0.0, 0.55, 0.45), emit_delta)
	if not player.powerups.is_empty():
		vfx.ribbons(player.global_transform * Vector3(-0.46, 0.86, 0.18),
				player.global_transform * Vector3(0.46, 0.86, 0.18),
				_active_powerup_vfx_color(), emit_delta)
	vfx.speed_motes(player.global_position + Vector3(0.0, 2.1, 2.0), pace, emit_delta)
	vfx.tick(delta)


func _update_follow_fx(pace: float) -> void:
	if player == null:
		return
	if vfx != null:
		vfx.set_cull_centre(player.global_position + Vector3.UP)
	if _near_snow != null:
		_near_snow.global_position = player.global_position + Vector3(
				player.position.x * -0.5, 3.4, -4.0)
		_near_snow.amount_ratio = 0.72 + pace * 0.28
	if _spindrift != null:
		_spindrift.global_position = player.global_position + Vector3(0.0, 0.65, -5.0)
		_spindrift.amount_ratio = 0.42 + pace * 0.58
	if _rim != null:
		_rim.global_position = player.global_position + Vector3(-1.5, 2.35, 1.7)


func _add_camera_shake(amount: float) -> void:
	match String(SettingsManager.get_setting("accessibility", "camera_shake")):
		"off":
			return
		"reduced":
			amount *= 0.35
	_camera_shake = minf(_camera_shake + amount, 1.0)


func _powerup_vfx_color(id: StringName) -> Color:
	match id:
		RunnerConfig.POWERUP_SHIELD:
			return RunnerVfx.duck_color()
		RunnerConfig.POWERUP_DOUBLE:
			return RunnerVfx.collect_color()
		_:
			return RunnerVfx.powerup_color()


func _active_powerup_vfx_color() -> Color:
	if player != null:
		if player.has_powerup(RunnerConfig.POWERUP_SHIELD):
			return RunnerVfx.duck_color()
		if player.has_powerup(RunnerConfig.POWERUP_DOUBLE):
			return RunnerVfx.collect_color()
	return RunnerVfx.powerup_color()


## --- World ------------------------------------------------------------------

## A compact polar daylight set. The racing courses build their environments
## through CourseBase; the runner is not a course, and copying the eight lines
## that matter is cheaper and clearer than inheriting a thousand-line base for
## a sky.
func _build_environment() -> void:
	if GameConfig.is_headless():
		return
	var day := _runner_environment(RunnerTrack.Biome.DAY)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = day.get("sky_top", Color(0.05, 0.35, 0.82))
	sky_mat.sky_horizon_color = day.get("sky_horizon", Color(0.40, 0.78, 0.96))
	sky_mat.ground_bottom_color = day.get("ground_bottom", Color(0.08, 0.32, 0.58))
	sky_mat.ground_horizon_color = day.get("ground_horizon", Color(0.28, 0.60, 0.82))
	sky_mat.sun_angle_max = 22.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(day.get("ambient", 0.38))
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Preserve headroom on pale deck cassettes; V6 clipped their authored value
	# bands into one white sheet before roughness or panel wear could read.
	env.tonemap_exposure = 0.86
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = day.get("fog", Color(0.40, 0.76, 0.95))
	env.fog_density = float(day.get("fog_density", 0.0016))
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
	sun.light_color = day.get("sun", Color(1.0, 0.94, 0.76))
	sun.light_energy = float(day.get("sun_energy", 1.55))
	# Higher and softer than the blockout rig. Pooled contact patches provide
	# timing; long raking shadows no longer cross whole lanes or black out paint.
	sun.rotation_degrees = Vector3(-58.0, 152.0, 0.0)
	sun.shadow_enabled = String(SettingsManager.get_setting("display", "shadow_quality")) != "off"
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 3.0
	add_child(sun)
	_sun = sun

	var fill := DirectionalLight3D.new()
	var day_horizon: Color = day.get("sky_horizon", Color(0.40, 0.78, 0.96))
	fill.light_color = day_horizon.lerp(Color.WHITE, 0.10)
	fill.light_energy = float(day.get("ambient", 0.38)) * 0.72
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-54.0, -28.0, 0.0)
	add_child(fill)
	_fill = fill

	var rim := OmniLight3D.new()
	rim.name = "PlayerRim"
	var day_shaft: Color = day.get("shaft", Color(1.0, 0.97, 0.86))
	rim.light_color = day_shaft.lerp(Color.WHITE, 0.12)
	# The player is a dorsal surface seen from behind: every feature the
	# penguin has faces away from this camera forever, so it reads as a hole in
	# the image unless something draws its edge. This is that something.
	rim.light_energy = 2.1
	rim.light_specular = 0.7
	rim.omni_range = 6.4
	rim.omni_attenuation = 1.25
	rim.shadow_enabled = false
	add_child(rim)
	_rim = rim

	_add_weather()
	if String(SettingsManager.get_setting("display", "quality_preset")) != "low":
		var shafts := SunShafts.new()
		shafts.name = "SunShafts"
		add_child(shafts)
		shafts.configure(sun, day_shaft, 0.34, 13, 99)
		var fan := shafts.get_node_or_null("ShaftFan") as MeshInstance3D
		if fan != null:
			_shaft_mat = fan.material_override as StandardMaterial3D


## Eases the sky, sun and fog toward the band the player is currently running
## through. The track authors the bands and publishes what each should look
## like; doing the blend here keeps one WorldEnvironment for the whole run
## (swapping environments per band would restart the sky and re-link its
## shader mid-run, which on web is a visible hitch).
## Authored atmosphere profiles override the procedural dictionary only after
## the whole art-set contract validates. Missing biome/profile data falls back
## atomically, so partial production data cannot produce a half-lit world.
func _runner_environment(biome: int) -> Dictionary:
	var fallback := RunnerTrack.biome_environment(biome)
	if _runner_art_set == null or biome < 0 or biome >= BIOME_IDS.size():
		return fallback
	var profile := _runner_art_set.profile_for_biome(BIOME_IDS[biome])
	if profile == null or not profile.validation_errors().is_empty():
		return fallback
	var authored := profile.environment_values()
	for key: Variant in authored.keys():
		fallback[key] = authored[key]
	return fallback


## Applies the same authored quality tier to procedural fallback dressing. Art
## density is presentation-only; gameplay generation owns a separate RNG and
## never sees this value.
func _runner_dressing_density(biome: int) -> float:
	var tier := String(SettingsManager.get_setting("display", "quality_preset"))
	var defaults: Dictionary = CourseVisualProfile.DEFAULT_QUALITY_TIERS.get(
			tier, CourseVisualProfile.DEFAULT_QUALITY_TIERS["medium"])
	var density := float(defaults.get("dressing_density", 0.65))
	if _runner_art_set != null and biome >= 0 and biome < BIOME_IDS.size():
		var profile := _runner_art_set.profile_for_biome(BIOME_IDS[biome])
		if profile != null and profile.validation_errors().is_empty():
			density = float(profile.quality_settings(tier).get("dressing_density", density))
	return clampf(density, 0.0, 1.0)


func _blend_biome(delta: float) -> void:
	if _world_env == null or track == null or player == null:
		return
	var want := _runner_environment(track.biome_at_z(player.position.z))
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
		sky_mat.ground_horizon_color = sky_mat.ground_horizon_color.lerp(
			want.get("ground_horizon", sky_mat.ground_horizon_color), k)
		sky_mat.ground_bottom_color = sky_mat.ground_bottom_color.lerp(
			want.get("ground_bottom", sky_mat.ground_bottom_color), k)
	env.fog_light_color = env.fog_light_color.lerp(want.get("fog", env.fog_light_color), k)
	env.fog_density = lerpf(env.fog_density,
			float(want.get("fog_density", env.fog_density)), k)
	env.ambient_light_energy = lerpf(env.ambient_light_energy,
		float(want.get("ambient", env.ambient_light_energy)), k)
	if _sun != null:
		_sun.light_color = _sun.light_color.lerp(want.get("sun", _sun.light_color), k)
		_sun.light_energy = lerpf(_sun.light_energy,
			float(want.get("sun_energy", _sun.light_energy)), k)
	var horizon: Color = want.get("sky_horizon", Color(0.4, 0.72, 0.94))
	var ambient := float(want.get("ambient", 0.35))
	if _fill != null:
		_fill.light_color = _fill.light_color.lerp(horizon.lerp(Color.WHITE, 0.10), k)
		_fill.light_energy = lerpf(_fill.light_energy, ambient * 0.72, k)
	var shaft: Color = want.get("shaft", Color.WHITE)
	if _shaft_mat != null:
		var current_shaft := _shaft_mat.albedo_color
		var shaft_target := Color(shaft.r, shaft.g, shaft.b, current_shaft.a)
		_shaft_mat.albedo_color = current_shaft.lerp(shaft_target, k)
	if _rim != null:
		_rim.light_color = _rim.light_color.lerp(shaft.lerp(Color.WHITE, 0.12), k)
		_rim.light_energy = lerpf(_rim.light_energy,
				clampf(0.72 + (0.38 - ambient) * 1.35, 0.68, 0.98), k)
	var weather_tint := horizon.lerp(Color.WHITE, 0.72)
	if _snow_mat != null:
		var snow_now := _snow_mat.albedo_color
		_snow_mat.albedo_color = snow_now.lerp(Color(
				weather_tint.r, weather_tint.g, weather_tint.b, snow_now.a), k)
	if _drift_mat != null:
		var drift_now := _drift_mat.albedo_color
		var drift_tint := shaft.lerp(Color.WHITE, 0.62)
		_drift_mat.albedo_color = drift_now.lerp(Color(
				drift_tint.r, drift_tint.g, drift_tint.b, drift_now.a), k)


## Snow around the lens. The racing courses get this through CourseBase; the
## runner is not a course, and the parallax of a few large out-of-focus flakes
## crossing close to the camera is the cheapest depth cue available to a
## renderer with no depth of field — at 38 m/s it is also most of what sells
## the speed.
func _add_weather() -> void:
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	if quality == "low":
		return
	var near := GPUParticles3D.new()
	near.name = "NearSnow"
	near.local_coords = false
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
	mat.scale_min = 0.45
	mat.scale_max = 1.35
	near.process_material = mat
	var flake := QuadMesh.new()
	flake.size = Vector2(0.20, 0.20)
	_snow_mat = VisualLibrary.billboard_puff_material(
			Color(0.97, 0.99, 1.0, 0.42), 32, 0.85).duplicate() as StandardMaterial3D
	flake.material = _snow_mat
	near.draw_pass_1 = flake
	near.amount = 54 if quality == "high" else 36
	near.lifetime = 2.6
	near.preprocess = 2.0
	near.visibility_aabb = AABB(Vector3(-20, -16, -20), Vector3(40, 32, 40))
	add_child(near)
	_near_snow = near

	var drift := GPUParticles3D.new()
	drift.name = "Spindrift"
	drift.local_coords = false
	var wind := ParticleProcessMaterial.new()
	wind.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	wind.emission_box_extents = Vector3(10.5, 0.48, 7.0)
	wind.direction = Vector3(0.55, 0.02, 1.0).normalized()
	wind.spread = 14.0
	wind.initial_velocity_min = 8.0
	wind.initial_velocity_max = 16.0
	wind.gravity = Vector3(1.8, -0.7, 7.0)
	wind.scale_min = 0.45
	wind.scale_max = 1.35
	drift.process_material = wind
	var mote := QuadMesh.new()
	mote.size = Vector2(0.13, 0.13)
	_drift_mat = VisualLibrary.billboard_puff_material(
			Color(0.86, 0.95, 1.0, 0.42), 32, 0.78).duplicate() as StandardMaterial3D
	mote.material = _drift_mat
	drift.draw_pass_1 = mote
	drift.amount = (20 if UITheme.reduced_motion() else 46) if quality == "high" \
			else (14 if UITheme.reduced_motion() else 30)
	drift.lifetime = 1.25
	drift.preprocess = 1.2
	drift.visibility_aabb = AABB(Vector3(-24, -8, -18), Vector3(48, 16, 42))
	add_child(drift)
	_spindrift = drift


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
