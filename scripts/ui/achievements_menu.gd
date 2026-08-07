extends Control
## Trophy case: a segmented collection meter that celebrates completion, the
## player's lifetime record, then the achievements split into an EARNED case
## and a STILL TO EARN case. Locked entries tease rather than grey out — every
## countable one carries a real progress bar and the closest ones float to the
## top of the list.
##
## Shares the results/main-menu design language: card radius 18, row radius 10,
## eyebrow → headline → accent rule, card titles as an accent tick plus an
## uppercase letter-spaced caption, values in the display font over small
## uppercase captions, real table columns on the right edge, and a staggered
## entrance that is skipped headless or with reduced motion on.

## Gold medallion for an earned trophy, dark padlock plaque for a locked one.
## Same circular-medal grammar as the results standings medals.
const BADGE_UNLOCKED_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
<circle cx="24" cy="24" r="21" fill="#f5c542" stroke="#c98f1b" stroke-width="2.5"/>
<circle cx="24" cy="24" r="15.5" fill="none" stroke="#c98f1b" stroke-width="1.4" opacity="0.5"/>
<path d="M24 10 L27.6 19.2 L37.4 19.9 L29.9 26.2 L32.2 35.7 L24 30.6 L15.8 35.7 L18.1 26.2 L10.6 19.9 L20.4 19.2 Z" fill="#fff4cd" stroke="#e0b030" stroke-width="1" stroke-linejoin="round"/>
</svg>"""

const BADGE_LOCKED_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
<circle cx="24" cy="24" r="21" fill="#14213a" stroke="#2b3d59" stroke-width="2.5"/>
<rect x="15" y="23" width="18" height="14" rx="3.5" fill="#42566f"/>
<path d="M19 23 V18.6 a5 5 0 0 1 10 0 V23" stroke="#42566f" stroke-width="3.4" fill="none"/>
<circle cx="24" cy="29.4" r="2.4" fill="#14213a"/>
<rect x="22.9" y="29.4" width="2.2" height="4.8" rx="1.1" fill="#14213a"/>
</svg>"""

## Authored width of the content column on the 1920x1080 desktop canvas. Touch
## and portrait viewports widen it through _measure_card_width().
const CARD_WIDTH: float = 940.0

## Corner language shared with results.gd: cards are soft, rows are tighter.
const RADIUS_CARD: int = 18
const RADIUS_ROW: int = 10

## Authored widths of the two right-hand columns every achievement row ends
## with, so the reward/progress readouts and the state chips line up into real
## columns instead of drifting with each description's length.
const COL_PROGRESS: float = 196.0
const COL_STATUS: float = 112.0

## XP granted per unlock (Progression.unlock_achievement), surfaced on earned
## rows so the case shows what each trophy was worth.
const ACHIEVEMENT_XP: int = 150

## Lifetime counters shown in the record card: save key -> caption.
const LIFETIME_STATS: Array[Array] = [
	["races_finished", "Races"],
	["races_won", "Wins"],
	["fish_total", "Fish"],
	["shoves_landed", "Shoves"],
]

## Extra enlargement for tall/narrow (portrait) viewports — see _tall_boost().
var _boost: float = 1.0
var _card_width: float = CARD_WIDTH
## Rows that cascade in after the screen's cards land, in build order.
var _reveal_items: Array[Control] = []


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)
	_boost = _tall_boost()
	_card_width = _measure_card_width()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UITheme.screen_margin())
	margin.add_theme_constant_override("margin_right", UITheme.screen_margin())
	margin.add_theme_constant_override("margin_top", _gap(22))
	margin.add_theme_constant_override("margin_bottom", _gap(20))
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	margin.add_child(layout)

	# The header is pinned outside the scroller — on a long trophy list the
	# title and the way out must not scroll away — but it is constrained to the
	# same column width as the cards so everything shares one left edge.
	var header_holder := CenterContainer.new()
	header_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(header_holder)
	var header := VBoxContainer.new()
	header.custom_minimum_size.x = _card_width
	header.add_theme_constant_override("separation", _gap(6))
	header_holder.add_child(header)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", _gap(20))
	header.add_child(top_row)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_box.add_theme_constant_override("separation", 0)
	top_row.add_child(title_box)
	var earned_count := _earned_count()
	var total := AchievementsDB.ORDER.size()
	_eyebrow(title_box, "Trophy Case · %d of %d claimed" % [earned_count, total],
		Color(UITheme.COLOR_ACCENT, 0.75))
	var title := UITheme.heading("Achievements", _heading(50))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_box.add_child(title)

	var back_button := UITheme.make_button(
		"Back", _row_size(Vector2(176, 50)), _f(22))
	back_button.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	var back_icon := UITheme.make_icon(UITheme.ICON_BACK, 1.0)
	if back_icon != null:
		back_button.icon = back_icon
		back_button.expand_icon = true
		back_button.add_theme_constant_override("icon_max_width", roundi(_u(22.0)))
		back_button.add_theme_constant_override("h_separation", roundi(_u(10.0)))
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.hook_sounds(back_button)
	back_button.pressed.connect(_go_back)
	top_row.add_child(back_button)
	header.add_child(UITheme.make_header_rule())

	var scroll := ScrollContainer.new()
	# Rows are panels and bars, which swallow touch drags before the
	# ScrollContainer can see them; this restores dragging the list on a phone.
	TouchScroll.attach(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Horizontal centring only: ScrollContainer stretches a child to its own size
	# on an axis only when that axis carries SIZE_EXPAND, so the case always
	# starts directly under the header rather than floating mid-viewport on a
	# tall screen or with a short trophy list.
	center.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = _card_width
	column.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	center.add_child(column)

	var collection := _build_collection_card(column, earned_count, total)
	var record := _build_record_card(column)
	var earned_card := _build_earned_card(column, earned_count)
	var locked_card := _build_locked_card(column, total - earned_count)

	var entrance_items: Array[Control] = [header, collection, record, earned_card, locked_card]
	if not UITheme.reduced_motion():
		UITheme.play_entrance(self, entrance_items)
	_play_reveal()

	UITheme.attach_swipe_back(self, _go_back)
	back_button.grab_focus()


## --- Layout scaling ---------------------------------------------------------
##
## The canvas_items/expand stretch pins the design height, so a portrait window
## keeps its logical width but gains logical height — every logical pixel then
## renders physically tiny and the screen shrinks into a small island. Enlarge
## by the ratio of live to design height, on top of UITheme's touch step (the
## same treatment results.gd and main_menu.gd use).
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
	return clampf(view_height / design_height, 1.0, 1.85)


## Authored font size -> on-screen size (touch step, then the tall step).
func _f(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_font(size)) * _boost))


## Display-heading size: UITheme's capped touch step, then the tall step.
func _heading(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_heading(size)) * minf(_boost, 1.5)))


## Authored horizontal metric -> on-screen metric.
func _u(value: float) -> float:
	return UITheme.scaled(value) * _boost


## Authored spacing step -> on-screen separation.
func _gap(value: int) -> int:
	return maxi(1, roundi(float(UITheme.spacing(value)) * _boost))


## Authored control size -> on-screen size, with UITheme's touch row floor.
func _row_size(size: Vector2) -> Vector2:
	var out := UITheme.scaled_size(size)
	out.y *= _boost
	return out


## Width of the content column: authored on desktop landscape, the touch
## content band on phones, most of the screen on a portrait window.
func _measure_card_width() -> float:
	if UITheme.is_touch():
		return UITheme.content_width(CARD_WIDTH, self)
	if GameConfig.is_headless() or not is_inside_tree():
		return CARD_WIDTH
	var view := get_viewport_rect().size
	if view.x <= 0.0:
		return CARD_WIDTH
	var usable := view.x - float(UITheme.screen_margin()) * 2.0
	if view.y > view.x:  # portrait window: fill it rather than float in it
		return clampf(usable, 480.0, 1700.0)
	return clampf(minf(CARD_WIDTH * _boost, view.x * 0.74), 480.0, usable)


## --- Shared building blocks -------------------------------------------------

## Small uppercase, letter-spaced context line above a headline.
func _eyebrow(parent: Control, text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(17))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


## Card shell: one radius, one border language, one padding rhythm.
func _make_card(parent: Control, accent: Color = Color(UITheme.COLOR_ACCENT, 0.22)) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = _card_width
	var style := UITheme.make_panel_style(Color(0.063, 0.114, 0.204, 0.90), accent)
	style.set_corner_radius_all(RADIUS_CARD)
	style.content_margin_left = _u(20.0)
	style.content_margin_right = _u(20.0)
	style.content_margin_top = _u(14.0)
	style.content_margin_bottom = _u(14.0)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0.0, 6.0)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _gap(8))
	panel.add_child(box)
	return box


## Card caption: uppercase, letter-spaced, behind a short accent tick, so every
## card announces itself the same way. `count` renders as a quiet trailing tally.
func _card_title(parent: Control, text: String, tint: Color = Color(UITheme.COLOR_ACCENT, 0.85),
		trailing: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(10))
	parent.add_child(row)
	var tick := ColorRect.new()
	tick.color = tint
	tick.custom_minimum_size = Vector2(_u(4.0), _u(17.0))
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tick)
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(17))
	label.add_theme_color_override("font_color", Color(0.72, 0.83, 0.94))
	row.add_child(label)
	if trailing.is_empty():
		return
	var tally := Label.new()
	tally.text = trailing.to_upper()
	tally.add_theme_font_override("font", UITheme.display_font())
	tally.add_theme_font_size_override("font_size", _f(15))
	tally.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	tally.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tally.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(tally)


## Pill chip used for the EARNED / LOCKED state column.
func _chip(text: String, fill: Color, border: Color, text_color: Color, width: float) -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size.x = _u(width)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pill := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(_u(11.0)))
	style.content_margin_left = _u(11.0)
	style.content_margin_right = _u(11.0)
	style.content_margin_top = _u(3.0)
	style.content_margin_bottom = _u(3.0)
	pill.add_theme_stylebox_override("panel", style)
	holder.add_child(pill)
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(14))
	label.add_theme_color_override("font_color", text_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.add_child(label)
	return holder


## --- Collection meter -------------------------------------------------------

## The celebration card: one segment per achievement, lit gold as it is earned,
## so the case reads as a filling trophy shelf rather than a percentage.
func _build_collection_card(parent: Control, earned: int, total: int) -> PanelContainer:
	var complete := total > 0 and earned >= total
	var accent := Color(UITheme.COLOR_GOLD, 0.55) if complete else Color(UITheme.COLOR_ACCENT, 0.22)
	var box := _make_card(parent, accent)
	_card_title(box, "Collection", Color(UITheme.COLOR_GOLD, 0.9) if complete else Color(UITheme.COLOR_ACCENT, 0.85))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(UITheme.SPACE_M))
	box.add_child(row)

	var count_box := VBoxContainer.new()
	count_box.add_theme_constant_override("separation", 0)
	count_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(count_box)
	var count_label := Label.new()
	count_label.text = "%d / %d" % [earned, total]
	count_label.add_theme_font_override("font", UITheme.display_font())
	count_label.add_theme_font_size_override("font_size", _f(40))
	count_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	count_box.add_child(count_label)
	var count_caption := Label.new()
	count_caption.text = "TROPHIES EARNED"
	count_caption.add_theme_font_override("font", UITheme.display_font())
	count_caption.add_theme_font_size_override("font_size", _f(14))
	count_caption.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	count_box.add_child(count_caption)

	var meter_box := VBoxContainer.new()
	meter_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter_box.add_theme_constant_override("separation", _gap(8))
	row.add_child(meter_box)
	meter_box.add_child(_build_segments(total, earned))

	var caption_row := HBoxContainer.new()
	caption_row.add_theme_constant_override("separation", _gap(12))
	meter_box.add_child(caption_row)
	var percent := 0 if total <= 0 else roundi(float(earned) / float(total) * 100.0)
	var left := Label.new()
	left.text = "%d%% COMPLETE" % percent
	left.add_theme_font_override("font", UITheme.display_font())
	left.add_theme_font_size_override("font_size", _f(14))
	left.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption_row.add_child(left)
	var right := Label.new()
	if complete:
		right.text = "COLLECTION COMPLETE"
		right.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	else:
		right.text = "%d TO GO · +%d XP EACH" % [total - earned, ACHIEVEMENT_XP]
		right.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	right.add_theme_font_override("font", UITheme.display_font())
	right.add_theme_font_size_override("font_size", _f(14))
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption_row.add_child(right)
	return box.get_parent() as PanelContainer


## One rounded segment per achievement, lit for the earned ones. Cheap (plain
## StyleBoxFlat panels) and it doubles as the progress bar.
func _build_segments(total: int, earned: int) -> Control:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", maxi(2, roundi(_u(3.0))))
	strip.custom_minimum_size.y = _u(14.0)
	for i: int in maxi(total, 1):
		var seg := Panel.new()
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seg.custom_minimum_size.y = _u(14.0)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(4)
		if i < earned:
			style.bg_color = UITheme.COLOR_GOLD
			style.border_color = Color(0.79, 0.56, 0.11)
			style.set_border_width_all(1)
			style.shadow_color = Color(UITheme.COLOR_GOLD, 0.30)
			style.shadow_size = 5
		else:
			style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
			style.border_color = Color(UITheme.COLOR_ACCENT, 0.18)
			style.set_border_width_all(1)
		seg.add_theme_stylebox_override("panel", style)
		strip.add_child(seg)
	return strip


## --- Lifetime record --------------------------------------------------------

func _build_record_card(parent: Control) -> PanelContainer:
	var box := _make_card(parent)
	_card_title(box, "Penguin Record")

	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", _gap(14))
	box.add_child(level_row)
	level_row.add_child(_chip("Level %d" % Progression.get_level(),
		Color(UITheme.COLOR_ACCENT, 0.14), Color(UITheme.COLOR_ACCENT, 0.5),
		UITheme.COLOR_ACCENT, 118.0))

	var xp_bar := ProgressBar.new()
	xp_bar.min_value = 0.0
	xp_bar.max_value = 1.0
	xp_bar.value = Progression.level_progress()
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(0.0, _u(14.0))
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = UITheme.COLOR_BG_DEEP
	bar_bg.set_corner_radius_all(7)
	bar_bg.set_border_width_all(1)
	bar_bg.border_color = Color(UITheme.COLOR_ACCENT, 0.28)
	xp_bar.add_theme_stylebox_override("background", bar_bg)
	xp_bar.add_theme_stylebox_override("fill",
		UITheme.make_bar_fill(Color(0.30, 0.62, 0.90), Color(0.55, 0.88, 1.0)))
	level_row.add_child(xp_bar)

	var xp_label := Label.new()
	xp_label.text = "%s / %s XP" % [
		_fmt_int(Progression.get_xp() % Progression.XP_PER_LEVEL),
		_fmt_int(Progression.XP_PER_LEVEL)]
	xp_label.add_theme_font_override("font", UITheme.display_font())
	xp_label.add_theme_font_size_override("font_size", _f(15))
	xp_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_row.add_child(xp_label)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", _gap(12))
	box.add_child(stats_row)
	for entry: Array in LIFETIME_STATS:
		stats_row.add_child(_stat_tile(
			_fmt_int(Progression.get_stat(String(entry[0]))), String(entry[1])))
	return box.get_parent() as PanelContainer


## Glass stat tile: big display value over a small uppercase caption.
func _stat_tile(value_text: String, caption_text: String) -> Control:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UITheme.make_panel_style(
		Color(0.086, 0.149, 0.251, 0.72), Color(UITheme.COLOR_ACCENT, 0.18))
	style.set_corner_radius_all(RADIUS_CARD)
	style.content_margin_left = _u(14.0)
	style.content_margin_right = _u(14.0)
	style.content_margin_top = _u(7.0)
	style.content_margin_bottom = _u(7.0)
	style.shadow_size = 5
	tile.add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	tile.add_child(stack)
	var value := Label.new()
	value.text = value_text
	value.add_theme_font_override("font", UITheme.display_font())
	value.add_theme_font_size_override("font_size", _f(28))
	value.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(value)
	var caption := Label.new()
	caption.text = caption_text.to_upper()
	caption.add_theme_font_override("font", UITheme.display_font())
	caption.add_theme_font_size_override("font_size", _f(14))
	caption.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(caption)
	return tile


## --- Trophy lists -----------------------------------------------------------

func _build_earned_card(parent: Control, earned: int) -> PanelContainer:
	var box := _make_card(parent, Color(UITheme.COLOR_GOLD, 0.28))
	_card_title(box, "Earned", Color(UITheme.COLOR_GOLD, 0.9),
		"" if earned == 0 else "%d trophies" % earned)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", _gap(6))
	box.add_child(list)
	if earned == 0:
		_empty_line(list, "No trophies yet — your first race win claims one.")
		return box.get_parent() as PanelContainer
	var index := 0
	for id: String in AchievementsDB.ORDER:
		if Progression.is_achievement_unlocked(id):
			_build_row(list, id, true, {}, index)
			index += 1
	return box.get_parent() as PanelContainer


## Locked entries, closest-first: a trophy you are 80% of the way to is a far
## better tease than an alphabetical wall of padlocks.
func _build_locked_card(parent: Control, locked: int) -> PanelContainer:
	var box := _make_card(parent)
	_card_title(box, "Still to Earn", Color(UITheme.COLOR_ACCENT, 0.85),
		"" if locked == 0 else "%d left" % locked)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", _gap(6))
	box.add_child(list)
	if locked == 0:
		_empty_line(list, "Every trophy claimed. Nothing left to chase — nice waddling.")
		return box.get_parent() as PanelContainer
	var pending: Array[Dictionary] = []
	for i: int in AchievementsDB.ORDER.size():
		var id := String(AchievementsDB.ORDER[i])
		if Progression.is_achievement_unlocked(id):
			continue
		var progress := _progress_for(id)
		var ratio := 0.0
		if not progress.is_empty() and int(progress["target"]) > 0:
			ratio = clampf(float(progress["current"]) / float(progress["target"]), 0.0, 1.0)
		pending.append({"id": id, "ratio": ratio, "order": i, "progress": progress})
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["ratio"]), float(b["ratio"])):
			return float(a["ratio"]) > float(b["ratio"])
		return int(a["order"]) < int(b["order"]))
	for i: int in pending.size():
		var entry := pending[i]
		_build_row(list, String(entry["id"]), false, entry["progress"] as Dictionary, i)
	return box.get_parent() as PanelContainer


func _empty_line(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _f(19))
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)


## One achievement as a real styled row. Earned rows are marked by a thick gold
## left edge, a gold medallion, a gold name and an EARNED chip over a quiet
## zebra — filling every earned row gold turned ten trophies into one olive
## slab and made the descriptions unreadable, so the gold is spent on the
## accents instead. Locked rows keep their name legible and carry either a live
## progress bar or a quiet LOCKED chip, so the case teases what is left rather
## than greying it into noise.
func _build_row(parent: Control, id: String, unlocked: bool, progress: Dictionary,
		index: int) -> void:
	var info := AchievementsDB.get_item(id)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_ROW)
	style.content_margin_left = _u(12.0)
	style.content_margin_right = _u(14.0)
	style.content_margin_top = _u(7.0)
	style.content_margin_bottom = _u(7.0)
	style.bg_color = Color(1.0, 1.0, 1.0, 0.05 if index % 2 == 0 else 0.014)
	# StyleBoxFlat carries one border color, so the row spends it entirely on the
	# left edge: a solid gold bar for earned, a thin cool bar for locked.
	style.set_border_width_all(0)
	if unlocked:
		style.border_color = Color(UITheme.COLOR_GOLD, 0.9)
		style.border_width_left = 5
	else:
		style.border_color = Color(UITheme.COLOR_ACCENT, 0.32)
		style.border_width_left = 3
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	_stagger(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(14))
	panel.add_child(row)
	row.add_child(_badge(unlocked))

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 1)
	row.add_child(text_box)
	var name_label := Label.new()
	name_label.text = String(info.get("name", id))
	name_label.add_theme_font_override("font", UITheme.bold_font())
	name_label.add_theme_font_size_override("font_size", _f(23))
	name_label.add_theme_color_override("font_color",
		UITheme.COLOR_GOLD if unlocked else UITheme.COLOR_TEXT)
	text_box.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = String(info.get("desc", ""))
	desc_label.add_theme_font_size_override("font_size", _f(18))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_color_override("font_color",
		Color(0.86, 0.90, 0.97) if unlocked else UITheme.COLOR_TEXT_DIM)
	text_box.add_child(desc_label)

	row.add_child(_progress_cell(unlocked, progress))
	if unlocked:
		row.add_child(_chip("Earned", Color(UITheme.COLOR_GOLD, 0.85),
			Color(UITheme.COLOR_GOLD, 0.9), Color(0.06, 0.09, 0.16), COL_STATUS))
	elif progress.is_empty():
		row.add_child(_chip("Locked", Color(1.0, 1.0, 1.0, 0.04),
			Color(1.0, 1.0, 1.0, 0.12), UITheme.COLOR_DISABLED, COL_STATUS))
	else:
		var ratio := clampf(float(progress["current"]) / maxf(float(progress["target"]), 1.0), 0.0, 1.0)
		var percent := Label.new()
		percent.text = "%d%%" % roundi(ratio * 100.0)
		percent.custom_minimum_size.x = _u(COL_STATUS)
		percent.add_theme_font_override("font", UITheme.display_font())
		percent.add_theme_font_size_override("font_size", _f(20))
		percent.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
		percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		percent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(percent)


func _badge(unlocked: bool) -> Control:
	var side := _u(46.0)
	var texture := UITheme.make_icon(BADGE_UNLOCKED_SVG if unlocked else BADGE_LOCKED_SVG, 1.0)
	if texture != null:
		var badge := TextureRect.new()
		badge.texture = texture
		badge.custom_minimum_size = Vector2(side, side)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not unlocked:
			badge.modulate = Color(1.0, 1.0, 1.0, 0.85)
		return badge
	# SVG module unavailable: keep the column, fall back to a glyph.
	var glyph := Label.new()
	glyph.text = "★" if unlocked else "🔒"
	glyph.add_theme_font_size_override("font_size", _f(30))
	glyph.add_theme_color_override("font_color",
		UITheme.COLOR_GOLD if unlocked else UITheme.COLOR_DISABLED)
	glyph.custom_minimum_size = Vector2(side, side)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return glyph


## Fixed-width right-hand column showing how far along a countable achievement
## is. Earned rows take no width here: "+150 XP" repeated down ten identical
## rows was noise, so the per-unlock reward is stated once on the collection
## card instead.
func _progress_cell(unlocked: bool, progress: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", _gap(4))
	if unlocked or progress.is_empty():
		return box
	box.custom_minimum_size.x = _u(COL_PROGRESS)
	var current := int(progress["current"])
	var target := int(progress["target"])
	var unit := String(progress.get("unit", ""))
	var ratio := clampf(float(current) / maxf(float(target), 1.0), 0.0, 1.0)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = ratio
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, _u(8.0))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.05, 0.10, 0.85)
	bg.set_corner_radius_all(4)
	bg.set_border_width_all(1)
	bg.border_color = Color(UITheme.COLOR_ACCENT, 0.22)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill",
		UITheme.make_bar_fill(Color(0.28, 0.58, 0.86), Color(0.55, 0.88, 1.0)))
	box.add_child(bar)
	var readout := Label.new()
	readout.text = "%s / %s%s" % [_fmt_int(mini(current, target)), _fmt_int(target), unit]
	readout.add_theme_font_override("font", UITheme.display_font())
	readout.add_theme_font_size_override("font_size", _f(15))
	readout.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(readout)
	return box


## --- Progress data ----------------------------------------------------------

## Live counter behind a countable achievement, as {current, target, unit}.
## Empty for the binary ones (win a race, finish a cup) — those have nothing
## honest to show a bar for.
func _progress_for(id: String) -> Dictionary:
	var raw: Variant = SaveManager.get_value("stats", {})
	var stats: Dictionary = raw as Dictionary if raw is Dictionary else {}
	match id:
		"fish_hoarder":
			return {"current": int(stats.get("fish_total", 0)), "target": 500, "unit": ""}
		"shove_master":
			return {"current": int(stats.get("shoves_landed", 0)), "target": 25, "unit": ""}
		"item_collector":
			var used_raw: Variant = stats.get("items_used", {})
			var used: Dictionary = used_raw as Dictionary if used_raw is Dictionary else {}
			var count := 0
			for pid: String in PowerupsDB.ORDER:
				if used.has(pid):
					count += 1
			return {"current": count, "target": PowerupsDB.ORDER.size(), "unit": ""}
		"long_waddle":
			return {
				"current": int(float(stats.get("endless_best_distance", 0.0))),
				"target": 2000, "unit": "m",
			}
	return {}


func _earned_count() -> int:
	var count := 0
	for id: String in AchievementsDB.ORDER:
		if Progression.is_achievement_unlocked(id):
			count += 1
	return count


## --- Motion -----------------------------------------------------------------

## Marks a freshly built row for the post-entrance cascade. Purely cosmetic.
func _stagger(item: Control) -> void:
	if GameConfig.is_headless() or UITheme.reduced_motion():
		return
	item.modulate.a = 0.0
	_reveal_items.append(item)


## Runs the row cascade once containers have finished sorting, so each row
## slides from its real resting position. Never gates input.
func _play_reveal() -> void:
	if GameConfig.is_headless() or _reveal_items.is_empty():
		return
	var tree := get_tree()
	if tree == null:
		for item: Control in _reveal_items:
			item.modulate.a = 1.0
		return
	var second_frame := func() -> void:
		_start_reveal()
	var first_frame := func() -> void:
		tree.process_frame.connect(second_frame, CONNECT_ONE_SHOT)
	tree.process_frame.connect(first_frame, CONNECT_ONE_SHOT)


func _start_reveal() -> void:
	for i: int in _reveal_items.size():
		var item := _reveal_items[i]
		if not is_instance_valid(item) or not item.is_inside_tree():
			continue
		var target := item.position.x
		item.position.x = target + 22.0
		var delay := minf(0.14 + 0.035 * float(i), 0.8)
		var tween := item.create_tween()
		tween.set_parallel(true)
		tween.tween_property(item, "modulate:a", 1.0, 0.22).set_delay(delay)
		tween.tween_property(item, "position:x", target, 0.32) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)


## 6500 -> "6,500". Big lifetime totals are easier to read grouped.
static func _fmt_int(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if value < 0 else "") + out


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()
