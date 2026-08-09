extends Node
## Visual QA: opens a target screen (or a live race), waits for it to settle,
## saves a PNG of the viewport, and quits. Must run WITH a window (not
## headless — there is nothing to capture headless).
##   godot res://tests/screenshot_tour.tscn -- shot=title out=build/shots/title.png [w=1920 h=1080] [course=glacier] [wait=2.5]

var _out_path: String = "build/shots/shot.png"
var _wait: float = 2.5
var _shot: String = "title"
var _course: String = "glacier"
var _elapsed: float = 0.0
var _captured: bool = false


func _ready() -> void:
	var width := 1920
	var height := 1080
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"shot": _shot = parts[1]
			"out": _out_path = parts[1]
			"w": width = int(parts[1])
			"h": height = int(parts[1])
			"course": _course = parts[1]
			"wait": _wait = float(parts[1])
			# Accessibility UI scale. Layout bugs that only appear for players
			# who have turned this up are invisible at the default, so QA needs
			# to be able to reach them.
			"uiscale": SettingsManager.set_setting(
				"accessibility", "ui_scale", float(parts[1]))
			# Render the phone layout on a desktop box. Touch-only layout rules
			# are gated on real hardware, so without this the phone paths are
			# untestable here.
			"touch": GameConfig.force_touch = parts[1] == "1"
	# Pin the accessibility scale for every capture. It is persisted in
	# settings.json, so a value left behind by an earlier `uiscale=` run
	# silently changes the canvas of every later capture -- which is how a
	# mobile layout fix got tuned against a canvas no phone has.
	if not _has_arg("uiscale"):
		SettingsManager.set_setting("accessibility", "ui_scale", 1.0)
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_set_position(Vector2i(40, 60))

	match _shot:
		"title":
			SceneRouter.go_to.call_deferred(Game.SCENE_TITLE)
		"menu":
			SceneRouter.go_to.call_deferred(Game.SCENE_MAIN_MENU)
		"mode_select":
			SceneRouter.go_to.call_deferred(Game.SCENE_MODE_SELECT)
		"customize":
			SceneRouter.go_to.call_deferred(Game.SCENE_CUSTOMIZE)
		"customize_buy":
			# Customize with the purchase confirmation open, so the dialog can
			# be inspected without driving clicks through the UI.
			SceneRouter.go_to.call_deferred(Game.SCENE_CUSTOMIZE)
			# Parented to the root, not to this node: go_to replaces the current
			# scene, which frees the tour and every timer connected to it.
			var opener := BuyDialogOpener.new()
			get_tree().root.add_child.call_deferred(opener)
		"difficulty_select":
			# Difficulty step, reached through the course picker.
			Game.mode = Game.Mode.QUICK_RACE
			SceneRouter.go_to.call_deferred(Game.SCENE_MODE_SELECT)
			var diff := CourseStepOpener.new()
			diff.go_to_difficulty = true
			get_tree().root.add_child.call_deferred(diff)
		"course_select":
			# Course-picker step of mode select, so the per-course poster art can
			# be inspected. Same root-parented opener trick as customize_buy.
			Game.mode = Game.Mode.QUICK_RACE
			SceneRouter.go_to.call_deferred(Game.SCENE_MODE_SELECT)
			var stepper := CourseStepOpener.new()
			get_tree().root.add_child.call_deferred(stepper)
		"achievements":
			SceneRouter.go_to.call_deferred(Game.SCENE_ACHIEVEMENTS)
		"leaderboard":
			SceneRouter.go_to.call_deferred(Game.SCENE_LEADERBOARD)
		"settings":
			SceneRouter.go_to.call_deferred(Game.SCENE_SETTINGS)
			if _has_arg("section"):
				var jumper := SectionJumper.new()
				for a: String in OS.get_cmdline_user_args():
					if a.begins_with("section="):
						jumper.section = a.split("=")[1]
				get_tree().root.add_child.call_deferred(jumper)
		"results":
			Game.mode = Game.Mode.QUICK_RACE
			Game.course_id = _course
			var rows: Array[Dictionary] = []
			var names := ["You", "Gus", "Pippa", "Scooter", "Marina", "Bruno", "Ziggy", "Nova"]
			for i: int in 8:
				rows.append({"key": "player" if i == 0 else names[i].to_lower(), "name": names[i],
					"is_player": i == 0, "position": i + 1, "time": 95.0 + float(i) * 3.2,
					"fish": 12 - i, "dnf": false})
			Game.last_race_results = rows
			Game.last_rewards = {"fish": 57, "xp": 145, "unlocks": []}
			SceneRouter.go_to.call_deferred(Game.SCENE_RESULTS)
		"race_shield":
			# Race with the player shielded, so the bubble can be inspected.
			Game.mode = Game.Mode.QUICK_RACE
			Game.course_id = _course
			Game.difficulty_id = "competitive"
			RaceManager.autopilot_player = true
			SceneRouter.go_to.call_deferred(Game.SCENE_RACE)
			var shielder := ShieldOpener.new()
			get_tree().root.add_child.call_deferred(shielder)
		"race_shove":
			# Stages a shove and captures a STRIP of frames across it. A single
			# screenshot cannot inspect a 0.4 s impulse -- the odds of landing
			# on the peak are poor, and a miss looks exactly like the effect
			# not existing, which is not a result worth acting on.
			Game.mode = Game.Mode.QUICK_RACE
			Game.course_id = _course
			Game.difficulty_id = "competitive"
			RaceManager.autopilot_player = true
			SceneRouter.go_to.call_deferred(Game.SCENE_RACE)
			var shover := ShoveStrip.new()
			shover.out_path = _out_path
			get_tree().root.add_child.call_deferred(shover)
			return
		"race":
			Game.mode = Game.Mode.QUICK_RACE
			Game.course_id = _course
			Game.difficulty_id = "competitive"
			RaceManager.autopilot_player = true
			SceneRouter.go_to.call_deferred(Game.SCENE_RACE)
		"tutorial":
			RaceManager.autopilot_player = true
			Game.start_tutorial.call_deferred()
		"endless":
			RaceManager.autopilot_player = true
			CourseEndless.run_seed = 424242
			Game.start_endless.call_deferred()

	_install_monitor()


func _has_arg(key: String) -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(key + "="):
			return true
	return false


func _install_monitor() -> void:
	var monitor := ShotMonitor.new()
	monitor.out_path = _out_path
	monitor.wait_time = _wait
	for arg: String in OS.get_cmdline_user_args():
		if arg == "pause=1":
			monitor.open_pause = true
		elif arg == "pause=settings":
			monitor.open_pause_settings = true
	get_tree().root.add_child.call_deferred(monitor)


class ShotMonitor:
	extends Node

	var out_path: String = ""
	var wait_time: float = 2.5
	var open_pause: bool = false
	## Also presses Settings inside the pause menu, so the in-race settings
	## overlay can be inspected. Implies open_pause.
	var open_pause_settings: bool = false
	var _elapsed: float = 0.0
	var _done: bool = false
	var _paused_sent: bool = false
	var _settings_sent: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS  # keep capturing while paused

	func _process(delta: float) -> void:
		if _done:
			return
		_elapsed += delta
		if (open_pause or open_pause_settings) and not _paused_sent \
				and _elapsed > wait_time - 1.4:
			_paused_sent = true
			var press := InputEventAction.new()
			press.action = "pause"
			press.pressed = true
			Input.parse_input_event(press)
		if open_pause_settings and _paused_sent and not _settings_sent \
				and _elapsed > wait_time - 0.7:
			_settings_sent = true
			# Called directly rather than by driving focus to the button: this
			# is verifying what the overlay LOOKS like, and synthesizing a click
			# at the right pixel would be testing the harness, not the screen.
			var menu := _find_pause_menu(get_tree().root)
			if menu != null:
				menu.call("_open_settings")
			else:
				print("[shot] no pause menu found")
		if _elapsed < wait_time:
			return
		_done = true
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var dir := out_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(dir)
		var err := image.save_png(out_path)
		print("[shot] saved %s (%dx%d) err=%d" % [out_path, image.get_width(), image.get_height(), err])
		get_tree().quit(0 if err == OK else 1)

	func _find_pause_menu(node: Node) -> Node:
		if node is PauseMenu:
			return node
		for child: Node in node.get_children():
			var found := _find_pause_menu(child)
			if found != null:
				return found
		return null


## Drags a rival alongside the player, throws a shove, and captures a strip of
## frames across the impulse so the animation can actually be looked at.
##
## The rival is teleported rather than waited for: two autopilot racers come
## within SHOVE_RANGE of each other only by luck, and a capture that depends on
## luck is a capture that mostly returns an ordinary frame of racing.
class ShoveStrip:
	extends Node

	## Seconds after the shove at which each frame is taken. Spans the lunge
	## (LUNGE_TIME 0.40) and most of the tumble (TUMBLE_TIME 1.05).
	const OFFSETS: PackedFloat32Array = [0.05, 0.18, 0.36, 0.70]

	var out_path: String = ""
	var _elapsed: float = 0.0
	var _shoved: bool = false
	var _shot: int = 0
	var _since_shove: float = 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_elapsed += delta
		if not _shoved:
			# Late enough that the grid has broken up. On the start line every
			# racer is inside shove range of several others, so the capture
			# frames a crowd instead of one legible hit.
			if _elapsed < 12.0:
				return
			if not _stage_shove() and _elapsed < 30.0:
				return
			_shoved = true
			return
		_since_shove += delta
		if _shot >= OFFSETS.size():
			return
		if _since_shove < OFFSETS[_shot]:
			return
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := "%s_%d.png" % [out_path.get_basename(), _shot]
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var err := image.save_png(path)
		print("[shot] saved %s t=+%.2fs err=%d" % [path, OFFSETS[_shot], err])
		_shot += 1
		if _shot >= OFFSETS.size():
			get_tree().quit(0 if err == OK else 1)

	## Returns true once the shove has been thrown.
	func _stage_shove() -> bool:
		var player: Node = null
		var victim: Node = null
		for racer: Node in get_tree().get_nodes_in_group(&"racers"):
			if racer.get("is_player") == true:
				player = racer
			elif victim == null:
				victim = racer
		if player == null or victim == null:
			return false
		# Park the victim just inside SHOVE_RANGE, off to the player's right so
		# the tumble direction is unambiguous in the capture.
		var xform: Transform3D = player.global_transform
		victim.global_position = xform.origin + xform.basis.x * 1.5 - xform.basis.z * 0.6
		victim.set("current_speed", player.get("current_speed"))
		player.call("_attempt_shove")
		print("[shot] shove: %s -> %s at %.1fm, camera racer=%s" % [
			player.get("racer_key"), victim.get("racer_key"),
			(player.global_position as Vector3).distance_to(victim.global_position),
			_camera_racer_key()])
		return true

	## Which racer the chase camera is actually looking at -- the capture is
	## only meaningful if that is the one doing the shoving.
	func _camera_racer_key() -> String:
		var cam := get_viewport().get_camera_3d()
		if cam == null or cam.get_parent() == null:
			return "(no camera)"
		var rig: Variant = cam.get_parent().get("target")
		if rig == null or not is_instance_valid(rig):
			return "(no target)"
		return String((rig as Node).get("racer_key"))


## Opens the customize screen's purchase confirmation once that screen exists.
##
## Lives on the tree root because SceneRouter.go_to frees the current scene --
## anything parented to the tour itself dies with it mid-transition.
class BuyDialogOpener:
	extends Node

	var _elapsed: float = 0.0
	var _done: bool = false

	func _process(delta: float) -> void:
		if _done:
			return
		_elapsed += delta
		if _elapsed < 0.8:
			return
		var screen := _find_customize(get_tree().root)
		if screen == null:
			if _elapsed > 8.0:
				_done = true
				print("[shot] customize screen never appeared")
			return
		_done = true
		Progression.add_fish(5000)
		for id: String in CosmeticsDB.items_in_category("hat"):
			if not Progression.is_cosmetic_unlocked(id):
				screen.call("_select_category", "hat")
				screen.call("_on_item_pressed", id)
				print("[shot] opened buy dialog for %s" % id)
				return
		print("[shot] no locked hat to buy")

	func _find_customize(node: Node) -> Node:
		if node.has_method("_open_buy_dialog") and node.has_method("_on_item_pressed"):
			return node
		for child: Node in node.get_children():
			var found := _find_customize(child)
			if found != null:
				return found
		return null


## Advances mode select to its course-picker step once that screen exists.
class CourseStepOpener:
	extends Node

	var go_to_difficulty: bool = false
	var _elapsed: float = 0.0
	var _done: bool = false

	func _process(delta: float) -> void:
		if _done:
			return
		_elapsed += delta
		if _elapsed < 0.8:
			return
		var screen := _find(get_tree().root)
		if screen == null:
			if _elapsed > 8.0:
				_done = true
				print("[shot] mode select never appeared")
			return
		_done = true
		screen.call("_show_course_step")
		if go_to_difficulty:
			screen.set("_chosen_course", CoursesDB.ORDER[3])
			screen.call("_show_difficulty_step")
			print("[shot] advanced to difficulty step")
			return
		print("[shot] advanced to course step")

	func _find(node: Node) -> Node:
		if node.has_method("_show_course_step") and node.has_method("_show_mode_step"):
			return node
		for child: Node in node.get_children():
			var found := _find(child)
			if found != null:
				return found
		return null


## Gives the player racer a shield once the race exists, so the bubble can be
## inspected without waiting for an item box to hand one out.
class ShieldOpener:
	extends Node

	var _elapsed: float = 0.0
	var _done: bool = false

	func _process(delta: float) -> void:
		if _done:
			return
		_elapsed += delta
		if _elapsed < 1.0:
			return
		for racer: Node in get_tree().get_nodes_in_group(&"racers"):
			if racer.get("is_player") == true and racer.has_method("give_shield"):
				racer.call("give_shield")
				_done = true
				print("[shot] shield given")
				return
		if _elapsed > 25.0:
			_done = true
			print("[shot] no player racer found for shield")


## Scrolls the settings screen to a named section, so a capture can inspect
## rows that are not on the first screenful.
class SectionJumper:
	extends Node

	var section: String = "gameplay"
	var _elapsed: float = 0.0
	var _done: bool = false

	func _process(delta: float) -> void:
		if _done:
			return
		_elapsed += delta
		if _elapsed < 0.9:
			return
		var screen := _find(get_tree().root)
		if screen == null:
			if _elapsed > 8.0:
				_done = true
				print("[shot] settings screen never appeared")
			return
		_done = true
		screen.call("_jump_to", section)
		print("[shot] jumped to %s" % section)

	func _find(node: Node) -> Node:
		if node.has_method("_jump_to"):
			return node
		for child: Node in node.get_children():
			var found := _find(child)
			if found != null:
				return found
		return null
