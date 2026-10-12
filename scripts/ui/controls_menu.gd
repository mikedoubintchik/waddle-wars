extends Control

const UtilityArt := preload("res://scripts/ui/utility_reference_art.gd")
## Control remapping screen.
##
## Same language as Settings and the results screen: eyebrow + headline hero, a
## focused workspace, cards at radius 18 titled with an accent tick and an
## uppercase tracked caption, rows at radius 10 with a faint zebra, and one
## promoted primary action — Back.
##
## Bindings read as keycaps: compact, fixed-width chips in a real column, so a
## glance down the screen reads as a keyboard rather than as a wall of buttons.
## Pressing one opens a calm full-screen capture state (scrim, the action being
## rebound, how to cancel) and the chip itself shows that it is listening.
## Duplicate bindings are called out on the chips and named underneath, because
## InputMap will happily fire two actions from one key.
## Portrait stacks rows for finger-width controls; wide landscape places the
## binding console and touch field guide side by side.

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
const WIDE_COLUMN_WIDTH: float = 1240.0
const KEYCAP_WIDTH: float = 140.0
const KEYCAP_HEIGHT: float = 66.0
const ICON_CELLS := {
	"steer_left": Vector2i(0, 0), "steer_right": Vector2i(1, 0),
	"jump": Vector2i(2, 0), "slide": Vector2i(0, 1),
	"use_item": Vector2i(1, 1), "pause": Vector2i(2, 1),
	"shove": Vector2i(0, 2), "aim_back": Vector2i(0, 0),
}
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
var _binding_icons: Dictionary = {}  # Bounded SVG set; independent of font coverage.
var _first_button: Button
var on_back: Callable = Callable()
var _back_button: Button
var _reset_button: Button
var _reset_armed: bool = false
var _conflict_note: Label
var _scroll: ScrollContainer
var _boost: float = 1.0
var _column: float = COLUMN_WIDTH
var _compact: bool = false
var _fit: float = 1.0
var _row_index: int = 0
var _profile: LayoutProfile = null
var _layout_root: Control = null


func _ready() -> void:
	UtilityArt.bind_background(self, "res://assets/art/ui/menu/controls_background_v2.webp", "res://assets/art/ui/menu/controls_background_landscape_v3.webp")
	UITheme.apply_ui_scale(self)
	var initial := UtilityScreenLayout.bind_view_class(self, _on_view_class_changed)
	_build_layout(initial, true, 0.0)
	UITheme.attach_swipe_back(self, _go_back)


func _on_view_class_changed(next: LayoutProfile) -> void:
	var fraction := UtilityScreenLayout.scroll_fraction(_scroll)
	if not _capturing_action.is_empty():
		_end_capture()
	_build_layout(next, false, fraction)


func _build_layout(next: LayoutProfile, animate: bool, scroll_fraction: float) -> void:
	if is_instance_valid(_layout_root):
		_layout_root.free()
	_profile = next
	_binding_buttons.clear()
	_first_button = null
	_reset_armed = false
	_column = _profile.safe_rect.size.x * (0.94 if _profile.is_portrait() else 0.52)
	_fit = _column / 880.0
	_boost = 1.0
	_compact = false
	_layout_root = Control.new()
	_layout_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_layout_root)
	var safe := _profile.safe_rect
	var back_size := safe.size.x * 0.14 if _profile.is_portrait() else safe.size.y * 0.11
	var header_back := ExpeditionMenuStyle.back_button(back_size)
	header_back.position = safe.position + Vector2(safe.size.x * 0.025, safe.size.y * 0.024)
	header_back.size = Vector2.ONE * back_size
	header_back.pressed.connect(_go_back)
	_layout_root.add_child(header_back)
	var title := TextureRect.new()
	title.name = "ControlsTitleArt"
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.texture = ExpeditionMenuStyle.title_texture("controls")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_width := safe.size.x * (0.62 if _profile.is_portrait() else 0.41)
	title.size = Vector2(title_width, title_width * 0.27)
	title.position = safe.position + Vector2(safe.size.x * (0.50 if _profile.is_portrait() else 0.225) - title_width * 0.5, safe.size.y * (0.045 if _profile.is_portrait() else 0.13))
	_layout_root.add_child(title)
	UtilityScreenLayout.defer_header_alignment(self, title, header_back)
	var panel := PanelContainer.new()
	panel.name = "ControlsReferencePanel"
	panel.position = safe.position + Vector2((safe.size.x - _column) * 0.5 if _profile.is_portrait() else safe.size.x - _column - safe.size.x * 0.02, safe.size.y * (0.267 if _profile.is_portrait() else 0.04))
	panel.size = Vector2(_column, safe.size.y * (0.703 if _profile.is_portrait() else 0.92))
	panel.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_card(_u(22), _u(24)))
	_layout_root.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", _ui(10))
	panel.add_child(layout)
	_scroll = ScrollContainer.new()
	_scroll.name = "ControlsBindingsScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	TouchScroll.attach(_scroll)
	_style_scrollbar(_scroll.get_v_scroll_bar())
	layout.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list)
	_build_bindings_card(list)
	var touch := _build_touch_card(list)
	touch.name = "TouchFieldGuide"
	touch.hide()
	var guide := ExpeditionMenuStyle.button("TOUCH CONTROLS", false, _f(17), _u(34))
	guide.custom_minimum_size.y = maxf(44.0, _u(34))
	guide.name = "ShowTouchFieldGuide"
	guide.pressed.connect(func() -> void:
		touch.visible = not touch.visible
		guide.text = "HIDE TOUCH CONTROLS" if touch.visible else "TOUCH CONTROLS")
	layout.add_child(guide)
	_back_button = _make_back_button(Vector2(_column * 0.64, _u(96)))
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.icon = UtilityArt.icon("back")
	_back_button.expand_icon = true
	_back_button.add_theme_constant_override("icon_max_width", _ui(44))
	UtilityArt.centered_button(_back_button, "BACK TO SETTINGS", UtilityArt.icon("back"), _f(26), _u(96))
	_tint_ice_button(_back_button)
	layout.add_child(_back_button)
	_build_capture_overlay()
	_refresh_all_bindings()
	UtilityScreenLayout.restore_scroll_fraction(self, _scroll, scroll_fraction)
	if animate:
		UITheme.play_entrance(self, [panel])


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
	return maxi(1 if _profile.is_portrait() else 28, roundi(float(size) * _fit * 1.28))


func _u(value: float) -> float:
	return value * _fit


func _ui(value: float) -> int:
	return maxi(1, roundi(_u(value)))


func _gap(value: int) -> int:
	return maxi(1, roundi(_u(float(value))))


func _btn(width: float, height: float) -> Vector2:
	return Vector2(_u(width), maxf(_u(height), UtilityScreenLayout.MIN_TOUCH_TARGET))


func _measure_column() -> float:
	# Headless is NOT a reason to fall back to the authored desktop width. The
	# profile is built from the live viewport, which is just as valid without a
	# window, and returning 860 here laid an 860-unit column out inside the
	# 800-unit canvas a portrait phone actually has -- pushing Back off the
	# right edge in every automated check.
	if _profile == null or not is_inside_tree():
		return COLUMN_WIDTH
	if _profile.is_portrait():
		return maxf(_profile.safe_rect.size.x - float(_page_gutter() * 2), 300.0)
	return maxf(_profile.safe_rect.size.x * 0.94 - float(_page_gutter() * 2), 300.0)


func _page_gutter() -> int:
	return 16 if UtilityScreenLayout.is_phone(_profile) else 24


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
	track.bg_color = Color("e0f1f7")
	track.set_corner_radius_all(4)
	track.content_margin_left = 2.0
	track.content_margin_right = 2.0
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color("49a9c7")
	grabber.set_corner_radius_all(4)
	grabber.anti_aliasing = true
	var hot := grabber.duplicate() as StyleBoxFlat
	hot.bg_color = Color("207b9c")
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight", hot)
	bar.add_theme_stylebox_override("grabber_pressed", hot)


## --- Type ramp (boost-aware mirrors of the UITheme helpers) ------------------

func _caption_label(text: String, size: int,
		color: Color = ExpeditionMenuStyle.INK) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UITheme.caption_font())
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", color)
	return label


func _text_label(text: String, size: int,
		color: Color = ExpeditionMenuStyle.INK) -> Label:
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
	tick.color = Color("379ec0")
	tick.custom_minimum_size = Vector2(_u(4.0), _u(17.0))
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tick)
	row.add_child(_caption_label(text, 17))
	return row


func _divider() -> Control:
	var rule := ColorRect.new()
	rule.color = Color("b6d9e7")
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _card(parent: Control) -> VBoxContainer:
	var card := PanelContainer.new()
	var style := StyleBoxEmpty.new()
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _gap(6 if _profile.is_portrait() else 4))
	card.add_child(body)
	_row_index = 0
	return body


## Row shell shared by both cards: name (plus optional hint) on the left, a
## right-hand block whose width never changes, so the keycap column is real.
func _row(body: VBoxContainer, label_text: String, hint: String,
		action: String = "") -> HBoxContainer:
	var panel := PanelContainer.new()
	var style := ExpeditionMenuStyle.material_box()
	style.content_margin_left = _u(14.0)
	style.content_margin_right = _u(14.0)
	style.content_margin_top = _u(6.0 if _profile.is_portrait() else 2.0)
	style.content_margin_bottom = _u(6.0 if _profile.is_portrait() else 2.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.tooltip_text = hint
	body.add_child(panel)
	_row_index += 1

	var outer: BoxContainer
	if _compact:
		outer = VBoxContainer.new()
	else:
		outer = HBoxContainer.new()
	outer.add_theme_constant_override("separation", _gap(8 if _compact else UITheme.SPACE_S))
	panel.add_child(outer)
	if ICON_CELLS.has(action):
		var symbol := TextureRect.new()
		symbol.name = "ActionIcon_" + action
		var atlas := AtlasTexture.new()
		atlas.atlas = ExpeditionMenuStyle._material_texture(
			"res://assets/art/ui/menu/controls_icons_v2.webp")
		var regions := {"steer_left":Rect2(58,135,341,214),"steer_right":Rect2(476,140,320,216),"jump":Rect2(882,96,304,301),"slide":Rect2(45,544,367,210),"use_item":Rect2(490,497,317,257),"pause":Rect2(940,522,225,242),"shove":Rect2(77,910,276,242),"aim_back":Rect2(58,135,341,214)}
		atlas.region = regions[action]
		atlas.filter_clip = true
		symbol.texture = atlas
		symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		symbol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		symbol.custom_minimum_size = Vector2(_u(112.0), _u(76.0 if _profile.is_portrait() else 66.0))
		symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outer.add_child(symbol)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", _ui(2.0))
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(text_box)
	var name_label := _text_label(label_text.to_upper() if not action.is_empty() else label_text, 29 if not action.is_empty() else 20)
	if not action.is_empty():
		name_label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(name_label)
	if hint != "" and action.is_empty():
		var hint_label := _text_label(hint, 15, Color("456778"))
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_box.add_child(hint_label)

	var slot := HBoxContainer.new()
	slot.add_theme_constant_override("separation", _ui(35.0))
	slot.alignment = BoxContainer.ALIGNMENT_END
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _compact:
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(slot)
	return slot


## --- Header -----------------------------------------------------------------

func _build_header(parent: VBoxContainer) -> Control:
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(header_panel)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	header_panel.add_child(header)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(titles)
	var title := TextureRect.new()
	title.name = "ControlsTitleArt"
	title.texture = ExpeditionMenuStyle._material_texture(
		"res://assets/art/ui/menu/controls_title_v1.webp")
	title.accessibility_name = "Controls"
	title.custom_minimum_size.y = _u(195.0)
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(title)

	if _docks_back():
		return header_panel
	header.add_child(_make_back_button(_btn(168.0, 48.0)))
	return header_panel


## True when Back belongs at the foot of the screen rather than in the header.
## Same rule as the settings screen: on a phone the top-right corner is out of
## thumb reach and the headline already wants the whole column width, so the
## promoted action moves to a docked bar. Landscape keeps the header action.
func _docks_back() -> bool:
	return _profile != null and _profile.is_portrait()


func _make_back_button(size: Vector2) -> Button:
	_back_button = ExpeditionMenuStyle.button("BACK TO SETTINGS", false, _f(22), size.y)
	_back_button.custom_minimum_size = size
	_back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(_go_back)
	return _back_button


## Portrait action bar: a rule, then one full-width primary target under the
## scrolling list. A sibling of the ScrollContainer, not a child of it, so the
## list shortens to make room and Back stays on screen at every scroll offset.
func _build_action_bar(parent: VBoxContainer) -> Control:
	var bar := VBoxContainer.new()
	bar.add_theme_constant_override("separation", _gap(8))
	parent.add_child(bar)
	var button := _make_back_button(_btn(0.0, 52.0))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_END
	bar.add_child(button)
	return bar


## --- Bindings card ----------------------------------------------------------

func _build_bindings_card(parent: Control) -> Control:
	var body := _card(parent)
	var card := body.get_parent() as Control

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	body.add_child(head)
	var controller := TextureRect.new()
	controller.texture = UtilityArt.icon("controller")
	controller.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	controller.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	controller.custom_minimum_size = Vector2.ONE * _u(76)
	head.add_child(controller)
	var title := _text_label("CONTROLS", 46)
	title.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	head.add_child(_flex_spacer())
	_reset_button = ExpeditionMenuStyle.button("RESET", false, _f(22),
		_btn(0.0, 82.0).y)
	_reset_button.icon = UtilityArt.icon("reset")
	_reset_button.expand_icon = true
	_reset_button.add_theme_constant_override("icon_max_width", _ui(44))
	_tint_ice_button(_reset_button)
	_reset_button.tooltip_text = "Reset all bindings to defaults"
	_reset_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_reset_button.custom_minimum_size.x = _u(215)
	_reset_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reset_button.pressed.connect(_on_reset_pressed)
	head.add_child(_reset_button)
	body.add_child(_divider())


	for action: String in SettingsManager.REMAPPABLE_ACTIONS:
		var slot := _row(body,
			String(ACTION_NAMES.get(action, action)),
			String(ACTION_HINTS.get(action, "")), action)
		slot.add_child(_make_keycap(action, "key"))
		slot.add_child(_make_keycap(action, "joy"))

	_conflict_note = _text_label("", 15, Color("a46b0f"))
	_conflict_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conflict_note.visible = false
	body.add_child(_conflict_note)

	var hint := _text_label(
		"Press a key to rebind it. Esc — or a tap anywhere — cancels.",
		15, Color("456778"))
	hint.name = "ControlsRebindHelp"
	if not _profile.is_portrait():
		# Binding caps retain their larger type; this supporting line fits below
		# all seven actions without being cut by the scroll viewport.
		hint.add_theme_font_size_override("font_size", roundi(_u(15.0) * 1.28))
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
	var key_height := 94.0 if _profile.is_portrait() else 66.0
	var key_size := _btn(88.0 if family == "joy" else 112.0, key_height)
	if _profile.is_portrait():
		# Seven actual actions fit above the fixed Back action. At the phone
		# design canvas this still gives a 50px native touch target.
		key_size.y = minf(key_size.y, maxf(66.0, _profile.safe_rect.size.y * 0.062))
	var cap := ExpeditionMenuStyle.button(
		SettingsManager.describe_action_binding(action, family), false,
		_f(26), key_size.y)
	if family == "joy": key_size.x = key_size.y
	cap.custom_minimum_size = key_size
	cap.set_meta("binding_family", family)
	cap.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var face := cap.get_theme_stylebox(state).duplicate() as StyleBox
		face.content_margin_left = _u(4.0)
		face.content_margin_right = _u(4.0)
		cap.add_theme_stylebox_override(state, face)
	cap.clip_text = true
	cap.tooltip_text = SettingsManager.describe_action_binding(action, family)
	if _compact:
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.pressed.connect(_begin_capture.bind(action, family))
	_binding_buttons["%s/%s" % [action, family]] = cap
	if _first_button == null:
		_first_button = cap
	return cap


## Chip state: quiet by default, gold while it is the one listening, gold-rimmed
## when its binding is shared with another action.
func _style_keycap(cap: Button, listening: bool, conflicting: bool) -> void:
	var controller := String(cap.get_meta("binding_family", "key")) == "joy"
	var accent := Color("fff2c6") if (listening or conflicting) else (Color.WHITE if controller else ExpeditionMenuStyle.INK)
	cap.add_theme_color_override("font_color", accent)
	cap.add_theme_color_override("font_focus_color", accent)
	var face := StyleBoxFlat.new()
	face.bg_color = Color("193856") if controller else Color("deefff")
	face.border_color = Color("3d5f85") if controller else Color("f8fdff")
	face.set_border_width_all(2)
	face.border_width_top = 6 if not controller else 4
	face.border_blend = true
	face.set_corner_radius_all(_ui(44 if controller else 15))
	face.content_margin_left = _u(4.0)
	face.content_margin_right = _u(4.0)
	face.content_margin_top = _u(6.0)
	face.content_margin_bottom = _u(8.0)
	face.shadow_color = Color("849cb6") if not controller else Color("102b43")
	face.shadow_size = _ui(4 if not controller else 3)
	face.shadow_offset = Vector2(0.0, _u(7.0 if not controller else 5.0))
	face.anti_aliasing = true
	if listening:
		face.bg_color = Color("8c650e")
		face.border_color = Color(UITheme.COLOR_GOLD, 0.90)
		face.set_border_width_all(2)
	elif conflicting:
		face.border_color = Color(UITheme.COLOR_GOLD, 0.70)
		face.set_border_width_all(1)
		face.border_width_top = 2
	cap.add_theme_stylebox_override("normal", face)
	var hover := face.duplicate() as StyleBoxFlat
	hover.bg_color = face.bg_color.lightened(0.12)
	cap.add_theme_stylebox_override("hover", hover)
	var pressed := face.duplicate() as StyleBoxFlat
	pressed.shadow_offset = Vector2(0.0, 1.0)
	pressed.bg_color = face.bg_color.darkened(0.10)
	cap.add_theme_stylebox_override("pressed", pressed)
	cap.add_theme_color_override("font_hover_color", accent)
	cap.add_theme_color_override("font_pressed_color", accent)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		cap.add_theme_color_override("icon_" + state + "_color", accent)


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
		var value := _text_label(String(entry[2]), 17, Color("456778"))
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
		15, Color("456778"))
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
	_layout_root.add_child(_capture_overlay)

	var scrim := ColorRect.new()
	scrim.color = Color(0.012, 0.027, 0.055, 0.72)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_overlay.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	UtilityScreenLayout.bind_safe_rect(self, center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_overlay.add_child(center)

	_capture_card = PanelContainer.new()
	var style := ExpeditionMenuStyle.material_card()
	style.content_margin_left = _u(34.0)
	style.content_margin_right = _u(34.0)
	style.content_margin_top = _u(24.0)
	style.content_margin_bottom = _u(26.0)
	_capture_card.add_theme_stylebox_override("panel", style)
	_capture_card.custom_minimum_size.x = minf(_u(380.0),
		maxf(_profile.safe_rect.size.x - 48.0, 260.0))
	center.add_child(_capture_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _gap(8))
	_capture_card.add_child(box)
	var eyebrow := _caption_label("Rebinding", 15, Color(UITheme.COLOR_GOLD, 0.85))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(eyebrow)
	_capture_title = UITheme.heading("", maxi(1, roundi(
		float(UITheme.scaled_heading(32)) * _boost)))
	_capture_title.add_theme_color_override("font_color", ExpeditionMenuStyle.INK)
	box.add_child(_capture_title)
	box.add_child(UITheme.accent_rule(_u(180.0), UITheme.COLOR_GOLD))
	_capture_hint = _text_label("", 18, Color("456778"))
	_capture_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_capture_hint)
	var cancel := _text_label("Esc or tap anywhere cancels", 16, Color("456778"))
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
func _binding_glyph(label: String, family: String) -> String:
	if family == "key":
		return "" if label in ["Left", "Right", "Up", "Down"] else label
	return String({"D-Pad Left": "", "D-Pad Right": "", "D-Pad Up": "",
		"D-Pad Down": "", "Start": "", "Axis 0-": "L", "Axis 0+": "L"}.get(label, label))


func _binding_icon(label: String, family: String) -> Texture2D:
	var symbol := String({"D-Pad Left": "left", "D-Pad Right": "right",
		"D-Pad Up": "up", "D-Pad Down": "down", "Start": "menu",
		"Axis 0-": "left", "Axis 0+": "right"}.get(label, ""))
	if family == "key":
		symbol = String({"Left": "left", "Right": "right", "Up": "up", "Down": "down"}.get(label, ""))
	if symbol.is_empty(): return null
	if not _binding_icons.has(symbol):
		var mark := ""
		match symbol:
			"left": mark = '<path d="M44 10 14 32 44 54Z" fill="white"/>'
			"right": mark = '<path d="M20 10 50 32 20 54Z" fill="white"/>'
			"up": mark = '<path d="M10 44 32 14 54 44Z" fill="white"/>'
			"down": mark = '<path d="M10 20 32 50 54 20Z" fill="white"/>'
			"menu": mark = '<path d="M12 16H52M12 32H52M12 48H52" fill="none" stroke="white" stroke-width="7" stroke-linecap="round"/>'
		_binding_icons[symbol] = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">' + mark + '</svg>')
	return _binding_icons[symbol] as Texture2D


func _refresh_all_bindings() -> void:
	var owners: Dictionary = {}  # "family|label" -> action names sharing it
	for keypath: String in _binding_buttons.keys():
		var parts := keypath.split("/")
		var label := SettingsManager.describe_action_binding(parts[0], parts[1])
		var button: Button = _binding_buttons[keypath]
		button.text = _binding_glyph(label, parts[1])
		button.icon = _binding_icon(label, parts[1])
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT if label.begins_with("Axis") else HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", roundi(button.custom_minimum_size.y * (0.33 if label.begins_with("Axis") else 0.50)))
		button.tooltip_text = label
		button.accessibility_name = String(ACTION_NAMES.get(parts[0], parts[0])) + ": " + label
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
	_reset_button.text = "RESET"
	_reset_button.add_theme_color_override("font_color", ExpeditionMenuStyle.INK)
	_reset_button.add_theme_color_override("font_hover_color", ExpeditionMenuStyle.INK)


func _go_back() -> void:
	if on_back.is_valid():
		on_back.call()
	else:
		SceneRouter.go_back(Game.SCENE_SETTINGS)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()


func _tint_ice_button(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var face := ExpeditionMenuStyle.material_box(false, _u(18), _u(10), Color("d7ebff"))
		button.add_theme_stylebox_override(state, face)
