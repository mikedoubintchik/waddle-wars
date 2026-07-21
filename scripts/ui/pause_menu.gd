class_name PauseMenu
extends CanvasLayer
## In-race pause overlay with resume / restart / quick settings / quit.

var _panel: Control = null
var _paused: bool = false
var _buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50


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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.14, 0.24, 0.95)
	style.set_corner_radius_all(16)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.6, 0.9)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	box.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

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
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size.x = 200
		slider.value = float(SettingsManager.get_setting("audio", String(bus_info[1])))
		var key := String(bus_info[1])
		slider.value_changed.connect(func(value: float) -> void:
			SettingsManager.set_setting("audio", key, value))
		row.add_child(slider)
	_add_button(vbox, "Quit to Menu", func() -> void:
		get_tree().paused = false
		Game.quit_race_to_menu())
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 52)
	button.add_theme_font_size_override("font_size", 26)
	button.pressed.connect(func() -> void:
		AudioManager.ui_click()
		action.call())
	button.mouse_entered.connect(AudioManager.ui_hover)
	button.focus_entered.connect(AudioManager.ui_hover)
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
