extends Control
## Post-race results — the emotional payoff of a run. Placement headline over
## a stat strip, a standings table whose rows are real styled rows (medal chip,
## tabular time/gap/fish columns, an unmistakable player row), animated reward
## tiles, Grand Prix standings between rounds, the cup ceremony after the final
## round, and records for Time Trial / Endless.

const MEDAL_COLORS: Array[String] = ["#f5c542", "#c9d2dc", "#cd8f5a"]
const MEDAL_RIMS: Array[String] = ["#c98f1b", "#8d99a6", "#96683f"]

## Row text tints for podium places: gold / silver / bronze.
const PODIUM_TINTS: Array[Color] = [
	Color(0.961, 0.773, 0.259),
	Color(0.788, 0.824, 0.863),
	Color(0.804, 0.561, 0.353),
]

## Same drawn fish glyph as the menu and HUD currency counters
## (main_menu.gd / customize_menu.gd / race_hud.gd) so fish read identically
## on every screen.
const FISH_ICON_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="60" height="40" viewBox="0 0 60 40">
<path d="M3 20 L19 8 L19 32 Z" fill="#6fc0ee"/>
<ellipse cx="34" cy="21" rx="21" ry="12" fill="#8fd8f8"/>
<path d="M26 11 Q35 3 44 11 Q35 15 26 11 Z" fill="#5fb0e2"/>
<path d="M20 21 Q34 31 50 22 Q34 27 20 21 Z" fill="#5fb0e2" opacity="0.7"/>
<circle cx="45" cy="17" r="3.2" fill="#0e2036"/>
<circle cx="46.2" cy="15.8" r="1.1" fill="#ffffff"/>
</svg>"""

## XP spark: the reward tile's counterpart to the fish glyph.
const XP_ICON_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
<path d="M24 3 L29 17 L43 22 L29 27 L24 41 L19 27 L5 22 L19 17 Z" fill="#9ff0a8" stroke="#4f9a5e" stroke-width="2" stroke-linejoin="round"/>
<path d="M24 12 L26.5 20 L24 28 L21.5 20 Z" fill="#e6ffe9" opacity="0.75"/>
</svg>"""

## Authored width of the results column on a 1920x1080 desktop canvas. Touch
## and tall/narrow viewports widen it through _measure_card_width().
const CARD_WIDTH: float = 900.0

## Authored standings column widths (position chip / time / gap / fish). The
## data columns are fixed and right-aligned so digits line up as a table
## instead of drifting with each name's length.
const COL_POS: float = 58.0
const COL_TIME: float = 152.0
const COL_GAP: float = 116.0
const COL_FISH: float = 92.0

## Corner language for the screen: cards are soft, rows are tighter, chips are
## pills. Shared here so results never mixes radii by accident.
const RADIUS_CARD: int = 18
const RADIUS_ROW: int = 10

## Promoted-button face, matching the main menu's Play hero (see _style_primary).
const PRIMARY_FILL: Color = Color(0.129, 0.361, 0.588)
const PRIMARY_FILL_HOVER: Color = Color(0.192, 0.478, 0.741)

var _buttons: Array[Button] = []
## Extra enlargement for tall/narrow (portrait) viewports — see _tall_boost().
var _boost: float = 1.0
var _card_width: float = CARD_WIDTH
## Rows/tiles that cascade in after the screen's blocks land, in build order.
var _reveal_items: Array[Control] = []


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)
	_boost = _tall_boost()
	_card_width = _measure_card_width()
	_add_celebration_glow()

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	vbox.custom_minimum_size.x = _card_width
	center.add_child(vbox)

	match Game.mode:
		Game.Mode.ENDLESS:
			_build_endless(vbox)
		Game.Mode.TIME_TRIAL:
			_build_time_trial(vbox)
		Game.Mode.TUTORIAL:
			_build_tutorial(vbox)
		Game.Mode.GRAND_PRIX:
			_build_race_results(vbox)
			_build_gp_standings(vbox)
		_:
			_build_race_results(vbox)

	_build_rewards(vbox)
	_build_buttons(vbox)
	var entrance_items: Array[Control] = []
	for child in vbox.get_children():
		if child is Control:
			entrance_items.append(child as Control)
	UITheme.play_entrance(self, entrance_items)
	_play_reveal()
	AudioManager.play_music("music_title")
	if not _buttons.is_empty():
		_buttons[0].grab_focus()
		# follow_focus keeps later gamepad/keyboard navigation on screen, but it
		# also scrolls the freshly focused button into view — on a long screen
		# (Grand Prix: two tables) that would open on the buttons instead of the
		# player's placement. Snap back to the top once the focus settles.
		_scroll_to_top(scroll)


func _scroll_to_top(scroll: ScrollContainer) -> void:
	if GameConfig.is_headless():
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.process_frame.connect(func() -> void:
		if is_instance_valid(scroll):
			scroll.scroll_vertical = 0,
		CONNECT_ONE_SHOT)


## --- Layout scaling ---------------------------------------------------------
##
## The canvas_items/expand stretch pins the design height, so a portrait window
## keeps 1920 logical units of width but gains logical height — every logical
## pixel then renders physically tiny and the whole screen shrinks into a small
## island. Menus that care (this one and the main menu) enlarge their own
## metrics by the ratio of live to design height, on top of UITheme's touch
## step, so a portrait phone reads as a phone app rather than a shrunk desktop.
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


## Authored horizontal metric -> on-screen metric.
func _u(value: float) -> float:
	return UITheme.scaled(value) * _boost


## Authored spacing step -> on-screen separation.
func _gap(value: int) -> int:
	return maxi(1, roundi(float(UITheme.spacing(value)) * _boost))


## Width of the results column: the authored width on desktop landscape, the
## touch content band on phones, and most of the screen on a portrait window.
func _measure_card_width() -> float:
	if UITheme.is_touch():
		return UITheme.content_width(CARD_WIDTH, self)
	if GameConfig.is_headless() or not is_inside_tree():
		return CARD_WIDTH
	var view := get_viewport_rect().size
	if view.x <= 0.0:
		return CARD_WIDTH
	if view.y > view.x:  # portrait window: fill it rather than float in it
		return clampf(view.x * 0.86, CARD_WIDTH, 1700.0)
	return minf(CARD_WIDTH * _boost, view.x * 0.72)


## Warm radial glow behind the headline area; brighter gold when the player
## podiumed so the screen reads celebratory at a glance.
func _add_celebration_glow() -> void:
	var podium := false
	for row: Dictionary in Game.last_race_results:
		if bool(row.get("is_player", false)) and int(row.get("position", 8)) <= 3:
			podium = true
	var grad := Gradient.new()
	var core := Color(0.96, 0.78, 0.28, 0.22) if podium else Color(0.5, 0.75, 0.95, 0.13)
	grad.colors = PackedColorArray([core, Color(core.r, core.g, core.b, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.18)
	tex.fill_to = Vector2(0.5, 0.75)
	var glow := TextureRect.new()
	glow.texture = tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)


## --- Shared building blocks -------------------------------------------------

## Small uppercase, letter-spaced context line above a headline ("QUICK RACE ·
## GLACIER GAUNTLET"). Sets the typographic hierarchy: tiny eyebrow, huge
## headline, medium stat strip.
func _eyebrow(parent: Control, text: String, color: Color = UITheme.COLOR_TEXT_DIM) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(19))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _headline(parent: Control, text: String, size: int, color: Color) -> Label:
	# scaled_heading applies the touch step and its landscape cap; the tall step
	# then goes on top, because a portrait viewport has the height to spare.
	var label := UITheme.heading(text, roundi(float(UITheme.scaled_heading(size)) * _boost))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


## Hero block: eyebrow, headline, accent rule. Returns the VBox so callers can
## keep adding into the same tight group.
func _hero(parent: Control, eyebrow: String, headline: String, size: int, color: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _gap(6))
	parent.add_child(box)
	if not eyebrow.is_empty():
		_eyebrow(box, eyebrow, Color(UITheme.COLOR_ACCENT, 0.75))
	_headline(box, headline, size, color)
	var rule := UITheme.accent_rule(_u(200.0), color)
	box.add_child(rule)
	return box


## Row of small glass stat tiles ({"value", "caption"} dictionaries). This is
## the line that makes a finish land: place, time, margin — big value over a
## quiet uppercase caption.
func _stat_strip(parent: Control, stats: Array[Dictionary], accent: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	for stat: Dictionary in stats:
		var tile := PanelContainer.new()
		# A lone tile stays its natural width and centers; two or more share the
		# column evenly so the strip reads as one measured band.
		if stats.size() > 1:
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			tile.custom_minimum_size.x = _u(190.0)
		var highlight := bool(stat.get("highlight", false))
		var style := UITheme.make_panel_style(
			Color(0.086, 0.149, 0.251, 0.72) if not highlight else Color(accent.r, accent.g, accent.b, 0.14),
			Color(accent, 0.55 if highlight else 0.18))
		style.set_corner_radius_all(RADIUS_CARD)
		style.content_margin_left = _u(16.0)
		style.content_margin_right = _u(16.0)
		style.content_margin_top = _u(7.0)
		style.content_margin_bottom = _u(7.0)
		style.shadow_size = 5
		tile.add_theme_stylebox_override("panel", style)
		row.add_child(tile)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 0)
		tile.add_child(stack)
		var value := Label.new()
		value.text = String(stat.get("value", ""))
		value.add_theme_font_override("font", UITheme.display_font())
		value.add_theme_font_size_override("font_size", _f(32))
		value.add_theme_color_override("font_color", accent if highlight else UITheme.COLOR_TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(value)
		var caption := Label.new()
		caption.text = String(stat.get("caption", "")).to_upper()
		caption.add_theme_font_override("font", UITheme.display_font())
		caption.add_theme_font_size_override("font_size", _f(15))
		caption.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(caption)


## Card shell shared by the standings, rewards and record blocks: one radius,
## one border language, one padding rhythm.
func _make_panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = _card_width
	var style := UITheme.make_panel_style(
		Color(0.063, 0.114, 0.204, 0.90), Color(UITheme.COLOR_ACCENT, 0.22))
	style.set_corner_radius_all(RADIUS_CARD)
	style.content_margin_left = _u(20.0)
	style.content_margin_right = _u(20.0)
	style.content_margin_top = _u(14.0)
	style.content_margin_bottom = _u(14.0)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0.0, 6.0)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


## Card caption: uppercase, letter-spaced, with a short accent tick in front so
## every card announces itself the same way.
func _card_title(parent: Control, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(10))
	parent.add_child(row)
	var tick := ColorRect.new()
	tick.color = Color(UITheme.COLOR_ACCENT, 0.85)
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


## Circular medal glyph with ribbon for podium positions (0-indexed place).
## Place is shown as pip dots (SVG <text> is unsupported by the rasterizer).
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


## Position cell: a medal for the podium, a round numeral chip otherwise, both
## drawn inside the same fixed box so every row keeps one rhythm.
func _position_cell(place_number: int) -> Control:
	var box := CenterContainer.new()
	var side := _u(COL_POS)
	box.custom_minimum_size = Vector2(side, side * 0.66)
	if place_number >= 1 and place_number <= 3:
		var texture := UITheme.make_icon(_medal_svg(place_number - 1), 1.0)
		if texture != null:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.custom_minimum_size = Vector2(side * 0.56, side * 0.66)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			box.add_child(icon)
			return box
	var chip := PanelContainer.new()
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(0.145, 0.216, 0.333, 0.85)
	chip_style.border_color = Color(UITheme.COLOR_ACCENT, 0.16)
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(roundi(side * 0.5))
	chip_style.content_margin_left = _u(2.0)
	chip_style.content_margin_right = _u(2.0)
	chip_style.content_margin_top = _u(2.0)
	chip_style.content_margin_bottom = _u(2.0)
	chip.add_theme_stylebox_override("panel", chip_style)
	chip.custom_minimum_size = Vector2(side * 0.62, side * 0.62)
	var numeral := Label.new()
	numeral.text = str(place_number)
	numeral.add_theme_font_override("font", UITheme.bold_font())
	numeral.add_theme_font_size_override("font_size", _f(19))
	numeral.add_theme_color_override("font_color", Color(0.74, 0.83, 0.93))
	numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	numeral.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(numeral)
	box.add_child(chip)
	return box


## Row text color: player row reads highlighted gold, podium rows carry their
## medal tint, everyone else stays neutral ice-white.
static func _row_color(is_player: bool, place_number: int) -> Color:
	if is_player:
		return Color(1.0, 0.9, 0.4)
	if place_number >= 1 and place_number <= PODIUM_TINTS.size():
		return PODIUM_TINTS[place_number - 1]
	return Color(0.9, 0.94, 1.0)


## One standings row as a real styled row rather than a grid line: the player's
## row is a filled gold card with a thick left edge and a YOU pill, podium rows
## get a faint warm wash, everyone else alternates a barely-there zebra.
func _make_row(parent: Control, index: int, is_player: bool, podium: bool) -> HBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_ROW)
	style.content_margin_left = _u(12.0)
	style.content_margin_right = _u(14.0)
	style.content_margin_top = _u(3.0)
	style.content_margin_bottom = _u(3.0)
	if is_player:
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
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(10))
	panel.add_child(row)
	_stagger(panel)
	return row


## Name column: the racer's name packed left, with the gold YOU pill sitting
## right beside it (not drifting to the far edge of the column) and the rest of
## the space pushed toward the numeric columns.
func _name_cell(parent: Control, text: String, size: int, color: Color,
		bold: bool, is_player: bool) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", _gap(10))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(box)
	var label := _cell(text, 0.0, size, color, bold, HORIZONTAL_ALIGNMENT_LEFT)
	# clip_text zeroes a Label's minimum width, so measure the name and ask for
	# exactly that (capped) — the name keeps its natural width, an absurdly long
	# one is trimmed instead of shoving the numeric columns off the card.
	var font: Font = UITheme.bold_font() if bold else ThemeDB.fallback_font
	var text_width := font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _f(size)).x
	label.custom_minimum_size.x = minf(text_width + 2.0, _u(260.0))
	label.clip_text = true
	box.add_child(label)
	# The default player name already reads "You"; the pill is only worth the
	# space when a custom/online name would otherwise hide who the player is.
	if is_player and text.to_lower() != "you":
		box.add_child(_you_pill())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)


## Small gold "YOU" pill appended to the player's name.
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
	label.add_theme_font_size_override("font_size", _f(14))
	label.add_theme_color_override("font_color", Color(0.06, 0.09, 0.16))
	pill.add_child(label)
	return pill


## Marks a freshly built row/tile for the post-entrance cascade. Purely
## cosmetic: the item is hidden now and revealed by _play_reveal().
func _stagger(item: Control) -> void:
	if GameConfig.is_headless():
		return
	item.modulate.a = 0.0
	_reveal_items.append(item)


## Runs the standings/reward cascade once containers have finished sorting, so
## each row slides from its real resting position. Never gates input: buttons
## are already focusable and the tweens only touch modulate/position.
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
		var delay := minf(0.14 + 0.04 * float(i), 0.8)
		var tween := item.create_tween()
		tween.set_parallel(true)
		tween.tween_property(item, "modulate:a", 1.0, 0.22).set_delay(delay)
		tween.tween_property(item, "position:x", target, 0.32) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)


## Counts a number up into `label` (e.g. "+57"). Cosmetic only: the final text
## is written immediately headless and the tween never gates input.
func _count_up(label: Label, to_value: int, prefix: String) -> void:
	if GameConfig.is_headless() or to_value <= 0:
		label.text = "%s%s" % [prefix, _fmt_int(to_value)]
		return
	label.text = "%s0" % prefix
	var tween := label.create_tween()
	tween.tween_interval(0.35)
	tween.tween_method(func(value: float) -> void:
		if is_instance_valid(label):
			label.text = "%s%s" % [prefix, _fmt_int(int(round(value)))],
		0.0, float(to_value), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 3830 -> "3,830". Big totals are easier to read grouped.
static func _fmt_int(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if value < 0 else "") + out


static func _ordinal(place: int) -> String:
	if place <= 0:
		return "—"
	var suffix := "th"
	if place % 100 < 11 or place % 100 > 13:
		match place % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [place, suffix]


static func _mode_name() -> String:
	match Game.mode:
		Game.Mode.GRAND_PRIX:
			return "Grand Prix"
		Game.Mode.TIME_TRIAL:
			return "Time Trial"
		Game.Mode.ENDLESS:
			return "Endless Expedition"
		Game.Mode.TUTORIAL:
			return "Waddle School"
		_:
			return "Quick Race"


## --- Race results -----------------------------------------------------------

func _build_race_results(parent: Control) -> void:
	var player_row: Dictionary = {}
	for row: Dictionary in Game.last_race_results:
		if bool(row.get("is_player", false)):
			player_row = row
	var pos := int(player_row.get("position", 8))
	var dnf := bool(player_row.get("dnf", false))
	var headline := "Race Complete!"
	var tint := Color(0.95, 0.97, 1.0)
	if pos == 1:
		headline = "VICTORY!"
		tint = UITheme.COLOR_GOLD
	elif pos <= 3:
		headline = "Podium Finish!"
		tint = PODIUM_TINTS[maxi(pos - 1, 0)]
	var eyebrow := "%s · %s" % [_mode_name(), CoursesDB.display_name(Game.course_id)]
	var hero := _hero(parent, eyebrow, headline, 58, tint)

	# Player-facing summary: where they finished, what it took, and the margin
	# to the racer that matters (2nd when they won, the leader otherwise).
	var winner_time := 0.0
	var runner_up_time := 0.0
	for row: Dictionary in Game.last_race_results:
		var place := int(row.get("position", 0))
		if place == 1:
			winner_time = float(row.get("time", 0.0))
		elif place == 2:
			runner_up_time = float(row.get("time", 0.0))
	var stats: Array[Dictionary] = []
	stats.append({"value": _ordinal(pos), "caption": "Finish", "highlight": true})
	if not player_row.is_empty():
		stats.append({
			"value": "DNF" if dnf else RaceHUD.format_time(float(player_row.get("time", 0.0))),
			"caption": "Your Time",
		})
		var player_time := float(player_row.get("time", 0.0))
		if not dnf and Game.last_race_results.size() > 1:
			if pos == 1 and runner_up_time > 0.0:
				stats.append({"value": "+%.2fs" % (runner_up_time - player_time), "caption": "Margin"})
			elif winner_time > 0.0:
				stats.append({"value": "+%.2fs" % (player_time - winner_time), "caption": "Behind"})
		stats.append({"value": str(int(player_row.get("fish", 0))), "caption": "Fish"})
	_stat_strip(hero, stats, tint)

	var panel := _make_panel(parent)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", _gap(4))
	panel.add_child(list)
	_card_title(list, "Final Standings")
	_standings_header(list)
	for i: int in Game.last_race_results.size():
		var row: Dictionary = Game.last_race_results[i]
		var is_player := bool(row.get("is_player", false))
		var place := int(row.get("position", 0))
		var podium := place >= 1 and place <= 3
		var color := _row_color(is_player, place)
		var line := _make_row(list, i, is_player, podium)
		line.add_child(_position_cell(place))
		_name_cell(line, String(row.get("name", "?")),
			25 if (podium or is_player) else 23, color, podium or is_player, is_player)
		var row_dnf := bool(row.get("dnf", false))
		var row_time := float(row.get("time", 0.0))
		line.add_child(_cell("DNF" if row_dnf else RaceHUD.format_time(row_time),
			COL_TIME, 24, color, podium or is_player))
		var gap_text := "—"
		if not row_dnf and winner_time > 0.0 and place > 1:
			gap_text = "+%.2f" % (row_time - winner_time)
		line.add_child(_cell(gap_text, COL_GAP, 20,
			Color(color, 0.62) if place > 1 else Color(color, 0.45), false))
		line.add_child(_cell(str(int(row.get("fish", 0))), COL_FISH, 24, color, is_player))


## Column captions above the standings rows, on the same fixed widths as the
## data cells so headings sit over their columns.
func _standings_header(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(10))
	# Match the row content margins so headings align with the cells below.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", roundi(_u(12.0)))
	pad.add_theme_constant_override("margin_right", roundi(_u(14.0)))
	pad.add_theme_constant_override("margin_top", roundi(_u(4.0)))
	pad.add_child(row)
	parent.add_child(pad)
	var head_color := Color(0.55, 0.66, 0.80)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = _u(COL_POS)
	row.add_child(spacer)
	var racer := _head_label("Racer", 0.0, head_color, HORIZONTAL_ALIGNMENT_LEFT)
	racer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(racer)
	row.add_child(_head_label("Time", COL_TIME, head_color))
	row.add_child(_head_label("Gap", COL_GAP, head_color))
	row.add_child(_head_label("Fish", COL_FISH, head_color))


func _head_label(text: String, width: float, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.custom_minimum_size.x = _u(width)
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(14))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	return label


## --- Grand Prix -------------------------------------------------------------

func _build_gp_standings(parent: Control) -> void:
	var panel := _make_panel(parent)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", _gap(4))
	panel.add_child(list)
	_card_title(list, "Cup Standings — Round %d of %d" % [
		mini(Game.gp_round + 1, CoursesDB.GRAND_PRIX_ORDER.size()),
		CoursesDB.GRAND_PRIX_ORDER.size()])
	var standings := Game.gp_standings()
	var leader_points := int(standings[0]["points"]) if not standings.is_empty() else 0
	for i: int in standings.size():
		var row: Dictionary = standings[i]
		var is_player := String(row.get("key", "")) == "player"
		var color := _row_color(is_player, i + 1)
		var line := _make_row(list, i, is_player, i < 3)
		line.add_child(_position_cell(i + 1))
		_name_cell(line, String(row["name"]), 24 if (is_player or i < 3) else 22,
			color, is_player or i < 3, is_player)
		var points := int(row["points"])
		var behind := leader_points - points
		line.add_child(_cell("—" if behind <= 0 else "-%d" % behind, COL_GAP, 20,
			Color(color, 0.6), false))
		line.add_child(_cell("%d pts" % points, COL_TIME, 24, color, true))
	if Game.is_final_gp_round():
		var standings_sorted := standings
		if not standings_sorted.is_empty():
			var winner := String(standings_sorted[0]["name"])
			var ceremony := _hero(parent, "Cup Ceremony", "%s wins the cup!" % winner, 42,
				UITheme.COLOR_GOLD)
			_build_podium(ceremony, standings_sorted)
			var player_place := 1
			for i: int in standings_sorted.size():
				if String(standings_sorted[i].get("key", "")) == "player":
					player_place = i + 1
			Game.gp_round = CoursesDB.GRAND_PRIX_ORDER.size()  # mark complete
			Progression.submit_gp_result(Game.difficulty_id, player_place, int(standings_sorted[player_place - 1]["points"]) if player_place <= standings_sorted.size() else 0)
			AudioManager.play_sfx("sfx_victory")


## Cup ceremony: 3D podium with the top three penguins, winner celebrating.
func _build_podium(parent: Control, standings: Array[Dictionary]) -> void:
	if GameConfig.is_headless():
		return
	var frame := PanelContainer.new()
	var frame_style := UITheme.make_panel_style(
		Color(0.055, 0.098, 0.176, 0.55), Color(UITheme.COLOR_GOLD, 0.30))
	frame_style.set_corner_radius_all(RADIUS_CARD)
	frame_style.content_margin_left = _u(10.0)
	frame_style.content_margin_right = _u(10.0)
	frame_style.content_margin_top = _u(10.0)
	frame_style.content_margin_bottom = _u(10.0)
	frame.add_theme_stylebox_override("panel", frame_style)
	parent.add_child(frame)

	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(
		minf(_card_width - _u(24.0), 720.0), _u(250.0))
	viewport_container.stretch = true
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport_container.add_child(viewport)
	UITheme.crisp_subviewport(viewport, self)
	frame.add_child(viewport_container)

	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.6, 4.6)
	camera.rotation_degrees = Vector3(-8, 0, 0)
	camera.fov = 45.0
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.4
	world.add_child(light)

	var heights := [1.0, 0.65, 0.4]
	var slots := [Vector3(0, 0, 0), Vector3(-1.5, 0, 0.3), Vector3(1.5, 0, 0.3)]
	var podium_colors := [Color(1.0, 0.85, 0.25), Color(0.8, 0.85, 0.9), Color(0.8, 0.6, 0.4)]
	var penguins: Array[PenguinVisual] = []
	for i: int in mini(3, standings.size()):
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.2, float(heights[i]), 1.2)
		box.mesh = mesh
		box.material_override = PenguinVisual.get_material(podium_colors[i], 0.3, 0.4)
		box.position = slots[i] + Vector3(0, float(heights[i]) * 0.5, 0)
		world.add_child(box)
		var key := String(standings[i].get("key", ""))
		var penguin := PenguinVisual.new()
		if key == "player":
			var body := CosmeticsDB.get_item(Progression.get_equipped("body"))
			penguin.setup({
				"body_color": body.get("body_color", Color(0.13, 0.16, 0.22)),
				"belly_color": body.get("belly_color", Color(0.95, 0.94, 0.9)),
				"hat": Progression.get_equipped("hat"),
			})
		else:
			var info := PersonalitiesDB.get_item(key)
			penguin.setup({
				"body_color": info.get("body_color", Color(0.13, 0.16, 0.22)),
				"belly_color": info.get("belly_color", Color(0.95, 0.94, 0.9)),
			})
		penguin.position = slots[i] + Vector3(0, float(heights[i]), 0)
		penguin.rotation.y = PI  # penguin forward is -Z; camera sits at +Z
		penguin.set_pose(PenguinVisual.Pose.CELEBRATE if i == 0 else PenguinVisual.Pose.IDLE)
		world.add_child(penguin)
		penguins.append(penguin)
	var ticker := Timer.new()
	ticker.wait_time = 1.0 / 30.0
	ticker.autostart = true
	ticker.timeout.connect(func() -> void:
		for penguin: PenguinVisual in penguins:
			penguin.tick(1.0 / 30.0, 0.5))
	viewport_container.add_child(ticker)


## --- Endless / Time Trial / Tutorial ----------------------------------------

func _build_endless(parent: Control) -> void:
	var result := Game.last_endless_result
	var record := bool(result.get("is_record", false))
	var tint := UITheme.COLOR_GOLD if record else Color(0.95, 0.97, 1.0)
	var hero := _hero(parent, "Endless Expedition", "Expedition Over!", 62, tint)
	if record:
		_badge(hero, "★  NEW HIGH SCORE  ★")
	var score := int(result.get("score", 0))
	var stats: Array[Dictionary] = [
		{"value": _fmt_int(score), "caption": "Score", "highlight": true},
		{"value": "%dm" % int(result.get("distance", 0.0)), "caption": "Distance"},
		{"value": str(int(result.get("fish", 0))), "caption": "Fish"},
		{"value": _fmt_int(Progression.endless_high_score()), "caption": "Best"},
	]
	_stat_strip(hero, stats, tint)
	_build_online_section(parent, "endless", "endless", score)


func _build_time_trial(parent: Control) -> void:
	var row: Dictionary = Game.last_race_results[0] if not Game.last_race_results.is_empty() else {}
	var record := bool(row.get("is_record", false))
	var tint := UITheme.COLOR_GOLD if record else Color(0.6, 0.95, 1.0)
	var time_value := float(row.get("time", 0.0))
	var hero := _hero(parent, "%s · %s" % [_mode_name(), CoursesDB.display_name(Game.course_id)],
		RaceHUD.format_time(time_value), 76, tint)
	if record:
		_badge(hero, "★  NEW RECORD  ★")
	# The run's time is already the headline, so the strip carries context
	# instead of repeating it: the standing best and how far off it this run
	# was. On a record run both of those *are* the headline, so only the fish
	# count remains and the strip collapses to a single centered chip.
	var best := Progression.best_time(Game.course_id)
	var stats: Array[Dictionary] = []
	if best > 0.0 and not record:
		stats.append({"value": RaceHUD.format_time(best), "caption": "Personal Best"})
		if time_value > best:
			stats.append({"value": "+%.2fs" % (time_value - best), "caption": "Off Best"})
	stats.append({"value": str(int(row.get("fish", 0))), "caption": "Fish",
		"highlight": record})
	_stat_strip(hero, stats, tint)
	_build_online_section(parent, "time", Game.course_id, int(round(time_value * 1000.0)))


func _build_tutorial(parent: Control) -> void:
	var hero := _hero(parent, "Waddle School", "Lesson Complete!", 60, Color(0.95, 0.97, 1.0))
	var line := UITheme.sub_label("You're ready to race, champ.", _f(26))
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(line)


## Gold pill used for record / high-score callouts.
func _badge(parent: Control, text: String) -> void:
	var holder := CenterContainer.new()
	parent.add_child(holder)
	var badge := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UITheme.COLOR_GOLD, 0.16)
	style.border_color = Color(UITheme.COLOR_GOLD, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(_u(18.0)))
	style.content_margin_left = _u(20.0)
	style.content_margin_right = _u(20.0)
	style.content_margin_top = _u(5.0)
	style.content_margin_bottom = _u(5.0)
	badge.add_theme_stylebox_override("panel", style)
	holder.add_child(badge)
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(22))
	label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	badge.add_child(label)
	# Looping ambient flourish, so it goes through the reduced-motion gate the
	# way every other continuous menu animation does.
	if not GameConfig.is_headless() and not UITheme.reduced_motion():
		var tween := badge.create_tween().set_loops()
		tween.tween_property(badge, "modulate:a", 0.72, 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(badge, "modulate:a", 1.0, 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Optional global leaderboard hook. Signed in: auto-post and show rank.
## Signed out on web: offer Clerk sign-in, then post. Desktop: stay quiet —
## boards are still viewable from the main menu.
func _build_online_section(parent: Control, mode: String, course: String, value: int) -> void:
	if GameConfig.is_headless() or value <= 0:
		return
	var label := UITheme.sub_label("", _f(22))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = _card_width
	var submit := func() -> void:
		label.text = "Posting to global leaderboard…"
		LeaderboardClient.submit_score(mode, course, value,
			func(ok: bool, data: Dictionary) -> void:
				if not is_instance_valid(label):
					return
				if not ok:
					label.text = "Couldn't reach the leaderboard."
					return
				var rank := int(data.get("rank", 0))
				if bool(data.get("improved", false)):
					label.text = "★ Global rank #%d — new personal best posted!" % rank
				else:
					label.text = "Global rank #%d (your best: %s)" % [
						rank, LeaderboardClient.format_value(mode, int(data.get("best", value)))])
	if LeaderboardClient.signed_in:
		parent.add_child(label)
		submit.call()
	elif LeaderboardClient.can_sign_in():
		label.text = "Sign in to post your score to the global leaderboard"
		parent.add_child(label)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		parent.add_child(row)
		var button := UITheme.make_button("Sign In", UITheme.scaled_size(Vector2(240, 52)), _f(22))
		UITheme.hook_sounds(button)
		button.pressed.connect(func() -> void:
			button.text = "Opening…"
			LeaderboardClient.sign_in())
		row.add_child(button)
		LeaderboardClient.auth_changed.connect(func() -> void:
			if LeaderboardClient.signed_in and is_instance_valid(label):
				if is_instance_valid(button):
					button.visible = false
				submit.call(),
			CONNECT_ONE_SHOT)


## --- Rewards ----------------------------------------------------------------

func _build_rewards(parent: Control) -> void:
	var rewards := Game.last_rewards
	if rewards.is_empty():
		return
	var fish_gain := int(rewards.get("fish", 0))
	var xp_gain := int(rewards.get("xp", 0))
	var panel := _make_panel(parent)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	panel.add_child(stack)
	_card_title(stack, "Rewards")
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	stack.add_child(tiles)
	_fish_tile(tiles, fish_gain)
	_xp_tile(tiles, xp_gain)


## Reward tile shell: icon rail on the left, content on the right.
func _reward_tile(parent: Control, accent: Color, icon_svg: String,
		icon_size: Vector2) -> VBoxContainer:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UITheme.make_panel_style(
		Color(accent.r, accent.g, accent.b, 0.10), Color(accent, 0.34))
	style.set_corner_radius_all(RADIUS_ROW + 2)
	style.content_margin_left = _u(18.0)
	style.content_margin_right = _u(18.0)
	style.content_margin_top = _u(12.0)
	style.content_margin_bottom = _u(12.0)
	style.shadow_size = 6
	tile.add_theme_stylebox_override("panel", style)
	parent.add_child(tile)
	_stagger(tile)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(14))
	tile.add_child(row)
	var texture := UITheme.make_icon(icon_svg, 1.5)
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.custom_minimum_size = Vector2(_u(icon_size.x), _u(icon_size.y))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", _gap(3))
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(stack)
	return stack


func _fish_tile(parent: Control, gain: int) -> void:
	var accent := Color(0.55, 0.85, 0.95)
	var stack := _reward_tile(parent, accent, FISH_ICON_SVG, Vector2(60.0, 40.0))
	var value := Label.new()
	value.add_theme_font_override("font", UITheme.display_font())
	value.add_theme_font_size_override("font_size", _f(34))
	value.add_theme_color_override("font_color", accent)
	stack.add_child(value)
	_count_up(value, gain, "+")
	var caption := Label.new()
	caption.text = "FISH EARNED  ·  %s TOTAL" % _fmt_int(Progression.get_fish())
	caption.add_theme_font_override("font", UITheme.display_font())
	caption.add_theme_font_size_override("font_size", _f(15))
	caption.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	stack.add_child(caption)


func _xp_tile(parent: Control, gain: int) -> void:
	var accent := Color(0.7, 0.95, 0.6)
	var stack := _reward_tile(parent, accent, XP_ICON_SVG, Vector2(40.0, 40.0))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", _gap(10))
	stack.add_child(top)
	var value := Label.new()
	value.add_theme_font_override("font", UITheme.display_font())
	value.add_theme_font_size_override("font_size", _f(34))
	value.add_theme_color_override("font_color", accent)
	top.add_child(value)
	_count_up(value, gain, "+")
	var xp_word := Label.new()
	xp_word.text = "XP"
	xp_word.add_theme_font_override("font", UITheme.display_font())
	xp_word.add_theme_font_size_override("font_size", _f(20))
	xp_word.add_theme_color_override("font_color", Color(accent, 0.75))
	xp_word.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(xp_word)

	# Level bar: fills from where the player stood before this run's XP landed,
	# so the reward is visibly what moved it.
	var level := Progression.get_level()
	var xp_now := Progression.get_xp()
	var xp_before := maxi(0, xp_now - gain)
	var level_before := 1 + xp_before / Progression.XP_PER_LEVEL
	var levelled := level_before < level
	var progress_from := 0.0 if levelled else float(xp_before % Progression.XP_PER_LEVEL) / float(Progression.XP_PER_LEVEL)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = progress_from
	bar.custom_minimum_size = Vector2(0.0, _u(14.0))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.043, 0.078, 0.137, 0.92)
	track.set_corner_radius_all(7)
	track.border_color = Color(accent, 0.30)
	track.set_border_width_all(1)
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", UITheme.make_bar_fill(
		Color(0.42, 0.78, 0.52), Color(0.78, 0.98, 0.66)))
	stack.add_child(bar)
	var caption := Label.new()
	caption.text = "LEVEL %d  ·  %d / %d XP" % [
		level, xp_now % Progression.XP_PER_LEVEL, Progression.XP_PER_LEVEL]
	caption.add_theme_font_override("font", UITheme.display_font())
	caption.add_theme_font_size_override("font_size", _f(15))
	caption.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	stack.add_child(caption)
	if levelled:
		var up := Label.new()
		up.text = "LEVEL UP!"
		up.add_theme_font_override("font", UITheme.display_font())
		up.add_theme_font_size_override("font_size", _f(17))
		up.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
		stack.add_child(up)
	if not GameConfig.is_headless():
		var target := Progression.level_progress()
		var tween := bar.create_tween()
		tween.tween_interval(0.35)
		tween.tween_property(bar, "value", target, 0.7) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## --- Actions ----------------------------------------------------------------

func _build_buttons(parent: Control) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(hbox)
	if Game.mode == Game.Mode.GRAND_PRIX and Game.gp_round < CoursesDB.GRAND_PRIX_ORDER.size() - 1:
		_add_button(hbox, "Next Race", func() -> void:
			Game.advance_grand_prix(), true)
	elif Game.mode == Game.Mode.GRAND_PRIX:
		_add_button(hbox, "Finish Cup", func() -> void:
			SceneRouter.go_to(Game.SCENE_MAIN_MENU), true)
	else:
		_add_button(hbox, "Race Again", func() -> void:
			SceneRouter.go_to(Game.SCENE_RACE), true)
	_add_share_button(hbox)
	_add_button(hbox, "Main Menu", func() -> void:
		SceneRouter.go_to(Game.SCENE_MAIN_MENU), false)


## Share copy for the finished run, or "" when there is nothing worth
## bragging about (tutorial, missing result handoff).
func _share_text() -> String:
	# A completed daily shares as a challenge rather than a boast: the link
	# carries the day, so whoever opens it races the identical course and
	# field. That is the only share in the game the recipient can accept.
	if not Game.daily_result.is_empty():
		var daily_row: Dictionary = {}
		for row: Dictionary in Game.last_race_results:
			if bool(row.get("is_player", false)):
				daily_row = row
		if not daily_row.is_empty() and not bool(daily_row.get("dnf", false)):
			return ShareManager.compose_daily_text(
				DailyChallenge.for_day(),
				RaceHUD.format_time(float(daily_row.get("time", 0.0))),
				int(Game.daily_result.get("streak", 0)))
	match Game.mode:
		Game.Mode.TUTORIAL:
			return ""
		Game.Mode.ENDLESS:
			var score := int(Game.last_endless_result.get("score", 0))
			if score <= 0:
				return ""
			return ShareManager.compose_race_text("endless", "", 0, str(score))
		Game.Mode.TIME_TRIAL:
			if Game.last_race_results.is_empty():
				return ""
			var row: Dictionary = Game.last_race_results[0]
			return ShareManager.compose_race_text(
				"time_trial", CoursesDB.display_name(Game.course_id), 0,
				RaceHUD.format_time(float(row.get("time", 0.0))))
		_:
			var player_row: Dictionary = {}
			for row: Dictionary in Game.last_race_results:
				if bool(row.get("is_player", false)):
					player_row = row
			if player_row.is_empty():
				return ""
			var time_text := "" if bool(player_row.get("dnf", false)) \
				else RaceHUD.format_time(float(player_row.get("time", 0.0)))
			var mode_tag := "grand_prix" if Game.mode == Game.Mode.GRAND_PRIX else "race"
			return ShareManager.compose_race_text(
				mode_tag, CoursesDB.display_name(Game.course_id),
				int(player_row.get("position", 0)), time_text)


## Share sits between the primary continue action and Main Menu. The native
## share sheet must open from inside the press (browser user gesture), so the
## handler calls ShareManager directly; the clipboard path toasts "Copied!".
func _add_share_button(parent: Control) -> void:
	var text := _share_text()
	if text.is_empty():
		return
	var button := ShareManager.make_share_button(
		"Share", UITheme.scaled_size(Vector2(210.0, 56.0)), _f(24))
	UITheme.hook_sounds(button)
	button.pressed.connect(func() -> void:
		ShareManager.share_with_toast(self, text))
	parent.add_child(button)
	_buttons.append(button)


func _add_button(parent: Control, text: String, action: Callable, primary: bool) -> void:
	var size := Vector2(270.0, 62.0) if primary else Vector2(210.0, 56.0)
	var button := UITheme.make_button(text, UITheme.scaled_size(size), _f(28 if primary else 24))
	if primary:
		_style_primary(button)
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)


## Filled ice-blue treatment for the one action the player most likely wants
## next. Same corner radius and margins as UITheme.make_button so the family
## stays coherent — only the fill weight changes.
func _style_primary(button: Button) -> void:
	# Solid, saturated face: a translucent accent wash reads as disabled, and
	# darkening COLOR_ACCENT (a pale cyan) only greys it. Same glacier blue the
	# main menu promotes Play with, so "the action to take next" looks the same
	# on both screens.
	button.add_theme_stylebox_override("normal",
		_primary_box(PRIMARY_FILL, Color(UITheme.COLOR_ACCENT, 0.85), 2, 8))
	button.add_theme_stylebox_override("hover",
		_primary_box(PRIMARY_FILL_HOVER, Color(0.90, 0.98, 1.0, 0.95), 2, 14))
	button.add_theme_stylebox_override("pressed",
		_primary_box(PRIMARY_FILL.darkened(0.35), Color(UITheme.COLOR_GOLD, 0.9), 2, 2))
	button.add_theme_color_override("font_color", Color(0.98, 0.995, 1.0))


static func _primary_box(bg: Color, border: Color, width: int, shadow: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(12)
	box.content_margin_left = 20.0
	box.content_margin_right = 20.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	box.shadow_color = Color(UITheme.COLOR_ACCENT, 0.28)
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0.0, 3.0)
	return box
