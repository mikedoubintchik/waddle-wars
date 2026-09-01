extends Node3D
## Race scene orchestrator: builds the selected course, spawns the race
## manager, camera, HUD, pause menu, and touch controls based on Game context.

var course: CourseBase = null
var manager: RaceManager = null
var camera_rig: ChaseCamera = null
var hud: RaceHUD = null


func _ready() -> void:
	var course_id := Game.course_id
	match Game.mode:
		Game.Mode.ENDLESS:
			course = _instantiate_course_script("res://scripts/courses/course_endless.gd")
		Game.Mode.TUTORIAL:
			course = _instantiate_course_script("res://scripts/courses/course_tutorial.gd")
		_:
			var info := CoursesDB.get_item(course_id)
			if info.is_empty():
				# An id with no database entry used to fall through to glacier
				# geometry while times and records were still filed under the
				# unknown id — a wrong record is worse than no race. Refuse.
				push_error("Race: unknown course id '%s'; returning to the menu" % course_id)
				SceneRouter.go_to(Game.SCENE_MAIN_MENU)
				return
			course = _instantiate_course_script(String(info.get("script", "res://scripts/courses/course_glacier.gd")))
	course.add_to_group(&"course")
	add_child(course)
	# On web the course builds itself over several frames so the loading
	# animation keeps running through it (CourseBase.stage()); everywhere else
	# this returns without suspending and the scene is assembled in one go.
	# Nothing below may touch course geometry before this resolves.
	await course.build_ready()

	var powerups := PowerupSystem.new()
	add_child(powerups)

	# Endless and Tutorial are whole flows, not variations on a race: they own
	# their own managers, their own finish call and their own results panels.
	# A course that cannot run them used to fall through to a standard race,
	# which then finished through finish_race while the results screen drew
	# endless panels off Game.mode and read a result nobody had written.
	# Refuse the run instead of showing the player a blank scoreboard.
	if Game.mode == Game.Mode.ENDLESS or Game.mode == Game.Mode.TUTORIAL:
		var entry := "run_endless" if Game.mode == Game.Mode.ENDLESS else "run_tutorial"
		if not course.has_method(entry):
			push_error("Race: course '%s' cannot run %s; returning to the menu"
				% [course_id, entry])
			SceneRouter.go_to(Game.SCENE_MAIN_MENU)
			return
		course.call(entry, self, powerups)
		ShaderWarmup.warm(self)
		return

	Game.used_item_this_race = false
	Game.was_last_place_this_race = false

	manager = RaceManager.new()
	add_child(manager)
	manager.setup(course, powerups, Game.mode == Game.Mode.TIME_TRIAL)

	camera_rig = ChaseCamera.new()
	add_child(camera_rig)
	camera_rig.attach_to(manager.player)
	if not GameConfig.is_headless():
		camera_rig.camera.make_current()
	manager.player_finished.connect(func(_racer: Racer) -> void:
		camera_rig.enter_finish_mode())
	manager.player.respawned.connect(func(_racer: Racer) -> void:
		camera_rig.add_shake(0.4)
		_vibrate(0.3, 0.5, 0.3))
	manager.player.stunned_changed.connect(func(_racer: Racer, is_stunned: bool) -> void:
		if is_stunned:
			camera_rig.add_shake(0.5)
			_vibrate(0.5, 0.8, 0.4))
	# Both halves of a shove kick the camera. Landing one is the player's own
	# action and gets the lighter tap; taking one is something done TO them and
	# hits harder, which is also the only cue when the attacker came from
	# behind and was never in frame.
	manager.player.shove_landed.connect(func(_attacker: Racer, _victim: Racer) -> void:
		camera_rig.add_shake(0.32)
		_vibrate(0.2, 0.4, 0.15))
	manager.player.shoved.connect(func(_racer: Racer, _attacker: Racer) -> void:
		camera_rig.add_shake(0.55)
		_vibrate(0.45, 0.7, 0.3))
	manager.player_finished.connect(func(_racer: Racer) -> void:
		_vibrate(0.4, 0.6, 0.5))

	hud = RaceHUD.new()
	add_child(hud)
	hud.setup(manager, manager.player)
	if Game.mode == Game.Mode.TIME_TRIAL and course.course_id != "":
		var ghost := GhostSystem.new()
		add_child(ghost)
		ghost.setup(manager.player, course.course_id)
		manager.race_started.connect(ghost.start_run)
		manager.player_finished.connect(func(racer: Racer) -> void:
			ghost.recording = false
			var best := Progression.best_time(course.course_id)
			if best <= 0.0 or racer.finish_time < best:
				ghost.save_recording(racer.finish_time)
			ghost.stop_run())
		if ghost.has_ghost():
			hud.show_message("Ghost: %s" % RaceHUD.format_time(ghost.ghost_total_time()))
		else:
			var best := Progression.best_time(course.course_id)
			if best > 0.0:
				hud.show_message("Best: %s" % RaceHUD.format_time(best))

	add_child(PauseMenu.new())

	if SettingsManager.touch_controls_enabled():
		var touch := TouchControls.new()
		add_child(touch)
		# Player.setup is deferred by RaceManager, so controller is still null here;
		# defer the wire-up so it runs after the controller exists.
		_setup_touch_deferred.call_deferred(touch)
	# Portrait play is supported (camera opens FOV + pulls back), so no
	# rotate-your-device gate here anymore.

	var music := String(CoursesDB.get_item(course_id).get("music", "music_race"))
	AudioManager.play_music(music)

	# Course geometry, props, HUD and the chase camera all exist now, and the
	# racers are queued on the deferred flush — the last moment before anything
	# is playable and the last moment SceneRouter's opaque overlay is still up.
	# ShaderWarmup links every first-sight GPU program here so Chrome's
	# ANGLE -> Metal path cannot stall a frame mid-race on a material it has
	# never drawn. It runs for two or three frames and frees itself; headless
	# sims skip it entirely.
	ShaderWarmup.warm(self)


## Runs after RaceManager's deferred player.setup, so the controller exists.
## On the staged (web) path the spawns are drained a couple per frame, so the
## controller can still be missing on the first deferred pass — wait for it
## rather than storing the null TouchControls used to store.
func _setup_touch_deferred(touch: TouchControls) -> void:
	while is_instance_valid(touch) and manager != null and manager.player != null \
			and manager.player.controller == null:
		await get_tree().process_frame
	if not is_instance_valid(touch) or manager == null or manager.player == null:
		return
	touch.setup(manager.player.controller as PlayerController)


## Controller rumble, gated by the vibration setting.
func _vibrate(weak: float, strong: float, duration: float) -> void:
	if GameConfig.is_headless() or not bool(SettingsManager.get_setting("gameplay", "vibration")):
		return
	for device: int in Input.get_connected_joypads():
		Input.start_joy_vibration(device, weak, strong, duration)


func _instantiate_course_script(path: String) -> CourseBase:
	var script: GDScript = load(path)
	if script == null:
		push_error("Race: missing course script %s, falling back to glacier" % path)
		script = load("res://scripts/courses/course_glacier.gd")
	return script.new() as CourseBase
