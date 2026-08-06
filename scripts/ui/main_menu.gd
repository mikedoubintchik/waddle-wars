extends Control
## Main menu: icon-glyph button stack with the unified staggered fade+rise
## entrance, animated title underline, and a fish/level chip.

## Same drawn fish glyph as the race HUD and customize menu currency counters
## (race_hud.gd / customize_menu.gd) so the icon is consistent across screens.
const FISH_ICON_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="60" height="40" viewBox="0 0 60 40">
<path d="M3 20 L19 8 L19 32 Z" fill="#6fc0ee"/>
<ellipse cx="34" cy="21" rx="21" ry="12" fill="#8fd8f8"/>
<path d="M26 11 Q35 3 44 11 Q35 15 26 11 Z" fill="#5fb0e2"/>
<path d="M20 21 Q34 31 50 22 Q34 27 20 21 Z" fill="#5fb0e2" opacity="0.7"/>
<circle cx="45" cy="17" r="3.2" fill="#0e2036"/>
<circle cx="46.2" cy="15.8" r="1.1" fill="#ffffff"/>
</svg>"""

var _buttons: Array[Button] = []
var _fish_label: Label
var _auth_chip_label: Label = null
var _auth_chip_button: Button = null
## Width of the button stack: authored on desktop, most of the screen on touch.
var _column_width: float = 520.0


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)
	_column_width = UITheme.content_width(520.0, self)

	# Single centered column filling the screen — the old side diorama shrank
	# the menu into a corner on phones. The scroll wrapper keeps every entry
	# reachable when the column outgrows the viewport (touch enlargement, a
	# large Menu Scale, or a short landscape phone); while it fits, the
	# expanding CenterContainer keeps the composition exactly centered.
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
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", UITheme.spacing(14))
	center.add_child(vbox)

	var title := UITheme.heading(GameConfig.GAME_NAME, UITheme.scaled_heading(84))
	title.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.25, 0.65, 1.0, 0.35))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_outline_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	# Shared header treatment: full-column rule sweeping in under the wordmark
	# (same make_header_rule every other menu uses).
	vbox.add_child(UITheme.make_header_rule())
	var tagline := UITheme.sub_label("Slide. Shove. Snack. Repeat.", UITheme.scaled_font(24))
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UITheme.spacing(UITheme.SPACE_M))
	vbox.add_child(gap)

	_add_button(vbox, "Play", UITheme.ICON_PLAY, func() -> void:
		SceneRouter.go_to(Game.SCENE_MODE_SELECT))
	_add_button(vbox, "Waddle School", UITheme.ICON_SCHOOL, func() -> void:
		Game.start_tutorial())
	_add_button(vbox, "Customize", UITheme.ICON_PALETTE, func() -> void:
		SceneRouter.go_to(Game.SCENE_CUSTOMIZE))
	_add_button(vbox, "Leaderboard", UITheme.ICON_PODIUM, func() -> void:
		SceneRouter.go_to(Game.SCENE_LEADERBOARD))
	_add_button(vbox, "Achievements", UITheme.ICON_TROPHY, func() -> void:
		SceneRouter.go_to(Game.SCENE_ACHIEVEMENTS))
	_add_button(vbox, "Settings", UITheme.ICON_GEAR, func() -> void:
		SceneRouter.go_to(Game.SCENE_SETTINGS))
	_add_button(vbox, "Credits", UITheme.ICON_FILM, func() -> void:
		SceneRouter.go_to(Game.SCENE_CREDITS))
	# Web exports cannot quit cleanly — get_tree().quit() freezes the canvas.
	if not GameConfig.is_mobile() and not OS.has_feature("web"):
		_add_button(vbox, "Quit", UITheme.ICON_DOOR, func() -> void:
			SaveManager.save_now()
			get_tree().quit())

	var chip := _build_status_chip(vbox)
	UITheme.attach_swipe_back(self, func() -> void:
		SceneRouter.go_to(Game.SCENE_TITLE))
	var entrance_items: Array[Control] = [title, tagline]
	for button: Button in _buttons:
		entrance_items.append(button)
	entrance_items.append(chip)
	UITheme.play_entrance(self, entrance_items)

	if not _buttons.is_empty():
		_buttons[0].grab_focus()
	AudioManager.play_music("music_title")


func _add_button(parent: Control, text: String, icon_svg: String, on_pressed: Callable) -> void:
	# make_menu_button already applies the touch enlargement; the width is then
	# widened to the viewport-relative column so the stack fills a phone screen.
	var button := UITheme.make_menu_button(text, icon_svg, Vector2(520, 72), 32)
	button.custom_minimum_size.x = _column_width
	UITheme.hook_sounds(button)
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	_buttons.append(button)


## Builds the fish/level (and, on web, sign-in) status chip and returns the
## Control the caller should include in the entrance cascade. On desktop the
## chip is pinned to the top-right corner; on touch there is no spare corner
## beside the enlarged wordmark, so it rides at the top of the menu column.
func _build_status_chip(column: VBoxContainer) -> Control:
	var touch := UITheme.is_touch()
	var chip := PanelContainer.new()
	# Rounded glass pill with a soft gold rim — quieter than the old full-
	# strength gold border, and the pill shape reads as a status chip.
	var chip_style := UITheme.make_panel_style(
		Color(0.055, 0.10, 0.18, 0.88), Color(UITheme.COLOR_GOLD, 0.5))
	chip_style.set_corner_radius_all(27)
	chip_style.content_margin_left = UITheme.scaled(22.0)
	chip_style.content_margin_right = UITheme.scaled(22.0)
	chip_style.content_margin_top = 8.0
	chip_style.content_margin_bottom = 8.0
	chip_style.shadow_size = 6
	chip.add_theme_stylebox_override("panel", chip_style)
	var host: Control = chip
	if touch:
		var holder := CenterContainer.new()
		column.add_child(holder)
		column.move_child(holder, 0)
		holder.add_child(chip)
		host = holder
	else:
		chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		chip.offset_left = -280.0
		chip.offset_top = 16.0
		chip.offset_right = -16.0
		chip.offset_bottom = 70.0
		add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.scaled_int(16))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(row)
	var fish_box := HBoxContainer.new()
	fish_box.add_theme_constant_override("separation", UITheme.scaled_int(8))
	row.add_child(fish_box)
	var fish_tex := _make_fish_texture()
	if fish_tex != null:
		var fish_icon := TextureRect.new()
		fish_icon.texture = fish_tex
		fish_icon.custom_minimum_size = Vector2(UITheme.scaled(36.0), UITheme.scaled(24.0))
		fish_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fish_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fish_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fish_box.add_child(fish_icon)
	else:
		# SVG module unavailable: fall back to a glyph so the counter
		# still reads correctly.
		var fish_glyph := Label.new()
		fish_glyph.text = "><>"
		fish_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fish_glyph.add_theme_font_size_override("font_size", UITheme.scaled_font(22))
		fish_glyph.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95))
		fish_box.add_child(fish_glyph)
	_fish_label = Label.new()
	_fish_label.add_theme_font_override("font", UITheme.bold_font())
	_fish_label.add_theme_font_size_override("font_size", UITheme.scaled_font(22))
	_fish_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_fish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fish_label.text = "%d" % Progression.get_fish()
	fish_box.add_child(_fish_label)
	row.add_child(_chip_divider())
	var level_label := Label.new()
	level_label.add_theme_font_override("font", UITheme.bold_font())
	level_label.add_theme_font_size_override("font_size", UITheme.scaled_font(22))
	level_label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	level_label.text = "Lv %d" % Progression.get_level()
	row.add_child(level_label)
	Progression.fish_changed.connect(_on_fish_changed)
	# Web: offer sign-in right on the menu — it backs up progress to the cloud
	# and unlocks leaderboard posting. Chip widens to fit.
	if LeaderboardClient.can_sign_in():
		if not touch:
			chip.offset_left = -560.0
		row.add_child(_chip_divider())
		_auth_chip_label = Label.new()
		_auth_chip_label.add_theme_font_size_override("font_size", UITheme.scaled_font(20))
		_auth_chip_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		_auth_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(_auth_chip_label)
		_auth_chip_button = UITheme.make_button(
			"Sign In", UITheme.scaled_size(Vector2(150, 44)), UITheme.scaled_font(20))
		UITheme.hook_sounds(_auth_chip_button)
		_auth_chip_button.pressed.connect(func() -> void:
			if LeaderboardClient.signed_in:
				LeaderboardClient.sign_out()
			else:
				_auth_chip_button.text = "Opening…"
				LeaderboardClient.sign_in())
		row.add_child(_auth_chip_button)
		_refresh_auth_chip()
		LeaderboardClient.auth_changed.connect(_refresh_auth_chip)
		# A restored cloud save changes fish/level: reload the menu to reflect it.
		LeaderboardClient.cloud_save_restored.connect(func() -> void:
			if is_inside_tree():
				SceneRouter.go_to(Game.SCENE_MAIN_MENU))
	return host


## Thin vertical separator between the chip's stat groups.
static func _chip_divider() -> Control:
	var divider := ColorRect.new()
	divider.color = Color(UITheme.COLOR_ACCENT, 0.22)
	divider.custom_minimum_size = Vector2(1.0, UITheme.scaled(26.0))
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


func _refresh_auth_chip() -> void:
	if _auth_chip_button == null:
		return
	if LeaderboardClient.signed_in:
		_auth_chip_label.text = LeaderboardClient.display_name
		_auth_chip_button.text = "Sign Out"
	else:
		_auth_chip_label.text = "Save progress online"
		_auth_chip_button.text = "Sign In"


func _on_fish_changed(total: int) -> void:
	_fish_label.text = "%d" % total


static func _make_fish_texture() -> ImageTexture:
	var img := Image.new()
	if img.load_svg_from_string(FISH_ICON_SVG, 2.0) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		SceneRouter.go_to(Game.SCENE_TITLE)
