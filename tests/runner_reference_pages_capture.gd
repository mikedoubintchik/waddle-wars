extends Node
## Short, settled stills of the shipped pause builder and results HUD.
## Uses isolated fixture state; no route, collision, timing or OS-input claim.

class PauseFixture extends RunnerGame:
	func _ready() -> void:
		build_finished = true
		_presentation_started = true
		running = true
	func _process(_delta: float) -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass

var _out := ""
var _captures: Array[Dictionary] = []
var _errors: Array[String] = []
var _results_only := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameConfig.is_headless():
		print("[runner-reference-pages] Parser only; no visual acceptance")
		get_tree().quit()
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
		elif arg == "results_only=1":
			_results_only = true
	if not _out.is_absolute_path() or not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(2)
		return
	GameConfig.force_native_offline_mvp = true
	LeaderboardClient.set_process(false)
	LeaderboardClient.force_available = false
	LayoutProfile.forced_insets = Vector4.ZERO
	SettingsManager.settings["accessibility"]["reduced_flashing"] = true
	DisplayServer.window_move_to_foreground()
	for shape: Vector2i in [Vector2i(540, 960), Vector2i(960, 540)]:
		GameConfig.force_touch = shape.y > shape.x
		DisplayServer.window_set_size(shape)
		await get_tree().process_frame
		await get_tree().process_frame
		if not _results_only:
			var pause := PauseFixture.new()
			add_child(pause)
			pause._toggle_pause()
			await _capture("pause", shape, pause._pause_layer)
			pause._close_pause()
			pause.free()
			await get_tree().process_frame
		var hud := RunnerHUD.new()
		add_child(hud)
		hud.setup()
		hud.show_game_over({"distance":363.0, "fish":27, "score":1038,
			"best":6692, "missions":["Run 250 m at x2 or better", "Collect 60 fish"]})
		await _capture("results", shape, hud._game_over)
		hud.free()
		await get_tree().process_frame
	for player: Node in AudioManager.get_children():
		if player is AudioStreamPlayer or player is AudioStreamPlayer3D:
			player.stop()
			player.stream = null
	await get_tree().create_timer(0.1).timeout
	var report := {"captures":_captures, "errors":_errors,
		"limits":"Actual native frames; synthetic summary and pause host without course. Production controls/rendering, isolated user save, Dummy audio. No route, physical input or performance acceptance."}
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[runner-reference-pages] %d captures; %d errors" % [_captures.size(), _errors.size()])
	get_tree().quit(0 if _captures.size() == (2 if _results_only else 4) and _errors.is_empty() else 1)

func _capture(page: String, shape: Vector2i, root: Node) -> void:
	await get_tree().create_timer(1.6).timeout
	DisplayServer.window_move_to_foreground()
	await get_tree().process_frame
	DisplayServer.window_move_to_foreground()
	await RenderingServer.frame_post_draw
	if not get_window().has_focus():
		_errors.append(page + ": native frame lost foreground")
	var path := _out.path_join("%s-%dx%d.png" % [page, shape.x, shape.y])
	var pixels := get_viewport().get_texture().get_image()
	if pixels == null or pixels.is_empty() or pixels.get_size() != shape or FileAccess.file_exists(path):
		_errors.append("Invalid capture: " + path)
		return
	for button: Node in root.find_children("*", "Button", true, false):
		if not (button as Button).is_visible_in_tree():
			continue
		var rect: Rect2 = (button as Button).get_global_rect()
		if not get_viewport().get_visible_rect().encloses(rect):
			_errors.append("%s: button outside view: %s %s" % [page, button.text, rect])
	DirAccess.make_dir_recursive_absolute(_out)
	var error := pixels.save_png(path)
	var missions: Array[Dictionary] = []
	if page == "results":
		var hud := root.get_parent() as RunnerHUD
		for label: Label in hud._results_mission_labels:
			var rect := label.get_global_rect()
			missions.append({"text":label.text, "lines":label.get_line_count(),
				"visible_lines":label.get_visible_line_count(), "font":label.get_theme_font_size("font_size"),
				"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
			if label.get_visible_line_count() != label.get_line_count() \
					or not get_viewport().get_visible_rect().encloses(rect):
				_errors.append("Completed mission not fully visible: " + label.text)
	_captures.append({"page":page,"path":path,"shape":[shape.x,shape.y],"save_error":error,
		"completed_mission_rows":missions})
	if error != OK:
		_errors.append("PNG save failed: " + path)
