extends Control
## Settings screen covering the full SettingsManager schema, organized into
## Display / Audio / Gameplay / Accessibility sections in a scrollable list.

var _sections: VBoxContainer


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	layout.add_child(header)
	var title := UITheme.heading("Settings", 48)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	var controls_button := UITheme.make_button("Controls", Vector2(200, 48), 22)
	UITheme.hook_sounds(controls_button)
	controls_button.pressed.connect(func() -> void:
		SceneRouter.go_to("res://scenes/menus/controls.tscn"))
	header.add_child(controls_button)
	var back_button := UITheme.make_button("Back", Vector2(160, 48), 22)
	UITheme.hook_sounds(back_button)
	back_button.pressed.connect(_go_back)
	header.add_child(back_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)

	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", 18)
	scroll.add_child(_sections)

	_build_display_section()
	_build_audio_section()
	_build_gameplay_section()
	_build_accessibility_section()

	controls_button.grab_focus()
	SettingsManager.setting_changed.connect(_on_setting_changed)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "accessibility/ui_scale":
		UITheme.apply_ui_scale(self)


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()


## --- Section builders -----------------------------------------------------

func _build_display_section() -> void:
	var body := _section("Display")
	_add_option_row(body, "display", "window_mode", "Window Mode", [
		["windowed", "Windowed"], ["fullscreen", "Fullscreen"], ["borderless", "Borderless"],
	])
	_add_option_row(body, "display", "resolution", "Resolution", [
		["1280x720", "1280 x 720"], ["1600x900", "1600 x 900"],
		["1920x1080", "1920 x 1080"], ["2560x1440", "2560 x 1440"],
	])
	_add_toggle_row(body, "display", "vsync", "V-Sync")
	_add_option_row(body, "display", "quality_preset", "Quality Preset", [
		["low", "Low"], ["medium", "Medium"], ["high", "High"],
	])
	_add_option_row(body, "display", "shadow_quality", "Shadow Quality", [
		["off", "Off"], ["low", "Low"], ["medium", "Medium"], ["high", "High"],
	])
	_add_option_row(body, "display", "particle_quality", "Particle Quality", [
		["low", "Low"], ["medium", "Medium"], ["high", "High"],
	])
	_add_option_row(body, "display", "msaa", "Anti-Aliasing (MSAA)", [
		["off", "Off"], ["2x", "2x"], ["4x", "4x"],
	])
	_add_int_option_row(body, "display", "fps_limit", "FPS Limit", [
		[0, "Uncapped"], [30, "30"], [60, "60"], [120, "120"],
	])


func _build_audio_section() -> void:
	var body := _section("Audio")
	_add_slider_row(body, "audio", "master_volume", "Master Volume", 0.0, 1.0, 0.05, true)
	_add_slider_row(body, "audio", "music_volume", "Music Volume", 0.0, 1.0, 0.05, true)
	_add_slider_row(body, "audio", "sfx_volume", "SFX Volume", 0.0, 1.0, 0.05, true)
	_add_toggle_row(body, "audio", "muted", "Mute All")
	_add_toggle_row(body, "audio", "mute_unfocused", "Mute When Unfocused")


func _build_gameplay_section() -> void:
	var body := _section("Gameplay")
	_add_slider_row(body, "gameplay", "steer_sensitivity", "Steer Sensitivity", 0.5, 1.5, 0.05, false)
	_add_toggle_row(body, "gameplay", "vibration", "Vibration")
	_add_toggle_row(body, "gameplay", "slide_toggle_mode", "Slide: Toggle Mode")
	_add_toggle_row(body, "gameplay", "tutorial_prompts", "Tutorial Prompts")
	_add_option_row(body, "gameplay", "touch_controls", "Touch Controls", [
		["auto", "Auto"], ["on", "On"], ["off", "Off"],
	])
	_add_slider_row(body, "gameplay", "touch_scale", "Touch Button Size", 0.7, 1.4, 0.05, false)
	_add_slider_row(body, "gameplay", "touch_opacity", "Touch Button Opacity", 0.2, 1.0, 0.05, true)
	_add_slider_row(body, "gameplay", "gamepad_deadzone", "Gamepad Deadzone", 0.05, 0.6, 0.05, false)


func _build_accessibility_section() -> void:
	var body := _section("Accessibility")
	_add_option_row(body, "accessibility", "camera_shake", "Camera Shake", [
		["full", "Full"], ["reduced", "Reduced"], ["off", "Off"],
	])
	_add_toggle_row(body, "accessibility", "high_contrast_pickups", "High-Contrast Pickups")
	_add_toggle_row(body, "accessibility", "reduced_flashing", "Reduced Flashing")
	_add_toggle_row(body, "accessibility", "colorblind_cues", "Colorblind Cues")
	_add_slider_row(body, "accessibility", "hud_scale", "HUD Scale", 0.8, 1.4, 0.05, false)
	_add_slider_row(body, "accessibility", "ui_scale", "Menu Scale", 0.8, 1.4, 0.05, false)
	_add_toggle_row(body, "accessibility", "pause_on_disconnect", "Pause On Controller Disconnect")
	_add_toggle_row(body, "accessibility", "audio_visual_cues", "Visual Cues For Sounds")


## --- Row helpers ----------------------------------------------------------

func _section(section_title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.make_panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var label := Label.new()
	label.text = section_title
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	body.add_child(label)
	return body


func _row(parent: VBoxContainer, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


func _add_option_row(parent: VBoxContainer, section: String, key: String, label_text: String, options: Array) -> void:
	var row := _row(parent, label_text)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(240, 40)
	picker.add_theme_font_size_override("font_size", 19)
	var current := String(SettingsManager.get_setting(section, key))
	for i: int in options.size():
		var pair: Array = options[i]
		picker.add_item(String(pair[1]), i)
		if String(pair[0]) == current:
			picker.select(i)
	picker.item_selected.connect(func(index: int) -> void:
		AudioManager.ui_click()
		SettingsManager.set_setting(section, key, String(options[index][0])))
	picker.mouse_entered.connect(AudioManager.ui_hover)
	picker.focus_entered.connect(AudioManager.ui_hover)
	row.add_child(picker)


func _add_int_option_row(parent: VBoxContainer, section: String, key: String, label_text: String, options: Array) -> void:
	var row := _row(parent, label_text)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(240, 40)
	picker.add_theme_font_size_override("font_size", 19)
	var current := int(SettingsManager.get_setting(section, key))
	for i: int in options.size():
		var pair: Array = options[i]
		picker.add_item(String(pair[1]), i)
		if int(pair[0]) == current:
			picker.select(i)
	picker.item_selected.connect(func(index: int) -> void:
		AudioManager.ui_click()
		SettingsManager.set_setting(section, key, int(options[index][0])))
	picker.mouse_entered.connect(AudioManager.ui_hover)
	picker.focus_entered.connect(AudioManager.ui_hover)
	row.add_child(picker)


func _add_slider_row(parent: VBoxContainer, section: String, key: String, label_text: String, min_value: float, max_value: float, step: float, as_percent: bool) -> void:
	var row := _row(parent, label_text)
	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 19)
	value_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(240, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = float(SettingsManager.get_setting(section, key))
	var update_label := func() -> void:
		if as_percent:
			value_label.text = "%d%%" % int(round(slider.value * 100.0))
		else:
			value_label.text = "%.2f" % slider.value
	update_label.call()
	slider.value_changed.connect(func(new_value: float) -> void:
		SettingsManager.set_setting(section, key, new_value)
		update_label.call())
	slider.mouse_entered.connect(AudioManager.ui_hover)
	slider.focus_entered.connect(AudioManager.ui_hover)
	slider.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			AudioManager.ui_click())
	row.add_child(slider)
	row.add_child(value_label)


func _add_toggle_row(parent: VBoxContainer, section: String, key: String, label_text: String) -> void:
	var row := _row(parent, label_text)
	var toggle := CheckButton.new()
	toggle.button_pressed = bool(SettingsManager.get_setting(section, key))
	toggle.toggled.connect(func(pressed_state: bool) -> void:
		SettingsManager.set_setting(section, key, pressed_state))
	UITheme.hook_sounds(toggle)
	row.add_child(toggle)
