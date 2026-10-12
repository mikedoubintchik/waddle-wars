extends "res://tests/mobile_ui_audit.gd"
## Eight settled native menu captures using live UI and blocked transport.

func _ready() -> void:
	var only_wide := false
	if GameConfig.is_headless():
		get_tree().quit(1)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_capture_prefix = arg.trim_prefix("out=")
		if arg == "only_wide=1":
			only_wide = true
	if _capture_prefix.is_empty() or not _capture_prefix.is_absolute_path():
		get_tree().quit(2)
		return
	LeaderboardClient.set_script(OfflineLeaderboard)
	CommerceClient.set_script(OfflineCommerce)
	LeaderboardClient.set_process(false)
	CommerceClient.set_process(false)
	LeaderboardClient.force_available = false
	LayoutProfile.forced_insets = Vector4.ZERO
	_capture_pass = true
	DisplayServer.window_move_to_foreground()
	for shape: Vector2i in [Vector2i(540, 960), Vector2i(960, 540)]:
		if only_wide and shape.y > shape.x:
			continue
		GameConfig.force_touch = shape.y > shape.x
		SettingsManager.settings["display"]["window_mode"] = "windowed"
		SettingsManager.settings["display"]["resolution"] = "%dx%d" % [shape.x, shape.y]
		SettingsManager.settings["accessibility"]["reduced_flashing"] = true
		SettingsManager.apply_all()
		for entry: Dictionary in SCENES:
			if String(entry["name"]) in ["cosmetic_shop", "achievements", "credits", "controls"]:
				await _audit(String(entry["name"]), String(entry["path"]), shape, false)
	var report := {"kind":"loader_remaining_menu_fidelity", "captures":_captured_frames,
		"failures":_failures, "warnings":_warnings,
		"limits":"Settled native stills and reachability only; offline transport, isolated default save. No real account, purchases or platform remapping end-to-end exercised."}
	var file := FileAccess.open(_capture_prefix.get_basename() + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("[menu-fidelity-shot] captures=%d geometry_failures=%d" % [_captured_frames, _failures.size()])
	get_tree().quit(0 if _captured_frames == (4 if only_wide else 8) and _failures.is_empty() else 1)

func _capture_screen(screen: String, shape: Vector2i) -> void:
	var path := _capture_path(screen, shape)
	DisplayServer.window_move_to_foreground()
	await get_tree().create_timer(0.8).timeout
	DisplayServer.window_move_to_foreground()
	await RenderingServer.frame_post_draw
	var pixels := get_viewport().get_texture().get_image()
	if FileAccess.file_exists(path) or pixels == null or pixels.is_empty() or pixels.get_size() != shape:
		_failures.append("Capture refused: " + path)
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if pixels.save_png(path) != OK:
		_failures.append("Capture save failed: " + path)
		return
	_captured_frames += 1
	print("[menu-fidelity-shot] " + path)
