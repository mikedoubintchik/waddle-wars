class_name TouchControls
extends CanvasLayer
## On-screen multitouch controls for phones and tablets (native + mobile web).
## The whole screen is one unified gesture surface — no left/right split. Each
## touch is classified once by its dominant axis after it has travelled
## CLASSIFY_PX: horizontal-dominant touches drive relative-drag steering
## (re-anchoring on direction reversal), vertical-dominant touches are swipe
## gestures — an upward fling (SWIPE_MIN_PX within SWIPE_WINDOW_MS) jumps, a
## downward drag (SWIPE_MIN_PX, any speed) holds slide until the finger lifts.
## Before classification a touch drives nothing, so taps and noise are ignored,
## and a diagonal move only ever feeds its dominant axis. Shove / item buttons
## sit in the bottom-right corner (they win over gestures when a touch starts
## inside them) and a small pause button sits top-right.
##
## All pointer input is routed centrally through InputEventScreenTouch /
## InputEventScreenDrag indices: Godot Buttons only react to mouse events, and
## on touchscreens only touch index 0 is mouse-emulated, so plain Buttons made
## the old implementation effectively single-touch. Tracking indices here lets
## the player steer with one finger while swiping or pressing buttons with
## others. One finger owns steering at a time (first wins) and one finger owns
## the vertical gesture at a time (latest wins).

const MOUSE_TOUCH_INDEX: int = 4096  ## Synthetic index for a real mouse press.
const HIT_MARGIN_PX: float = 14.0    ## Invisible extra hit padding per side.
const BUTTON_SIZE_PX: float = 120.0  ## Action button diameter (logical px).
const PAUSE_SIZE_PX: float = 72.0    ## Pause stays small and out of the way.
const SWIPE_WINDOW_MS: int = 300     ## Jump fling window (from classification).
## Gesture distances as fractions of the viewport SHORT side, so a swipe is
## the same physical thumb travel on a 3x-DPR phone and a desktop window —
## raw pixel constants made phones hypersensitive (24px ~= 2mm at DPR 3).
const CLASSIFY_FRAC: float = 0.022   ## Travel before a touch picks its axis.
const SWIPE_FRAC: float = 0.065      ## Vertical travel that counts as a swipe.
const STEER_RANGE_FRAC: float = 0.24 ## Horizontal drag for full steering lock.
const DOMINANCE: float = 1.35        ## Axis must beat the other by this ratio.
const HINT_VISIBLE_SEC: float = 4.0  ## First-race gesture hint hold time.
const HINT_FADE_SEC: float = 0.6     ## Gesture hint fade-out duration.

var controller: PlayerController = null

var _root: Control = null
## Unclassified touches awaiting axis classification.
## Keyed by touch index; values: {origin: Vector2, ms: int press time}.
var _pending: Dictionary = {}
var _steer_touch_index: int = -1
var _steer_origin: Vector2 = Vector2.ZERO
var _gesture_touch_index: int = -1
var _gesture_origin: Vector2 = Vector2.ZERO
var _gesture_start_ms: int = 0
var _gesture_fired: bool = false    ## Jump fired or slide engaged.
var _gesture_sliding: bool = false  ## Swipe-down slide currently held.
## Entries: {panel: Panel, on_press: Callable, on_hold: Callable, pressed_by: int}.
var _buttons: Array[Dictionary] = []
var _ui_scale: float = 1.0
var _opacity: float = 0.55


func _ready() -> void:
	layer = 10  # Above the HUD (default 1), below the pause menu (50).


func setup(p_controller: PlayerController) -> void:
	controller = p_controller
	_build()
	_maybe_show_gesture_hint()
	if not SettingsManager.setting_changed.is_connected(_on_setting_changed):
		SettingsManager.setting_changed.connect(_on_setting_changed)


## --- Layout ----------------------------------------------------------------

func _build() -> void:
	_release_all()
	_buttons.clear()
	if _root != null:
		_root.queue_free()
		_root = null
	_ui_scale = clampf(float(SettingsManager.get_setting("gameplay", "touch_scale")), 0.5, 2.0)
	_opacity = clampf(float(SettingsManager.get_setting("gameplay", "touch_opacity")), 0.1, 1.0)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Action buttons: bottom-right corner, side by side. Offsets are button
	# centres relative to that corner; the pairwise gap stays >= 16 logical px
	# at scale 1 and every button is well above the 64 px minimum. Jump, slide
	# and steering are full-screen gestures, so only shove and item remain.
	# Buttons win over gestures for touches that start inside their (padded)
	# rects.
	var s := _ui_scale
	_add_button("SHOVE", Vector2(-220, -80) * s, BUTTON_SIZE_PX * s, false,
		func() -> void: controller.touch_shove(), Callable())
	_add_button("ITEM", Vector2(-80, -80) * s, BUTTON_SIZE_PX * s, false,
		func() -> void: controller.touch_item(), Callable())
	# Touch has no modifier to hold, so the over-the-shoulder throw gets its own
	# button. Smaller and set above ITEM: it is the rarer of the two and the
	# corner is already crowded, but it stays clear of ITEM's padded rect.
	_add_button("BACK", Vector2(-80, -80 - BUTTON_SIZE_PX * 0.82) * s,
		BUTTON_SIZE_PX * 0.62 * s, false,
		func() -> void: controller.touch_item_back(), Callable())

	# Pause: small, top-right, kept left of the RaceHUD item panel (which spans
	# offsets -170..-24 from the right edge and does not scale with touch
	# scale) so both stay fully visible.
	_add_button("II", Vector2(-194.0 - PAUSE_SIZE_PX * 0.5 * s, 60.0 * s), PAUSE_SIZE_PX * s, true,
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


## One-time translucent overlay teaching the touch gestures. Gated on the
## "tutorial_prompts" setting (checked before the seen flag is written, so
## re-enabling prompts later still shows the hint once). Shown on the first
## race only; persisted via the gameplay "touch_hints_seen" flag
## (get_setting returns null while the flag has never been written, which
## reads as "not seen"). Fades out after HINT_VISIBLE_SEC.
func _maybe_show_gesture_hint() -> void:
	if GameConfig.is_headless():
		return
	if not bool(SettingsManager.get_setting("gameplay", "tutorial_prompts")):
		return
	if SettingsManager.get_setting("gameplay", "touch_hints_seen") == true:
		return
	SettingsManager.set_setting("gameplay", "touch_hints_seen", true)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.modulate.a = 0.9
	add_child(overlay)  # Direct child of the layer: survives settings rebuilds.

	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.14, 0.8)
	style.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -110
	panel.offset_bottom = 110
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(panel)

	# Drawn arrows, one row each. These used to be typed ▲ ▼ ◄ ► characters,
	# which the bundled font does not carry -- on the web build the hint that
	# teaches the controls opened with three rows of empty boxes.
	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 14)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rows)
	for hint: Array in [
		["up", "swipe up — jump"],
		["down", "swipe down + hold — slide"],
		["both", "drag sideways — steer"],
	]:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(UITheme.arrow_icon(String(hint[0]), 34.0, UITheme.COLOR_ACCENT))
		var text := Label.new()
		text.text = String(hint[1])
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.add_theme_font_size_override("font_size", 28)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(text)
		rows.add_child(row)

	var tween := overlay.create_tween()
	tween.tween_interval(HINT_VISIBLE_SEC)
	tween.tween_property(overlay, "modulate:a", 0.0, HINT_FADE_SEC)
	tween.tween_callback(overlay.queue_free)


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
				and (_steer_touch_index == MOUSE_TOUCH_INDEX
					or _gesture_touch_index == MOUSE_TOUCH_INDEX
					or _pending.has(MOUSE_TOUCH_INDEX)):
			_handle_drag(MOUSE_TOUCH_INDEX, motion.position)


func _handle_point(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		# Buttons win over gestures when the touch starts inside them.
		for button: Dictionary in _buttons:
			if int(button["pressed_by"]) >= 0:
				continue
			var rect := (button["panel"] as Panel).get_global_rect().grow(HIT_MARGIN_PX)
			if rect.has_point(pos):
				_set_button_pressed(button, index)
				return
		# Everything else starts an unclassified touch anywhere on screen; it
		# drives nothing until it travels CLASSIFY_PX and picks an axis.
		_pending[index] = {"origin": pos, "ms": Time.get_ticks_msec()}
	else:
		_pending.erase(index)
		if index == _steer_touch_index:
			_steer_touch_index = -1
			controller.touch_steer = 0.0
		if index == _gesture_touch_index:
			_end_gesture()
		for button: Dictionary in _buttons:
			if int(button["pressed_by"]) == index:
				_set_button_released(button)


func _handle_drag(index: int, pos: Vector2) -> void:
	if index == _steer_touch_index:
		_apply_steer(pos)
		return
	if index == _gesture_touch_index:
		_update_gesture(pos)
		# A finger holding a slide steers too (claimed in _update_gesture).
		if _gesture_sliding and index == _steer_touch_index:
			_apply_steer(pos)
		return
	if not _pending.has(index):
		return
	var entry: Dictionary = _pending[index]
	var origin: Vector2 = entry["origin"]
	var delta := pos - origin
	var classify_px := _short_side() * CLASSIFY_FRAC
	if delta.length() < classify_px:
		return  # Inside the dead zone: taps and noise drive nothing.
	# Classify once by dominant axis; the touch keeps that role for its whole
	# lifetime, so a diagonal move only ever feeds one axis. Near-45-degree
	# moves wait (up to 2x the dead zone) until one axis clearly dominates,
	# which kills the wrong-axis mispicks diagonal noise used to cause.
	var ax := absf(delta.x)
	var ay := absf(delta.y)
	if maxf(ax, ay) < minf(ax, ay) * DOMINANCE and delta.length() < classify_px * 2.0:
		return
	_pending.erase(index)
	if ax >= ay:
		# Horizontal-dominant: steering. First steering finger wins; a second
		# horizontal touch while one is steering becomes inert.
		if _steer_touch_index < 0:
			_steer_touch_index = index
			_steer_origin = origin
			_apply_steer(pos)
	else:
		# Vertical-dominant: jump / slide gesture. Latest finger wins (ending
		# the previous gesture releases any in-progress slide). The fling
		# window starts NOW — measuring from the original press meant a
		# rest-then-flick never registered as a jump.
		_begin_gesture(index, origin, Time.get_ticks_msec())
		_update_gesture(pos)


## Relative-drag steering through the existing steer pipeline. Once the drag
## exceeds the full-lock range the origin re-anchors so reversing direction
## responds immediately.
func _apply_steer(pos: Vector2) -> void:
	var range_px := _short_side() * STEER_RANGE_FRAC
	var dx := pos.x - _steer_origin.x
	if absf(dx) > range_px:
		_steer_origin.x = pos.x - signf(dx) * range_px
		dx = signf(dx) * range_px
	controller.touch_steer = clampf(dx / range_px, -1.0, 1.0)


## Evaluates a vertical-gesture finger: an upward fling within the swipe
## window jumps once; a downward drag of the same distance (any speed) starts
## a slide that _end_gesture releases when the finger lifts.
func _update_gesture(pos: Vector2) -> void:
	if _gesture_fired:
		return
	var swipe_px := _short_side() * SWIPE_FRAC
	var dy := pos.y - _gesture_origin.y
	if dy <= -swipe_px:
		if Time.get_ticks_msec() - _gesture_start_ms <= SWIPE_WINDOW_MS:
			_gesture_fired = true
			controller.touch_jump()
		# Too slow for a jump fling: the touch stays live so dragging back
		# down past the threshold can still start a slide.
	elif dy >= swipe_px:
		_gesture_fired = true
		_gesture_sliding = true
		controller.touch_slide_changed(true)
		# The sliding finger takes over steering when no other finger is
		# already doing it. Belly slides are the fastest, most committed part
		# of a run, and a one-finger player had no way to turn during one
		# without lifting off (playtest: "when sliding on mobile, turning is
		# harder"). Anchor at the current point so the slide itself does not
		# register as steering input.
		if _steer_touch_index < 0:
			_steer_touch_index = _gesture_touch_index
			_steer_origin = pos
			controller.touch_steer = 0.0


## Short side of the visible viewport in event-space pixels — gesture
## thresholds scale with it so thumb travel feels the same on every device.
func _short_side() -> float:
	var vp := get_viewport()
	if vp == null:
		return 1080.0
	var s := vp.get_visible_rect().size
	return minf(s.x, s.y)


## Starts tracking a vertical gesture for the given touch. If another finger
## already owns the gesture, the latest finger wins: the old gesture ends
## first (which releases an in-progress slide).
func _begin_gesture(index: int, origin: Vector2, start_ms: int) -> void:
	_end_gesture()
	_gesture_touch_index = index
	_gesture_origin = origin
	_gesture_start_ms = start_ms


func _end_gesture() -> void:
	if _gesture_sliding and controller != null:
		controller.touch_slide_changed(false)
	# Hand back the steering claim a sliding finger took over.
	if _gesture_touch_index >= 0 and _gesture_touch_index == _steer_touch_index:
		_steer_touch_index = -1
		if controller != null:
			controller.touch_steer = 0.0
	_gesture_touch_index = -1
	_gesture_fired = false
	_gesture_sliding = false


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


## Clears held state (steering + swipe slide + hold buttons + unclassified
## touches). Called when the tree pauses or the app loses focus, because
## release events delivered while this node is paused would otherwise be
## missed and leave inputs stuck.
func _release_all() -> void:
	_pending.clear()
	_steer_touch_index = -1
	if controller != null:
		controller.touch_steer = 0.0
	_end_gesture()
	for button: Dictionary in _buttons:
		if int(button["pressed_by"]) >= 0:
			_set_button_released(button)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all()
