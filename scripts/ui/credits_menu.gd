extends Control
## End credits.
##
## A real roll rather than a static list: the column starts a beat after the
## screen lands and creeps upward at a readable pace, stops itself at the end,
## and hands control back the moment the reader scrolls or drags. Reduced motion
## and headless runs get the same content standing still.
##
## Typography follows the house ramp used by results and the main menu: an
## eyebrow over the wordmark, an accent rule, then credit blocks of a small
## uppercase tracked role over a display-font name. The engineering-partner
## credit is a card — a tick-and-caption plate with the name as type and the
## link as one quiet control, rather than a gold call-to-action button parked in
## the middle of the roll.
##
## Every authored size below is the desktop value; UITheme.scaled* enlarges them
## on touch devices only.

const NINJA_URL: String = "https://ninjaconsulting.ai"
const NINJA_NAME: String = "Ninja Consulting"

## External-link glyph in the same hand-drawn style as the UITheme icon set.
const ICON_LINK: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M30 14 H14 V50 H50 V34" stroke="#f5c542" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M36 10 H54 V28" stroke="#f5c542" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M53 11 L31 33" stroke="#f5c542" stroke-width="5" fill="none" stroke-linecap="round"/>
</svg>"""

## Authored width of the credits column on a desktop landscape window.
const COLUMN_WIDTH: float = 720.0
## Roll speed in authored pixels per second, and the beat before it starts.
const ROLL_SPEED: float = 44.0
const ROLL_DELAY: float = 1.4
const BOOST_MAX: float = 1.35

var _content: VBoxContainer
var _scroll: ScrollContainer
var _reduced: bool = false
var _boost: float = 1.0
var _column: float = COLUMN_WIDTH
## Roll state. `_rolling` goes false for good once the reader takes over.
var _rolling: bool = true
var _roll_delay: float = ROLL_DELAY
var _roll_pos: float = 0.0


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)
	_reduced = UITheme.reduced_motion()
	_boost = _tall_boost()
	_column = _measure_column()

	_scroll = ScrollContainer.new()
	# The roll is automatic, but a reader who grabs the list must be able to
	# drag it; without this the touch never reaches the ScrollContainer.
	TouchScroll.attach(_scroll)
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	_style_scrollbar(_scroll.get_v_scroll_bar())

	# Expand flags let the CenterContainer fill the scroll viewport while the
	# content fits (keeping the centered composition) and grow past it when it
	# does not, which is what makes the roll scrollable.
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", _gap(UITheme.SPACE_L))
	pad.add_theme_constant_override("margin_bottom", _gap(UITheme.SPACE_L))
	center.add_child(pad)

	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.custom_minimum_size.x = _column
	_content.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	pad.add_child(_content)

	_build_hero()
	_content.add_child(_spacer(UITheme.SPACE_L))
	_build_roles()
	_content.add_child(_spacer(UITheme.SPACE_M))
	_build_partner_credit()
	_content.add_child(_spacer(UITheme.SPACE_M))
	_build_colophon()
	var back_button := _build_farewell()

	# Unified fade+rise entrance over the credit blocks.
	var entrance_items: Array[Control] = []
	for child in _content.get_children():
		if child is Control:
			entrance_items.append(child as Control)
	UITheme.play_entrance(self, entrance_items, 14.0)

	_build_exit_affordance()
	UITheme.attach_swipe_back(self, _go_back)
	back_button.grab_focus()
	# grab_focus + follow_focus would scroll the roll straight to its end.
	_snap_to_top()


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


func _h(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_heading(size)) * _boost))


func _u(value: float) -> float:
	return UITheme.scaled(value) * _boost


func _gap(value: int) -> int:
	return maxi(1, roundi(float(UITheme.spacing(value)) * _boost))


func _measure_column() -> float:
	if UITheme.is_touch():
		return UITheme.content_width(COLUMN_WIDTH, self)
	if GameConfig.is_headless() or not is_inside_tree():
		return COLUMN_WIDTH
	var view := get_viewport_rect().size
	if view.x <= 0.0:
		return COLUMN_WIDTH
	var usable := maxf(view.x - float(UITheme.screen_margin()) * 2.0, 300.0)
	return clampf(COLUMN_WIDTH * _boost, 300.0, usable)


func _style_scrollbar(bar: VScrollBar) -> void:
	if bar == null:
		return
	bar.custom_minimum_size.x = _u(9.0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(UITheme.COLOR_BG_DEEP, 0.30)
	track.set_corner_radius_all(4)
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
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _text_label(text: String, size: int, color: Color = UITheme.COLOR_TEXT_DIM) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Display-font name line — the thing a credit exists to show.
func _name_label(text: String, size: int, color: Color = UITheme.COLOR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _h(size))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, float(_gap(height)))
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## --- Blocks -----------------------------------------------------------------

func _build_hero() -> void:
	_content.add_child(_caption_label(
		"a %s production" % GameConfig.STUDIO_NAME, 17, Color(UITheme.COLOR_GOLD, 0.85)))
	var logo := UITheme.heading(GameConfig.GAME_NAME.to_upper(), _h(60))
	logo.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	_content.add_child(logo)
	_content.add_child(UITheme.accent_rule(_u(260.0), UITheme.COLOR_GOLD))
	_content.add_child(_text_label("Slide. Shove. Snack. Repeat.", 21))


## Classic credit blocks: the role in the caption rung, the name in the display
## rung, one pair at a time down the roll.
func _build_roles() -> void:
	var roles: Array = [
		["Game Design", GameConfig.STUDIO_NAME],
		["Programming", GameConfig.STUDIO_NAME],
		["Course Design", GameConfig.STUDIO_NAME],
		["Procedural Art", GameConfig.STUDIO_NAME],
		["Audio & Music", GameConfig.STUDIO_NAME],
		["QA & Testing", GameConfig.STUDIO_NAME],
	]
	for entry: Array in roles:
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", _gap(2))
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content.add_child(block)
		block.add_child(_caption_label(String(entry[0]), 16))
		block.add_child(_name_label(String(entry[1]), 27))
		_content.add_child(_spacer(10))


## Engineering-partner plate: a card in the same language as every other card in
## the game, with the name set as type and the site behind one quiet control.
func _build_partner_credit() -> void:
	var card := PanelContainer.new()
	var style := UITheme.make_card_style()
	style.content_margin_left = _u(26.0)
	style.content_margin_right = _u(26.0)
	style.content_margin_top = _u(16.0)
	style.content_margin_bottom = _u(18.0)
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _gap(6))
	card.add_child(body)

	# Card title: accent tick plus an uppercase tracked caption, centered here
	# because the whole roll is centered.
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", _gap(10))
	body.add_child(title_row)
	var tick := ColorRect.new()
	tick.color = Color(UITheme.COLOR_ACCENT, 0.85)
	tick.custom_minimum_size = Vector2(_u(4.0), _u(17.0))
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(tick)
	var title := _caption_label("Engineering Partner", 16, Color(0.72, 0.83, 0.94))
	# Inside a centered HBox a wrapping label's minimum width is one glyph, which
	# stacks the caption vertically. Titles never wrap.
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_row.add_child(title)

	body.add_child(_text_label("Engineered in partnership with", 16))
	body.add_child(_name_label(NINJA_NAME, 30, UITheme.COLOR_GOLD))

	var link_center := CenterContainer.new()
	body.add_child(link_center)
	var link := UITheme.make_ghost_button(
		NINJA_URL.trim_prefix("https://"), _btn(0.0, 40.0), _f(18))
	link.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	link.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.66))
	link.tooltip_text = NINJA_URL
	var icon := UITheme.make_icon(ICON_LINK, 1.0)
	if icon != null:
		link.icon = icon
		link.expand_icon = true
		link.add_theme_constant_override("icon_max_width", maxi(1, roundi(_u(18.0))))
		link.add_theme_constant_override("h_separation", maxi(1, roundi(_u(10.0))))
	UITheme.hook_sounds(link)
	link.pressed.connect(func() -> void:
		_open_url(NINJA_URL))
	link_center.add_child(link)


func _btn(width: float, height: float) -> Vector2:
	return UITheme.scaled_size(Vector2(width, height)) * _boost


## Tools, provenance and version — the small print, set as small print.
func _build_colophon() -> void:
	_content.add_child(_caption_label("Built with", 15))
	_content.add_child(_name_label("Godot Engine", 22))
	_content.add_child(_spacer(10))
	_content.add_child(_text_label(
		"All art, audio and code are original and procedurally generated.", 16))
	_content.add_child(_caption_label("Version %s" % GameConfig.GAME_VERSION, 14))


## The last beat of the roll, and the one promoted action on the screen.
func _build_farewell() -> Button:
	_content.add_child(_spacer(UITheme.SPACE_L))
	_content.add_child(_name_label("Thanks for playing.", 26, UITheme.COLOR_GOLD))
	_content.add_child(_spacer(UITheme.SPACE_S))
	var button_center := CenterContainer.new()
	_content.add_child(button_center)
	var back_button := UITheme.make_button("Main Menu", _btn(240.0, 52.0), _f(23))
	UITheme.style_primary(back_button)
	var back_icon := UITheme.make_icon(UITheme.ICON_BACK, 1.0)
	if back_icon != null:
		back_button.icon = back_icon
		back_button.expand_icon = true
		back_button.add_theme_constant_override("icon_max_width", maxi(1, roundi(_u(20.0))))
		back_button.add_theme_constant_override("h_separation", maxi(1, roundi(_u(10.0))))
	UITheme.hook_sounds(back_button)
	back_button.pressed.connect(_go_back)
	button_center.add_child(back_button)
	return back_button


## A roll that has not reached its end still needs a way out that does not
## involve waiting: a quiet pinned Back, over the scroll, out of the reading
## column.
func _build_exit_affordance() -> void:
	var holder := MarginContainer.new()
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	holder.add_theme_constant_override("margin_left", roundi(_u(14.0)))
	holder.add_theme_constant_override("margin_top", roundi(_u(12.0)))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(row)
	var exit_button := UITheme.make_ghost_button("Back", _btn(0.0, 40.0), _f(17))
	exit_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var icon := UITheme.make_icon(UITheme.ICON_BACK, 1.0)
	if icon != null:
		exit_button.icon = icon
		exit_button.expand_icon = true
		exit_button.add_theme_constant_override("icon_max_width", maxi(1, roundi(_u(16.0))))
		exit_button.add_theme_constant_override("h_separation", maxi(1, roundi(_u(8.0))))
	UITheme.hook_sounds(exit_button)
	exit_button.pressed.connect(_go_back)
	row.add_child(exit_button)
	row.add_child(_flex_spacer())


func _flex_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## --- The roll ---------------------------------------------------------------

func _snap_to_top() -> void:
	if GameConfig.is_headless():
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.process_frame.connect(func() -> void:
		if is_instance_valid(_scroll):
			_scroll.scroll_vertical = 0
			_roll_pos = 0.0,
		CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	if not _rolling or _reduced or GameConfig.is_headless():
		return
	if not is_instance_valid(_scroll):
		return
	_roll_delay -= delta
	if _roll_delay > 0.0:
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar == null:
		return
	var limit := bar.max_value - bar.page
	if limit <= 1.0:
		return  # everything fits; there is nothing to roll
	# The reader scrolling, dragging or tabbing away takes the roll over for
	# good — nothing is more annoying than a list that fights the hand on it.
	if absf(float(_scroll.scroll_vertical) - _roll_pos) > 2.0:
		_rolling = false
		return
	_roll_pos = minf(_roll_pos + _u(ROLL_SPEED) * delta, limit)
	_scroll.scroll_vertical = roundi(_roll_pos)


## Opens `url` in the player's browser. Web exports run inside the WASM sandbox
## where OS.shell_open does nothing, so they go through window.open instead;
## headless runs open nothing at all.
static func _open_url(url: String) -> void:
	if GameConfig.is_headless():
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('%s','_blank')" % url, true)
		return
	OS.shell_open(url)


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()
