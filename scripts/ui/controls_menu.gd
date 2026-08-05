extends Control
## Control remapping screen. Lists every remappable action with its keyboard
## and gamepad bindings; pressing a binding cell enters capture mode.

const ACTION_NAMES: Dictionary = {
	"steer_left": "Steer Left",
	"steer_right": "Steer Right",
	"jump": "Jump",
	"slide": "Slide",
	"shove": "Flipper Shove",
	"use_item": "Use Item",
	"pause": "Pause",
}

var _capturing_action: String = ""
var _capturing_family: String = ""
var _capture_started_at: int = 0
var _capture_overlay: PanelContainer
var _capture_label: Label
var _binding_buttons: Dictionary = {}  # "action/family" -> Button
var _first_button: Button


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UITheme.SCREEN_MARGIN)
	margin.add_theme_constant_override("margin_right", UITheme.SCREEN_MARGIN)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	layout.add_child(header)
	var title := UITheme.heading("Controls", 48)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	var reset_button := UITheme.make_button("Reset to Defaults", Vector2(240, 48), 20)
	UITheme.hook_sounds(reset_button)
	reset_button.pressed.connect(_on_reset_pressed)
	header.add_child(reset_button)
	var back_button := UITheme.make_button("Back", Vector2(160, 48), 22)
	UITheme.hook_sounds(back_button)
	back_button.pressed.connect(_go_back)
	header.add_child(back_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	var header_row := _make_row(list)
	var header_panel := header_row.get_parent() as PanelContainer
	var header_style := UITheme.make_panel_style(Color(0.055, 0.098, 0.172, 0.9), Color(UITheme.COLOR_ACCENT, 0.4))
	header_style.content_margin_top = 10.0
	header_style.content_margin_bottom = 10.0
	header_panel.add_theme_stylebox_override("panel", header_style)
	for header_text: String in ["Action", "Keyboard", "Gamepad"]:
		var cell := _cell_label(header_text, UITheme.COLOR_ACCENT, 24)
		cell.add_theme_font_override("font", UITheme.display_font())
		header_row.add_child(cell)

	for action: String in SettingsManager.REMAPPABLE_ACTIONS:
		var row := _make_row(list)
		row.add_child(_cell_label(String(ACTION_NAMES.get(action, action)), UITheme.COLOR_TEXT, 21))
		row.add_child(_make_binding_button(action, "key"))
		row.add_child(_make_binding_button(action, "joy"))

	var touch_panel := PanelContainer.new()
	touch_panel.add_theme_stylebox_override("panel", UITheme.make_panel_style())
	list.add_child(touch_panel)
	var touch_box := VBoxContainer.new()
	touch_box.add_theme_constant_override("separation", 4)
	touch_panel.add_child(touch_box)
	var touch_title := Label.new()
	touch_title.text = "Touch"
	touch_title.add_theme_font_size_override("font_size", 24)
	touch_title.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	touch_box.add_child(touch_title)
	for hint: String in [
		"Steer: left / right screen halves or on-screen stick",
		"Jump: JUMP button    Slide: SLIDE button",
		"Shove: SHOVE button    Item: ITEM button",
		"Pause: pause icon, top corner",
	]:
		touch_box.add_child(UITheme.sub_label(hint, 19))

	_build_capture_overlay()
	if _first_button != null:
		_first_button.grab_focus()


func _make_row(parent: VBoxContainer) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.make_panel_style(Color(0.106, 0.180, 0.298, 0.7)))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	return row


func _cell_label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_binding_button(action: String, family: String) -> Button:
	var button := UITheme.make_button(SettingsManager.describe_action_binding(action, family), Vector2(220, 44), 19)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.hook_sounds(button)
	button.pressed.connect(_begin_capture.bind(action, family))
	_binding_buttons["%s/%s" % [action, family]] = button
	if _first_button == null:
		_first_button = button
	return button


func _build_capture_overlay() -> void:
	_capture_overlay = PanelContainer.new()
	_capture_overlay.add_theme_stylebox_override("panel", UITheme.make_panel_style(Color(0.04, 0.08, 0.15, 0.97), UITheme.COLOR_GOLD))
	_capture_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_capture_overlay.visible = false
	_capture_overlay.z_index = 10
	add_child(_capture_overlay)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_capture_overlay.add_child(box)
	_capture_label = Label.new()
	_capture_label.add_theme_font_size_override("font_size", 28)
	_capture_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_capture_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_capture_label)
	var hint := UITheme.sub_label("Esc cancels", 19)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _begin_capture(action: String, family: String) -> void:
	_capturing_action = action
	_capturing_family = family
	_capture_started_at = Time.get_ticks_msec()
	var device := "key" if family == "key" else "gamepad button or stick"
	_capture_label.text = "Press any %s for  %s" % [device, String(ACTION_NAMES.get(action, action))]
	_capture_overlay.visible = true
	_capture_overlay.reset_size()
	_capture_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if _capturing_action == "":
		return
	if Time.get_ticks_msec() - _capture_started_at < 150:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key_event := event as InputEventKey
		get_viewport().set_input_as_handled()
		if key_event.echo:
			return
		if key_event.keycode == KEY_ESCAPE:
			_end_capture()
			return
		if _capturing_family == "key":
			SettingsManager.rebind_action(_capturing_action, key_event.duplicate())
			_finish_capture()
		return
	if _capturing_family == "joy":
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
			get_viewport().set_input_as_handled()
			SettingsManager.rebind_action(_capturing_action, event.duplicate())
			_finish_capture()
		elif event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			if absf(motion.axis_value) > 0.6:
				get_viewport().set_input_as_handled()
				var captured := InputEventJoypadMotion.new()
				captured.axis = motion.axis
				captured.axis_value = 1.0 if motion.axis_value > 0.0 else -1.0
				SettingsManager.rebind_action(_capturing_action, captured)
				_finish_capture()


func _finish_capture() -> void:
	AudioManager.ui_click()
	_end_capture()
	_refresh_all_bindings()


func _end_capture() -> void:
	_capturing_action = ""
	_capturing_family = ""
	_capture_overlay.visible = false


func _refresh_all_bindings() -> void:
	for keypath: String in _binding_buttons.keys():
		var parts := keypath.split("/")
		var button: Button = _binding_buttons[keypath]
		button.text = SettingsManager.describe_action_binding(parts[0], parts[1])


func _on_reset_pressed() -> void:
	SettingsManager.reset_bindings()
	_refresh_all_bindings()


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_SETTINGS)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()
