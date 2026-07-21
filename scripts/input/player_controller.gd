class_name PlayerController
extends RacerController
## Maps keyboard / gamepad / touch input to racer intents.
## Touch buttons call the public touch_* methods from TouchControls.

var touch_steer: float = 0.0
var _touch_jump: bool = false
var _touch_slide: bool = false
var _touch_shove: bool = false
var _touch_item: bool = false
var _slide_toggled: bool = false
var _smoothed_steer: float = 0.0
var input_enabled: bool = true


func tick(delta: float) -> void:
	if not input_enabled:
		steer = 0.0
		slide_held = false
		return
	var raw := Input.get_axis("steer_left", "steer_right")
	if absf(touch_steer) > 0.05:
		raw = clampf(raw + touch_steer, -1.0, 1.0)
	# Keyboard input benefits from smoothing; analog passes through.
	var smooth_rate := 9.0 if absf(raw) > absf(_smoothed_steer) else 12.0
	_smoothed_steer = move_toward(_smoothed_steer, raw, smooth_rate * delta)
	steer = _smoothed_steer

	if Input.is_action_just_pressed("jump") or _touch_jump:
		jump_pressed = true
		_touch_jump = false
	jump_held = Input.is_action_pressed("jump")

	var toggle_mode := bool(SettingsManager.get_setting("gameplay", "slide_toggle_mode"))
	if toggle_mode:
		if Input.is_action_just_pressed("slide"):
			_slide_toggled = not _slide_toggled
		slide_held = _slide_toggled or _touch_slide
	else:
		slide_held = Input.is_action_pressed("slide") or _touch_slide

	if Input.is_action_just_pressed("shove") or _touch_shove:
		shove_pressed = true
		_touch_shove = false
	if Input.is_action_just_pressed("use_item") or _touch_item:
		item_pressed = true
		_touch_item = false


func touch_jump() -> void:
	_touch_jump = true


func touch_slide_changed(held: bool) -> void:
	_touch_slide = held


func touch_shove() -> void:
	_touch_shove = true


func touch_item() -> void:
	_touch_item = true
