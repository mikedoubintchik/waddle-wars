extends Control
## Global leaderboard: a segmented course picker over a real ranked table
## (rank column, player, right-aligned value column, zebra striping and an
## unmistakable gold row for the player), the player's own local records, and
## the account block that turns a signed-out visitor into a poster.
##
## Every network state is a designed state rather than a line of grey text:
## LOADING draws shimmering skeleton rows under the live column headers,
## EMPTY draws an empty-podium invitation, ERROR draws an offline glyph with a
## Retry action, and the signed-out case becomes a proper call to action.
##
## Shares the results/main-menu design language: card radius 18, row radius 10,
## eyebrow → headline → accent rule, card titles as an accent tick plus an
## uppercase letter-spaced caption, and one promoted primary action in solid
## glacier blue (Challenge Friends) with every secondary kept quieter.

## Board tabs: one per race course, plus Endless.
##
## Built from CoursesDB rather than hand-listed. The hand-listed version named
## three courses, so the two added after it had no board at all -- a course you
## can race but cannot post a time on is a course that quietly does not count.
## Anything added to the roster from here on gets a tab for free.
static func tabs() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id: String in CoursesDB.ORDER:
		var info := CoursesDB.get_item(id)
		# First word of the course name: "Glacier Gauntlet" -> "Glacier". Tabs
		# share a row, so a full two-word name would not fit five of them.
		var full := String(info.get("name", id.capitalize()))
		var space := full.find(" ")
		list.append({"mode": "time", "course": id,
			"label": full.substr(0, space) if space > 0 else full})
	list.append({"mode": "endless", "course": "endless", "label": "Endless"})
	return list

## Authored width of the board column on the 1920x1080 desktop canvas.
const CARD_WIDTH: float = 880.0

## Corner language shared with results.gd.
const RADIUS_CARD: int = 18
const RADIUS_ROW: int = 10

## Authored table column widths. The rank chip and the value are fixed and
## right-aligned so digits form real columns instead of drifting with names.
const COL_RANK: float = 64.0
const COL_VALUE: float = 168.0

## Promoted-button face, matching the main menu's Play hero and results'
## Race Again (see _style_primary).
const PRIMARY_FILL: Color = Color(0.129, 0.361, 0.588)
const PRIMARY_FILL_HOVER: Color = Color(0.192, 0.478, 0.741)

## Podium tints, identical to the results standings.
const PODIUM_TINTS: Array[Color] = [
	Color(0.961, 0.773, 0.259),
	Color(0.788, 0.824, 0.863),
	Color(0.804, 0.561, 0.353),
]
const MEDAL_COLORS: Array[String] = ["#f5c542", "#c9d2dc", "#cd8f5a"]
const MEDAL_RIMS: Array[String] = ["#c98f1b", "#8d99a6", "#96683f"]

## Struck-through cloud for the "couldn't reach the board" state.
const ICON_OFFLINE: String = """<svg xmlns="http://www.w3.org/2000/svg" width="72" height="72" viewBox="0 0 72 72">
<path d="M22 50 h28 a12 12 0 0 0 0-24 a16 16 0 0 0-30-4 A11 11 0 0 0 22 50 Z" fill="#22344e" stroke="#3d5878" stroke-width="2.5" stroke-linejoin="round"/>
<path d="M15 15 L57 57" stroke="#ff8b7a" stroke-width="6" stroke-linecap="round"/>
</svg>"""

## Number of skeleton rows drawn while a board request is in flight.
const SKELETON_ROWS: int = 6

var _tab_index: int = 0
var _tab_buttons: Array[Button] = []
var _list_box: VBoxContainer
var _state_box: VBoxContainer
var _header_row: Control
var _board_caption: Label
var _value_caption: Label
var _records_box: VBoxContainer
var _status_label: Label
var _status_dancers: PenguinLoader = null
var _dancer_holder: CenterContainer = null
var _auth_button: Button
var _auth_label: Label
var _auth_title: Label
var _auth_card: PanelContainer = null
var _name_row: HBoxContainer = null
var _name_edit: LineEdit = null
var _name_status: Label = null
var _fetch_serial: int = 0
## Extra enlargement for tall/narrow (portrait) viewports — see _tall_boost().
var _boost: float = 1.0
var _card_width: float = CARD_WIDTH


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

	# Header and course picker stay pinned: a twenty-row board must not push the
	# way out or the tab you want to switch to off the screen.
	var header_holder := CenterContainer.new()
	header_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(header_holder)
	var header := VBoxContainer.new()
	header.custom_minimum_size.x = _card_width
	header.add_theme_constant_override("separation", _gap(8))
	header_holder.add_child(header)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", _gap(20))
	header.add_child(top_row)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_box.add_theme_constant_override("separation", 0)
	top_row.add_child(title_box)
	_eyebrow(title_box, "Global board · Top 20", Color(UITheme.COLOR_ACCENT, 0.75))
	var title := UITheme.heading("Leaderboard", _heading(50))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_box.add_child(title)
	var back := UITheme.make_button("Back", _row_size(Vector2(176, 50)), _f(22))
	back.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	var back_icon := UITheme.make_icon(UITheme.ICON_BACK, 1.0)
	if back_icon != null:
		back.icon = back_icon
		back.expand_icon = true
		back.add_theme_constant_override("icon_max_width", roundi(_u(22.0)))
		back.add_theme_constant_override("h_separation", roundi(_u(10.0)))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.hook_sounds(back)
	back.pressed.connect(_go_back)
	top_row.add_child(back)
	header.add_child(UITheme.make_header_rule())
	_build_tabs(header)

	var scroll := ScrollContainer.new()
	# Rows and buttons swallow touch drags before the ScrollContainer can see
	# them; this restores dragging the page on a phone.
	TouchScroll.attach(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Horizontal centring only. ScrollContainer stretches a child to its own size
	# on an axis only when that axis carries SIZE_EXPAND, so dropping it here
	# keeps the column at its natural height and pinned under the header —
	# with EXPAND a short page (empty board on a tall phone) floated in the
	# middle of the viewport with a dead gap under the tabs.
	center.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = _card_width
	column.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	center.add_child(column)

	var board := _build_board_card(column)
	var records := _build_records_card(column)
	_build_auth_card(column)
	var cta := _build_cta_row(column)

	UITheme.attach_swipe_back(self, _go_back)
	# Only the header takes UITheme's fade+rise. The cards below sit above a
	# panel whose height changes when the fetch lands (skeletons -> rows, or an
	# empty/error block), and a position tween running across that re-sort
	# leaves every card below it stranded at its pre-resize Y. They cascade with
	# opacity alone, which the container can never fight.
	var cards: Array[Control] = [board, records]
	if _auth_card != null:
		cards.append(_auth_card)
	cards.append(cta)
	if not UITheme.reduced_motion():
		UITheme.play_entrance(self, [header] as Array[Control])
		_fade_in(cards)
	LeaderboardClient.auth_changed.connect(_on_auth_changed)
	_select_tab(0)
	if not _tab_buttons.is_empty():
		_tab_buttons[0].grab_focus()
	AudioManager.play_music("music_title")


## Staggered opacity-only cascade for the card stack. Never touches position,
## so a card is always exactly where its container put it.
func _fade_in(items: Array[Control]) -> void:
	if GameConfig.is_headless():
		return
	for i: int in items.size():
		var item := items[i]
		item.modulate.a = 0.0
		var tween := item.create_tween()
		tween.tween_interval(0.04 + 0.06 * float(i))
		tween.tween_property(item, "modulate:a", 1.0, 0.26) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## --- Layout scaling ---------------------------------------------------------
##
## Same treatment as results.gd / main_menu.gd: a portrait window keeps its
## logical width but gains logical height, so every metric is enlarged by the
## ratio of live to design height on top of UITheme's touch step.
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


func _f(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_font(size)) * _boost))


func _heading(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_heading(size)) * minf(_boost, 1.5)))


func _u(value: float) -> float:
	return UITheme.scaled(value) * _boost


func _gap(value: int) -> int:
	return maxi(1, roundi(float(UITheme.spacing(value)) * _boost))


func _row_size(size: Vector2) -> Vector2:
	var out := UITheme.scaled_size(size)
	out.y *= _boost
	return out


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
		return clampf(usable, 440.0, 1500.0)
	return clampf(minf(CARD_WIDTH * _boost, view.x * 0.62), 440.0, usable)


## --- Shared building blocks -------------------------------------------------

func _eyebrow(parent: Control, text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(17))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


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


## Card caption: accent tick plus an uppercase, letter-spaced label. Returns the
## label so the board card can retitle itself when the course tab changes.
func _card_title(parent: Control, text: String,
		tint: Color = Color(UITheme.COLOR_ACCENT, 0.85)) -> Label:
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
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return label


## Fixed-width, right-aligned table cell so numbers form real columns.
func _cell(text: String, width: float, size: int, color: Color, bold: bool,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = _u(width)
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", UITheme.bold_font())
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _head_label(text: String, width: float,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.custom_minimum_size.x = _u(width)
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(14))
	label.add_theme_color_override("font_color", Color(0.55, 0.66, 0.80))
	label.horizontal_alignment = align
	return label


## --- Course tabs ------------------------------------------------------------

## Segmented picker: the four boards sit in one grouped strip, and the active
## segment is the only filled thing in the header.
func _build_tabs(parent: Control) -> void:
	var strip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.043, 0.086, 0.161, 0.80)
	style.border_color = Color(UITheme.COLOR_ACCENT, 0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS_CARD)
	style.content_margin_left = _u(6.0)
	style.content_margin_right = _u(6.0)
	style.content_margin_top = _u(6.0)
	style.content_margin_bottom = _u(6.0)
	strip.add_theme_stylebox_override("panel", style)
	parent.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(6))
	strip.add_child(row)
	var tab_list := tabs()
	for i: int in tab_list.size():
		var tab: Dictionary = tab_list[i]
		var button := UITheme.make_button(
			String(tab["label"]), _row_size(Vector2(0, 48)), _f(21))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		_style_tab(button)
		UITheme.hook_sounds(button)
		button.pressed.connect(_on_tab.bind(i))
		row.add_child(button)
		_tab_buttons.append(button)


func _style_tab(button: Button) -> void:
	var quiet := StyleBoxFlat.new()
	quiet.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	quiet.set_corner_radius_all(RADIUS_ROW + 2)
	quiet.content_margin_left = _u(14.0)
	quiet.content_margin_right = _u(14.0)
	quiet.content_margin_top = _u(8.0)
	quiet.content_margin_bottom = _u(8.0)
	var hover := quiet.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.07)
	hover.border_color = Color(UITheme.COLOR_ACCENT, 0.45)
	hover.set_border_width_all(1)
	var active := quiet.duplicate() as StyleBoxFlat
	active.bg_color = PRIMARY_FILL
	active.border_color = Color(UITheme.COLOR_ACCENT, 0.85)
	active.set_border_width_all(1)
	active.shadow_color = Color(UITheme.COLOR_ACCENT, 0.28)
	active.shadow_size = 7
	active.shadow_offset = Vector2(0.0, 2.0)
	var active_hover := active.duplicate() as StyleBoxFlat
	active_hover.bg_color = PRIMARY_FILL_HOVER
	button.add_theme_stylebox_override("normal", quiet)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover_pressed", active_hover)
	button.add_theme_color_override("font_color", Color(0.72, 0.82, 0.93))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(0.98, 0.995, 1.0))
	button.add_theme_color_override("font_hover_pressed_color", Color.WHITE)


## --- Board card -------------------------------------------------------------

func _build_board_card(parent: Control) -> PanelContainer:
	var box := _make_card(parent)
	# A floor height so switching between loading skeletons, an empty board and
	# an error block does not resize the page under the player's finger.
	(box.get_parent() as PanelContainer).custom_minimum_size.y = _u(300.0)
	_board_caption = _card_title(box, "Glacier Gauntlet · Best Times")

	# Column captions sit on the same fixed widths as the data cells, indented to
	# match the row content margins so headings sit over their columns.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", roundi(_u(12.0)))
	pad.add_theme_constant_override("margin_right", roundi(_u(14.0)))
	pad.add_theme_constant_override("margin_top", roundi(_u(2.0)))
	box.add_child(pad)
	_header_row = pad
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _gap(10))
	pad.add_child(head)
	head.add_child(_head_label("Rank", COL_RANK, HORIZONTAL_ALIGNMENT_LEFT))
	var player_head := _head_label("Player", 0.0, HORIZONTAL_ALIGNMENT_LEFT)
	player_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(player_head)
	_value_caption = _head_label("Time", COL_VALUE)
	head.add_child(_value_caption)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", _gap(4))
	box.add_child(_list_box)

	_state_box = VBoxContainer.new()
	_state_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Takes the slack under the rows so an empty/error block sits centred in the
	# card's floor height instead of hugging the column headers.
	_state_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_state_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_state_box.add_theme_constant_override("separation", _gap(8))
	box.add_child(_state_box)
	# Dancing penguins mark the fetch. Built once and kept parented at the top of
	# the state area for the whole screen's life: it owns a SubViewport and a 3D
	# penguin, so rebuilding it per tab switch (or orphaning it on the way to
	# another state) would churn real resources.
	if not GameConfig.is_headless():
		_dancer_holder = CenterContainer.new()
		_dancer_holder.visible = false
		_state_box.add_child(_dancer_holder)
		_status_dancers = PenguinLoader.new(150.0)
		_dancer_holder.add_child(_status_dancers)
	# Kept for the fetch caption; parented into whichever state block is live.
	_status_label = Label.new()
	_status_label.add_theme_font_override("font", UITheme.display_font())
	_status_label.add_theme_font_size_override("font_size", _f(16))
	_status_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return box.get_parent() as PanelContainer


## Circular medal with ribbon for the podium ranks, matching the results
## standings. Place is drawn as pip dots (the rasterizer has no <text>).
static func _medal_svg(place: int) -> String:
	var fill := MEDAL_COLORS[place]
	var rim := MEDAL_RIMS[place]
	var pips := ""
	var count := place + 1
	for i: int in count:
		var x := 18.0 + (float(i) - float(count - 1) * 0.5) * 7.0
		pips += "<circle cx=\"%.1f\" cy=\"30\" r=\"2.6\" fill=\"%s\"/>" % [x, rim]
	return """<svg xmlns="http://www.w3.org/2000/svg" width="36" height="48" viewBox="0 0 36 48">
<path d="M10 2 L18 16 L26 2 L20 2 L18 6 L16 2 Z" fill="#5a7ba6"/>
<path d="M10 2 L14 2 L20 13 L16 16 Z" fill="#48648a"/>
<circle cx="18" cy="30" r="14" fill="%s" stroke="%s" stroke-width="2.5"/>
<circle cx="18" cy="30" r="9.5" fill="none" stroke="%s" stroke-width="1.5" opacity="0.55"/>
%s
</svg>""" % [fill, rim, rim, pips]


## Rank cell: a medal for the podium, a round numeral chip otherwise, both drawn
## inside the same fixed box so every row keeps one rhythm.
func _rank_cell(rank: int) -> Control:
	var box := CenterContainer.new()
	var side := _u(COL_RANK)
	box.custom_minimum_size = Vector2(side, side * 0.62)
	if rank >= 1 and rank <= 3:
		var texture := UITheme.make_icon(_medal_svg(rank - 1), 1.0)
		if texture != null:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.custom_minimum_size = Vector2(side * 0.50, side * 0.62)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			box.add_child(icon)
			return box
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.145, 0.216, 0.333, 0.85)
	style.border_color = Color(UITheme.COLOR_ACCENT, 0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(side * 0.5))
	style.content_margin_left = _u(2.0)
	style.content_margin_right = _u(2.0)
	style.content_margin_top = _u(2.0)
	style.content_margin_bottom = _u(2.0)
	chip.add_theme_stylebox_override("panel", style)
	chip.custom_minimum_size = Vector2(side * 0.58, side * 0.58)
	var numeral := Label.new()
	numeral.text = str(rank)
	numeral.add_theme_font_override("font", UITheme.bold_font())
	numeral.add_theme_font_size_override("font_size", _f(18))
	numeral.add_theme_color_override("font_color", Color(0.74, 0.83, 0.93))
	numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	numeral.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(numeral)
	box.add_child(chip)
	return box


## Small gold YOU pill appended to the player's name.
func _you_pill() -> Control:
	var pill := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UITheme.COLOR_GOLD, 0.85)
	style.set_corner_radius_all(roundi(_u(9.0)))
	style.content_margin_left = _u(9.0)
	style.content_margin_right = _u(9.0)
	style.content_margin_top = _u(1.0)
	style.content_margin_bottom = _u(1.0)
	pill.add_theme_stylebox_override("panel", style)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = "YOU"
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(13))
	label.add_theme_color_override("font_color", Color(0.06, 0.09, 0.16))
	pill.add_child(label)
	return pill


## One board row as a real styled row: the player's is a filled gold card with a
## thick left edge and a glow, podium rows carry a faint warm wash, everyone
## else alternates a barely-there zebra.
func _make_row(rank: int, name_text: String, value_text: String, highlight: bool,
		index: int = 0) -> Control:
	var podium := rank >= 1 and rank <= 3
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_ROW)
	style.content_margin_left = _u(12.0)
	style.content_margin_right = _u(14.0)
	style.content_margin_top = _u(3.0)
	style.content_margin_bottom = _u(3.0)
	if highlight:
		style.bg_color = Color(UITheme.COLOR_GOLD.r, UITheme.COLOR_GOLD.g, UITheme.COLOR_GOLD.b, 0.15)
		style.border_color = Color(UITheme.COLOR_GOLD, 0.55)
		style.set_border_width_all(1)
		style.border_width_left = 5
		style.shadow_color = Color(UITheme.COLOR_GOLD, 0.16)
		style.shadow_size = 8
	elif podium:
		style.bg_color = Color(0.161, 0.239, 0.365, 0.42)
		style.border_color = Color(0.78, 0.88, 1.0, 0.10)
		style.set_border_width_all(1)
	else:
		style.bg_color = Color(1.0, 1.0, 1.0, 0.035 if index % 2 == 0 else 0.0)
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(10))
	panel.add_child(row)
	var color := _row_color(highlight, rank)
	row.add_child(_rank_cell(rank))

	var name_box := HBoxContainer.new()
	name_box.add_theme_constant_override("separation", _gap(10))
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_box)
	var name_label := _cell(name_text, 0.0, 23 if (podium or highlight) else 22,
		color, podium or highlight, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_box.add_child(name_label)
	if highlight and name_text.to_lower() != "you":
		name_box.add_child(_you_pill())

	row.add_child(_cell(value_text, COL_VALUE, 24, color, true))
	return panel


static func _row_color(highlight: bool, rank: int) -> Color:
	if highlight:
		return Color(1.0, 0.9, 0.4)
	if rank >= 1 and rank <= PODIUM_TINTS.size():
		return PODIUM_TINTS[rank - 1]
	return Color(0.9, 0.94, 1.0)


## --- Board states -----------------------------------------------------------

## Clears the rows and the state block so a state can be drawn fresh.
func _clear_board() -> void:
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	# The status label outlives every state block, so it is detached before the
	# block that held it is freed. The penguin loader's holder is a permanent
	# child of _state_box and is skipped entirely.
	if _status_label.get_parent() != null:
		_status_label.get_parent().remove_child(_status_label)
	for child in _state_box.get_children():
		if child == _dancer_holder:
			continue
		_state_box.remove_child(child)
		child.queue_free()


## Grey placeholder rows while a request is in flight — the board keeps its
## shape instead of collapsing to a blank rectangle, so the switch to real data
## never jumps the layout.
func _show_loading(tab: Dictionary) -> void:
	_clear_board()
	_header_row.visible = true
	_status_label.text = "Fetching %s times…" % String(tab["label"])
	for i: int in SKELETON_ROWS:
		_list_box.add_child(_skeleton_row(i))
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", _gap(4))
	_state_box.add_child(block)
	block.add_child(_status_label)


func _skeleton_row(index: int) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_ROW)
	style.bg_color = Color(1.0, 1.0, 1.0, 0.035 if index % 2 == 0 else 0.015)
	style.content_margin_left = _u(12.0)
	style.content_margin_right = _u(14.0)
	style.content_margin_top = _u(9.0)
	style.content_margin_bottom = _u(9.0)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(10))
	panel.add_child(row)
	row.add_child(_skeleton_bar(_u(COL_RANK) * 0.5, false))
	row.add_child(_skeleton_bar(_u(120.0 + float((index * 37) % 90)), true))
	row.add_child(_skeleton_bar(_u(COL_VALUE) * 0.6, false))
	if not GameConfig.is_headless() and not UITheme.reduced_motion():
		panel.modulate.a = 0.45
		var tween := panel.create_tween()
		tween.set_loops()
		tween.tween_interval(0.09 * float(index))
		tween.tween_property(panel, "modulate:a", 0.95, 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(panel, "modulate:a", 0.45, 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return panel


func _skeleton_bar(width: float, expand: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, _u(14.0))
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if expand:
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := Panel.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	if expand:
		bar.anchor_right = 0.0
		bar.offset_right = width
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.62, 0.76, 0.92, 0.16)
	style.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("panel", style)
	holder.add_child(bar)
	return holder


## Centered illustration + headline + body used by the empty and error states,
## with an optional action so a dead end always offers a way forward.
func _show_message(icon_svg: String, headline: String, body: String,
		action_text: String, action: Callable) -> void:
	_clear_board()
	_header_row.visible = false
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", _gap(8))
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state_box.add_child(block)
	var pad := Control.new()
	pad.custom_minimum_size.y = _u(10.0)
	block.add_child(pad)
	var texture := UITheme.make_icon(icon_svg, 1.0)
	if texture != null:
		var holder := CenterContainer.new()
		block.add_child(holder)
		var icon := TextureRect.new()
		icon.texture = texture
		icon.custom_minimum_size = Vector2(_u(88.0), _u(88.0))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate.a = 0.9
		holder.add_child(icon)
	var title := Label.new()
	title.text = headline
	title.add_theme_font_override("font", UITheme.display_font())
	title.add_theme_font_size_override("font_size", _f(26))
	title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(title)
	_status_label.text = body
	block.add_child(_status_label)
	if action_text.is_empty():
		var tail := Control.new()
		tail.custom_minimum_size.y = _u(10.0)
		block.add_child(tail)
		return
	var holder_row := CenterContainer.new()
	block.add_child(holder_row)
	var button := UITheme.make_button(action_text, _row_size(Vector2(210, 48)), _f(21))
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	holder_row.add_child(button)


## --- Local records ----------------------------------------------------------

## The board the player always has, online or not: their own bests, with the
## row for the selected tab lit gold so the two cards read as one screen.
func _build_records_card(parent: Control) -> PanelContainer:
	var box := _make_card(parent)
	_card_title(box, "Your Records", Color(UITheme.COLOR_GOLD, 0.9))
	_records_box = VBoxContainer.new()
	_records_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_records_box.add_theme_constant_override("separation", _gap(4))
	box.add_child(_records_box)
	return box.get_parent() as PanelContainer


func _refresh_records() -> void:
	if _records_box == null:
		return
	for child in _records_box.get_children():
		_records_box.remove_child(child)
		child.queue_free()
	var active_course := String(tabs()[_tab_index]["course"])
	var index := 0
	for course_id: String in CoursesDB.ORDER:
		var best := Progression.best_time(course_id)
		_records_box.add_child(_record_row(
			CoursesDB.display_name(course_id),
			"—" if best <= 0.0 else RaceHUD.format_time(best),
			course_id == active_course, index))
		index += 1
	var high := Progression.endless_high_score()
	_records_box.add_child(_record_row("Endless Expedition",
		"—" if high <= 0 else _fmt_int(high), active_course == "endless", index))


func _record_row(name_text: String, value_text: String, active: bool, index: int) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_ROW)
	style.content_margin_left = _u(12.0)
	style.content_margin_right = _u(14.0)
	style.content_margin_top = _u(5.0)
	style.content_margin_bottom = _u(5.0)
	if active:
		style.bg_color = Color(UITheme.COLOR_GOLD.r, UITheme.COLOR_GOLD.g, UITheme.COLOR_GOLD.b, 0.13)
		style.border_color = Color(UITheme.COLOR_GOLD, 0.45)
		style.set_border_width_all(1)
		style.border_width_left = 5
	else:
		style.bg_color = Color(1.0, 1.0, 1.0, 0.035 if index % 2 == 0 else 0.0)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(10))
	panel.add_child(row)
	var color := Color(1.0, 0.9, 0.4) if active else Color(0.9, 0.94, 1.0)
	var name_label := _cell(name_text, 0.0, 22, color, active, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)
	var unset := value_text == "—"
	row.add_child(_cell(value_text, COL_VALUE, 23,
		Color(color, 0.45) if unset else color, not unset))
	return panel


## --- Account ----------------------------------------------------------------

## One card that carries all three account states: a call to action when signed
## out, the name editor when signed in, and an honest note on builds that
## cannot sign in at all.
func _build_auth_card(parent: Control) -> void:
	var box := _make_card(parent)
	_auth_card = box.get_parent() as PanelContainer
	_auth_title = _card_title(box, "Post Your Times")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(16))
	box.add_child(row)
	_auth_label = Label.new()
	_auth_label.add_theme_font_size_override("font_size", _f(19))
	_auth_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_auth_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auth_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_auth_label)
	if LeaderboardClient.can_sign_in():
		_auth_button = UITheme.make_button("Sign In", _row_size(Vector2(190, 48)), _f(21))
		# Accent-outlined rather than solid: the one solid glacier-blue action on
		# this screen is Challenge Friends, and two filled buttons would fight.
		_auth_button.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
		_auth_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UITheme.hook_sounds(_auth_button)
		_auth_button.pressed.connect(func() -> void:
			if LeaderboardClient.signed_in:
				LeaderboardClient.sign_out()
			else:
				_auth_button.text = "Opening…"
				LeaderboardClient.sign_in())
		row.add_child(_auth_button)

	# Signed-in players pick the name shown on the boards.
	_name_row = HBoxContainer.new()
	_name_row.add_theme_constant_override("separation", _gap(12))
	_name_row.visible = false
	box.add_child(_name_row)
	var name_label := Label.new()
	name_label.text = "BOARD NAME"
	name_label.add_theme_font_override("font", UITheme.display_font())
	name_label.add_theme_font_size_override("font_size", _f(14))
	name_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.max_length = 20
	_name_edit.placeholder_text = "2-20 letters/numbers"
	_name_edit.custom_minimum_size = _row_size(Vector2(260, 46))
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_edit.add_theme_font_size_override("font_size", _f(20))
	var edit_style := StyleBoxFlat.new()
	edit_style.bg_color = Color(0.031, 0.063, 0.125, 0.9)
	edit_style.border_color = Color(UITheme.COLOR_ACCENT, 0.3)
	edit_style.set_border_width_all(1)
	edit_style.set_corner_radius_all(RADIUS_ROW)
	edit_style.content_margin_left = _u(12.0)
	edit_style.content_margin_right = _u(12.0)
	_name_edit.add_theme_stylebox_override("normal", edit_style)
	var focus_style := edit_style.duplicate() as StyleBoxFlat
	focus_style.border_color = Color(UITheme.COLOR_ACCENT, 0.85)
	focus_style.set_border_width_all(2)
	_name_edit.add_theme_stylebox_override("focus", focus_style)
	_name_row.add_child(_name_edit)
	var save_button := UITheme.make_button("Save", _row_size(Vector2(112, 46)), _f(20))
	save_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.hook_sounds(save_button)
	save_button.pressed.connect(func() -> void:
		var wanted := _name_edit.text.strip_edges()
		if wanted.length() < 2:
			_set_name_status("Name needs at least 2 characters.", true)
			return
		save_button.text = "…"
		LeaderboardClient.set_display_name(wanted, func(ok: bool, data: Dictionary) -> void:
			if not is_instance_valid(save_button):
				return
			save_button.text = "Save"
			if ok:
				_set_name_status("Saved as %s" % String(data.get("name", wanted)), false)
				_select_tab(_tab_index)
			else:
				_set_name_status("Couldn't save name: %s" % String(data.get("error", "error")), true)))
	_name_row.add_child(save_button)

	_name_status = Label.new()
	_name_status.add_theme_font_size_override("font_size", _f(17))
	_name_status.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_name_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_status.visible = false
	box.add_child(_name_status)
	_refresh_auth_row()


func _set_name_status(text: String, is_error: bool) -> void:
	if _name_status == null:
		return
	_name_status.text = text
	_name_status.visible = true
	_name_status.add_theme_color_override("font_color",
		Color(1.0, 0.55, 0.45) if is_error else Color(0.62, 0.94, 0.68))


func _refresh_auth_row() -> void:
	if LeaderboardClient.can_sign_in():
		if LeaderboardClient.signed_in:
			_auth_title.text = "ACCOUNT"
			_auth_label.text = "Signed in as %s. Your times post automatically and your progress backs up to the cloud." % LeaderboardClient.display_name
			_auth_button.text = "Sign Out"
			_auth_button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		else:
			_auth_title.text = "POST YOUR TIMES"
			_auth_label.text = "Sign in to put your runs on the global board and back your progress up to the cloud."
			_auth_button.text = "Opening…" if LeaderboardClient.sign_in_pending else "Sign In"
			_auth_button.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	else:
		_auth_title.text = "POST YOUR TIMES"
		_auth_label.text = "Browsing works everywhere, but posting needs the web version — play at %s to claim a spot on these boards." % \
			ShareManager.SHARE_URL.trim_prefix("https://")
	if _name_row != null:
		_name_row.visible = LeaderboardClient.can_sign_in() and LeaderboardClient.signed_in
		if _name_row.visible and _name_edit.text.is_empty():
			var stored := String(SettingsManager.get_setting("online", "display_name"))
			_name_edit.text = stored if not stored.is_empty() else LeaderboardClient.display_name
		if not _name_row.visible and _name_status != null:
			_name_status.visible = false


## --- Call to action ---------------------------------------------------------

func _build_cta_row(parent: Control) -> Control:
	var holder := CenterContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(holder)
	# navigator.share needs the press's user gesture, so share runs directly in
	# the handler; the clipboard fallback confirms with a toast.
	var challenge := ShareManager.make_share_button(
		"Challenge Friends", _row_size(Vector2(340, 60)), _f(25))
	challenge.add_theme_constant_override("icon_max_width", roundi(_u(28.0)))
	challenge.add_theme_constant_override("h_separation", roundi(_u(12.0)))
	_style_primary(challenge)
	UITheme.hook_sounds(challenge)
	challenge.pressed.connect(func() -> void:
		ShareManager.share_with_toast(self, ShareManager.compose_challenge_text()))
	holder.add_child(challenge)
	return holder


## Filled ice-blue treatment for the screen's one promoted action, identical to
## the main menu's Play hero and results' Race Again.
func _style_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal",
		_primary_box(PRIMARY_FILL, Color(UITheme.COLOR_ACCENT, 0.85), 8))
	button.add_theme_stylebox_override("hover",
		_primary_box(PRIMARY_FILL_HOVER, Color(0.90, 0.98, 1.0, 0.95), 14))
	button.add_theme_stylebox_override("pressed",
		_primary_box(PRIMARY_FILL.darkened(0.35), Color(UITheme.COLOR_GOLD, 0.9), 2))
	button.add_theme_color_override("font_color", Color(0.98, 0.995, 1.0))


static func _primary_box(bg: Color, border: Color, shadow: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	box.content_margin_left = 22.0
	box.content_margin_right = 22.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	box.shadow_color = Color(UITheme.COLOR_ACCENT, 0.30)
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0.0, 3.0)
	return box


## --- Fetch flow -------------------------------------------------------------

func _on_auth_changed() -> void:
	_refresh_auth_row()
	_select_tab(_tab_index)


func _on_tab(index: int) -> void:
	AudioManager.ui_click()
	_select_tab(index)


func _select_tab(index: int) -> void:
	_tab_index = index
	for i: int in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == index
	var tab: Dictionary = tabs()[index]
	var mode := String(tab["mode"])
	_board_caption.text = ("%s · %s" % [
		_board_name(tab), "Best Times" if mode == "time" else "High Scores"]).to_upper()
	_value_caption.text = "TIME" if mode == "time" else "SCORE"
	_refresh_records()
	_set_busy(true)
	_show_loading(tab)
	_fetch_serial += 1
	var serial := _fetch_serial
	LeaderboardClient.fetch_board(mode, String(tab["course"]), 20,
		func(ok: bool, data: Dictionary) -> void:
			if not is_inside_tree() or serial != _fetch_serial:
				return
			_populate(ok, data, tab))


func _populate(ok: bool, data: Dictionary, tab: Dictionary) -> void:
	_set_busy(false)
	if not ok:
		_show_message(ICON_OFFLINE, "Board unreachable",
			"We couldn't reach the global leaderboard. Check your connection — your local records below are always available.",
			"Try Again", func() -> void: _select_tab(_tab_index))
		return
	var entries: Array = data.get("entries", [])
	if entries.is_empty():
		_show_message(UITheme.ICON_PODIUM, "No times posted yet",
			"Nobody has claimed %s. Set a run and the top of this board is yours." % _board_name(tab),
			"", Callable())
		return
	_clear_board()
	_header_row.visible = true
	var mode := String(tab["mode"])
	var me: Variant = data.get("me")
	var my_rank := int((me as Dictionary).get("rank", -1)) if me is Dictionary else -1
	var index := 0
	for entry: Variant in entries:
		if not (entry is Dictionary):
			continue
		var row := entry as Dictionary
		var rank := int(row.get("rank", 0))
		_list_box.add_child(_make_row(
			rank, String(row.get("name", "?")),
			LeaderboardClient.format_value(mode, int(row.get("value", 0))),
			rank == my_rank and LeaderboardClient.signed_in, index))
		index += 1
	if me is Dictionary and my_rank > entries.size():
		_list_box.add_child(_gap_marker())
		_list_box.add_child(_make_row(
			my_rank, "You",
			LeaderboardClient.format_value(mode, int((me as Dictionary).get("value", 0))),
			true, index))


## Full name of the board behind a tab ("Glacier" -> "Glacier Gauntlet"), used
## by the card title and the empty-state copy so the screen never refers to a
## course by its short tab label.
static func _board_name(tab: Dictionary) -> String:
	if String(tab["mode"]) == "time":
		return CoursesDB.display_name(String(tab["course"]))
	return "Endless Expedition"


## 3213 -> "3,213". Endless scores get big.
static func _fmt_int(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if value < 0 else "") + out


## Ellipsis divider between the visible top of the board and the player's own
## row further down it.
func _gap_marker() -> Control:
	var label := Label.new()
	label.text = "· · ·"
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(18))
	label.add_theme_color_override("font_color", Color(UITheme.COLOR_ACCENT, 0.45))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()


## Toggles the dancing-penguin busy row (headless builds have none). Hiding the
## holder also parks the loader's SubViewport, so an idle board costs nothing.
func _set_busy(busy: bool) -> void:
	if _dancer_holder != null and is_instance_valid(_dancer_holder):
		_dancer_holder.visible = busy
