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
			course = _instantiate_course_script(String(info.get("script", "res://scripts/courses/course_glacier.gd")))
	course.add_to_group(&"course")
	add_child(course)

	var powerups := PowerupSystem.new()
	add_child(powerups)

	if Game.mode == Game.Mode.ENDLESS and course.has_method("run_endless"):
		course.call("run_endless", self, powerups)
		return
	if Game.mode == Game.Mode.TUTORIAL and course.has_method("run_tutorial"):
		course.call("run_tutorial", self, powerups)
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
	manager.player.shove_landed.connect(func(_attacker: Racer, _victim: Racer) -> void:
		_vibrate(0.2, 0.4, 0.15))
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
		touch.setup(manager.player.controller as PlayerController)

	var music := String(CoursesDB.get_item(course_id).get("music", "music_race"))
	AudioManager.play_music(music)


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
