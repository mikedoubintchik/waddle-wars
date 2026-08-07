class_name PlayerController
extends RacerController
## Maps keyboard / gamepad / touch input to racer intents.
## Touch buttons call the public touch_* methods from TouchControls.

var touch_steer: float = 0.0
var _touch_jump: bool = false
var _touch_slide: bool = false
var _touch_shove: bool = false
var _touch_item: bool = false
var _touch_item_back: bool = false
var _touch_aim_back: bool = false
var _slide_toggled: bool = false
var _smoothed_steer: float = 0.0
var input_enabled: bool = true
## Lean-to-steer, created on demand when the setting is on (see _tilt_axis).
var _tilt: TiltSteering = null


func tick(delta: float) -> void:
	if not input_enabled:
		steer = 0.0
		slide_held = false
		return
	var raw := Input.get_axis("steer_left", "steer_right")
	if absf(touch_steer) > 0.05:
		raw = clampf(raw + touch_steer, -1.0, 1.0)
	elif is_zero_approx(raw):
		# Tilt is the fallback, never the override: a finger on the screen or a
		# hand on the keyboard always wins. That ordering is what makes it safe
		# to leave both enabled -- a player who finds the lean awkward mid-race
		# can just start dragging and the phone stops steering for them.
		raw = _tilt_axis(delta)
	# Racer yaw math: +steer_offset = +yaw = world-LEFT (-sin), so the raw
	# axis (left=-1/right=+1) must be negated for the player. AI generates
	# steer in the racer's native convention already — do not "fix" it there.
	raw = -raw
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
	aim_back = Input.is_action_pressed("aim_back") or _touch_aim_back
	if Input.is_action_just_pressed("use_item") or _touch_item:
		item_pressed = true
		_touch_item = false
	if _touch_item_back:
		item_pressed = true
		aim_back = true
		_touch_item_back = false


## Steering from the phone's lean, or 0.0 when tilt is off or unavailable.
##
## The reader is built lazily and torn down when the setting goes off, so a
## desktop or a player who never enables it pays nothing -- not even the
## JavaScript shim.
func _tilt_axis(delta: float) -> float:
	if not bool(SettingsManager.get_setting("gameplay", "tilt_steering")):
		if _tilt != null:
			_tilt.queue_free()
			_tilt = null
		return 0.0
	if not TiltSteering.supported():
		return 0.0
	if _tilt == null:
		_tilt = TiltSteering.new()
		_tilt.name = "TiltSteering"
		Engine.get_main_loop().root.add_child(_tilt)
	return _tilt.poll(delta)


## Re-reads the neutral pose. Called when a race starts, because how the player
## is holding the phone on the grid is the pose they mean by "straight ahead".
func recalibrate_tilt() -> void:
	if _tilt != null:
		_tilt.recalibrate()


func touch_jump() -> void:
	_touch_jump = true


func touch_slide_changed(held: bool) -> void:
	_touch_slide = held


func touch_shove() -> void:
	_touch_shove = true


func touch_item() -> void:
	_touch_item = true


## Touch has no modifier key to hold, so the back-throw is its own button and
## fires the item in one action rather than arming a mode.
func touch_item_back() -> void:
	_touch_item_back = true
