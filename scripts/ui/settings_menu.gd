extends Control
## Settings screen covering the full SettingsManager schema. Rows are grouped
## into Display / Audio / Gameplay / Accessibility / Online cards, each with a
## drawn icon header and its own two-press "Reset" affordance, and every row
## shares one shape: name on the left, current value and its control aligned to
## a common right-hand column. Controls re-read their value from
## SettingsManager.setting_changed, so a section reset — or a change made from
## anywhere else — updates the screen in place instead of rebuilding it.
##
## All authored sizes below are desktop values; UITheme.scaled* enlarges them
## on touch devices only, so the desktop layout is exactly what is written here.

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

const ICON_ONLINE: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<circle cx="32" cy="32" r="24" fill="#1d3a55" stroke="#7fd0f7" stroke-width="3"/>
<path d="M8 32 H56 M32 8 Q44 32 32 56 M32 8 Q20 32 32 56" stroke="#7fd0f7" stroke-width="2.5" fill="none"/>
<path d="M12 20 Q32 30 52 20 M12 44 Q32 34 52 44" stroke="#7fd0f7" stroke-width="2.5" fill="none" opacity="0.7"/>
</svg>"""

## Right-hand column geometry (authored desktop px). Every control lines its
## right edge up on the same axis: sliders and switches sit in CONTROL_WIDTH
## with their readout in VALUE_WIDTH beside them, and pickers/fields simply
## span both so the column edge never jitters between rows.
const VALUE_WIDTH: float = 88.0
const CONTROL_WIDTH: float = 240.0
const WIDE_CONTROL_WIDTH: float = 344.0  # VALUE_WIDTH + CONTROL_WIDTH + ROW_SEPARATION
const ROW_SEPARATION: int = 16
const ROW_HEIGHT: float = 46.0
const CONTROL_HEIGHT: float = 42.0

var _sections: VBoxContainer
var _entrance_items: Array[Control] = []
## "section/key" -> Callable(value) that pushes a stored value back into its
## control. Driven by SettingsManager.setting_changed.
var _refreshers: Dictionary = {}
## Section id whose Reset button is armed for its confirming second press.
var _reset_armed: String = ""
var _reset_buttons: Dictionary = {}  # section id -> Button


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UITheme.screen_margin())
	margin.add_theme_constant_override("margin_right", UITheme.screen_margin())
	margin.add_theme_constant_override("margin_top", UITheme.spacing(28))
	margin.add_theme_constant_override("margin_bottom", UITheme.spacing(28))
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", UITheme.spacing(UITheme.SPACE_S))
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.scaled_int(16))
	layout.add_child(header)
	var title := UITheme.heading("Settings", UITheme.scaled_heading(48))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	var controls_button := UITheme.make_button(
		"Controls", UITheme.scaled_size(Vector2(200, 50)), UITheme.scaled_font(22))
	UITheme.hook_sounds(controls_button)
	controls_button.pressed.connect(func() -> void:
		SceneRouter.go_to("res://scenes/menus/controls.tscn"))
	header.add_child(controls_button)
	var back_button := _make_back_button()
	header.add_child(back_button)
	layout.add_child(UITheme.make_header_rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)

	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", UITheme.spacing(UITheme.SPACE_M))
	scroll.add_child(_sections)

	_entrance_items.append(header)
	_build_display_section()
	_build_audio_section()
	_build_gameplay_section()
	_build_accessibility_section()
	_build_online_section()

	# Closing note plus breathing room so the last card is never flush against
	# the bottom edge of the scroll viewport.
	var footer := UITheme.sub_label("Changes save automatically.", UITheme.scaled_font(18))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sections.add_child(footer)
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0.0, float(UITheme.spacing(UITheme.SPACE_M)))
	_sections.add_child(tail)

	UITheme.play_entrance(self, _entrance_items)

	SettingsManager.setting_changed.connect(_on_setting_changed)
	UITheme.attach_swipe_back(self, _go_back)
	back_button.grab_focus()


## Prominent, icon-led Back: gold text plus the shared chevron so the way out
## reads at a glance on a phone.
func _make_back_button() -> Button:
	var button := UITheme.make_button(
		"Back", UITheme.scaled_size(Vector2(176, 50)), UITheme.scaled_font(23))
	button.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	var icon := UITheme.make_icon(UITheme.ICON_BACK, 1.0)
	if icon != null:
		button.icon = icon
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", UITheme.scaled_int(22))
		button.add_theme_constant_override("h_separation", UITheme.scaled_int(10))
	UITheme.hook_sounds(button)
	button.pressed.connect(_go_back)
	return button


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "accessibility/ui_scale":
		UITheme.apply_ui_scale(self)
	var refresher: Variant = _refreshers.get(key)
	if refresher is Callable:
		(refresher as Callable).call(value)


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()


## --- Section builders -----------------------------------------------------

func _build_display_section() -> void:
	var body := _section("display", "Display", ICON_DISPLAY)
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
	_add_option_row(body, "display", "fps_limit", "FPS Limit", [
		[0, "Uncapped"], [30, "30"], [60, "60"], [120, "120"],
	], true)


func _build_audio_section() -> void:
	var body := _section("audio", "Audio", ICON_AUDIO)
	_add_slider_row(body, "audio", "master_volume", "Master Volume", 0.0, 1.0, 0.05, true)
	_add_slider_row(body, "audio", "music_volume", "Music Volume", 0.0, 1.0, 0.05, true)
	_add_slider_row(body, "audio", "sfx_volume", "SFX Volume", 0.0, 1.0, 0.05, true)
	_add_toggle_row(body, "audio", "muted", "Mute All")
	_add_toggle_row(body, "audio", "mute_unfocused", "Mute When Unfocused")


func _build_gameplay_section() -> void:
	var body := _section("gameplay", "Gameplay", ICON_GAMEPLAY)
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
	var body := _section("accessibility", "Accessibility", ICON_ACCESSIBILITY)
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


func _build_online_section() -> void:
	var body := _section("online", "Online", ICON_ONLINE)
	_add_text_row(body, "online", "display_name", "Leaderboard Name", "2-20 letters/numbers")
	var status := UITheme.sub_label(_account_status(), UITheme.scaled_font(18))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)


## One-line description of the leaderboard account state, so the Online section
## explains what the name is actually for.
func _account_status() -> String:
	if not LeaderboardClient.can_sign_in():
		return "Play the web version to sign in and post times."
	if LeaderboardClient.signed_in:
		return "Signed in as %s — times post to the global boards." % LeaderboardClient.display_name
	return "Sign in from the Leaderboard screen to post times and back up progress."


## --- Section / row helpers ------------------------------------------------

## Builds a section card and returns the VBox its rows go into. `section` is
## the SettingsManager section id, which is also what the card's Reset button
## restores to defaults.
func _section(section: String, section_title: String, icon_svg: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := UITheme.make_panel_style()
	style.content_margin_left = UITheme.scaled(26.0)
	style.content_margin_right = UITheme.scaled(26.0)
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
	header.add_theme_constant_override("separation", UITheme.scaled_int(12))
	body.add_child(header)
	if icon_svg != "":
		var texture := UITheme.make_icon(icon_svg, 1.0)
		if texture != null:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.custom_minimum_size = Vector2(UITheme.scaled(30.0), UITheme.scaled(30.0))
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			header.add_child(icon)
	var label := Label.new()
	label.text = section_title
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", UITheme.scaled_heading(28))
	label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(label)

	var reset := UITheme.make_button(
		"Reset", UITheme.scaled_size(Vector2(150, 40)), UITheme.scaled_font(19))
	UITheme.hook_sounds(reset)
	reset.pressed.connect(_on_reset_pressed.bind(section))
	_reset_buttons[section] = reset
	header.add_child(reset)

	var rule := ColorRect.new()
	rule.color = Color(UITheme.COLOR_ACCENT, 0.28)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rule)
	UITheme.animate_rule(rule)
	return body


## Restoring a whole section is easy to hit by accident and undoes several
## choices at once, so the first press arms the button and the second commits —
## the same two-press pattern the shop and the pause menu use.
func _on_reset_pressed(section: String) -> void:
	if _reset_armed != section:
		_disarm_resets()
		_reset_armed = section
		var button: Button = _reset_buttons[section]
		button.text = "Confirm?"
		button.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
		return
	_disarm_resets()
	var defaults: Dictionary = SettingsManager.default_settings().get(section, {})
	for key: Variant in defaults.keys():
		SettingsManager.set_setting(section, String(key), defaults[key])


func _disarm_resets() -> void:
	_reset_armed = ""
	for section: String in _reset_buttons.keys():
		var button: Button = _reset_buttons[section]
		if not is_instance_valid(button):
			continue
		button.text = "Reset"
		button.add_theme_color_override("font_color", UITheme.COLOR_TEXT)


## Shared row shell: the setting's name fills the left, and callers append the
## readout and control that make up the aligned right-hand column.
func _row(parent: VBoxContainer, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.scaled_int(ROW_SEPARATION))
	row.custom_minimum_size = Vector2(0.0, UITheme.scaled_size(Vector2(0.0, ROW_HEIGHT)).y)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", UITheme.scaled_font(21))
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Wrap rather than truncate: on a 4:3 tablet the right-hand column leaves
	# the longest setting names (Pause On Controller Disconnect) short of room.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	return row


## Always-visible readout for controls that do not render their own value.
func _value_label() -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UITheme.bold_font())
	label.add_theme_font_size_override("font_size", UITheme.scaled_font(19))
	label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	label.custom_minimum_size = Vector2(UITheme.scaled(VALUE_WIDTH), 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## Picker row. `options` is an array of [stored_value, label] pairs; set
## `as_int` for keys stored as integers (fps_limit).
func _add_option_row(parent: VBoxContainer, section: String, key: String,
		label_text: String, options: Array, as_int: bool = false) -> void:
	var row := _row(parent, label_text)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(
		UITheme.scaled(WIDE_CONTROL_WIDTH),
		UITheme.scaled_size(Vector2(0.0, CONTROL_HEIGHT)).y)
	picker.add_theme_font_size_override("font_size", UITheme.scaled_font(19))
	UITheme.style_option_button(picker)
	for i: int in options.size():
		var pair: Array = options[i]
		picker.add_item(String(pair[1]), i)
	# select() never emits item_selected, so the refresher cannot loop back
	# into set_setting.
	var apply := func(value: Variant) -> void:
		for i: int in options.size():
			var pair: Array = options[i]
			var matches := int(pair[0]) == int(value) if as_int else String(pair[0]) == String(value)
			if matches:
				picker.select(i)
				return
	apply.call(SettingsManager.get_setting(section, key))
	picker.item_selected.connect(func(index: int) -> void:
		AudioManager.ui_click()
		_disarm_resets()
		var chosen: Variant = int(options[index][0]) if as_int else String(options[index][0])
		SettingsManager.set_setting(section, key, chosen))
	picker.mouse_entered.connect(AudioManager.ui_hover)
	picker.focus_entered.connect(AudioManager.ui_hover)
	row.add_child(picker)
	_refreshers["%s/%s" % [section, key]] = apply


func _add_slider_row(parent: VBoxContainer, section: String, key: String, label_text: String,
		min_value: float, max_value: float, step: float, as_percent: bool) -> void:
	var row := _row(parent, label_text)
	var value_label := _value_label()
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(
		UITheme.scaled(CONTROL_WIDTH),
		UITheme.scaled_size(Vector2(0.0, 32.0)).y)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.style_slider(slider)
	var format := func(amount: float) -> String:
		return "%d%%" % int(round(amount * 100.0)) if as_percent else "%.2f" % amount
	var apply := func(value: Variant) -> void:
		slider.set_value_no_signal(float(value))
		value_label.text = String(format.call(slider.value))
	apply.call(SettingsManager.get_setting(section, key))
	slider.value_changed.connect(func(new_value: float) -> void:
		value_label.text = String(format.call(new_value))
		_disarm_resets()
		SettingsManager.set_setting(section, key, new_value))
	slider.mouse_entered.connect(AudioManager.ui_hover)
	slider.focus_entered.connect(AudioManager.ui_hover)
	slider.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			AudioManager.ui_click())
	row.add_child(value_label)
	row.add_child(slider)
	_refreshers["%s/%s" % [section, key]] = apply


func _add_toggle_row(parent: VBoxContainer, section: String, key: String, label_text: String) -> void:
	var row := _row(parent, label_text)
	var value_label := _value_label()
	var toggle := CheckButton.new()
	# CheckButton draws its switch flush to the right of its rect, so giving it
	# the full control width parks the switch on the shared column edge.
	toggle.custom_minimum_size = Vector2(
		UITheme.scaled(CONTROL_WIDTH),
		UITheme.scaled_size(Vector2(0.0, CONTROL_HEIGHT)).y)
	var apply := func(value: Variant) -> void:
		var enabled := bool(value)
		toggle.set_pressed_no_signal(enabled)
		value_label.text = "On" if enabled else "Off"
		value_label.add_theme_color_override("font_color",
			UITheme.COLOR_ACCENT if enabled else UITheme.COLOR_TEXT_DIM)
	apply.call(SettingsManager.get_setting(section, key))
	toggle.toggled.connect(func(pressed_state: bool) -> void:
		apply.call(pressed_state)
		_disarm_resets()
		SettingsManager.set_setting(section, key, pressed_state))
	UITheme.hook_sounds(toggle)
	row.add_child(value_label)
	row.add_child(toggle)
	_refreshers["%s/%s" % [section, key]] = apply


## Free-text row (leaderboard display name). Commits on Enter and on focus
## loss so a player who just taps Back still keeps what they typed.
func _add_text_row(parent: VBoxContainer, section: String, key: String,
		label_text: String, placeholder: String) -> void:
	var row := _row(parent, label_text)
	var edit := LineEdit.new()
	edit.max_length = 20
	edit.placeholder_text = placeholder
	edit.text = String(SettingsManager.get_setting(section, key))
	edit.custom_minimum_size = Vector2(
		UITheme.scaled(WIDE_CONTROL_WIDTH),
		UITheme.scaled_size(Vector2(0.0, CONTROL_HEIGHT)).y)
	edit.add_theme_font_size_override("font_size", UITheme.scaled_font(19))
	var commit := func() -> void:
		var wanted := edit.text.strip_edges()
		if wanted == String(SettingsManager.get_setting(section, key)):
			return
		_disarm_resets()
		SettingsManager.set_setting(section, key, wanted)
	edit.text_submitted.connect(func(_text: String) -> void:
		AudioManager.ui_click()
		commit.call())
	edit.focus_exited.connect(commit)
	row.add_child(edit)
	# Never fight the player mid-word: an external change only lands while the
	# field is idle.
	var apply := func(value: Variant) -> void:
		if not edit.has_focus():
			edit.text = String(value)
	_refreshers["%s/%s" % [section, key]] = apply
