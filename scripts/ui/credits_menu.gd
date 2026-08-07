extends Control
## Credits screen with a gentle floating scroll animation. The list lives in
## a ScrollContainer so cramped viewports (large Menu Scale, short landscape
## phones) can still reach the Back button; the float only runs when the
## content fits and reduced motion is off. Every authored size below is the
## desktop value — UITheme.scaled* enlarges them on touch devices only.

const NINJA_URL: String = "https://ninjaconsulting.ai"
const NINJA_NAME: String = "Ninja Consulting"

## External-link glyph in the same hand-drawn style as the UITheme icon set.
const ICON_LINK: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M30 14 H14 V50 H50 V34" stroke="#f5c542" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M36 10 H54 V28" stroke="#f5c542" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M53 11 L31 33" stroke="#f5c542" stroke-width="5" fill="none" stroke-linecap="round"/>
</svg>"""

var _content: VBoxContainer
var _scroll: ScrollContainer
var _reduced: bool = false
var _elapsed: float = 0.0
var _base_y: float = 0.0
var _base_y_set: bool = false


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)
	_reduced = UITheme.reduced_motion()

	_scroll = ScrollContainer.new()
	# Credits auto-scroll, but a reader who grabs the list should be able to
	# drag it; without this the touch never reaches the ScrollContainer.
	TouchScroll.attach(_scroll)
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)

	# Expand flags let the CenterContainer fill the scroll viewport while the
	# content fits (keeping the centered composition) and grow past it when it
	# does not, which is what makes the list scrollable.
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)

	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", UITheme.spacing(10))
	center.add_child(_content)

	var logo := UITheme.heading(GameConfig.GAME_NAME.to_upper(), UITheme.scaled_heading(64))
	logo.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	_content.add_child(logo)
	_content.add_child(UITheme.make_header_rule(UITheme.COLOR_GOLD))

	var studio := UITheme.heading("a %s production" % GameConfig.STUDIO_NAME, UITheme.scaled_heading(26))
	studio.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_content.add_child(studio)

	_content.add_child(_spacer(UITheme.spacing(24)))

	var roles: Array = [
		["Game Design", "Claude"],
		["Programming", "Claude"],
		["Course Design", "Claude"],
		["Procedural Art", "Claude"],
		["Audio & Music", "Claude"],
		["QA & Testing", "Claude"],
	]
	for entry: Array in roles:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", UITheme.scaled_int(24))
		_content.add_child(row)
		var role_label := Label.new()
		role_label.text = String(entry[0])
		role_label.add_theme_font_size_override("font_size", UITheme.scaled_font(23))
		role_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		role_label.custom_minimum_size = Vector2(UITheme.scaled(280.0), 0.0)
		role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(role_label)
		var name_label := Label.new()
		name_label.text = String(entry[1])
		name_label.add_theme_font_size_override("font_size", UITheme.scaled_font(23))
		name_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
		name_label.custom_minimum_size = Vector2(UITheme.scaled(280.0), 0.0)
		row.add_child(name_label)

	_content.add_child(_spacer(UITheme.spacing(24)))
	_build_partner_credit()
	_content.add_child(_spacer(UITheme.spacing(20)))

	var engine_label := UITheme.heading("Made with Godot Engine", UITheme.scaled_heading(24))
	engine_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_content.add_child(engine_label)

	var original_label := UITheme.heading(
		"All art, audio and code are original and procedurally generated.",
		UITheme.scaled_heading(20))
	original_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_content.add_child(original_label)

	var version_label := UITheme.heading("Version %s" % GameConfig.GAME_VERSION, UITheme.scaled_heading(18))
	version_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_content.add_child(version_label)

	_content.add_child(_spacer(UITheme.spacing(20)))

	var back_button := UITheme.make_button(
		"Back", UITheme.scaled_size(Vector2(220, 52)), UITheme.scaled_font(24))
	var back_icon := UITheme.make_icon(UITheme.ICON_BACK, 1.0)
	if back_icon != null:
		back_button.icon = back_icon
		back_button.expand_icon = true
		back_button.add_theme_constant_override("icon_max_width", UITheme.scaled_int(22))
		back_button.add_theme_constant_override("h_separation", UITheme.scaled_int(10))
	UITheme.hook_sounds(back_button)
	back_button.pressed.connect(_go_back)
	var button_center := CenterContainer.new()
	button_center.add_child(back_button)
	_content.add_child(button_center)

	# Unified fade+rise entrance over the credit rows. The gentle floating
	# animation in _process moves _content itself, so animating its children
	# here never fights it.
	var entrance_items: Array[Control] = []
	for child in _content.get_children():
		if child is Control:
			entrance_items.append(child as Control)
	UITheme.play_entrance(self, entrance_items, 14.0)

	UITheme.attach_swipe_back(self, _go_back)
	back_button.grab_focus()


## Engineering-partner credit: a tappable card that opens ninjaconsulting.ai,
## styled as a gold link button so it reads as the one interactive line in an
## otherwise static list.
func _build_partner_credit() -> void:
	var intro := UITheme.sub_label("Engineered in partnership with", UITheme.scaled_font(21))
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(intro)

	var link_center := CenterContainer.new()
	_content.add_child(link_center)
	var link := UITheme.make_button(
		NINJA_NAME, UITheme.scaled_size(Vector2(360, 56)), UITheme.scaled_font(26))
	link.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	link.add_theme_color_override("font_focus_color", UITheme.COLOR_GOLD)
	link.tooltip_text = NINJA_URL
	var icon := UITheme.make_icon(ICON_LINK, 1.0)
	if icon != null:
		link.icon = icon
		link.expand_icon = true
		link.add_theme_constant_override("icon_max_width", UITheme.scaled_int(24))
		link.add_theme_constant_override("h_separation", UITheme.scaled_int(12))
	UITheme.hook_sounds(link)
	link.pressed.connect(func() -> void:
		_open_url(NINJA_URL))
	link_center.add_child(link)

	var url_label := UITheme.sub_label(NINJA_URL.trim_prefix("https://"), UITheme.scaled_font(17))
	url_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(url_label)


## Opens `url` in the player's browser. Web exports run inside the WASM
## sandbox where OS.shell_open does nothing, so they go through window.open
## instead; headless runs open nothing at all.
static func _open_url(url: String) -> void:
	if GameConfig.is_headless():
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('%s','_blank')" % url, true)
		return
	OS.shell_open(url)


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _process(delta: float) -> void:
	_elapsed += delta
	if not _base_y_set:
		_base_y = _content.position.y
		_base_y_set = true
	# Float only while everything fits on screen; once the ScrollContainer has
	# to scroll (or reduced motion is on), the list must sit still. Compare
	# against the scroll viewport, not the center wrapper — the wrapper grows
	# with the content when it overflows.
	if _reduced or _content.size.y > _scroll.size.y + 1.0:
		return
	_content.position.y = _base_y + sin(_elapsed * 0.8) * 10.0


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()
