extends Node
## Actual SVG decode, remapping and reference-keycap fit without font fallback.
var passed := 0
var failed := 0

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(2)
		return
	_test_arrow_migration()
	for shape: Vector2i in [Vector2i(1672, 941), Vector2i(941, 1672)]:
		GameConfig.force_touch = shape.y > shape.x
		SettingsManager.reset_bindings()
		var viewport := SubViewport.new()
		viewport.size = shape
		add_child(viewport)
		var controls := load("res://scenes/menus/controls.tscn").instantiate() as Control
		viewport.add_child(controls)
		for frame: int in 4: await get_tree().process_frame
		for action: String in SettingsManager.REMAPPABLE_ACTIONS:
			for family: String in ["key", "joy"]:
				var cap: Button = controls._binding_buttons[action + "/" + family]
				var binding := SettingsManager.describe_action_binding(action, family)
				check(cap.tooltip_text == binding and cap.accessibility_name.ends_with(binding), "exact binding remains accessible: " + action + "/" + family)
				check(Rect2(Vector2.ZERO, Vector2(shape)).encloses(cap.get_global_rect()), "binding hitbox contained: " + action + "/" + family)
		for action: String in ["steer_left", "steer_right", "pause"]:
			var cap: Button = controls._binding_buttons[action + "/joy"]
			check(cap.icon != null and not cap.text.contains("◀") and not cap.text.contains("▶") and not cap.text.contains("≡"), "default pad symbol is texture-backed: " + action)
			check(cap.icon.get_image().get_used_rect().has_area(), "actual Godot SVG decoder yields visible symbol: " + action)
			check(cap.get_theme_constant("icon_max_width") < cap.size.y * 0.60, "pad symbol leaves interior cap padding: " + action)
		for action: String in ["steer_left", "steer_right", "jump", "slide"]:
			var cap: Button = controls._binding_buttons[action + "/key"]
			check(cap.text.is_empty() and cap.icon != null, "primary keyboard binding displays an arrow: " + action)
			check(cap.icon.get_image().get_used_rect().has_area(), "keyboard arrow decodes without font fallback: " + action)
		for direction: int in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
			var event := InputEventJoypadButton.new()
			event.button_index = direction
			SettingsManager.rebind_action("steer_left", event)
			controls._refresh_all_bindings()
			var cap: Button = controls._binding_buttons["steer_left/joy"]
			check(cap.text.is_empty() and cap.icon != null and cap.icon.get_image().get_used_rect().has_area(), "remapped D-pad uses decoded arrow texture: %d" % direction)
			check(cap.tooltip_text == SettingsManager.describe_action_binding("steer_left", "joy"), "remapped D-pad retains authoritative description")
		var letter := InputEventJoypadButton.new()
		letter.button_index = JOY_BUTTON_A
		SettingsManager.rebind_action("steer_left", letter)
		controls._refresh_all_bindings()
		var remapped: Button = controls._binding_buttons["steer_left/joy"]
		check(remapped.text == "A" and remapped.icon == null, "letter remap clears obsolete directional icon")
		controls._begin_capture("jump", "key")
		check(controls._capture_overlay.visible, "styled cap retains capture behavior")
		controls._end_capture()
		check(not controls._capture_overlay.visible, "capture cancellation retains existing behavior")
		controls.free()
		viewport.free()
	SettingsManager.reset_bindings()
	for voice in AudioManager._sfx_pool:
		voice.stop(); voice.stream = null
	for player in [AudioManager._music_a, AudioManager._music_b]:
		player.stop(); player.stream = null
	await get_tree().create_timer(0.1).timeout
	print("[controls-binding-icons] DONE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)


func _test_arrow_migration() -> void:
	SettingsManager.reset_bindings()
	for entry: Array in [["steer_left", KEY_LEFT, "Left"], ["steer_right", KEY_RIGHT, "Right"], ["jump", KEY_UP, "Up"], ["slide", KEY_DOWN, "Down"]]:
		var event := InputEventKey.new()
		event.physical_keycode = entry[1]
		event.pressed = true
		check(InputMap.event_is_action(event, entry[0]), "real directional key resolves to action: " + entry[0])
		check(SettingsManager.describe_action_binding(entry[0], "key") == entry[2], "direction is primary displayed binding: " + entry[0])
	SettingsManager.settings["controls"] = {
		"slide": [{"type":"key", "code":KEY_CTRL}, {"type":"key", "code":KEY_S}, {"type":"joy_button", "index":JOY_BUTTON_B}],
		"steer_left": [{"type":"key", "code":KEY_J}],
	}
	SettingsManager.settings["controls_meta"] = {"version":0}
	SettingsManager._apply_control_remaps()
	check(SettingsManager.describe_action_binding("slide", "key") == "Down", "saved old defaults gain Down")
	check(SettingsManager.describe_action_binding("slide", "joy") == "B", "saved controller binding preserved")
	check(SettingsManager.describe_action_binding("steer_left", "key") == "J", "custom keyboard mapping preserved")
	SettingsManager._load_settings()
	SettingsManager._apply_control_remaps()
	check(SettingsManager.describe_action_binding("slide", "key") == "Down", "migration survives settings reload")
	var custom := InputEventKey.new()
	custom.physical_keycode = KEY_V
	SettingsManager.rebind_action("slide",custom)
	SettingsManager._load_settings()
	SettingsManager._apply_control_remaps()
	check(SettingsManager.describe_action_binding("slide", "key") == "V", "subsequent custom binding never overwritten")
	SettingsManager.reset_bindings()

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("[controls-binding-icons] %s %s" % ["PASS" if ok else "FAIL", label])
