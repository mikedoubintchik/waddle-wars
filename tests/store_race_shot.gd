extends Node
## Phone-sized desktop preview of the real quick-race scene.
## Autopilot supplies player input only. Never use as native-build acceptance.

var _out: String = ""
var _size: Vector2i = Vector2i(1080, 1920)
var _course: String = "glacier"
var _times: PackedFloat32Array = [2.0, 6.0, 10.0]
var _race: Node3D = null
var _manager: RaceManager = null
var _started_msec: int = -1
var _deadline_msec: int = 0
var _shot: int = 0
var _capturing: bool = false
var _monitor: bool = false


func _ready() -> void:
	if not _monitor:
		call_deferred("_install_monitor")
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", false, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"out": _out = parts[1]
			"w": _size.x = int(parts[1])
			"h": _size.y = int(parts[1])
			"course": _course = parts[1]
			"at":
				_times = PackedFloat32Array()
				for piece: String in parts[1].split(","):
					_times.append(float(piece))
	if _out.is_empty() or not _out.is_absolute_path() or _times.is_empty():
		push_error("store_race_shot: supply absolute out path and capture times")
		get_tree().quit(2)
		return
	GameConfig.force_touch = true
	GameConfig.force_native_offline_mvp = true
	LeaderboardClient.set_process(false)
	var display: Dictionary = SettingsManager.settings.get("display", {}).duplicate(true)
	display["window_mode"] = "windowed"
	display["resolution"] = "%dx%d" % [_size.x, _size.y]
	SettingsManager.settings["display"] = display
	SettingsManager.apply_all()
	DisplayServer.window_set_size(_size)
	DisplayServer.window_move_to_foreground()
	RaceManager.autopilot_player = true
	Game.mode = Game.Mode.QUICK_RACE
	Game.course_id = _course
	Game.difficulty_id = "competitive"
	_deadline_msec = Time.get_ticks_msec() + 70000
	Game.start_quick_race.call_deferred(_course, "competitive")


func _install_monitor() -> void:
	var monitor: Node = get_script().new()
	monitor.name = "StoreRaceMonitor"
	monitor.set("_monitor", true)
	get_tree().root.add_child(monitor)
	set_process(false)


func _process(_delta: float) -> void:
	if not _monitor:
		return
	if Time.get_ticks_msec() > _deadline_msec:
		push_error("store_race_shot: race/capture timeout")
		get_tree().quit(1)
		return
	if _race == null and get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path == Game.SCENE_RACE:
		_race = get_tree().current_scene as Node3D
	if _manager == null and _race != null:
		_manager = _race.get("manager") as RaceManager
		if _manager != null:
			_manager.race_started.connect(_on_race_started)
	if _capturing or _started_msec < 0 or _shot >= _times.size():
		return
	if float(Time.get_ticks_msec() - _started_msec) < _times[_shot] * 1000.0:
		return
	_capturing = true
	_capture(_shot)


func _on_race_started() -> void:
	_started_msec = Time.get_ticks_msec()
	print("[store-race] started course=%s" % _course)


func _capture(index: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s_%d.png" % [_out.get_basename(), index]
	var error := ERR_INVALID_DATA
	if image != null and not image.is_empty() and image.get_size() == _size:
		error = image.save_png(path)
	print("[store-race] saved %s t=+%.1fs err=%d" % [path, _times[index], error])
	_shot += 1
	_capturing = false
	if error != OK or _shot >= _times.size():
		get_tree().quit(0 if error == OK else 1)
