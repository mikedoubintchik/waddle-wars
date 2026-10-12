extends Node
## Native screenshots of the form; never submits mail or changes player saves.

var _out := ""
var _captures: Array[Dictionary] = []
var _errors: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
	if GameConfig.is_headless() or not _out.is_absolute_path() or not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(2)
		return
	LeaderboardClient.set_process(false)
	GameConfig.force_native_offline_mvp = true
	LayoutProfile.forced_insets = Vector4.ZERO
	for shape: Vector2i in [Vector2i(540, 960), Vector2i(1280, 720)]:
		GameConfig.force_touch = shape.y > shape.x
		DisplayServer.window_set_size(shape)
		SettingsManager._apply_ui_scale(1.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var form = preload("res://scripts/ui/feedback_form.gd").new()
		form.open(self)
		await _capture("form", shape, form)
		form._selected = "bug"
		form._message.text = "The mission labels overlapped when I rotated my phone."
		form._email.text = ""
		form._completed(false, "Could not connect. Your message is still here; please try again.")
		await _capture("retry", shape, form)
		form._completed(true, "Your message is on its way to support@waddlewars.io.")
		await _capture("thanks", shape, form)
		form.free()
	for player: AudioStreamPlayer in [AudioManager._music_a, AudioManager._music_b]:
		player.stop()
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures": _captures, "errors": _errors,
		"limits": "Real native frames; synthetic failure/success responses, no network, no mail. Dummy audio, isolated saves."}, "\t"))
	file.close()
	print("[feedback-capture] %d frames, %d errors" % [_captures.size(), _errors.size()])
	get_tree().quit(1 if not _errors.is_empty() else 0)

func _capture(state: String, shape: Vector2i, form: Node) -> void:
	await get_tree().create_timer(0.8).timeout
	DisplayServer.window_move_to_foreground()
	await RenderingServer.frame_post_draw
	var path := _out.path_join("%s-%dx%d.png" % [state, shape.x, shape.y])
	var pixels := get_viewport().get_texture().get_image()
	if pixels == null or pixels.is_empty() or FileAccess.file_exists(path):
		_errors.append("Invalid capture: " + path)
		return
	for control: Control in [form._back, form._send, form._email, form._message]:
		if control.is_visible_in_tree() and not get_viewport().get_visible_rect().encloses(control.get_global_rect()):
			_errors.append("%s outside view: %s" % [state, control.name])
	DirAccess.make_dir_recursive_absolute(_out)
	var error := pixels.save_png(path)
	_captures.append({"state": state, "shape": [shape.x, shape.y], "path": path,
		"logical_size": str(get_viewport().get_visible_rect().size), "save_error": error})
	if error != OK:
		_errors.append("PNG save failed")
