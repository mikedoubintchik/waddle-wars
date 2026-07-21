class_name TouchControls
extends CanvasLayer
## On-screen touch controls: left steering zone (horizontal drag) and right
## action buttons. Only shown when touch controls are enabled in settings.

var controller: PlayerController = null

var _steer_zone: Control
var _steer_origin: Vector2 = Vector2.ZERO
var _steer_touch_index: int = -1
var _root: Control


func setup(p_controller: PlayerController) -> void:
	controller = p_controller
	var ui_scale := float(SettingsManager.get_setting("gameplay", "touch_scale"))
	var opacity := float(SettingsManager.get_setting("gameplay", "touch_opacity"))
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Steering zone: left 40% of the screen.
	_steer_zone = Control.new()
	_steer_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	_steer_zone.anchor_right = 0.42
	_steer_zone.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_steer_zone)
	var hint := Label.new()
	hint.text = "◄ drag ►"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.anchor_top = 0.85
	hint.anchor_bottom = 0.85
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.offset_left = -70
	hint.offset_right = 70
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = opacity * 0.6
	hint.add_theme_font_size_override("font_size", 22)
	_steer_zone.add_child(hint)

	var size := 92.0 * ui_scale
	_add_action_button("JUMP", Vector2(-30 - size, -30 - size), size, opacity,
		func() -> void: controller.touch_jump(), Callable())
	_add_action_button("SLIDE", Vector2(-30 - size * 2.2, -30), size, opacity,
		Callable(), func(held: bool) -> void: controller.touch_slide_changed(held))
	_add_action_button("SHOVE", Vector2(-30 - size * 2.2, -30 - size * 1.6), size, opacity,
		func() -> void: controller.touch_shove(), Callable())
	_add_action_button("ITEM", Vector2(-30, -30 - size * 2.2), size, opacity,
		func() -> void: controller.touch_item(), Callable())

	# Pause button top right.
	var pause_button := Button.new()
	pause_button.text = "II"
	pause_button.custom_minimum_size = Vector2(64, 64) * ui_scale
	pause_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_button.position = Vector2(-100, 100)
	pause_button.modulate.a = opacity
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(func() -> void:
		var event := InputEventAction.new()
		event.action = "pause"
		event.pressed = true
		Input.parse_input_event(event))
	_root.add_child(pause_button)


func _add_action_button(text: String, offset: Vector2, size: float, opacity: float, on_press: Callable, on_hold: Callable) -> void:
	var control_button := Button.new()
	control_button.text = text
	control_button.custom_minimum_size = Vector2(size, size)
	control_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	control_button.position = Vector2(offset.x - size * 0.0, offset.y - size)
	control_button.anchor_left = 1.0
	control_button.anchor_top = 1.0
	control_button.anchor_right = 1.0
	control_button.anchor_bottom = 1.0
	control_button.offset_left = offset.x - size
	control_button.offset_top = offset.y - size
	control_button.offset_right = offset.x
	control_button.offset_bottom = offset.y
	control_button.modulate.a = opacity
	control_button.focus_mode = Control.FOCUS_NONE
	control_button.add_theme_font_size_override("font_size", int(size * 0.24))
	if on_press.is_valid():
		control_button.button_down.connect(on_press)
	if on_hold.is_valid():
		control_button.button_down.connect(func() -> void: on_hold.call(true))
		control_button.button_up.connect(func() -> void: on_hold.call(false))
	_root.add_child(control_button)


func _input(event: InputEvent) -> void:
	if controller == null or _steer_zone == null:
		return
	var zone_rect := _steer_zone.get_global_rect()
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and zone_rect.has_point(touch.position) and _steer_touch_index < 0:
			_steer_touch_index = touch.index
			_steer_origin = touch.position
		elif not touch.pressed and touch.index == _steer_touch_index:
			_steer_touch_index = -1
			controller.touch_steer = 0.0
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _steer_touch_index:
			var dx := (drag.position.x - _steer_origin.x) / 140.0
			controller.touch_steer = clampf(dx, -1.0, 1.0)
