extends Control
## Control remapping screen.
##
## Same language as Settings and the results screen: eyebrow + headline hero, a
## centered column, cards at radius 18 titled with an accent tick and an
## uppercase tracked caption, rows at radius 10 with a faint zebra, and one
## promoted primary action — Back.
##
## Bindings read as keycaps: compact, fixed-width chips in a real column, so a
## glance down the screen reads as a keyboard rather than as a wall of buttons.
## Pressing one opens a calm full-screen capture state (scrim, the action being
## rebound, how to cancel) and the chip itself shows that it is listening.
## Duplicate bindings are called out on the chips and named underneath, because
## InputMap will happily fire two actions from one key.

const ACTION_NAMES: Dictionary = {
	"steer_left": "Steer Left",
	"steer_right": "Steer Right",
	"jump": "Jump",
	"slide": "Slide",
	"shove": "Flipper Shove",
	"use_item": "Use Item",
	"aim_back": "Aim Behind (hold)",
	"pause": "Pause",
}

## One short line per action, so the label column explains the verb instead of
## leaving a gap between the name and its keycaps.
const ACTION_HINTS: Dictionary = {
	"steer_left": "Lean into a left-hand bend.",
	"steer_right": "Lean into a right-hand bend.",
	"jump": "Hop cracks, gaps and low hazards.",
	"slide": "Belly-slide: faster, lower, harder to steer.",
	"shove": "Flipper-check a rival off their line.",
	"use_item": "Fire whatever you are carrying.",
	"pause": "Pause the race and open the menu.",
}

## Authored desktop metrics; UITheme.scaled* enlarges them on touch only.
const COLUMN_WIDTH: float = 860.0
const KEYCAP_WIDTH: float = 122.0
const KEYCAP_HEIGHT: float = 40.0
const COMPACT_COLUMN: float = 660.0
const BOOST_MAX: float = 1.35

var _capturing_action: String = ""
var _capturing_family: String = ""
var _capture_started_at: int = 0
var _capture_overlay: Control
var _capture_card: PanelContainer
var _capture_title: Label
var _capture_hint: Label
var _binding_buttons: Dictionary = {}  # "action/family" -> Button
var _first_button: Button
var _back_button: Button
var _reset_button: Button
var _reset_armed: bool = false
var _conflict_note: Label
var _scroll: ScrollContainer
var _boost: float = 1.0
var _column: float = COLUMN_WIDTH
var _compact: bool = false
var _row_index: int = 0


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)
	_boost = _tall_boost()
	_column = _measure_column()
	_compact = _column < UITheme.scaled(COMPACT_COLUMN) * _boost

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UITheme.screen_margin())
	margin.add_theme_constant_override("margin_right", UITheme.screen_margin())
	margin.add_theme_constant_override("margin_top", _gap(24))
	margin.add_theme_constant_override("margin_bottom", _gap(20))
	add_child(margin)

	var centered := HBoxContainer.new()
	centered.add_theme_constant_override("separation", 0)
	margin.add_child(centered)
	centered.add_child(_flex_spacer())
	var layout := VBoxContainer.new()
	layout.custom_minimum_size.x = _column
	layout.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	centered.add_child(layout)
	centered.add_child(_flex_spacer())

	var header := _build_header(layout)
	layout.add_child(UITheme.make_header_rule())

	_scroll = ScrollContainer.new()
	# Rows are buttons, which swallow touch drags before the ScrollContainer can
	# see them; this restores dragging the list on a phone.
	TouchScroll.attach(_scroll)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	layout.add_child(_scroll)
	_style_scrollbar(_scroll.get_v_scroll_bar())

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Fill and center: on a tall window the two cards sit in the middle of the
	# viewport instead of clinging to the top over a void, and on a short one the
	# list simply overflows and scrolls.
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.alignment = BoxContainer.ALIGNMENT_CENTER
	list.add_theme_constant_override("separation", _gap(UITheme.SPACE_M))
	_scroll.add_child(list)

	var entrance_items: Array[Control] = [header]
	entrance_items.append(_build_bindings_card(list))
	entrance_items.append(_build_touch_card(list))

	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0.0, _u(20.0))
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(tail)

	UITheme.play_entrance(self, entrance_items)

	_build_capture_overlay()
	_refresh_all_bindings()
	UITheme.attach_swipe_back(self, _go_back)
	if _back_button != null:
		_back_button.grab_focus()


## --- Layout scaling ---------------------------------------------------------

func _tall_boost() -> float:
	if GameConfig.is_headless() or not is_inside_tree():
		return 1.0
	var view_height := get_viewport_rect().size.y
	if view_height <= 0.0:
		return 1.0
	var design_height := 1080.0
	var window := get_window()
	if window != null and window.content_scale_size.y > 0:
		design_height = float(window.content_scale_size.y)
	return clampf(view_height / design_height, 1.0, BOOST_MAX)


func _f(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_font(size)) * _boost))


func _u(value: float) -> float:
	return UITheme.scaled(value) * _boost


func _ui(value: float) -> int:
	return maxi(1, roundi(_u(value)))


func _gap(value: int) -> int:
	return maxi(1, roundi(float(UITheme.spacing(value)) * _boost))


func _btn(width: float, height: float) -> Vector2:
	return UITheme.scaled_size(Vector2(width, height)) * _boost


func _measure_column() -> float:
	if UITheme.is_touch():
		return UITheme.content_width(COLUMN_WIDTH, self)
	if GameConfig.is_headless() or not is_inside_tree():
		return COLUMN_WIDTH
	var view := get_viewport_rect().size
	if view.x <= 0.0:
		return COLUMN_WIDTH
	var usable := maxf(view.x - float(UITheme.screen_margin()) * 2.0, 320.0)
	if view.y > view.x:
		return usable
	return clampf(minf(COLUMN_WIDTH * _boost, view.x * 0.68), 420.0, usable)


func _flex_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _style_scrollbar(bar: VScrollBar) -> void:
	if bar == null:
		return
	bar.custom_minimum_size.x = _u(9.0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(UITheme.COLOR_BG_DEEP, 0.30)
	track.set_corner_radius_all(4)
	track.content_margin_left = 2.0
	track.content_margin_right = 2.0
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(UITheme.COLOR_ACCENT, 0.32)
	grabber.set_corner_radius_all(4)
	grabber.anti_aliasing = true
	var hot := grabber.duplicate() as StyleBoxFlat
	hot.bg_color = Color(UITheme.COLOR_ACCENT, 0.62)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight", hot)
	bar.add_theme_stylebox_override("grabber_pressed", hot)


## --- Type ramp (boost-aware mirrors of the UITheme helpers) ------------------

func _caption_label(text: String, size: int, color: Color = UITheme.COLOR_TEXT_DIM) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UITheme.caption_font())
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", color)
	return label


func _text_label(text: String, size: int, color: Color = UITheme.COLOR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", color)
	return label


func _card_title(parent: Control, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _ui(10.0))
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(row)
	var tick := ColorRect.new()
	tick.color = Color(UITheme.COLOR_ACCENT, 0.85)
	tick.custom_minimum_size = Vector2(_u(4.0), _u(17.0))
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tick)
	row.add_child(_caption_label(text, 17, Color(0.72, 0.83, 0.94)))
	return row


func _divider() -> Control:
	var rule := ColorRect.new()
	rule.color = Color(UITheme.COLOR_ACCENT, 0.16)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _card(parent: Control) -> VBoxContainer:
	var card := PanelContainer.new()
	var style := UITheme.make_card_style()
	style.content_margin_left = _u(18.0)
	style.content_margin_right = _u(18.0)
	style.content_margin_top = _u(14.0)
	style.content_margin_bottom = _u(16.0)
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _gap(6))
	card.add_child(body)
	_row_index = 0
	return body


## Row shell shared by both cards: name (plus optional hint) on the left, a
## right-hand block whose width never changes, so the keycap column is real.
func _row(body: VBoxContainer, label_text: String, hint: String) -> HBoxContainer:
	var panel := PanelContainer.new()
	var style := UITheme.make_row_style(_row_index)
	style.content_margin_left = _u(14.0)
	style.content_margin_right = _u(14.0)
	style.content_margin_top = _u(8.0)
	style.content_margin_bottom = _u(8.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_row_index += 1

	var outer: BoxContainer
	if _compact:
		outer = VBoxContainer.new()
	else:
		outer = HBoxContainer.new()
	outer.add_theme_constant_override("separation", _gap(8 if _compact else UITheme.SPACE_S))
	panel.add_child(outer)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", _ui(2.0))
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(text_box)
	var name_label := _text_label(label_text, 20)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(name_label)
	if hint != "":
		var hint_label := _text_label(hint, 15, UITheme.COLOR_TEXT_DIM)
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_box.add_child(hint_label)

	var slot := HBoxContainer.new()
	slot.add_theme_constant_override("separation", _ui(10.0))
	slot.alignment = BoxContainer.ALIGNMENT_END
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _compact:
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(slot)
	return slot


## --- Header -----------------------------------------------------------------

func _build_header(parent: VBoxContainer) -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	parent.add_child(header)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(titles)
	titles.add_child(_caption_label("Settings", 15, Color(UITheme.COLOR_ACCENT, 0.75)))
	var title := UITheme.heading("Controls", maxi(1, roundi(
		float(UITheme.scaled_heading(46)) * _boost)))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	titles.add_child(title)

	_back_button = UITheme.make_button("Back", _btn(168.0, 48.0), _f(22))
	UITheme.style_primary(_back_button)
	_back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var back_icon := UITheme.make_icon(UITheme.ICON_BACK, 1.0)
	if back_icon != null:
		_back_button.icon = back_icon
		_back_button.expand_icon = true
		_back_button.add_theme_constant_override("icon_max_width", _ui(20.0))
		_back_button.add_theme_constant_override("h_separation", _ui(10.0))
	UITheme.hook_sounds(_back_button)
	_back_button.pressed.connect(_go_back)
	header.add_child(_back_button)
	return header


## --- Bindings card ----------------------------------------------------------

func _build_bindings_card(parent: Control) -> Control:
	var body := _card(parent)
	var card := body.get_parent() as Control

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	body.add_child(head)
	_card_title(head, "Key Bindings")
	head.add_child(_flex_spacer())
	_reset_button = UITheme.make_ghost_button("Reset to Defaults", _btn(0.0, 32.0), _f(16))
	_reset_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.hook_sounds(_reset_button)
	_reset_button.pressed.connect(_on_reset_pressed)
	head.add_child(_reset_button)
	body.add_child(_divider())

	# Column heads, in the same caption rung as every other column heading in
	# the game. Hidden when rows stack, where the columns no longer exist.
	if not _compact:
		# Inset by exactly the row padding, so the heads sit on the same two
		# vertical axes as the keycaps below them.
		var head_pad := MarginContainer.new()
		head_pad.add_theme_constant_override("margin_left", _ui(14.0))
		head_pad.add_theme_constant_override("margin_right", _ui(14.0))
		body.add_child(head_pad)
		var heads := HBoxContainer.new()
		heads.add_theme_constant_override("separation", _ui(10.0))
		head_pad.add_child(heads)
		var action_head := _caption_label("Action", 14)
		action_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heads.add_child(action_head)
		heads.add_child(_column_head("Keyboard"))
		heads.add_child(_column_head("Gamepad"))

	for action: String in SettingsManager.REMAPPABLE_ACTIONS:
		var slot := _row(body,
			String(ACTION_NAMES.get(action, action)),
			String(ACTION_HINTS.get(action, "")))
		slot.add_child(_make_keycap(action, "key"))
		slot.add_child(_make_keycap(action, "joy"))

	_conflict_note = _text_label("", 15, UITheme.COLOR_GOLD)
	_conflict_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conflict_note.visible = false
	body.add_child(_conflict_note)

	var hint := _text_label(
		"Press a key to rebind it. Esc — or a tap anywhere — cancels.",
		15, UITheme.COLOR_TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	return card


func _column_head(text: String) -> Control:
	var label := _caption_label(text, 14)
	label.custom_minimum_size.x = _u(KEYCAP_WIDTH)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## A binding chip. Fixed width, tight radius, bold tracked glyph — a keycap, not
## a button that happens to hold a letter.
func _make_keycap(action: String, family: String) -> Button:
	var cap := UITheme.make_button(
		SettingsManager.describe_action_binding(action, family),
		_btn(KEYCAP_WIDTH, KEYCAP_HEIGHT), _f(19))
	cap.add_theme_font_override("font", UITheme.caption_font())
	cap.clip_text = true
	if _compact:
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.hook_sounds(cap)
	cap.pressed.connect(_begin_capture.bind(action, family))
	_binding_buttons["%s/%s" % [action, family]] = cap
	if _first_button == null:
		_first_button = cap
	return cap


## Chip state: quiet by default, gold while it is the one listening, gold-rimmed
## when its binding is shared with another action.
func _style_keycap(cap: Button, listening: bool, conflicting: bool) -> void:
	var accent := UITheme.COLOR_GOLD if (listening or conflicting) else UITheme.COLOR_TEXT
	cap.add_theme_color_override("font_color", accent)
	cap.add_theme_color_override("font_focus_color", accent)
	var face := StyleBoxFlat.new()
	face.bg_color = Color(0.141, 0.227, 0.369, 0.68)
	face.border_color = UITheme.COLOR_RIM
	face.set_border_width_all(1)
	face.border_width_top = 2
	face.border_blend = true
	face.set_corner_radius_all(UITheme.RADIUS_ROW)
	face.content_margin_left = _u(8.0)
	face.content_margin_right = _u(8.0)
	face.content_margin_top = _u(6.0)
	face.content_margin_bottom = _u(8.0)
	face.shadow_color = UITheme.COLOR_SHADOW_SOFT
	face.shadow_size = 4
	face.shadow_offset = Vector2(0.0, 3.0)
	face.anti_aliasing = true
	if listening:
		face.bg_color = Color(UITheme.COLOR_GOLD, 0.20)
		face.border_color = Color(UITheme.COLOR_GOLD, 0.90)
		face.set_border_width_all(2)
	elif conflicting:
		face.border_color = Color(UITheme.COLOR_GOLD, 0.70)
		face.set_border_width_all(1)
		face.border_width_top = 2
	cap.add_theme_stylebox_override("normal", face)


## --- Touch card -------------------------------------------------------------

func _build_touch_card(parent: Control) -> Control:
	var body := _card(parent)
	var card := body.get_parent() as Control
	_card_title(body, "Touch")
	body.add_child(_divider())
	for entry: Array in [
		["Steer", "Or the on-screen stick, when it is enabled.", "Left / right screen halves"],
		["Jump", "", "JUMP button"],
		["Slide", "", "SLIDE button"],
		["Shove", "", "SHOVE button"],
		["Use Item", "", "ITEM button"],
		["Pause", "", "Pause icon, top corner"],
	]:
		var slot := _row(body, String(entry[0]), String(entry[1]))
		var value := _text_label(String(entry[2]), 17, UITheme.COLOR_TEXT_DIM)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if not _compact \
			else HORIZONTAL_ALIGNMENT_LEFT
		if _compact:
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			value.custom_minimum_size.x = _u(340.0)
		slot.add_child(value)
	var note := _text_label(
		"Touch controls follow the Touch Controls setting and cannot be rebound.",
		15, UITheme.COLOR_TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	return card


## --- Capture ----------------------------------------------------------------

## Full-screen, deliberately calm: a scrim so nothing else competes, the action
## being rebound spelled out, and the way out stated.
func _build_capture_overlay() -> void:
	_capture_overlay = Control.new()
	_capture_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_capture_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_capture_overlay.visible = false
	_capture_overlay.z_index = 10
	add_child(_capture_overlay)

	var scrim := ColorRect.new()
	scrim.color = Color(0.012, 0.027, 0.055, 0.72)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_overlay.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_overlay.add_child(center)

	_capture_card = PanelContainer.new()
	var style := UITheme.make_panel_style(
		Color(0.055, 0.098, 0.172, 0.97), Color(UITheme.COLOR_GOLD, 0.55))
	style.content_margin_left = _u(34.0)
	style.content_margin_right = _u(34.0)
	style.content_margin_top = _u(24.0)
	style.content_margin_bottom = _u(26.0)
	style.shadow_size = 18
	_capture_card.add_theme_stylebox_override("panel", style)
	_capture_card.custom_minimum_size.x = _u(380.0)
	center.add_child(_capture_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _gap(8))
	_capture_card.add_child(box)
	var eyebrow := _caption_label("Rebinding", 15, Color(UITheme.COLOR_GOLD, 0.85))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(eyebrow)
	_capture_title = UITheme.heading("", maxi(1, roundi(
		float(UITheme.scaled_heading(32)) * _boost)))
	_capture_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	box.add_child(_capture_title)
	box.add_child(UITheme.accent_rule(_u(180.0), UITheme.COLOR_GOLD))
	_capture_hint = _text_label("", 18, UITheme.COLOR_TEXT_DIM)
	_capture_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_capture_hint)
	var cancel := _text_label("Esc or tap anywhere cancels", 16, UITheme.COLOR_TEXT_DIM)
	cancel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cancel)


func _begin_capture(action: String, family: String) -> void:
	_capturing_action = action
	_capturing_family = family
	_capture_started_at = Time.get_ticks_msec()
	_capture_title.text = String(ACTION_NAMES.get(action, action))
	_capture_hint.text = "Press any key…" if family == "key" \
		else "Press a gamepad button, trigger or stick…"
	_capture_overlay.visible = true
	_refresh_all_bindings()
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if _capturing_action == "":
		return
	if Time.get_ticks_msec() - _capture_started_at < 150:
		return
	# Touch players have no Esc: any tap or click cancels capture mode.
	var tap_cancel := (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if tap_cancel:
		get_viewport().set_input_as_handled()
		_end_capture()
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


func _end_capture() -> void:
	_capturing_action = ""
	_capturing_family = ""
	_capture_overlay.visible = false
	_refresh_all_bindings()


## Repaints every chip: its label, whether it is the one listening, and whether
## another action already answers to the same input.
func _refresh_all_bindings() -> void:
	var owners: Dictionary = {}  # "family|label" -> action names sharing it
	for keypath: String in _binding_buttons.keys():
		var parts := keypath.split("/")
		var label := SettingsManager.describe_action_binding(parts[0], parts[1])
		var button: Button = _binding_buttons[keypath]
		button.text = label
		if label == "—":
			continue
		var slot_key := "%s|%s" % [parts[1], label]
		var names: PackedStringArray = owners.get(slot_key, PackedStringArray())
		names.append(String(ACTION_NAMES.get(parts[0], parts[0])))
		owners[slot_key] = names

	var clashes := PackedStringArray()
	for slot_key: String in owners.keys():
		var names: PackedStringArray = owners[slot_key]
		if names.size() < 2:
			continue
		clashes.append("%s is bound to %s" % [slot_key.split("|")[1], " and ".join(names)])

	for keypath: String in _binding_buttons.keys():
		var parts := keypath.split("/")
		var label := SettingsManager.describe_action_binding(parts[0], parts[1])
		var slot_key := "%s|%s" % [parts[1], label]
		var shared: PackedStringArray = owners.get(slot_key, PackedStringArray())
		var conflicting := label != "—" and shared.size() > 1
		var listening := parts[0] == _capturing_action and parts[1] == _capturing_family
		var cap: Button = _binding_buttons[keypath]
		_style_keycap(cap, listening, conflicting)

	if _conflict_note == null:
		return
	_conflict_note.visible = not clashes.is_empty()
	if not clashes.is_empty():
		_conflict_note.text = "%s. Both actions will fire." % ". ".join(clashes)


func _on_reset_pressed() -> void:
	# Two presses, like every other destructive control in the game: the first
	# arms, the second commits.
	if not _reset_armed:
		_reset_armed = true
		_reset_button.text = "Confirm?"
		_reset_button.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
		_reset_button.add_theme_color_override("font_hover_color", UITheme.COLOR_GOLD)
		return
	_disarm_reset()
	SettingsManager.reset_bindings()
	_refresh_all_bindings()


func _disarm_reset() -> void:
	_reset_armed = false
	if not is_instance_valid(_reset_button):
		return
	_reset_button.text = "Reset to Defaults"
	_reset_button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_reset_button.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT)


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_SETTINGS)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()
