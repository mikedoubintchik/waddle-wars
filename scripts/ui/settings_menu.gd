extends Control
## Settings screen covering the full SettingsManager schema, organized into
## Display / Audio / Gameplay / Accessibility section cards with icon headers
## in a scrollable list.

## Drawn 64x64 section glyphs, same style family as the UITheme menu icons.
const ICON_DISPLAY: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<rect x="8" y="10" width="48" height="32" rx="4" fill="#274866" stroke="#7fd0f7" stroke-width="2.5"/>
<rect x="26" y="46" width="12" height="4" fill="#7fd0f7"/>
<rect x="18" y="52" width="28" height="4" rx="2" fill="#7fd0f7"/>
</svg>"""

const ICON_AUDIO: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M10 24 H20 L34 12 V52 L20 40 H10 Z" fill="#7fd0f7" stroke="#3d6d94" stroke-width="2" stroke-linejoin="round"/>
<path d="M42 22 Q48 32 42 42" stroke="#7fd0f7" stroke-width="3.5" fill="none" stroke-linecap="round"/>
<path d="M48 16 Q58 32 48 48" stroke="#7fd0f7" stroke-width="3.5" fill="none" stroke-linecap="round"/>
</svg>"""

const ICON_GAMEPLAY: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M16 20 H48 C58 20 62 44 54 46 C48 47 44 38 40 38 H24 C20 38 16 47 10 46 C2 44 6 20 16 20 Z" fill="#5a7ba6" stroke="#3d5578" stroke-width="2"/>
<path d="M20 25 V35 M15 30 H25" stroke="#e8f4ff" stroke-width="3.5" stroke-linecap="round"/>
<circle cx="44" cy="26" r="3" fill="#f5c542"/>
<circle cx="50" cy="32" r="3" fill="#ff6b57"/>
</svg>"""

const ICON_ACCESSIBILITY: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<circle cx="32" cy="11" r="6" fill="#7fe08f"/>
<path d="M10 24 Q32 32 54 24" stroke="#7fe08f" stroke-width="5" fill="none" stroke-linecap="round"/>
<path d="M32 28 V42 M32 42 L21 58 M32 42 L43 58" stroke="#7fe08f" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""

var _sections: VBoxContainer
var _entrance_items: Array[Control] = []


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UITheme.screen_margin())
	margin.add_theme_constant_override("margin_right", UITheme.screen_margin())
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", UITheme.SPACE_S)
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
	layout.add_child(UITheme.make_header_rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)

	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", UITheme.SPACE_M)
	scroll.add_child(_sections)

	_entrance_items.append(header)
	_build_display_section()
	_build_audio_section()
	_build_gameplay_section()
	_build_accessibility_section()
	UITheme.play_entrance(self, _entrance_items)

	controls_button.grab_focus()
	SettingsManager.setting_changed.connect(_on_setting_changed)
	UITheme.attach_swipe_back(self, _go_back)


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
	var body := _section("Display", ICON_DISPLAY)
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
	var body := _section("Audio", ICON_AUDIO)
	_add_slider_row(body, "audio", "master_volume", "Master Volume", 0.0, 1.0, 0.05, true)
	_add_slider_row(body, "audio", "music_volume", "Music Volume", 0.0, 1.0, 0.05, true)
	_add_slider_row(body, "audio", "sfx_volume", "SFX Volume", 0.0, 1.0, 0.05, true)
	_add_toggle_row(body, "audio", "muted", "Mute All")
	_add_toggle_row(body, "audio", "mute_unfocused", "Mute When Unfocused")


func _build_gameplay_section() -> void:
	var body := _section("Gameplay", ICON_GAMEPLAY)
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
	var body := _section("Accessibility", ICON_ACCESSIBILITY)
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

func _section(section_title: String, icon_svg: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := UITheme.make_panel_style()
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_child(panel)
	_entrance_items.append(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.spacing(12))
	panel.add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	body.add_child(header)
	if icon_svg != "":
		var texture := UITheme.make_icon(icon_svg, 1.0)
		if texture != null:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.custom_minimum_size = Vector2(30, 30)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			header.add_child(icon)
	var label := Label.new()
	label.text = section_title
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	header.add_child(label)
	var rule := ColorRect.new()
	rule.color = Color(UITheme.COLOR_ACCENT, 0.28)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rule)
	UITheme.animate_rule(rule)
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
	UITheme.style_option_button(picker)
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
	UITheme.style_option_button(picker)
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
	value_label.add_theme_font_override("font", UITheme.bold_font())
	value_label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	value_label.custom_minimum_size = Vector2(72, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(240, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.style_slider(slider)
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
	if UITheme.is_touch():
		# The switch glyph is small; give fingertips a full-height target.
		toggle.custom_minimum_size = Vector2(88, UITheme.TOUCH_MIN_HEIGHT)
	toggle.button_pressed = bool(SettingsManager.get_setting(section, key))
	toggle.toggled.connect(func(pressed_state: bool) -> void:
		SettingsManager.set_setting(section, key, pressed_state))
	UITheme.hook_sounds(toggle)
	row.add_child(toggle)
