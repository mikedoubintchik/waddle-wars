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

const HitDistortion = preload("res://scripts/runner/runner_hit_distortion.gd")
const SkyBirds = preload("res://scripts/runner/runner_sky_birds.gd")
const COUNTDOWN_TIME: float = 1.6
## Let the last impact read, then let snow catch the penguin before results.
## Results are banked immediately; this interval is presentation only.
const CATCH_TIME: float = 2.4
const RUNNER_ART_SET_PATH: String = "res://data/art/runner_art_set_foundation.tres"
const RUNNER_DAY_PREVIEW_FRAGMENT_PATH: String = \
		"res://data/art/fragments/runner_day_kit_v1.json"
const BIOME_IDS: PackedStringArray = ["day", "dusk", "cave", "night"]
const BIOME_MILESTONE_NAMES: PackedStringArray = ["SUNLIT SHELF", "TWILIGHT PASS", "CRYSTAL CAVES", "AURORA NIGHT"]
## Runner events, results, and shared button feedback. Keep scene-scoped: race
## audio and music are not added to the runner's loading or memory budget.
const RUNNER_SFX_KEYS: PackedStringArray = [
	"sfx_checkpoint", "sfx_fish", "sfx_powerup", "sfx_go", "sfx_unlock",
	"sfx_impact", "sfx_snowball_hit", "sfx_victory", "sfx_finish",
	"sfx_ui_hover", "sfx_ui_select",
	"sfx_jump", "sfx_slide",
]

var track: RunnerTrack = null
var player: RunnerPlayer = null
var chaser: RunnerChaser = null
var hud: RunnerHUD = null
var camera: Camera3D = null
var vfx: RunnerVfx = null

var running: bool = false
var elapsed: float = 0.0
# One pending live simulation step, consumed once even when a collision emits
# death synchronously from inside player.tick(). No menus/countdowns/catch time.
var _activity_seconds: float = 0.0
var _activity_distance: float = 0.0
var _activity_clean: float = 0.0
var fish: int = 0
var hits_taken: int = 0
## Distance since the last hit, which is what the score multiplier keys off.
var clean_metres: float = 0.0
var _score: float = 0.0
var _countdown: float = COUNTDOWN_TIME
var _dead: bool = false
var _catch_elapsed: float = 0.0
var _catch_camera_captured := false
var _catch_camera_start := Transform3D.IDENTITY
var _catch_camera_start_fov := 74.0
var _pending_results: Dictionary = {}
var _camera_shake: float = 0.0
var _shake_roll: float = 0.0
var _fov_kick: float = 0.0
## The chase offset eases in the runner's forward frame. Easing world Z would
## add speed-dependent trailing distance, shrinking the intended composition.
var _camera_follow_z: float = NAN
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
var _startup_warmup: ShaderWarmup = null
## Native Compatibility can redraw a costly sky for every covered warmup item.
## Keep its lighting/cubemap and the exact mesh workload, deferring only the
## hidden screen background. Restore it before the final real-scene draw.
var _covered_warmup_environment: Environment = null
var _covered_background_mode: int = Environment.BG_SKY
var _covered_reflection_source: int = Environment.REFLECTION_SOURCE_BG
var _covered_fog_aerial_perspective: float = 0.0
## Countdown belongs to the visible run, never to asynchronous construction or
## the opaque transition. Retried runs retain this latch and their warm assets.
var _presentation_started: bool = false
## Opt-in, stage-only Android load trace. QA snapshots enable this project
## setting; ordinary exports do no logging and keep their normal workload.
var _qa_native_load_trace: bool = false
var _qa_native_load_started_msec: int = 0
var _near_snow: GPUParticles3D = null
## Low, fast, lateral snow. Falling flakes read as weather; flakes blowing
## ACROSS the corridor at deck height read as speed, which is the thing this
## mode is actually selling.
var _spindrift: GPUParticles3D = null
var _snow_mat: StandardMaterial3D = null
var _drift_mat: StandardMaterial3D = null
var _world_env: WorldEnvironment = null
var _painted_sea: RunnerPaintedSea = null
var _painted_clouds: RunnerPaintedClouds = null
var _sky_birds: SkyBirds = null
var _hit_distortion: HitDistortion = null
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
## Opaque CanvasLayer pages suspend 3D rendering, including the sky. A viewport
## lease prevents an exiting scene from restoring 3D under a newer cover.
var _world_covered: bool = false
var _world_visible_before_cover: bool = true
var _covered_viewport: Viewport = null
const COVER_RENDER_LEASE := &"waddle_opaque_3d_cover"
var _runner_settings_panel: Control = null
var _touch: RunnerTouch = null
var _layout: LayoutProfile = null
var _camera_hero_height: float = 0.0
## Foundation resources are advisory while procedural fallback is enabled.
## They give authored production assets one stable seam without making a
## schema fixture or a failed manifest capable of blanking a playable run.
var _runner_art_set: RunnerArtSet = null
## Profile resources are fixed for a run. Resolve/validate a blend target only
## when entering a biome (or replacing the art set), never every render frame.
var _environment_target_biome: int = -1
var _environment_target_art_set: RunnerArtSet = null
var _environment_target: Dictionary = {}
var _art_catalog: ArtCatalog = null
var missions: RunnerMissions = null
var _last_multiplier: int = 1
var _last_biome_band: int = 0
## Ramps hit and near misses survived, both reported to the mission system and
## shown to the player, because a runner has to reward style as well as
## survival or it is just a dodging drill.
var ramps_hit: int = 0
var near_misses: int = 0
## Sim hook: ends the run after this many seconds when > 0.
static var auto_quit_after: float = 0.0
## QA replay seed. Ordinary games keep the default random route; harnesses set
## this before entering the tree so before/after profiles cover identical art.
var generation_seed: int = -1


func _ready() -> void:
	_qa_native_load_trace = OS.has_feature("android") and (OS.is_debug_build() or bool(ProjectSettings.get_setting(
		"application/qa/native_load_trace", false)))
	_qa_native_load_started_msec = Time.get_ticks_msec()
	_qa_load_mark("ready_start")
	if generation_seed < 0:
		_rng.randomize()
	else:
		_rng.seed = generation_seed
	_refresh_layout()
	if not SettingsManager.setting_changed.is_connected(_on_runner_setting_changed):
		SettingsManager.setting_changed.connect(_on_runner_setting_changed)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_refresh_layout):
		viewport.size_changed.connect(_refresh_layout)
	await _initialize_art_foundation()
	_qa_load_mark("art_foundation_done")
	# Do this before world/camera construction: yielding after those exist but
	# before InitialVisualWarmup would submit the entire cold 3D world at once.
	await _warm_runner_audio()
	_qa_load_mark("audio_done")
	_build_environment()
	await _stage()
	_qa_load_mark("environment_drawn")

	missions = RunnerMissions.new()
	missions.load_state()
	missions.completed.connect(_on_mission_complete)
	missions.set_cleared.connect(func(star_count: int) -> void:
		if hud != null:
			hud.show_mission_complete("SET COMPLETE — %d ★" % star_count)
		AudioManager.play_sfx("sfx_unlock"))

	track = RunnerTrack.new()
	track.name = "RunnerTrack"
	# Moving seal colliders have their own process clock. Loading duration must
	# not advance hazards while the gameplay clock and countdown are frozen.
	track.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(track)
	track.setup(_rng.randi(), _runner_dressing_density(RunnerTrack.Biome.DAY))
	await _stage()
	_qa_load_mark("track_drawn")

	player = RunnerPlayer.new()
	player.name = "RunnerPlayer"
	add_child(player)
	player.setup(_player_visual_config())
	_qa_load_mark("player_setup_done")
	_camera_hero_height = RunnerCameraComposition.authored_height(player._visual)
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
	_hit_distortion = HitDistortion.new()
	_hit_distortion.name = "LifeLossDistortion"
	add_child(_hit_distortion)
	if not GameConfig.is_headless():
		_hit_distortion.setup()
	await _stage()
	_hit_distortion.finish_warmup()
	_qa_load_mark("chaser_drawn")
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
		if _sky_birds != null:
			_sky_birds.present(camera, 0.0, UITheme.reduced_motion(), true)

		hud = RunnerHUD.new()
		add_child(hud)
		hud.setup()
		hud.pause_pressed.connect(_on_hud_pause_pressed)
		hud.restart_pressed.connect(restart)
		hud.results_cover_changed.connect(_on_results_cover_changed)
		hud.menu_pressed.connect(func() -> void:
			if not SceneRouter.is_busy():
				SceneRouter.go_to(Game.SCENE_MAIN_MENU))
		if hud != null:
			hud.set_missions(missions.rows())
		if SettingsManager.touch_controls_enabled():
			_touch = RunnerTouch.new()
			_touch.name = "RunnerTouch"
			add_child(_touch)
			_touch.setup(player)
		AudioManager.play_music("music_race")
	_qa_load_mark("hud_done")

	# A Canvas loader does not prevent the first 3D frame from submitting the
	# entire cold world. Native covered loading first hides original geometry,
	# warms its resource inventory with tiny probes, then reveals the unchanged
	# real instances (including skin/MultiMesh). Web keeps its proven order.
	var deferred_background := _begin_covered_background_warmup()
	_qa_load_mark("initial_visual_start")
	var initial_warmup := InitialVisualWarmup.warm(self, deferred_background)
	# Android emulator traces show the generic 128-probe pass can occupy the
	# render thread for longer than the entire loading deadline, even with host
	# graphics. Reveal actual scene instances in bounded batches instead; this
	# still uploads the resources the opening gameplay needs, without warming
	# absent-at-start variants before the player can enter the run. Keep the
	# existing probe pass on iOS until native timings justify the same policy.
	if deferred_background and initial_warmup != null:
		if not OS.has_feature("android"):
			_startup_warmup = ShaderWarmup.warm(self, {}, RunnerTrack.SHADER_WARMUP_SCOPE,
					initial_warmup.originally_visible_ids())
			_qa_load_mark("shader_warm_start")
			if is_instance_valid(_startup_warmup):
				await _startup_warmup.tree_exited
			_qa_load_mark("shader_warm_done")
		if not _covered_warmup_can_finish():
			return
		initial_warmup.begin_reveal()
	if initial_warmup != null:
		await initial_warmup.completed
		_qa_load_mark("initial_visual_done")
		# Completion is emitted after draw. Start the next pass on a new process
		# frame so it cannot mistake that same signal for its own first draw.
		await _stage()
	if hud != null:
		# Hidden Canvas shaders are outside both 3D warmup inventories. Submit
		# the speed overlay invisibly while build_finished still holds countdown.
		await hud.warm_render_resources()
		await _stage()
		_qa_load_mark("hud_warm_done")
	# Contact patches first meet PlayerRim farther down the course. Their
	# unshaded MultiMesh still selects a distinct Compatibility light variant;
	# generic MeshInstance probes cannot prepare that exact combination.
	if not GameConfig.is_headless():
		await ShaderWarmup.warm_instanced_pair(self, VisualLibrary.contact_patch_mesh(),
				VisualLibrary.contact_shadow_material(0.22))
		await _stage()
		_qa_load_mark("instanced_warm_done")
	if not deferred_background:
		build_finished = true
		_qa_load_mark("build_finished_no_deferred_sky")
	# Native covered loading already submitted this exact inventory before
	# revealing original geometry. Avoid a duplicate serial probe pass.
	if not deferred_background:
		# Select only runner late-content probes. Shared cached materials,
		# visible nodes, feature probes and particles remain unchanged on web.
		_startup_warmup = ShaderWarmup.warm(self, {}, RunnerTrack.SHADER_WARMUP_SCOPE)
		_qa_load_mark("shader_warm_start")
	if deferred_background:
		if not _covered_warmup_can_finish():
			return
		_restore_covered_warmup_background()
		_qa_load_mark("sky_restored")
		# Leave any tree-exit/post-draw callback before submitting the restored
		# sky. Full resolution, MSAA, fog, lights and geometry remain unchanged.
		await _stage()
		await RenderingServer.frame_post_draw
		await _stage()
		if not _covered_warmup_can_finish():
			return
		build_finished = true
		_qa_load_mark("build_finished")


func _qa_load_mark(stage: String) -> void:
	if not _qa_native_load_trace:
		return
	print("[runner_load_qa] stage=%s elapsed_ms=%d frame=%d" % [
		stage, Time.get_ticks_msec() - _qa_native_load_started_msec,
		Engine.get_process_frames()])


static func use_covered_background_warmup(native_platform: bool, renderer: String) -> bool:
	return native_platform and renderer == "gl_compatibility"


func _begin_covered_background_warmup() -> bool:
	if GameConfig.is_headless() or not use_covered_background_warmup(
			OS.has_feature("android") or OS.has_feature("ios"),
			RenderingServer.get_current_rendering_method()) \
			or not SceneRouter.has_opaque_loading_cover(self) \
			or not is_instance_valid(_world_env):
		return false
	return _defer_warmup_background(_world_env.environment)


func _defer_warmup_background(env: Environment) -> bool:
	# BG_KEEP alone would disable background-derived reflections in GLES3.
	# Explicit SKY preserves the same cubemap binding while skipping _draw_sky.
	# Reject other environment sources rather than changing their semantics.
	if _covered_warmup_environment != null or env == null or env.sky == null \
			or env.background_mode != Environment.BG_SKY \
			or env.ambient_light_source != Environment.AMBIENT_SOURCE_SKY \
			or env.reflected_light_source not in [Environment.REFLECTION_SOURCE_BG,
				Environment.REFLECTION_SOURCE_SKY]:
		return false
	_covered_warmup_environment = env
	_covered_background_mode = env.background_mode
	_covered_reflection_source = env.reflected_light_source
	# Godot clears this when BG_SKY becomes BG_KEEP. Preserve it explicitly;
	# otherwise every native warmup silently changes the final scene's fog.
	_covered_fog_aerial_perspective = env.fog_aerial_perspective
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.background_mode = Environment.BG_KEEP
	env.fog_aerial_perspective = _covered_fog_aerial_perspective
	return true


func _restore_covered_warmup_background() -> void:
	if _covered_warmup_environment == null:
		return
	_covered_warmup_environment.background_mode = _covered_background_mode
	_covered_warmup_environment.reflected_light_source = _covered_reflection_source
	_covered_warmup_environment.fog_aerial_perspective = _covered_fog_aerial_perspective
	_covered_warmup_environment = null


func _covered_warmup_can_finish() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() \
			and SceneRouter.has_opaque_loading_cover(self)


## Yields a frame so the loading overlay can draw. Headless has no overlay and
## no renderer, so it builds straight through.
func _stage() -> void:
	if GameConfig.is_headless():
		return
	var tree := get_tree()
	if tree != null:
		await tree.process_frame


func _warm_runner_audio() -> void:
	# Resource loading and any non-looping copy belong behind the loader, not
	# the first mission/pickup/death. Playback/backend work is not warmed here.
	# Logic simulations keep their no-extra-sound-IO startup contract. Retry
	# reuses the scene and AudioManager cache; it never enters this loader.
	if GameConfig.is_headless():
		return
	for key: String in RUNNER_SFX_KEYS:
		AudioManager.preload_sfx(key)
		await _stage()


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
	if not bool(ProjectSettings.get_setting("application/qa/release_runner_art_only", false)) \
			and ArtCatalog.preview_overlay_allowed(OS.is_debug_build(), OS.has_feature("editor")):
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
	player.jumped.connect(_on_player_jumped)
	player.slid.connect(_on_player_slid)
	player.lane_changed.connect(func() -> void: missions.note_lane_change())
	player.presentation_event.connect(_on_presentation_event)


func _on_player_jumped() -> void:
	missions.note_jump()
	if running:
		AudioManager.play_sfx("sfx_jump", 1.0, -1.0)


func _on_player_slid() -> void:
	missions.note_slide()
	if running:
		AudioManager.play_sfx("sfx_slide", 1.0, -2.0)


func _player_visual_config() -> Dictionary:
	# The runner wears whatever the player has equipped in the racing game:
	# one penguin, one wardrobe, both modes.
	var equipped := Progression.equipped()
	var body_info := CosmeticsDB.get_item(String(equipped.get("body", "body_classic")))
	var config := {
		"species": body_info.get("species", "emperor"),
		"body_color": body_info.get("body_color", Color(0.13, 0.16, 0.22)),
		"belly_color": body_info.get("belly_color", Color(0.95, 0.94, 0.9)),
		"hat": equipped.get("hat", ""),
		"scarf": equipped.get("scarf", ""),
		"goggles": equipped.get("goggles", ""),
		"trail": equipped.get("trail", ""),
	}
	if body_info.has("crest_color"):
		config["crest_color"] = body_info["crest_color"]
	return config


func _process(delta: float) -> void:
	# The catch and the results fade still own their complete presentation.
	# Once the opaque result has landed, no hidden terminal animation is needed.
	if _dead and _world_covered:
		return
	if not _presentation_started:
		if not build_finished or is_instance_valid(_startup_warmup) \
				or SceneRouter.is_presenting():
			return
		_presentation_started = true
		track.process_mode = Node.PROCESS_MODE_INHERIT
		_emit_lifecycle("runner_countdown_ready", {"retry": false})
		# The preceding rendered frame can include a cold shader/upload stall.
		# Do not charge that interval against the first visible countdown frame.
		return
	_presentation_time += delta
	if _dead:
		if player != null:
			player.tick(delta, player.speed)
		_update_follow_fx(0.0)
		if vfx != null:
			vfx.tick(delta)
		if not UITheme.reduced_motion():
			_settle_camera(delta)
		_advance_catch(delta)
		return
	if not running:
		_countdown -= delta
		_intro_t = clampf(_countdown / COUNTDOWN_TIME, 0.0, 1.0)
		if hud != null:
			var count := int(ceil(_countdown / COUNTDOWN_TIME * 3.0))
			hud.show_message("GO!" if count <= 0 else str(count))
		if chaser != null:
			chaser.set_intro_preview(1.0, player.distance, delta)
		if _countdown <= 0.0:
			_enter_running(false)
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
	_begin_activity_tick(delta)
	player.tick(delta, speed)
	_commit_activity_tick()
	# A collision can emit died synchronously inside tick(). The saved result
	# is already final then; do not add another score/mission tick behind it.
	if _dead:
		return
	_advance_hit_distortion(delta)
	var gained := player.distance - before
	clean_metres += gained
	var multiplier := RunnerConfig.multiplier_for(clean_metres)
	if player.has_powerup(RunnerConfig.POWERUP_DOUBLE):
		multiplier *= 2
	_score += gained * RunnerConfig.POINTS_PER_METRE * float(multiplier)
	missions.note_distance(player.distance)
	_update_biome_milestone(player.distance)

	# Difficulty is distance-driven rather than time-driven: a player who dies
	# early and restarts should always see the same gentle opening, however
	# long they have had the mode open.
	track.update_stream(player.position.z, clampf(player.distance / 7000.0, 0.0, 1.0))
	chaser.tick(delta, player.distance, float(hits_taken))
	_place_camera(delta, false)
	chaser.set_intro_preview(chaser.chase_preview_strength(elapsed), player.distance, delta)
	_blend_biome(delta)
	_update_runner_presentation(delta)

	if hud != null:
		hud.set_stats(player.distance, fish, int(_score), multiplier,
			player.hits_left, chaser.gap)
		hud.set_powerups(player.powerups)
		hud.set_missions(missions.rows())
		hud.set_speed_ratio(clampf((player.speed - RunnerConfig.START_SPEED)
			/ maxf(RunnerConfig.MAX_SPEED - RunnerConfig.START_SPEED, 0.001), 0.0, 1.0))
		hud.set_combo(multiplier, multiplier > _last_multiplier)
		if multiplier > _last_multiplier:
			hud.add_floater("x%d" % multiplier, &"score")
			AudioManager.play_sfx("sfx_checkpoint")
	_last_multiplier = multiplier

	if auto_quit_after > 0.0 and elapsed >= auto_quit_after:
		_on_death()


func _begin_activity_tick(delta: float) -> void:
	_activity_seconds = 0.0
	if not running or _dead or player == null or not _presentation_started \
			or (is_inside_tree() and get_tree().paused):
		return
	_activity_seconds = clampf(delta, 0.0, 0.25)
	_activity_distance = player.distance
	_activity_clean = clean_metres


func _commit_activity_tick() -> void:
	if _activity_seconds <= 0.0 or player == null:
		return
	var seconds := _activity_seconds
	_activity_seconds = 0.0
	var gained := maxf(0.0, player.distance - _activity_distance)
	Progression.record_runner_activity(seconds, gained, player.distance, _activity_clean + gained)


func _enter_running(retry: bool) -> void:
	running = true
	Telemetry.run_started()
	if not retry:
		missions.begin_run()
	player.set_input_enabled(true)
	if hud != null:
		hud.set_missions(missions.rows())
		hud.set_pause_available(true)
		hud.show_message("GO!")
	_emit_lifecycle("runner_running", {
		"retry": retry,
		"max_fps": Engine.max_fps,
		"msaa_3d": get_viewport().msaa_3d,
		"scale_3d": get_viewport().scaling_3d_scale,
		"quality": String(SettingsManager.get_setting("display", "quality_preset")),
		"viewport_width": get_viewport().get_visible_rect().size.x,
		"viewport_height": get_viewport().get_visible_rect().size.y,
	})


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
## speed, preserving the reference horizon as the run accelerates.
func _place_camera(delta: float, snap: bool) -> void:
	if camera == null or player == null:
		return
	if _camera_hero_height > 0.0:
		_place_authored_camera(delta, snap)
		return
	var portrait := _layout != null and _layout.is_portrait()
	var speed_ratio := clampf((player.speed - RunnerConfig.START_SPEED)
		/ maxf(RunnerConfig.MAX_SPEED - RunnerConfig.START_SPEED, 0.001), 0.0, 1.0)
	var speed_fov := RunnerCameraComposition.reference_fov(speed_ratio)
	# Reference framing uses the neutral Emperor silhouette. Species retain
	# their real relative sizes. A longer lens and farther optical centre give
	# the lower rear view without lowering the camera into tunnel geometry.
	var fit := RunnerCameraComposition.reference_fit(1.2, speed_fov, portrait)
	var chase_distance := fit.x
	var chase_height := fit.y
	var look_ahead := _layout.runner_look_ahead if _layout != null else 11.0
	var lift := 0.32 if player.position.y < 1.6 else 0.72
	var intro := smoothstep(0.0, 1.0, _intro_t)
	_land_dip = move_toward(_land_dip, 0.0, delta * 2.8)
	var target := Vector3(player.position.x * 0.55, chase_height + player.position.y * lift,
		player.position.z + chase_distance)
	# Countdown starts on a wider establishing view, then settles behind the
	# penguin by GO. A landing punch moves only the camera, never the player.
	target += Vector3(0.0, intro * chase_height * 0.75 - _land_dip,
			intro * chase_distance * 0.42)
	_ease_camera_target(target, delta, snap)
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
	# Keep the reference horizon steady while partial height tracking lets a
	# jump rise above its ground shadow. Only yaw follows the lane decision.
	camera.position.y = maxf(camera.position.y, 2.95)
	var aim_distance := camera.position.z - player.position.z + look_ahead
	var look := Vector3(player.position.x * 0.5,
		camera.position.y - tan(deg_to_rad(fit.z)) * aim_distance,
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


func _place_authored_camera(delta: float, snap: bool) -> void:
	var size := get_viewport().get_visible_rect().size
	var portrait := size.y >= size.x
	var speed_ratio := clampf((player.speed - RunnerConfig.START_SPEED)
		/ maxf(RunnerConfig.MAX_SPEED - RunnerConfig.START_SPEED, 0.001), 0.0, 1.0)
	var speed_fov := RunnerCameraComposition.reference_fov(speed_ratio)
	var fit := RunnerCameraComposition.reference_fit(_camera_hero_height, speed_fov, portrait)
	var pitch := fit.z
	var lift := 0.32 if player.position.y < 1.6 else 0.72
	var intro := smoothstep(0.0, 1.0, _intro_t)
	_land_dip = move_toward(_land_dip, 0.0, delta * 2.8)
	var target := Vector3(player.position.x * 0.75,
		maxf(fit.y - _land_dip, 2.95) + player.position.y * lift + intro * fit.y * 0.75,
		player.position.z + fit.x + intro * fit.x * 0.42)
	_ease_camera_target(target, delta, snap)
	if _camera_shake > 0.0:
		_camera_shake = maxf(0.0, _camera_shake - delta * 2.4)
		var phase := _presentation_time * 47.0
		camera.position += Vector3(sin(phase), sin(phase * 1.37 + 1.1), 0.0) \
			* _camera_shake * 0.42
		_shake_roll = sin(phase * 0.73) * _camera_shake * 0.035
	else:
		_shake_roll = move_toward(_shake_roll, 0.0, delta * 0.18)
	# Contact impulses never push the authored camera below its tunnel-safe
	# floor, including the smaller species whose neutral shot already uses it.
	camera.position.y = maxf(camera.position.y, 2.95)
	camera.rotation = Vector3(deg_to_rad(-pitch), 0.0,
		player.rotation.z * 0.34 + _shake_roll)
	_fov_kick = maxf(0.0, _fov_kick - delta * 14.0)
	camera.fov = speed_fov + _fov_kick + intro * (3.0 if UITheme.reduced_motion() else 8.0)


func _ease_camera_target(target: Vector3, delta: float, snap: bool) -> void:
	if snap or is_nan(_camera_follow_z):
		camera.position = target
	else:
		# Transport only forward travel immediately; lane, jump height, intro
		# dolly and changes to the chase distance retain their existing easing.
		camera.position.z += player.position.z - _camera_follow_z
		camera.position = camera.position.lerp(target, clampf(delta * 9.0, 0.0, 1.0))
	_camera_follow_z = player.position.z


## After death, ease toward the reference catch composition. This camera
## owns presentation only; the dead player and its collision body stay frozen.
func _settle_camera(delta: float) -> void:
	if camera == null or player == null:
		return
	if UITheme.reduced_motion():
		return
	if not _catch_camera_captured:
		_catch_camera_start = camera.transform
		_catch_camera_start_fov = camera.fov
		_catch_camera_captured = true
	var portrait := get_viewport().get_visible_rect().size.y >= get_viewport().get_visible_rect().size.x
	var height := _camera_hero_height if _camera_hero_height > 0.0 else 1.2
	var lens := 58.0
	# Fit the prone body above the powder/gauge. Portrait preserves more course
	# above its rear-facing slide; desktop presents the face-first tumble.
	var fit := RunnerCameraComposition.solve(height, lens,
		0.13 if portrait else 0.19, 0.73 if portrait else 0.71, 5.0)
	var target := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-5.0), 0.0, 0.0)),
		Vector3(player.position.x, player.position.y + fit.y, player.position.z + fit.x))
	var blend := smoothstep(0.10, 1.05, _catch_elapsed + minf(delta, 0.05))
	camera.transform = _catch_camera_start.interpolate_with(target, blend)
	camera.fov = lerpf(_catch_camera_start_fov, lens, blend)


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
	if running and not _dead:
		Progression.record_runner_event("runner_fish_collected", value)
	missions.note_fish(value)
	if hud != null:
		hud.add_floater("+%d" % worth, &"fish")
	AudioManager.play_sfx("sfx_fish")


func _on_powerup_gained(id: StringName) -> void:
	if running and not _dead:
		Progression.record_runner_event("runner_powerups_collected")
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
	if running and not _dead:
		Progression.record_runner_event("runner_near_misses")
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


func _update_biome_milestone(distance: float) -> void:
	var band := int(floor(distance / RunnerTrack.BIOME_LENGTH))
	if band <= _last_biome_band:
		return
	_last_biome_band = band
	# Cycling biomes remain part of an endless run. First arrival at each of
	# the four destinations is a permanent milestone, never a paid shortcut.
	var index := band % BIOME_MILESTONE_NAMES.size()
	if hud != null:
		hud.show_message("NEW DESTINATION · %s" % BIOME_MILESTONE_NAMES[index])
		hud.add_floater("DISCOVERED!", &"mission")
	if band < BIOME_MILESTONE_NAMES.size() and band > int(SaveManager.get_value("runner_biome_milestone", 0)):
		SaveManager.set_value("runner_biome_milestone", band)
		Progression.add_xp(75)
		AudioManager.play_sfx("sfx_unlock")


func _on_hit_taken(hits_left: int) -> void:
	_commit_activity_tick()
	hits_taken += 1
	if _hit_distortion != null:
		_hit_distortion.lost_life(hits_left)
	clean_metres = 0.0
	missions.note_hit()
	AudioManager.play_sfx("sfx_impact")
	if hud != null:
		hud.flash_hit()
		if hits_left > 0:
			hud.show_message("%d left" % hits_left)


func _on_death() -> void:
	if _dead:
		return
	_commit_activity_tick()
	_dead = true
	running = false
	if _hit_distortion != null:
		_hit_distortion.reset()
	_catch_elapsed = 0.0
	_catch_camera_captured = false
	_emit_lifecycle("runner_death")
	if player != null:
		# Natural third-hit deaths already entered DEAD. Forced/sim endings use
		# the same frozen player state rather than accumulating distance here.
		if player.state != RunnerPlayer.State.DEAD:
			player.kill()
		player.set_input_enabled(false)
	if chaser != null:
		chaser.overrun(UITheme.reduced_motion())
	if hud != null:
		hud.set_pause_available(false)
		# The reference headline is owned by the catch canvas for its full clock.
		hud.show_message("")
		hud.set_powerups({})
		hud.set_speed_ratio(0.0)
		if player != null and chaser != null:
			hud.set_stats(player.distance, fish, int(_score), _last_multiplier,
				player.hits_left, chaser.gap)
	if UITheme.reduced_motion():
		_camera_shake = 0.0
		_shake_roll = 0.0
		_fov_kick = 0.0
	AudioManager.play_sfx("sfx_snowball_hit")
	var score := int(_score)
	Telemetry.run_ended(player.distance if player != null else 0.0, score, fish)
	# Bank the whole result in one synchronous save below. Mission completion
	# can award currency and stage the next board; saving here used to write an
	# incomplete result and force another autosave after score/fish were added.
	missions.note_run_ended(player.distance if player != null else 0.0, fish, score, false)
	if hud != null:
		hud.set_missions(missions.rows())
	var previous := Progression.runner_high_score()
	var is_best := Progression.submit_runner_score(score, player.distance if player != null else 0.0)
	Progression.evaluate_runner_achievements()
	if fish > 0:
		Progression.add_fish(fish)
	_pending_results = {
		"distance": player.distance if player != null else 0.0,
		"fish": fish,
		"score": score,
		"best": previous,
		"is_new_best": is_best,
		"missions": missions.completed_this_run(),
		"mission_rows": missions.rows().duplicate(true),
	}
	SaveManager.save_now()
	LeaderboardClient.submit_completed_run("runner", "runner", score)


func _advance_catch(delta: float) -> void:
	if not _dead or _pending_results.is_empty():
		return
	# A stalled frame must not skip the entire visible catch. This clock owns
	# only the animation; distance, awards and the saved result stay frozen.
	_catch_elapsed = minf(CATCH_TIME, _catch_elapsed + minf(delta, 0.05))
	if _catch_elapsed >= 0.15 and player != null and player._visual != null:
		# Presentation only: retain DEAD/input-off, frozen distance and collision
		# authority while the existing belly-slide pose falls into the powder.
		player._visual.set_pose(PenguinVisual.Pose.SLIDE)
		if not UITheme.reduced_motion():
			# Turn only the visual facade: root yaw, hitbox, distance and lane
			# authority remain untouched. One bounded tip resolves into the pose.
			var viewport_size := get_viewport().get_visible_rect().size
			var portrait := viewport_size.y >= viewport_size.x
			var turn := smoothstep(0.18, 0.72, _catch_elapsed)
			var tip := sin(PI * smoothstep(0.15, 1.10, _catch_elapsed))
			player._visual.rotation = Vector3(0.0, 0.0 if portrait else PI * turn, -0.16 * tip)
			if not portrait:
				player._visual.present_catch_face(smoothstep(0.30, 0.85, _catch_elapsed), camera)
	if chaser != null:
		chaser.present_overrun(_catch_elapsed / CATCH_TIME)
		if hud != null and player != null:
			hud.set_stats(player.distance, fish, int(_score), _last_multiplier,
				player.hits_left, chaser.gap)
	if _catch_elapsed < CATCH_TIME:
		return
	var summary := _pending_results
	_pending_results = {}
	if hud != null:
		hud.show_game_over(summary)
	_emit_lifecycle("runner_results_ready")


## Restarts in place — no scene reload, so a retry is instant even on the web
## build where a fresh scene would pay the whole build and shader cost again.
func restart() -> void:
	# The game-over panel processes ALWAYS. A queued/focused activation must
	# not reset the covered world or consume a seed during scene navigation.
	if SceneRouter.is_busy():
		return
	_set_world_covered(false)
	_emit_lifecycle("runner_retry_started")
	if hud != null:
		hud.set_pause_available(false)
		hud.hide_game_over()
	_dead = false
	_catch_elapsed = 0.0
	_catch_camera_captured = false
	_pending_results.clear()
	running = false
	elapsed = 0.0
	_activity_seconds = 0.0
	_activity_distance = 0.0
	_activity_clean = 0.0
	fish = 0
	hits_taken = 0
	clean_metres = 0.0
	_score = 0.0
	_countdown = 0.0
	_camera_shake = 0.0
	_shake_roll = 0.0
	_fov_kick = 0.0
	_intro_t = 0.0
	_land_dip = 0.0
	_ramp_airborne = false
	_last_multiplier = 1
	_last_biome_band = 0
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
	_camera_hero_height = RunnerCameraComposition.authored_height(player._visual)
	player.set_input_enabled(false)
	_connect_player()
	if vfx != null:
		vfx.clear()
	if _touch != null and is_instance_valid(_touch):
		_touch.setup(player)
	chaser.reset()
	if _hit_distortion != null:
		_hit_distortion.reset()
	if _sky_birds != null:
		_sky_birds.reset()
	if _painted_sea != null:
		_painted_sea.follow_z(0.0)
		_painted_sea.blend_environment(_runner_environment(RunnerTrack.Biome.DAY), 1.0)
	if _painted_clouds != null:
		_painted_clouds.follow_z(0.0)
		_painted_clouds.blend_environment(_runner_environment(RunnerTrack.Biome.DAY), 1.0)
	# The results panel covered these readouts, so the live HUD still contains
	# the completed run until gameplay feeds it again. Reset
	# it in this same retry callback: the first live frame must never show stale score,
	# fish, lives, avalanche pressure or power-ups from the previous run.
	if hud != null:
		hud.set_stats(0.0, 0, 0, 1, player.hits_left, chaser.gap)
		hud.set_powerups(player.powerups)
		hud.set_speed_ratio(0.0)
	_place_camera(0.0, true)
	# Retry stays in the warm scene. Do not add a second first-run countdown:
	# input and gameplay authority become live before this callback returns.
	_enter_running(true)


func _emit_lifecycle(event_name: String, fields: Dictionary = {}) -> void:
	BootProfiler.lifecycle_event(event_name, fields)


## Presentation consumes the player's already-resolved state. It never feeds
## positions, timings or random values back into the runner simulation.
func _advance_hit_distortion(delta: float) -> void:
	if _hit_distortion != null:
		_hit_distortion.advance(delta, running and not _dead and _presentation_started \
			and not _world_covered and not get_tree().paused, UITheme.reduced_motion(),
			String(SettingsManager.get_setting("accessibility", "camera_shake")))


func _update_runner_presentation(delta: float) -> void:
	if player == null:
		return
	if _sky_birds != null and camera != null:
		_sky_birds.present(camera, delta, UITheme.reduced_motion(),
			track.biome_at_z(player.position.z) == RunnerTrack.Biome.DAY
			or track.biome_at_z(player.position.z) == RunnerTrack.Biome.DUSK)
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
	if _painted_sea != null:
		_painted_sea.follow_z(player.position.z)
	if _painted_clouds != null:
		_painted_clouds.follow_z(player.position.z)
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
	env.ambient_light_color = day["ambient_color"]
	env.ambient_light_sky_contribution = float(day["sky_contribution"])
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
	_painted_sea = RunnerPaintedSea.new()
	_painted_sea.name = "PaintedSea"
	add_child(_painted_sea)
	_painted_sea.setup(day)
	_painted_clouds = RunnerPaintedClouds.new()
	_painted_clouds.name = "PaintedClouds"
	add_child(_painted_clouds)
	_painted_clouds.setup(day)
	_sky_birds = SkyBirds.new()
	_sky_birds.name = "SkyBirds"
	add_child(_sky_birds)
	_sky_birds.setup()

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
	fill.light_color = day["fill"]
	fill.light_energy = float(day["fill_energy"])
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-54.0, -28.0, 0.0)
	add_child(fill)
	_fill = fill

	var rim := OmniLight3D.new()
	rim.name = "PlayerRim"
	var day_shaft: Color = day.get("shaft", Color(1.0, 0.97, 0.86))
	rim.light_color = day["rim"]
	# The player is a dorsal surface seen from behind: every feature the
	# penguin has faces away from this camera forever, so it reads as a hole in
	# the image unless something draws its edge. This is that something.
	rim.light_energy = float(day["rim_energy"])
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
	var values := RunnerTrack.biome_environment(biome)
	if _runner_art_set != null and biome >= 0 and biome < BIOME_IDS.size():
		var profile := _runner_art_set.profile_for_biome(BIOME_IDS[biome])
		if profile != null and profile.validation_errors().is_empty():
			values.merge(profile.environment_values(), true)
	# The sky is the backdrop, not a visibility budget. At sky contribution 1,
	# Godot ignores ambient color/energy; reducing those energies as the sky
	# darkened therefore left the lane lit almost entirely by a weak blue sun.
	# Blend DAY's azure sky with the reference's white bounce, then introduce
	# cool bounce for later bands. Existing lights/uniforms, no extra passes.
	var horizon: Color = values["sky_horizon"]
	var shaft: Color = values["shaft"]
	var ambient := float(values["ambient"])
	values.merge({
		"ambient_color": Color.WHITE,
		"sky_contribution": 1.0,
		"fill": horizon.lerp(Color.WHITE, 0.10),
		"fill_energy": ambient * 0.72,
		"rim": shaft.lerp(Color.WHITE, 0.12),
		"rim_energy": clampf(0.72 + (0.38 - ambient) * 1.35, 0.68, 0.98),
	})
	match biome:
		RunnerTrack.Biome.DAY:
			values.merge({"ambient_color": Color(0.90, 0.96, 1.0),
				"sky_contribution": 0.55, "fill": Color(0.84, 0.94, 1.0),
				"fill_energy": 0.40, "rim_energy": 0.95,
				"water_tint": Color(0.008, 0.44, 0.75), "water_haze": Vector2(110.0, 600.0),
				"water_crest_tint": Vector3(0.08, 0.75, 1.0), "water_detail_weight": 1.0}, true)
		RunnerTrack.Biome.DUSK:
			values.merge({"ambient": maxf(ambient, 0.50),
				"ambient_color": Color(0.78, 0.84, 1.0), "sky_contribution": 0.32,
				"fill": Color(0.82, 0.87, 1.0), "fill_energy": 0.40,
				"rim": Color(0.82, 0.90, 1.0), "rim_energy": 1.15}, true)
		RunnerTrack.Biome.CAVE:
			values.merge({"ambient": maxf(ambient, 0.56),
				"ambient_color": Color(0.56, 0.82, 1.0), "sky_contribution": 0.16,
				"fill": Color(0.65, 0.86, 1.0), "fill_energy": 0.48,
				"rim": Color(0.72, 0.91, 1.0), "rim_energy": 1.25}, true)
		RunnerTrack.Biome.NIGHT:
			values.merge({"ambient": maxf(ambient, 0.56),
				"ambient_color": Color(0.64, 0.75, 1.0), "sky_contribution": 0.12,
				"fill": Color(0.72, 0.80, 1.0), "fill_energy": 0.50,
				"rim": Color(0.78, 0.87, 1.0), "rim_energy": 1.35}, true)
	return values


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


func _on_runner_setting_changed(key: String, _value: Variant) -> void:
	if key == "display/quality_preset" and track != null:
		# Runner profiles currently choose density at setup from DAY. Keep that
		# same contract while making an in-run governor change effective now.
		track.set_dressing_density(_runner_dressing_density(RunnerTrack.Biome.DAY))


func _environment_blend_target(biome: int) -> Dictionary:
	if biome != _environment_target_biome or _runner_art_set != _environment_target_art_set:
		_environment_target = _runner_environment(biome)
		_environment_target_biome = biome
		_environment_target_art_set = _runner_art_set
	return _environment_target


func _blend_biome(delta: float) -> void:
	if _world_env == null or track == null or player == null:
		return
	var want := _environment_blend_target(track.biome_at_z(player.position.z))
	if want.is_empty():
		return
	var env := _world_env.environment
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	var k := clampf(delta * 0.9, 0.0, 1.0)
	if _painted_sea != null:
		_painted_sea.blend_environment(want, k)
	if _painted_clouds != null:
		_painted_clouds.blend_environment(want, k)
	if sky_mat != null:
		# Compatibility dirties sky radiance even for identical uniform writes.
		# Preserve the exact blend, but stop resubmitting unchanged colors.
		var sky_top := sky_mat.sky_top_color.lerp(
			want.get("sky_top", sky_mat.sky_top_color), k)
		if sky_top != sky_mat.sky_top_color:
			sky_mat.sky_top_color = sky_top
		var sky_horizon := sky_mat.sky_horizon_color.lerp(
			want.get("sky_horizon", sky_mat.sky_horizon_color), k)
		if sky_horizon != sky_mat.sky_horizon_color:
			sky_mat.sky_horizon_color = sky_horizon
		var ground_horizon := sky_mat.ground_horizon_color.lerp(
			want.get("ground_horizon", sky_mat.ground_horizon_color), k)
		if ground_horizon != sky_mat.ground_horizon_color:
			sky_mat.ground_horizon_color = ground_horizon
		var ground_bottom := sky_mat.ground_bottom_color.lerp(
			want.get("ground_bottom", sky_mat.ground_bottom_color), k)
		if ground_bottom != sky_mat.ground_bottom_color:
			sky_mat.ground_bottom_color = ground_bottom
	env.fog_light_color = env.fog_light_color.lerp(want.get("fog", env.fog_light_color), k)
	env.fog_density = lerpf(env.fog_density,
			float(want.get("fog_density", env.fog_density)), k)
	env.ambient_light_energy = lerpf(env.ambient_light_energy,
		float(want.get("ambient", env.ambient_light_energy)), k)
	env.ambient_light_color = env.ambient_light_color.lerp(want["ambient_color"], k)
	env.ambient_light_sky_contribution = lerpf(env.ambient_light_sky_contribution,
			float(want["sky_contribution"]), k)
	if _sun != null:
		_sun.light_color = _sun.light_color.lerp(want.get("sun", _sun.light_color), k)
		_sun.light_energy = lerpf(_sun.light_energy,
			float(want.get("sun_energy", _sun.light_energy)), k)
	var horizon: Color = want.get("sky_horizon", Color(0.4, 0.72, 0.94))
	if _fill != null:
		_fill.light_color = _fill.light_color.lerp(want["fill"], k)
		_fill.light_energy = lerpf(_fill.light_energy, float(want["fill_energy"]), k)
	var shaft: Color = want.get("shaft", Color.WHITE)
	if _shaft_mat != null:
		var current_shaft := _shaft_mat.albedo_color
		var shaft_target := Color(shaft.r, shaft.g, shaft.b, current_shaft.a)
		_shaft_mat.albedo_color = current_shaft.lerp(shaft_target, k)
	if _rim != null:
		_rim.light_color = _rim.light_color.lerp(want["rim"], k)
		_rim.light_energy = lerpf(_rim.light_energy, float(want["rim_energy"]), k)
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
	if tree == null or SceneRouter.is_busy() or _dead \
			or _runner_settings_panel != null:
		return
	if tree.paused:
		_close_pause()
		return
	if not build_finished or not _presentation_started:
		return
	if _touch != null and is_instance_valid(_touch):
		_touch.cancel_gesture()
	tree.paused = true
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 90
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var scrim := ColorRect.new()
	scrim.color = Color(0.64, 0.80, 0.94, 0.58)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(scrim)
	var profile := LayoutProfile.for_viewport(get_viewport())
	var portrait := profile.is_portrait()
	var background := TextureRect.new()
	background.name = "PauseIllustration"
	background.texture = load("res://assets/art/ui/menu/runner_pause_background_v2.webp" if portrait else "res://assets/art/ui/menu/runner_pause_landscape_background_v2.webp")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	TouchScroll.attach(scroll)
	scrim.add_child(scroll)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override("margin_top", roundi(profile.viewport_size.y * 0.42) if portrait else 24)
	inset.add_theme_constant_override("margin_bottom", roundi(profile.viewport_size.y * 0.035) if portrait else 24)
	inset.add_theme_constant_override("margin_left", 24 if portrait else roundi(profile.viewport_size.x * 0.54))
	inset.add_theme_constant_override("margin_right", 24 if portrait else roundi(profile.viewport_size.x * 0.10))
	scroll.add_child(inset)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inset.add_child(center)
	var card := PanelContainer.new()
	card.name = "PauseCard"
	var card_width := minf(profile.viewport_size.x * 0.74, profile.safe_rect.size.x) if portrait \
		else profile.safe_rect.size.x * 0.345
	var unit := card_width / 700.0
	card.custom_minimum_size = Vector2(card_width, profile.viewport_size.y * 0.535 if portrait else profile.safe_rect.size.y * 0.82)
	card.add_theme_stylebox_override("panel", preload("res://scripts/ui/runner_end_art.gd").pause_card(unit))
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", roundi(12.0 * unit))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)
	var title := TextureRect.new()
	title.name = "PausedWordmark"
	title.accessibility_name = "Paused"
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.texture = RunnerHUDArt.paused_wordmark()
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.custom_minimum_size = Vector2((450.0 if portrait else 500.0) * unit, 116.0 * unit)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var resume := ExpeditionMenuStyle.button("RESUME", true, roundi(72 * unit), 150 * unit)
	resume.pressed.connect(_close_pause)
	box.add_child(resume)
	var retry := ExpeditionMenuStyle.button("RESTART RUN", false, roundi(51 * unit), 142 * unit)
	retry.pressed.connect(func() -> void:
		_close_pause()
		restart())
	box.add_child(retry)
	var settings := ExpeditionMenuStyle.button("SETTINGS", false, roundi(51 * unit), 142 * unit)
	settings.pressed.connect(_open_runner_settings)
	box.add_child(settings)
	var quit := ExpeditionMenuStyle.button("BASE CAMP", false, roundi(51 * unit), 142 * unit)
	quit.pressed.connect(func() -> void:
		if SceneRouter.is_busy():
			return
		get_tree().paused = false
		SceneRouter.go_to(Game.SCENE_MAIN_MENU))
	box.add_child(quit)
	for entry: Array in [[resume, "play", 72, 150, true], [retry, "retry", 51, 142, false], [settings, "settings", 51, 142, false], [quit, "camp", 51, 142, false]]:
		var button := entry[0] as Button
		var focus := StyleBoxFlat.new()
		focus.draw_center = false
		focus.border_color = Color("b5cbdc")
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(roundi(float(entry[3]) * unit * 0.5))
		button.add_theme_stylebox_override("focus", focus)
		preload("res://scripts/ui/utility_reference_art.gd").centered_button(button, button.text,
			preload("res://scripts/ui/runner_end_art.gd").pause_icon(String(entry[1])), roundi(float(entry[2]) * unit),
			float(entry[3]) * unit, bool(entry[4]))
		var picture := button.get_node("IllustratedAction").get_child(0) as TextureRect
		picture.custom_minimum_size = Vector2.ONE * 76.0 * unit
	var footer := HBoxContainer.new()
	footer.name = "PauseFeedbackFooter"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", roundi(18.0 * unit))
	box.add_child(footer)
	for index in 3:
		if index != 1:
			var line := ColorRect.new()
			line.color = Color("cbbda8")
			line.custom_minimum_size = Vector2(78.0 * unit, 2.0 * unit)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			footer.add_child(line)
			continue
		var feedback := ExpeditionMenuStyle.button("FEEDBACK", false, roundi(33 * unit), 50.0 * unit)
		feedback.name = "PauseFeedback"
		feedback.custom_minimum_size.x = 250.0 * unit
		feedback.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		for state: String in ["normal", "hover", "pressed"]:
			feedback.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var envelope := UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="48" viewBox="0 0 64 48"><rect x="5" y="6" width="54" height="36" rx="2" fill="none" stroke="#112b50" stroke-width="5"/><path d="m6 8 26 21L58 8M6 40l19-16m33 16L39 24" fill="none" stroke="#112b50" stroke-width="4"/></svg>')
		preload("res://scripts/ui/utility_reference_art.gd").centered_button(feedback, "FEEDBACK", envelope, roundi(33 * unit), 50.0 * unit)
		var feedback_art := feedback.get_node("IllustratedAction") as HBoxContainer
		(feedback_art.get_child(0) as TextureRect).custom_minimum_size = Vector2(45.0, 34.0) * unit
		feedback.pressed.connect(func() -> void:
			preload("res://scripts/ui/feedback_form.gd").new().open(_pause_layer))
		footer.add_child(feedback)
	add_child(_pause_layer)
	# The full-rect illustration is opaque; CanvasLayer controls remain visible
	# when their Node3D ancestor is hidden. Missing art must keep the world drawn.
	if background.texture != null:
		_set_world_covered(true)
	resume.grab_focus()


func _open_runner_settings() -> void:
	if _pause_layer == null or _runner_settings_panel != null:
		return
	var packed := load(Game.SCENE_SETTINGS) as PackedScene
	if packed == null:
		return
	var screen := packed.instantiate() as Control
	if screen == null:
		return
	(_pause_layer.get_child(0) as Control).hide()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.set("on_back", Callable(self, "_close_runner_settings"))
	_runner_settings_panel = screen
	_pause_layer.add_child(screen)


func _close_runner_settings() -> void:
	if _runner_settings_panel != null:
		_runner_settings_panel.queue_free()
		_runner_settings_panel = null
	if _pause_layer != null and is_instance_valid(_pause_layer):
		(_pause_layer.get_child(0) as Control).show()


func _on_hud_pause_pressed() -> void:
	# The on-screen control is a pause entrypoint, never a hidden resume toggle
	# or an action over loading/countdown/results. Keyboard pause is unchanged.
	var tree := get_tree()
	if tree == null or tree.paused or not running or _dead \
			or not build_finished or not _presentation_started \
			or is_instance_valid(_startup_warmup) or SceneRouter.is_busy():
		return
	_toggle_pause()


func _close_pause() -> void:
	# Recovery owns the global pause until its replacement scene is ready to
	# swap. A still-alive old pause button cannot resume gameplay underneath.
	if SceneRouter.is_busy():
		return
	_set_world_covered(false)
	get_tree().paused = false
	_runner_settings_panel = null
	if _pause_layer != null and is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
	_pause_layer = null


func _on_results_cover_changed(covered: bool) -> void:
	_set_world_covered((covered and _dead) or is_instance_valid(_pause_layer))


func _set_world_covered(covered: bool) -> void:
	if covered == _world_covered:
		return
	_world_covered = covered
	if covered:
		_world_visible_before_cover = visible
		visible = false
		_suspend_covered_viewport()
	else:
		visible = _world_visible_before_cover
		_restore_covered_viewport()


func _suspend_covered_viewport() -> void:
	_covered_viewport = get_viewport()
	if _covered_viewport == null:
		return
	var lease: Dictionary = _covered_viewport.get_meta(COVER_RENDER_LEASE, {})
	if lease.is_empty():
		lease = {"before": _covered_viewport.disable_3d, "owners": {}}
	var owners: Dictionary = lease["owners"]
	owners[get_instance_id()] = true
	_covered_viewport.set_meta(COVER_RENDER_LEASE, lease)
	_covered_viewport.disable_3d = true


func _restore_covered_viewport() -> void:
	if not is_instance_valid(_covered_viewport):
		_covered_viewport = null
		return
	var lease: Dictionary = _covered_viewport.get_meta(COVER_RENDER_LEASE, {})
	if not lease.is_empty():
		var owners: Dictionary = lease["owners"]
		owners.erase(get_instance_id())
		if owners.is_empty():
			_covered_viewport.disable_3d = bool(lease["before"])
			_covered_viewport.remove_meta(COVER_RENDER_LEASE)
		else:
			_covered_viewport.set_meta(COVER_RENDER_LEASE, lease)
	_covered_viewport = null


func _exit_tree() -> void:
	_set_world_covered(false)
	if running and not _dead and missions != null:
		missions.checkpoint()
		Progression.evaluate_runner_achievements()
		SaveManager.save_now()
	# Interrupted loading/recovery must not retain temporary environment flags.
	_restore_covered_warmup_background()
	# A mode that can be left while paused must never hand the next scene a
	# paused tree.
	var tree := get_tree()
	if tree != null and not SceneRouter.is_busy():
		tree.paused = false
