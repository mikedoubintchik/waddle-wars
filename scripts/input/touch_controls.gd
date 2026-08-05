class_name TouchControls
extends CanvasLayer
## On-screen multitouch controls for phones and tablets (native + mobile web).
## Left half of the screen is a relative-drag steering zone; jump / slide /
## shove / item sit in an arc around the bottom-right corner and a small pause
## button sits top-right.
##
## All pointer input is routed centrally through InputEventScreenTouch /
## InputEventScreenDrag indices: Godot Buttons only react to mouse events, and
## on touchscreens only touch index 0 is mouse-emulated, so plain Buttons made
## the old implementation effectively single-touch. Tracking indices here lets
## the player steer with one finger while pressing buttons with others.

const MOUSE_TOUCH_INDEX: int = 4096  ## Synthetic index for a real mouse press.
const STEER_RANGE_PX: float = 150.0  ## Drag distance for full steering lock.
const HIT_MARGIN_PX: float = 14.0    ## Invisible extra hit padding per side.
const BUTTON_SIZE_PX: float = 120.0  ## Action button diameter (logical px).
const JUMP_SIZE_PX: float = 150.0    ## Jump is the primary action: bigger.
const PAUSE_SIZE_PX: float = 72.0    ## Pause stays small and out of the way.

var controller: PlayerController = null

var _root: Control = null
var _steer_zone: Control = null
var _steer_touch_index: int = -1
var _steer_origin: Vector2 = Vector2.ZERO
## Entries: {panel: Panel, on_press: Callable, on_hold: Callable, pressed_by: int}.
var _buttons: Array[Dictionary] = []
var _ui_scale: float = 1.0
var _opacity: float = 0.55


func _ready() -> void:
	layer = 10  # Above the HUD (default 1), below the pause menu (50).


func setup(p_controller: PlayerController) -> void:
	controller = p_controller
	_build()
	if not SettingsManager.setting_changed.is_connected(_on_setting_changed):
		SettingsManager.setting_changed.connect(_on_setting_changed)


## --- Layout ----------------------------------------------------------------

func _build() -> void:
	_release_all()
	_buttons.clear()
	if _root != null:
		_root.queue_free()
		_root = null
		_steer_zone = null
	_ui_scale = clampf(float(SettingsManager.get_setting("gameplay", "touch_scale")), 0.5, 2.0)
	_opacity = clampf(float(SettingsManager.get_setting("gameplay", "touch_opacity")), 0.1, 1.0)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Steering zone: left half of the screen, relative horizontal drag.
	_steer_zone = Control.new()
	_steer_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	_steer_zone.anchor_right = 0.5
	_steer_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_steer_zone)
	var hint := Label.new()
	hint.text = "◄ drag to steer ►"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.anchor_top = 0.85
	hint.anchor_bottom = 0.85
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.offset_left = -140
	hint.offset_right = 140
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = _opacity * 0.6
	hint.add_theme_font_size_override("font_size", 26)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_steer_zone.add_child(hint)

	# Action buttons: arc around the bottom-right corner. Offsets are button
	# centres relative to that corner; every pairwise gap stays >= 16 logical
	# px at scale 1 and every button is well above the 64 px minimum.
	var s := _ui_scale
	_add_button("JUMP", Vector2(-110, -110) * s, JUMP_SIZE_PX * s, false,
		func() -> void: controller.touch_jump(), Callable())
	_add_button("SLIDE", Vector2(-300, -80) * s, BUTTON_SIZE_PX * s, false,
		Callable(), func(held: bool) -> void: controller.touch_slide_changed(held))
	_add_button("SHOVE", Vector2(-260, -260) * s, BUTTON_SIZE_PX * s, false,
		func() -> void: controller.touch_shove(), Callable())
	_add_button("ITEM", Vector2(-80, -300) * s, BUTTON_SIZE_PX * s, false,
		func() -> void: controller.touch_item(), Callable())

	# Pause: small, top-right, clear of the action cluster.
	_add_button("II", Vector2(-60, 60) * s, PAUSE_SIZE_PX * s, true,
		_press_pause, Callable())


func _add_button(text: String, center: Vector2, size: float, top_anchor: bool,
		on_press: Callable, on_hold: Callable) -> void:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.10, 0.17, 0.85)
	style.set_corner_radius_all(int(size * 0.5))
	style.set_border_width_all(3)
	style.border_color = Color(1.0, 1.0, 1.0, 0.55)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var anchor_y := 0.0 if top_anchor else 1.0
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = anchor_y
	panel.anchor_bottom = anchor_y
	panel.offset_left = center.x - size * 0.5
	panel.offset_right = center.x + size * 0.5
	panel.offset_top = center.y - size * 0.5
	panel.offset_bottom = center.y + size * 0.5
	panel.modulate = Color(1.0, 1.0, 1.0, _opacity)
	var label := Label.new()
	label.text = text
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(20, int(size * 0.22)))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	_root.add_child(panel)
	_buttons.append({
		"panel": panel,
		"on_press": on_press,
		"on_hold": on_hold,
		"pressed_by": -1,
	})


func _press_pause() -> void:
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	Input.parse_input_event(event)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "gameplay/touch_scale" or key == "gameplay/touch_opacity":
		_build()


## --- Input routing (multitouch-safe) ---------------------------------------

func _input(event: InputEvent) -> void:
	if controller == null or _root == null:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_handle_point(touch.index, touch.position, touch.pressed)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_handle_drag(drag.index, drag.position)
	elif event is InputEventMouseButton:
		# Real mouse fallback (touch laptops / desktop testing). Emulated
		# mouse events from touch index 0 are skipped to avoid doubling.
		var mouse := event as InputEventMouseButton
		if mouse.device != InputEvent.DEVICE_ID_EMULATION \
				and mouse.button_index == MOUSE_BUTTON_LEFT:
			_handle_point(MOUSE_TOUCH_INDEX, mouse.position, mouse.pressed)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.device != InputEvent.DEVICE_ID_EMULATION \
				and _steer_touch_index == MOUSE_TOUCH_INDEX:
			_handle_drag(MOUSE_TOUCH_INDEX, motion.position)


func _handle_point(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		for button: Dictionary in _buttons:
			if int(button["pressed_by"]) >= 0:
				continue
			var rect := (button["panel"] as Panel).get_global_rect().grow(HIT_MARGIN_PX)
			if rect.has_point(pos):
				_set_button_pressed(button, index)
				return
		if _steer_touch_index < 0 and _steer_zone.get_global_rect().has_point(pos):
			_steer_touch_index = index
			_steer_origin = pos
	else:
		if index == _steer_touch_index:
			_steer_touch_index = -1
			controller.touch_steer = 0.0
		for button: Dictionary in _buttons:
			if int(button["pressed_by"]) == index:
				_set_button_released(button)


func _handle_drag(index: int, pos: Vector2) -> void:
	if index != _steer_touch_index:
		return
	var dx := pos.x - _steer_origin.x
	if absf(dx) > STEER_RANGE_PX:
		# Re-anchor so reversing direction responds immediately.
		_steer_origin.x = pos.x - signf(dx) * STEER_RANGE_PX
		dx = signf(dx) * STEER_RANGE_PX
	controller.touch_steer = clampf(dx / STEER_RANGE_PX, -1.0, 1.0)


func _set_button_pressed(button: Dictionary, index: int) -> void:
	button["pressed_by"] = index
	(button["panel"] as Panel).modulate = Color(1.35, 1.35, 1.35, minf(1.0, _opacity + 0.3))
	var on_press: Callable = button["on_press"]
	if on_press.is_valid():
		on_press.call()
	var on_hold: Callable = button["on_hold"]
	if on_hold.is_valid():
		on_hold.call(true)


func _set_button_released(button: Dictionary) -> void:
	button["pressed_by"] = -1
	(button["panel"] as Panel).modulate = Color(1.0, 1.0, 1.0, _opacity)
	var on_hold: Callable = button["on_hold"]
	if on_hold.is_valid():
		on_hold.call(false)


## Clears held state (steering + hold buttons). Called when the tree pauses or
## the app loses focus, because release events delivered while this node is
## paused would otherwise be missed and leave inputs stuck.
func _release_all() -> void:
	_steer_touch_index = -1
	if controller != null:
		controller.touch_steer = 0.0
	for button: Dictionary in _buttons:
		if int(button["pressed_by"]) >= 0:
			_set_button_released(button)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all()
