extends Control
## Settings screen covering the full SettingsManager schema.
##
## Shape follows the results/main-menu language: an eyebrow + headline hero, a
## centered content column (never a full-bleed table), cards at radius 18 whose
## titles are an accent tick plus an uppercase tracked caption, rows at radius
## 10 with a faint zebra, and one promoted primary action — Back.
##
## Every row shares one anatomy: name, an optional one-line description, and a
## control block of a single fixed width so the right edge is a real column.
## The controls themselves are one family: two or three short choices render as
## a segmented pill (booleans included, as Off / On), longer lists as a picker,
## numbers as a slider with a display-font readout, and free text as an inset
## field — all the same height, radius and rim.
##
## Narrow viewports (portrait phones) stack each row instead, label over a
## full-width control, which is the only layout that stays legible there.
##
## Controls re-read their value from SettingsManager.setting_changed, so a
## section reset — or a change made from anywhere else — updates the screen in
## place instead of rebuilding it.
##
## All authored sizes below are desktop values; UITheme.scaled* enlarges them on
## touch devices and _boost enlarges them on tall/portrait windows, so the
## desktop landscape layout is exactly what is written here.

## Width of the centered content column on a desktop landscape window.
const COLUMN_WIDTH: float = 940.0
## Width of the right-hand control block. Every control fills exactly this, so
## pickers, sliders and segmented pills all end on one vertical axis.
const CONTROL_COLUMN: float = 340.0
## Readout gutter to the left of a slider track.
const VALUE_WIDTH: float = 76.0
const CONTROL_HEIGHT: float = 40.0
## Below this column width a row stacks (label over a full-width control)
## instead of splitting left/right.
const COMPACT_COLUMN: float = 720.0
## Portrait windows gain logical height; metrics grow with it, but far less than
## the results screen needs — settings is dense and must not overflow.
const BOOST_MAX: float = 1.35

## Section id (also the SettingsManager section) -> title, in screen order.
const SECTIONS: Array = [
	["display", "Display"],
	["audio", "Audio"],
	["gameplay", "Gameplay"],
	["accessibility", "Accessibility"],
	["online", "Online"],
]

var _scroll: ScrollContainer
var _sections: VBoxContainer
var _back_button: Button
var _entrance_items: Array[Control] = []
## "section/key" -> Callable(value) that pushes a stored value back into its
## control. Driven by SettingsManager.setting_changed.
var _refreshers: Dictionary = {}
## Section id whose Reset button is armed for its confirming second press.
var _reset_armed: String = ""
var _reset_buttons: Dictionary = {}  # section id -> Button
var _section_cards: Dictionary = {}  # section id -> PanelContainer, for the jump chips
var _boost: float = 1.0
var _column: float = COLUMN_WIDTH
var _compact: bool = false
## Zebra counter, reset at the top of each card.
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

	# Fixed-width column centered by two weightless spacers. A MarginContainer
	# cannot center a column whose width is computed at runtime, and a
	# CenterContainer would refuse to let the scroll list fill the height.
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
	var chips := _build_section_chips(layout)

	_scroll = ScrollContainer.new()
	# Rows are buttons and sliders, which swallow touch drags before the
	# ScrollContainer can see them; this restores dragging the list on a phone.
	TouchScroll.attach(_scroll)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	layout.add_child(_scroll)
	_style_scrollbar(_scroll.get_v_scroll_bar())

	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", _gap(UITheme.SPACE_M))
	_scroll.add_child(_sections)

	_entrance_items.append(header)
	_entrance_items.append(chips)
	_build_display_section()
	_build_audio_section()
	_build_gameplay_section()
	_build_accessibility_section()
	_build_online_section()
	_build_about_footer()

	# Closing note plus breathing room so the last card is never flush against
	# the bottom edge of the scroll viewport.
	var footer := _text_label("Changes save automatically.", 16, UITheme.COLOR_TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sections.add_child(footer)
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0.0, _u(24.0))
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sections.add_child(tail)

	UITheme.play_entrance(self, _entrance_items)

	SettingsManager.setting_changed.connect(_on_setting_changed)
	UITheme.attach_swipe_back(self, _go_back)
	if _back_button != null:
		_back_button.grab_focus()


## --- Layout scaling ---------------------------------------------------------

## Portrait/tall windows keep the design width but gain logical height, so every
## authored pixel renders physically small and the screen shrinks into an
## island. Grow the metrics by the ratio of live to design height — the same
## step the results screen takes, capped lower because a settings row carries a
## label, a description and a control on one line.
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


## Authored font size -> on-screen size (touch step, then the tall step).
func _f(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_font(size)) * _boost))


## Authored metric -> on-screen metric.
func _u(value: float) -> float:
	return UITheme.scaled(value) * _boost


## Integer flavour of _u(), for theme constants.
func _ui(value: float) -> int:
	return maxi(1, roundi(_u(value)))


## Authored spacing step -> on-screen separation.
func _gap(value: int) -> int:
	return maxi(1, roundi(float(UITheme.spacing(value)) * _boost))


## Authored button size -> on-screen button size.
func _btn(width: float, height: float) -> Vector2:
	return UITheme.scaled_size(Vector2(width, height)) * _boost


## Height every control in the family shares.
func _control_height() -> float:
	return maxf(UITheme.scaled_size(Vector2(0.0, CONTROL_HEIGHT)).y, CONTROL_HEIGHT) * _boost


## Width of the centered column: the authored width on a desktop landscape
## window, the touch content band on phones, and the full usable width on a
## portrait window (where floating a narrow column would waste the screen).
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
	return clampf(minf(COLUMN_WIDTH * _boost, view.x * 0.72), 420.0, usable)


## The engine's default scrollbar is the one grey rectangle left on the screen;
## give it the same rounded, accent-tinted material as everything else.
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


func _flex_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## --- Header -----------------------------------------------------------------

## Eyebrow over headline on the left, the one promoted action on the right.
func _build_header(parent: VBoxContainer) -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	parent.add_child(header)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(titles)
	var eyebrow := _caption_label(
		GameConfig.GAME_NAME, 15, Color(UITheme.COLOR_ACCENT, 0.75))
	titles.add_child(eyebrow)
	var title := UITheme.heading("Settings", maxi(1, roundi(
		float(UITheme.scaled_heading(46)) * _boost)))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	titles.add_child(title)

	_back_button = UITheme.make_button("Back", _btn(168.0, 48.0), _f(22))
	UITheme.style_primary(_back_button)
	_back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := UITheme.make_icon(UITheme.ICON_BACK, 1.0)
	if icon != null:
		_back_button.icon = icon
		_back_button.expand_icon = true
		_back_button.add_theme_constant_override("icon_max_width", _ui(20.0))
		_back_button.add_theme_constant_override("h_separation", _ui(10.0))
	UITheme.hook_sounds(_back_button)
	_back_button.pressed.connect(_go_back)
	header.add_child(_back_button)
	return header


## Jump strip: one small quiet button per card. On a long settings list this is
## the difference between scanning and hunting, and it wraps onto a second line
## rather than clipping on a narrow window.
func _build_section_chips(parent: VBoxContainer) -> Control:
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", _ui(8.0))
	chips.add_theme_constant_override("v_separation", _ui(6.0))
	parent.add_child(chips)
	for entry: Array in SECTIONS:
		var id := String(entry[0])
		var chip := UITheme.make_button(String(entry[1]), _btn(0.0, 34.0), _f(16))
		chip.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		UITheme.hook_sounds(chip)
		chip.pressed.connect(func() -> void:
			_jump_to(id))
		chips.add_child(chip)
	return chips


func _jump_to(id: String) -> void:
	var card: Variant = _section_cards.get(id)
	if not (card is Control) or not is_instance_valid(card as Control):
		return
	if _scroll == null:
		return
	_scroll.scroll_vertical = maxi(0, roundi((card as Control).position.y - _u(6.0)))


## --- Type ramp (boost-aware mirrors of the UITheme helpers) ------------------

## Small uppercase tracked caption — card titles, eyebrows, column heads.
func _caption_label(text: String, size: int, color: Color = UITheme.COLOR_TEXT_DIM) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UITheme.caption_font())
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", color)
	return label


## Readable body copy (row names, descriptions, notes).
func _text_label(text: String, size: int, color: Color = UITheme.COLOR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", color)
	return label


## A value the player reads at a glance: display font, accent-tinted, parked in
## a fixed gutter so readouts line up down the card.
func _value_label() -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(18))
	label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	label.custom_minimum_size.x = _u(VALUE_WIDTH)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## Card caption: accent tick plus uppercase tracked label. Mirrors
## UITheme.card_title so the tick tracks the tall-window boost with everything
## else on the screen.
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


## --- Section / row shells ---------------------------------------------------

## Builds a section card and returns the VBox its rows go into. `id` is the
## SettingsManager section, which is also what the card's Reset restores.
## Small print naming the exact build and the canvas it is laying out for.
##
## Every screenshot of a layout bug so far has been ambiguous about which of
## those two things was wrong, and several turned out to be neither -- just a
## cached build from before the fix. One line makes both answerable from a
## photo of the screen.
func _build_about_footer() -> void:
	var line := Label.new()
	var view := get_viewport_rect().size
	var scale_size := Vector2i.ZERO
	var window := get_window()
	if window != null:
		scale_size = window.content_scale_size
	line.text = "Waddle Wars %s · build %s · canvas %d×%d · design %d×%d" % [
		GameConfig.GAME_VERSION, GameConfig.BUILD_ID,
		int(view.x), int(view.y), scale_size.x, scale_size.y]
	line.add_theme_font_size_override("font_size", _f(14))
	line.add_theme_color_override("font_color", Color(0.52, 0.62, 0.75, 0.75))
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sections.add_child(line)


func _section(id: String, title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	var style := UITheme.make_card_style()
	style.content_margin_left = _u(18.0)
	style.content_margin_right = _u(18.0)
	style.content_margin_top = _u(14.0)
	style.content_margin_bottom = _u(16.0)
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_child(card)
	_section_cards[id] = card
	_entrance_items.append(card)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _gap(6))
	card.add_child(body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	body.add_child(head)
	_card_title(head, title)
	head.add_child(_flex_spacer())
	var reset := UITheme.make_ghost_button("Reset", _btn(0.0, 32.0), _f(16))
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.hook_sounds(reset)
	reset.pressed.connect(_on_reset_pressed.bind(id))
	_reset_buttons[id] = reset
	head.add_child(reset)

	body.add_child(_divider())
	_row_index = 0
	return body


## Restoring a whole section is easy to hit by accident and undoes several
## choices at once, so the first press arms the button and the second commits —
## the same two-press pattern the shop and the pause menu use.
func _on_reset_pressed(section: String) -> void:
	if _reset_armed != section:
		_disarm_resets()
		_reset_armed = section
		var button: Button = _reset_buttons[section]
		button.text = "Confirm?"
		button.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
		button.add_theme_color_override("font_hover_color", UITheme.COLOR_GOLD)
		return
	_disarm_resets()
	var defaults: Dictionary = SettingsManager.default_settings().get(section, {})
	for key: Variant in defaults.keys():
		SettingsManager.set_setting(section, String(key), defaults[key])


func _disarm_resets() -> void:
	_reset_armed = ""
	for section: String in _reset_buttons.keys():
		var button: Button = _reset_buttons[section]
		if not is_instance_valid(button):
			continue
		button.text = "Reset"
		button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		button.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT)


## Shared row shell. Returns the control slot: a fixed-width right-hand block on
## a wide window, a full-width block under the label on a narrow one. Callers
## fill it with exactly one control family member.
func _row(body: VBoxContainer, label_text: String, description: String = "") -> HBoxContainer:
	var panel := PanelContainer.new()
	var style := UITheme.make_row_style(_row_index)
	style.content_margin_left = _u(14.0)
	style.content_margin_right = _u(14.0)
	style.content_margin_top = _u(9.0)
	style.content_margin_bottom = _u(9.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_row_index += 1

	var outer: BoxContainer
	if _compact:
		outer = VBoxContainer.new()
	else:
		outer = HBoxContainer.new()
	outer.add_theme_constant_override("separation", _gap(10 if _compact else UITheme.SPACE_S))
	panel.add_child(outer)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", _ui(2.0))
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(text_box)
	var name_label := _text_label(label_text, 20)
	# Wrap rather than truncate: on a 4:3 tablet the right-hand column leaves the
	# longest setting names (Pause On Controller Disconnect) short of room.
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(name_label)
	if description != "":
		var desc := _text_label(description, 15, UITheme.COLOR_TEXT_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_box.add_child(desc)

	var slot := HBoxContainer.new()
	slot.add_theme_constant_override("separation", _ui(10.0))
	slot.alignment = BoxContainer.ALIGNMENT_END
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _compact:
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		slot.custom_minimum_size.x = _u(CONTROL_COLUMN)
	outer.add_child(slot)
	return slot


## Full-width explanatory line inside a card (no control, no zebra).
func _note(body: VBoxContainer, text: String) -> Label:
	var label := _text_label(text, 15, UITheme.COLOR_TEXT_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)
	return label


## --- Control family ---------------------------------------------------------

## True when a choice list is short enough to render as a segmented pill.
func _fits_segmented(options: Array) -> bool:
	if options.size() > 3:
		return false
	for pair: Array in options:
		if String(pair[1]).length() > 10:
			return false
	return true


## Value comparison that survives the JSON round trip (ints arriving as floats)
## and the three stored kinds: bool, number, string.
static func _matches(a: Variant, b: Variant) -> bool:
	if a is bool or b is bool:
		return bool(a) == bool(b)
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return String(a) == String(b)


## The one focus affordance: an accent ring drawn outside the face, so focus
## never changes a control's size. Mirrors the ring UITheme puts on buttons.
func _focus_ring() -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Color(0.75, 0.93, 1.0, 0.98)
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(UITheme.RADIUS_BUTTON)
	ring.set_expand_margin_all(2.0)
	ring.shadow_color = Color(UITheme.COLOR_ACCENT, 0.28)
	ring.shadow_size = 6
	ring.anti_aliasing = true
	return ring


## Inset channel shared by the segmented track and the text field: the inverse
## of a raised button face, so a control that *holds* something reads as sunken.
func _inset_style(radius: int = UITheme.RADIUS_BUTTON) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UITheme.COLOR_BG_DARK, 0.55)
	box.border_color = Color(UITheme.COLOR_ACCENT, 0.20)
	box.set_border_width_all(1)
	box.border_width_top = 2
	box.border_blend = true
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	return box


## Segmented pill: every choice visible, the current one tinted. Used for
## booleans (Off / On) as well as short enums, which is what makes toggles and
## pickers read as one family instead of three widgets.
func _build_segmented(slot: HBoxContainer, options: Array, on_pick: Callable) -> Callable:
	var track := PanelContainer.new()
	var style := _inset_style()
	style.set_content_margin_all(_u(3.0))
	track.add_theme_stylebox_override("panel", style)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(track)

	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", _ui(3.0))
	track.add_child(strip)

	var buttons: Array[Button] = []
	for i: int in options.size():
		var pair: Array = options[i]
		var value: Variant = pair[0]
		var segment := Button.new()
		segment.text = String(pair[1])
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.custom_minimum_size.y = maxf(_control_height() - _u(8.0), 28.0)
		segment.clip_text = true
		segment.add_theme_font_override("font", UITheme.bold_font())
		segment.add_theme_font_size_override("font_size", _f(17))
		segment.add_theme_stylebox_override("focus", _focus_ring())
		UITheme.hook_sounds(segment)
		segment.pressed.connect(func() -> void:
			on_pick.call(value))
		strip.add_child(segment)
		buttons.append(segment)

	var apply := func(current: Variant) -> void:
		for i: int in buttons.size():
			var chosen := _matches(current, options[i][0])
			_style_segment(buttons[i], chosen, chosen and _is_off(options[i][0]))
	return apply


## "Off" is still the selected state, but it should not glow like an enabled
## one: a card of accent-tinted Offs would read as a card of things switched on.
static func _is_off(value: Variant) -> bool:
	if value is bool:
		return not bool(value)
	return value is String and String(value) == "off"


## Segment state: selected is an accent-tinted face with a rim, unselected is
## bare and dim. Deliberately *not* the promoted-primary blue — that weight is
## reserved for the screen's one real action.
func _style_segment(segment: Button, selected: bool, muted: bool = false) -> void:
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(UITheme.RADIUS_BUTTON - 3)
	normal.content_margin_left = _u(8.0)
	normal.content_margin_right = _u(8.0)
	normal.content_margin_top = _u(5.0)
	normal.content_margin_bottom = _u(5.0)
	normal.anti_aliasing = true
	if selected and muted:
		normal.bg_color = Color(0.78, 0.86, 0.96, 0.10)
		normal.border_color = Color(UITheme.COLOR_TEXT_DIM, 0.50)
		normal.set_border_width_all(1)
		normal.border_width_top = 2
		normal.border_blend = true
	elif selected:
		normal.bg_color = Color(UITheme.COLOR_ACCENT, 0.26)
		normal.border_color = Color(UITheme.COLOR_ACCENT, 0.78)
		normal.set_border_width_all(1)
		normal.border_width_top = 2
		normal.border_blend = true
		normal.shadow_color = Color(UITheme.COLOR_ACCENT, 0.18)
		normal.shadow_size = 5
	else:
		normal.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	var hover := normal.duplicate() as StyleBoxFlat
	if not selected:
		hover.bg_color = Color(0.78, 0.90, 1.0, 0.10)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.02, 0.05, 0.10, 0.45)
	segment.add_theme_stylebox_override("normal", normal)
	segment.add_theme_stylebox_override("hover", hover)
	segment.add_theme_stylebox_override("pressed", pressed)
	segment.add_theme_color_override("font_color",
		UITheme.COLOR_TEXT if selected else UITheme.COLOR_TEXT_DIM)
	segment.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT)
	segment.add_theme_color_override("font_focus_color", UITheme.COLOR_TEXT)


## Picker for choice lists too long or too wordy for a segmented pill.
func _build_picker(slot: HBoxContainer, options: Array, on_pick: Callable) -> Callable:
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picker.custom_minimum_size.y = _control_height()
	picker.add_theme_font_override("font", UITheme.bold_font())
	picker.add_theme_font_size_override("font_size", _f(18))
	UITheme.style_option_button(picker)
	for i: int in options.size():
		var pair: Array = options[i]
		picker.add_item(String(pair[1]), i)
	picker.item_selected.connect(func(index: int) -> void:
		AudioManager.ui_click()
		on_pick.call(options[index][0]))
	picker.mouse_entered.connect(AudioManager.ui_hover)
	picker.focus_entered.connect(AudioManager.ui_hover)
	slot.add_child(picker)
	# select() never emits item_selected, so the refresher cannot loop back into
	# set_setting.
	return func(current: Variant) -> void:
		for i: int in options.size():
			if _matches(current, options[i][0]):
				picker.select(i)
				return


## --- Rows -------------------------------------------------------------------

func _commit(section: String, key: String, value: Variant) -> void:
	_disarm_resets()
	SettingsManager.set_setting(section, key, value)


## Choice row. `options` is an array of [stored_value, label] pairs; the stored
## value is written back verbatim, so a key's type never drifts.
func _add_choice_row(body: VBoxContainer, section: String, key: String,
		label_text: String, options: Array, description: String = "") -> void:
	var slot := _row(body, label_text, description)
	var on_pick := func(value: Variant) -> void:
		_commit(section, key, value)
	var apply: Callable = _build_segmented(slot, options, on_pick) if _fits_segmented(options) \
		else _build_picker(slot, options, on_pick)
	apply.call(SettingsManager.get_setting(section, key))
	_refreshers["%s/%s" % [section, key]] = apply


## Boolean row — the same segmented control as any other short choice, so a
## switch is not a different species from a picker.
func _add_toggle_row(body: VBoxContainer, section: String, key: String,
		label_text: String, description: String = "") -> void:
	_add_choice_row(body, section, key, label_text,
		[[false, "Off"], [true, "On"]], description)


func _add_slider_row(body: VBoxContainer, section: String, key: String, label_text: String,
		min_value: float, max_value: float, step: float, as_percent: bool,
		description: String = "") -> void:
	var slot := _row(body, label_text, description)
	var value_label := _value_label()
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(_u(140.0), maxf(_control_height() - _u(8.0), 28.0))
	UITheme.style_slider(slider)
	var format := func(amount: float) -> String:
		return "%d%%" % int(round(amount * 100.0)) if as_percent else "%.2f" % amount
	var apply := func(value: Variant) -> void:
		slider.set_value_no_signal(float(value))
		value_label.text = String(format.call(slider.value))
	apply.call(SettingsManager.get_setting(section, key))
	slider.value_changed.connect(func(new_value: float) -> void:
		value_label.text = String(format.call(new_value))
		_commit(section, key, new_value))
	slider.mouse_entered.connect(AudioManager.ui_hover)
	slider.focus_entered.connect(AudioManager.ui_hover)
	slider.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			AudioManager.ui_click())
	slot.add_child(value_label)
	slot.add_child(slider)
	_refreshers["%s/%s" % [section, key]] = apply


## Free-text row (leaderboard display name). Commits on Enter and on focus loss
## so a player who just taps Back still keeps what they typed.
func _add_text_row(body: VBoxContainer, section: String, key: String,
		label_text: String, placeholder: String, description: String = "") -> void:
	var slot := _row(body, label_text, description)
	var edit := LineEdit.new()
	edit.max_length = 20
	edit.placeholder_text = placeholder
	edit.text = String(SettingsManager.get_setting(section, key))
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.custom_minimum_size.y = _control_height()
	edit.add_theme_font_size_override("font_size", _f(18))
	edit.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	edit.add_theme_color_override("font_placeholder_color", Color(UITheme.COLOR_TEXT_DIM, 0.6))
	edit.add_theme_color_override("caret_color", UITheme.COLOR_ACCENT)
	var normal := _inset_style()
	normal.content_margin_left = _u(12.0)
	normal.content_margin_right = _u(12.0)
	normal.content_margin_top = _u(6.0)
	normal.content_margin_bottom = _u(6.0)
	var focused := normal.duplicate() as StyleBoxFlat
	focused.border_color = Color(UITheme.COLOR_ACCENT, 0.8)
	focused.set_border_width_all(2)
	edit.add_theme_stylebox_override("normal", normal)
	edit.add_theme_stylebox_override("focus", focused)
	var commit := func() -> void:
		var wanted := edit.text.strip_edges()
		if wanted == String(SettingsManager.get_setting(section, key)):
			return
		_commit(section, key, wanted)
	edit.text_submitted.connect(func(_text: String) -> void:
		AudioManager.ui_click()
		commit.call())
	edit.focus_exited.connect(commit)
	slot.add_child(edit)
	# Never fight the player mid-word: an external change only lands while the
	# field is idle.
	var apply := func(value: Variant) -> void:
		if not edit.has_focus():
			edit.text = String(value)
	_refreshers["%s/%s" % [section, key]] = apply


## Navigation row: reads like every other row, but its control opens a screen.
func _add_link_row(body: VBoxContainer, label_text: String, description: String,
		button_text: String, target: String) -> void:
	var slot := _row(body, label_text, description)
	var button := UITheme.make_button(button_text, _btn(0.0, CONTROL_HEIGHT), _f(18))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.hook_sounds(button)
	button.pressed.connect(func() -> void:
		SceneRouter.go_to(target))
	slot.add_child(button)


## Live sensor state, plus a way to ask again.
##
## Tilt shipped defaulting to ON with no way to tell whether the sensor had
## actually been granted: on iOS the permission can be refused silently, so the
## setting read "On" while nothing moved and there was nothing anywhere to say
## why. This row says what the sensor is doing in plain words and gives the
## player a button whose press is itself the gesture the browser needs.
func _add_tilt_status_row(body: VBoxContainer) -> void:
	var slot := _row(body, "Motion Access",
		"Leaning needs the browser's permission to read the phone's motion.")
	var status := Label.new()
	status.add_theme_font_size_override("font_size", _f(17))
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot.add_child(status)

	var button := UITheme.make_button("Allow", _btn(0.0, CONTROL_HEIGHT), _f(18))
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.hook_sounds(button)
	slot.add_child(button)

	var refresh := func() -> void:
		var state := TiltSteering.permission_state()
		match state:
			"granted":
				status.text = "Working"
				status.add_theme_color_override("font_color", Color(0.55, 0.88, 0.62))
				button.visible = false
			"listening", "pending":
				status.text = "Waiting for the sensor…"
				status.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
				button.visible = false
			"denied":
				status.text = "Blocked by the browser"
				status.add_theme_color_override("font_color", Color(1.0, 0.62, 0.55))
				button.text = "Try Again"
				button.visible = true
			"nosensor", "unsupported":
				status.text = "No motion sensor on this device"
				status.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
				button.visible = false
			_:
				status.text = "Not granted yet"
				status.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
				button.text = "Allow"
				button.visible = true
	refresh.call()
	button.pressed.connect(func() -> void:
		TiltSteering.request_permission()
		refresh.call())
	# The browser answers asynchronously, so poll while this screen is open
	# rather than leaving a stale label until the player navigates away.
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(func() -> void: refresh.call())
	slot.add_child(timer)


## --- Section builders -------------------------------------------------------

func _build_display_section() -> void:
	var body := _section("display", "Display")
	_add_choice_row(body, "display", "window_mode", "Window Mode", [
		["windowed", "Windowed"], ["fullscreen", "Fullscreen"], ["borderless", "Borderless"],
	])
	_add_choice_row(body, "display", "resolution", "Resolution", [
		["1280x720", "1280 x 720"], ["1600x900", "1600 x 900"],
		["1920x1080", "1920 x 1080"], ["2560x1440", "2560 x 1440"],
	], "Windowed size. Fullscreen always uses the display's own.")
	_add_toggle_row(body, "display", "vsync", "V-Sync",
		"Matches the display's refresh rate and removes tearing.")
	_add_choice_row(body, "display", "quality_preset", "Quality Preset", [
		["low", "Low"], ["medium", "Medium"], ["high", "High"],
	], "Sets shadows, particles and effects together.")
	_add_choice_row(body, "display", "shadow_quality", "Shadow Quality", [
		["off", "Off"], ["low", "Low"], ["medium", "Medium"], ["high", "High"],
	])
	_add_choice_row(body, "display", "particle_quality", "Particle Quality", [
		["low", "Low"], ["medium", "Medium"], ["high", "High"],
	])
	_add_choice_row(body, "display", "msaa", "Anti-Aliasing", [
		["off", "Off"], ["2x", "2x"], ["4x", "4x"],
	], "MSAA. Smooths jagged edges, and costs frame rate to do it.")
	_add_choice_row(body, "display", "fps_limit", "FPS Limit", [
		[0, "Uncapped"], [30, "30"], [60, "60"], [120, "120"],
	])


func _build_audio_section() -> void:
	var body := _section("audio", "Audio")
	_add_slider_row(body, "audio", "master_volume", "Master Volume", 0.0, 1.0, 0.05, true)
	_add_slider_row(body, "audio", "music_volume", "Music Volume", 0.0, 1.0, 0.05, true)
	_add_slider_row(body, "audio", "sfx_volume", "SFX Volume", 0.0, 1.0, 0.05, true)
	_add_toggle_row(body, "audio", "muted", "Mute All",
		"Silences music and effects without losing your levels.")
	_add_toggle_row(body, "audio", "mute_unfocused", "Mute When Unfocused",
		"Goes quiet while another window has focus.")


func _build_gameplay_section() -> void:
	var body := _section("gameplay", "Gameplay")
	_add_slider_row(body, "gameplay", "steer_sensitivity", "Steer Sensitivity",
		0.5, 1.5, 0.05, true, "How sharply the penguin answers a turn.")
	# Tilt only appears where a lean can actually be read. On a desktop it
	# would be a control that does nothing, which is worse than an absent one.
	if TiltSteering.supported():
		_add_toggle_row(body, "gameplay", "tilt_steering", "Tilt Steering",
			"Lean the phone left and right to steer. Dragging still works and "
			+ "takes over whenever your finger is down.")
		_add_slider_row(body, "gameplay", "tilt_sensitivity", "Tilt Sensitivity",
			0.4, 2.0, 0.05, true, "How far you have to lean for a full turn.")
		_add_toggle_row(body, "gameplay", "tilt_invert", "Invert Tilt",
			"Swap which way the lean steers.")
		_add_tilt_status_row(body)

	_add_toggle_row(body, "gameplay", "slide_toggle_mode", "Slide: Toggle Mode",
		"On: press once to keep sliding. Off: hold the button.")
	_add_toggle_row(body, "gameplay", "tutorial_prompts", "Tutorial Prompts",
		"Control hints during a race.")
	_add_toggle_row(body, "gameplay", "vibration", "Vibration")
	_add_slider_row(body, "gameplay", "gamepad_deadzone", "Gamepad Deadzone",
		0.05, 0.6, 0.05, false, "Ignores stick movement this close to centre.")
	_add_link_row(body, "Key Bindings", "Rebind keyboard and gamepad controls.",
		"Customise", "res://scenes/menus/controls.tscn")
	_add_choice_row(body, "gameplay", "touch_controls", "Touch Controls", [
		["auto", "Auto"], ["on", "On"], ["off", "Off"],
	], "Auto shows the on-screen pad on touchscreens only.")
	_add_slider_row(body, "gameplay", "touch_scale", "Touch Button Size", 0.7, 1.4, 0.05, true)
	_add_slider_row(body, "gameplay", "touch_opacity", "Touch Button Opacity", 0.2, 1.0, 0.05, true)


func _build_accessibility_section() -> void:
	var body := _section("accessibility", "Accessibility")
	_add_choice_row(body, "accessibility", "camera_shake", "Camera Shake", [
		["full", "Full"], ["reduced", "Reduced"], ["off", "Off"],
	], "Impact and speed shake, softened or removed.")
	_add_toggle_row(body, "accessibility", "reduced_flashing", "Reduced Flashing",
		"Calms menu motion, flashes and screen effects.")
	_add_toggle_row(body, "accessibility", "high_contrast_pickups", "High-Contrast Pickups",
		"Brighter outlines on items, fish and hazards.")
	_add_toggle_row(body, "accessibility", "colorblind_cues", "Colorblind Cues",
		"Adds shapes and text wherever colour carries meaning.")
	_add_toggle_row(body, "accessibility", "audio_visual_cues", "Visual Cues For Sounds",
		"On-screen markers for sounds that matter in a race.")
	_add_toggle_row(body, "accessibility", "pause_on_disconnect", "Pause On Controller Disconnect")
	_add_slider_row(body, "accessibility", "hud_scale", "HUD Scale", 0.8, 1.4, 0.05, true,
		"Size of the in-race readouts.")
	_add_slider_row(body, "accessibility", "ui_scale", "Menu Scale", 0.8, 1.4, 0.05, true,
		"Size of menu text and controls, applied immediately.")


func _build_online_section() -> void:
	var body := _section("online", "Online")
	_add_text_row(body, "online", "display_name", "Leaderboard Name",
		"2-20 letters/numbers", "Shown beside your times on the global boards.")
	_note(body, _account_status())


## One-line description of the leaderboard account state, so the Online section
## explains what the name is actually for.
func _account_status() -> String:
	if not LeaderboardClient.can_sign_in():
		return "Play the web version to sign in and post times."
	if LeaderboardClient.signed_in:
		return "Signed in as %s — times post to the global boards." % LeaderboardClient.display_name
	return "Sign in from the Leaderboard screen to post times and back up progress."


## --- Plumbing ---------------------------------------------------------------

func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "accessibility/ui_scale":
		UITheme.apply_ui_scale(self)
	var refresher: Variant = _refreshers.get(key)
	if refresher is Callable:
		(refresher as Callable).call(value)


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()
