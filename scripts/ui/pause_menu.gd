class_name PauseMenu
extends CanvasLayer
## In-race pause overlay with resume / restart / quick settings / quit.

var _panel: Control = null
var _paused: bool = false
var _buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if not connected and not _paused and not GameConfig.is_headless() \
			and bool(SettingsManager.get_setting("accessibility", "pause_on_disconnect")):
		_open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _paused:
		_close()
	else:
		_open()


func _open() -> void:
	_paused = true
	get_tree().paused = true
	AudioManager.ui_click()
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.1, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
	var box := PanelContainer.new()
	var style := UITheme.make_panel_style(Color(0.06, 0.108, 0.19, 0.96), Color(UITheme.COLOR_ACCENT, 0.55))
	style.set_corner_radius_all(18)
	style.content_margin_left = 44.0
	style.content_margin_right = 44.0
	style.content_margin_top = 30.0
	style.content_margin_bottom = 30.0
	style.shadow_size = 14
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	box.add_child(vbox)

	var title := UITheme.heading("Paused", 44)
	vbox.add_child(title)
	vbox.add_child(UITheme.accent_rule(180.0))

	_buttons.clear()
	_add_button(vbox, "Resume", _close)
	_add_button(vbox, "Restart Race", func() -> void:
		get_tree().paused = false
		SceneRouter.go_to(Game.SCENE_RACE))
	# Quick volume sliders.
	for bus_info: Array in [["Music", "music_volume"], ["Sound", "sfx_volume"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)
		var label := Label.new()
		label.text = bus_info[0]
		label.custom_minimum_size.x = 90
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size.x = 200
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UITheme.style_slider(slider)
		slider.value = float(SettingsManager.get_setting("audio", String(bus_info[1])))
		var key := String(bus_info[1])
		slider.value_changed.connect(func(value: float) -> void:
			SettingsManager.set_setting("audio", key, value))
		row.add_child(slider)
	_add_button(vbox, "Quit to Menu", func() -> void:
		get_tree().paused = false
		Game.quit_race_to_menu())
	# Edge swipe resumes, mirroring the Resume button for touch players.
	UITheme.attach_swipe_back(_panel, _close)
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := UITheme.make_button(text, Vector2(280, 52), 26)
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)


func _close() -> void:
	_paused = false
	get_tree().paused = false
	if _panel != null:
		_panel.queue_free()
		_panel = null


func _notification(what: int) -> void:
	# Auto-pause when focus is lost or a controller disconnects mid-race.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _paused and is_inside_tree():
		if not GameConfig.is_headless():
			_open()
