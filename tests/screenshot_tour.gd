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
		"achievements":
			SceneRouter.go_to.call_deferred(Game.SCENE_ACHIEVEMENTS)
		"leaderboard":
			SceneRouter.go_to.call_deferred(Game.SCENE_LEADERBOARD)
		"settings":
			SceneRouter.go_to.call_deferred(Game.SCENE_SETTINGS)
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

	var monitor := ShotMonitor.new()
	monitor.out_path = _out_path
	monitor.wait_time = _wait
	for arg: String in OS.get_cmdline_user_args():
		if arg == "pause=1":
			monitor.open_pause = true
	get_tree().root.add_child.call_deferred(monitor)


class ShotMonitor:
	extends Node

	var out_path: String = ""
	var wait_time: float = 2.5
	var open_pause: bool = false
	var _elapsed: float = 0.0
	var _done: bool = false
	var _paused_sent: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS  # keep capturing while paused

	func _process(delta: float) -> void:
		if _done:
			return
		_elapsed += delta
		if open_pause and not _paused_sent and _elapsed > wait_time - 1.0:
			_paused_sent = true
			var press := InputEventAction.new()
			press.action = "pause"
			press.pressed = true
			Input.parse_input_event(press)
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
