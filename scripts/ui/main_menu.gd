extends Control
## Main menu: a wordmark header over a deliberately ranked action list — one
## hero Play button, the four places you actually go next, then a quiet utility
## row — with the unified staggered fade+rise entrance and a fish/level chip.

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

## Authored width of the button column on the 1920x1080 desktop canvas.
const COLUMN_BASE: float = 520.0
## Account name budget in the status chip: characters before it is shortened to
## "First L.", and the logical width it is finally trimmed to with an ellipsis.
const AUTH_NAME_MAX_CHARS: int = 16
const AUTH_NAME_MAX_WIDTH: float = 170.0

## Hero-button face: the saturated glacier blue of the menu icon set, one step
## deeper than UITheme's hover fill so Play reads as solid rather than washed.
const PRIMARY_FILL: Color = Color(0.129, 0.361, 0.588)
const PRIMARY_FILL_HOVER: Color = Color(0.192, 0.478, 0.741)

var _buttons: Array[Button] = []
var _fish_label: Label
var _auth_chip_label: Label = null
var _auth_chip_button: Button = null
## Width of the button stack: authored on desktop, most of the screen on touch
## and on portrait windows.
var _column_width: float = COLUMN_BASE
## Extra enlargement for tall/narrow (portrait) viewports — see _tall_boost().
var _boost: float = 1.0


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)
	_boost = _tall_boost()
	_column_width = _measure_column_width()

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
	vbox.custom_minimum_size.x = _column_width
	vbox.add_theme_constant_override("separation", _gap(12))
	center.add_child(vbox)

	var title := UITheme.heading(GameConfig.GAME_NAME, _title_size())
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
	var tagline := UITheme.sub_label("Slide. Shove. Snack. Repeat.", _f(24))
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tagline)
	_spacer(vbox, UITheme.SPACE_M)

	# Rank one: the button the player came here to press.
	_add_button(vbox, "Play", UITheme.ICON_PLAY, func() -> void:
		SceneRouter.go_to(Game.SCENE_MODE_SELECT), true)
	_spacer(vbox, 6)
	# The daily sits directly under Play: it is the reason to open the game on
	# a day you were not otherwise going to, so it has to be visible without a
	# menu dive. Its label carries the state (streak, or done for today) so the
	# button itself is the reminder.
	_add_button(vbox, _daily_label(), UITheme.ICON_TROPHY, func() -> void:
		Game.start_daily_challenge(), false)
	# Rank two: the rest of the game, full width and evenly weighted.
	_add_button(vbox, "Waddle School", UITheme.ICON_SCHOOL, func() -> void:
		Game.start_tutorial(), false)
	_add_button(vbox, "Customize", UITheme.ICON_PALETTE, func() -> void:
		SceneRouter.go_to(Game.SCENE_CUSTOMIZE), false)
	_add_button(vbox, "Leaderboard", UITheme.ICON_PODIUM, func() -> void:
		SceneRouter.go_to(Game.SCENE_LEADERBOARD), false)
	_add_button(vbox, "Achievements", UITheme.ICON_TROPHY, func() -> void:
		SceneRouter.go_to(Game.SCENE_ACHIEVEMENTS), false)

	# Rank three: housekeeping, grouped behind a divider and sized down so the
	# stack reads as three deliberate tiers instead of one long list.
	_spacer(vbox, 6)
	vbox.add_child(_divider())
	var utility := HBoxContainer.new()
	utility.add_theme_constant_override("separation", _gap(10))
	utility.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(utility)
	_add_utility_button(utility, "Settings", UITheme.ICON_GEAR, func() -> void:
		SceneRouter.go_to(Game.SCENE_SETTINGS))
	_add_utility_button(utility, "Credits", UITheme.ICON_FILM, func() -> void:
		SceneRouter.go_to(Game.SCENE_CREDITS))
	# Web exports cannot quit cleanly — get_tree().quit() freezes the canvas.
	if not GameConfig.is_mobile() and not OS.has_feature("web"):
		_add_utility_button(utility, "Quit", UITheme.ICON_DOOR, func() -> void:
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


## --- Layout scaling ---------------------------------------------------------
##
## The canvas_items/expand stretch pins the design height, so a portrait window
## keeps its logical width but gains logical height — every logical pixel then
## renders physically tiny and the menu shrinks into a small island. Enlarge by
## the ratio of live to design height, on top of UITheme's touch step.
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


## Authored spacing step -> on-screen separation.
func _gap(value: int) -> int:
	return maxi(1, roundi(float(UITheme.spacing(value)) * _boost))


## Authored horizontal metric (inset, icon size) -> on-screen metric.
func _u(value: float) -> float:
	return UITheme.scaled(value) * _boost


## Authored control size -> on-screen size. Width comes from the column, so
## only the height needs the tall step on top of UITheme's touch floor.
func _row_size(size: Vector2) -> Vector2:
	var out := UITheme.scaled_size(size)
	out.y *= _boost
	return out


## Display heading size: enlarged for tall viewports but more gently than body
## text (a wordmark that grows with the full step dwarfs the buttons).
func _title_size() -> int:
	return roundi(float(UITheme.scaled_heading(84)) * minf(_boost, 1.5))


func _measure_column_width() -> float:
	if UITheme.is_touch():
		return UITheme.content_width(COLUMN_BASE, self)
	if GameConfig.is_headless() or not is_inside_tree():
		return COLUMN_BASE
	var view := get_viewport_rect().size
	if view.x <= 0.0:
		return COLUMN_BASE
	if view.y > view.x:  # portrait window: fill it rather than float in it
		return clampf(view.x * 0.80, COLUMN_BASE, 1600.0)
	return COLUMN_BASE * _boost


func _spacer(parent: Control, height: int) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, float(_gap(height)))
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gap)


## Hairline rule that separates the utility row from the main actions.
## Label for the daily button, carrying today's state so the button is its own
## reminder: an unplayed day advertises the streak it would continue, and a
## finished day shows the time to beat rather than pretending there is nothing
## left to do.
func _daily_label() -> String:
	# Kept short deliberately: this row shares an icon rail and chevron with
	# every other nav row, and a long label pushes both off the button.
	if DailyChallenge.is_complete_today():
		return "Daily Done · %s" % RaceHUD.format_time(DailyChallenge.today_best())
	var pending := DailyChallenge.pending_streak()
	if pending > 1:
		return "Daily · Day %d" % pending
	return "Daily Challenge"


func _divider() -> Control:
	var rule := ColorRect.new()
	rule.color = Color(UITheme.COLOR_ACCENT, 0.16)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## --- Buttons ----------------------------------------------------------------

## Stack entry. `primary` promotes it to the hero action: taller, larger type
## and a filled ice-blue face, so the eye lands on Play first and the rest of
## the stack reads as one calm tier beneath it.
func _add_button(parent: Control, text: String, icon_svg: String,
		on_pressed: Callable, primary: bool) -> void:
	var authored := Vector2(COLUMN_BASE, 92.0 if primary else 70.0)
	# make_menu_button already applies the touch enlargement; the width is then
	# widened to the viewport-relative column so the stack fills a phone screen.
	var button := UITheme.make_menu_button(text, icon_svg, authored, 38 if primary else 30)
	button.custom_minimum_size = Vector2(_column_width, _row_size(authored).y)
	button.add_theme_font_size_override("font_size", _f(38 if primary else 30))
	# Icon then label on one left rail: with centered text the glyph floated off
	# on its own and every row read slightly different.
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width", roundi(_icon_width(primary)))
	button.add_theme_constant_override("h_separation", roundi(_icon_width(primary) * 0.55))
	_add_chevron(button, primary)
	if primary:
		_style_primary(button)
	UITheme.hook_sounds(button)
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	_buttons.append(button)


## Right-edge chevron. A full-width row with left-aligned text leaves a wide
## void on the right; the chevron closes the row and makes the stack read as
## navigation. Inert overlay child, like UITheme's glass edge strips.
func _add_chevron(button: Button, primary: bool) -> void:
	var chevron := Label.new()
	chevron.name = "Chevron"
	chevron.text = "›"
	chevron.add_theme_font_override("font", UITheme.display_font())
	chevron.add_theme_font_size_override("font_size", _f(34 if primary else 28))
	chevron.add_theme_color_override("font_color",
		Color(0.88, 0.95, 1.0, 0.75) if primary else Color(0.68, 0.79, 0.92, 0.45))
	chevron.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron.anchor_left = 1.0
	chevron.anchor_right = 1.0
	chevron.anchor_top = 0.0
	chevron.anchor_bottom = 1.0
	chevron.offset_left = -UITheme.scaled(52.0)
	chevron.offset_right = -UITheme.scaled(20.0)
	button.add_child(chevron)


func _icon_width(primary: bool) -> float:
	return UITheme.scaled(40.0 if primary else 32.0) * minf(_boost, 1.5)


## Compact third-tier entry: three of these share the column width.
func _add_utility_button(parent: Control, text: String, icon_svg: String,
		on_pressed: Callable) -> void:
	var authored := Vector2(0.0, 54.0)
	var button := UITheme.make_menu_button(text, icon_svg, authored, 20)
	button.custom_minimum_size = Vector2(0.0, _row_size(authored).y)
	button.add_theme_font_size_override("font_size", _f(20))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_constant_override("icon_max_width", roundi(UITheme.scaled(22.0) * minf(_boost, 1.5)))
	button.add_theme_constant_override("h_separation", roundi(UITheme.scaled(8.0)))
	button.add_theme_color_override("font_color", Color(0.78, 0.86, 0.95))
	UITheme.hook_sounds(button)
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	_buttons.append(button)


## Filled ice-blue treatment for the hero action. Same radius and margins as
## UITheme.make_button so the family stays coherent (results.gd promotes its
## continue button the same way) — only the fill weight changes.
func _style_primary(button: Button) -> void:
	# A translucent accent wash read as a washed-out/disabled face, and simply
	# darkening COLOR_ACCENT (a pale cyan) only greys it. The hero instead uses
	# the saturated glacier blue already in the menu icon set (#3d6d94/#4d7fae),
	# rimmed with COLOR_ACCENT so it still belongs to the same family.
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


## --- Status chip ------------------------------------------------------------

## Builds the fish/level (and, on web, sign-in) status chip and returns the
## Control the caller should include in the entrance cascade. On desktop the
## chip is pinned to the top-right corner; on touch there is no spare corner
## beside the enlarged wordmark, so it rides at the top of the menu column.
func _build_status_chip(column: VBoxContainer) -> Control:
	var touch := UITheme.is_touch()
	var stacked := touch or _column_width > COLUMN_BASE * 1.2
	var chip := PanelContainer.new()
	# Rounded glass pill with a soft gold rim — quieter than the old full-
	# strength gold border, and the pill shape reads as a status chip.
	var chip_style := UITheme.make_panel_style(
		Color(0.055, 0.10, 0.18, 0.88), Color(UITheme.COLOR_GOLD, 0.5))
	chip_style.set_corner_radius_all(27)
	chip_style.content_margin_left = _u(22.0)
	chip_style.content_margin_right = _u(22.0)
	chip_style.content_margin_top = _u(8.0)
	chip_style.content_margin_bottom = _u(8.0)
	chip_style.shadow_size = 6
	chip.add_theme_stylebox_override("panel", chip_style)
	var host: Control = chip
	if stacked:
		var holder := CenterContainer.new()
		column.add_child(holder)
		column.move_child(holder, 0)
		holder.add_child(chip)
		host = holder
	else:
		# Pin the top-right CORNER and let the chip size itself from its own
		# contents, growing leftward and downward. It used to be given a fixed
		# rect (offset_left -280, later -560 when the auth controls appear),
		# which ignores minimum size: a display name longer than that budget --
		# any ordinary full name -- pushed "Sign Out" straight off the right
		# edge of the screen.
		chip.anchor_left = 1.0
		chip.anchor_right = 1.0
		chip.anchor_top = 0.0
		chip.anchor_bottom = 0.0
		chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		chip.grow_vertical = Control.GROW_DIRECTION_END
		chip.offset_left = 0.0
		chip.offset_right = -16.0
		chip.offset_top = 16.0
		chip.offset_bottom = 0.0
		add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_u(16.0)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(row)
	var fish_box := HBoxContainer.new()
	fish_box.add_theme_constant_override("separation", roundi(_u(8.0)))
	row.add_child(fish_box)
	var fish_tex := _make_fish_texture()
	if fish_tex != null:
		var fish_icon := TextureRect.new()
		fish_icon.texture = fish_tex
		fish_icon.custom_minimum_size = Vector2(_u(36.0), _u(24.0))
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
		fish_glyph.add_theme_font_size_override("font_size", _f(22))
		fish_glyph.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95))
		fish_box.add_child(fish_glyph)
	_fish_label = Label.new()
	_fish_label.add_theme_font_override("font", UITheme.bold_font())
	_fish_label.add_theme_font_size_override("font_size", _f(22))
	_fish_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_fish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fish_label.text = "%d" % Progression.get_fish()
	fish_box.add_child(_fish_label)
	row.add_child(_chip_divider())
	var level_label := Label.new()
	level_label.add_theme_font_override("font", UITheme.bold_font())
	level_label.add_theme_font_size_override("font_size", _f(22))
	level_label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	level_label.text = "Lv %d" % Progression.get_level()
	row.add_child(level_label)
	Progression.fish_changed.connect(_on_fish_changed)
	# Web: offer sign-in right on the menu — it backs up progress to the cloud
	# and unlocks leaderboard posting. Chip widens to fit.
	if LeaderboardClient.can_sign_in():
		row.add_child(_chip_divider())
		_auth_chip_label = Label.new()
		_auth_chip_label.add_theme_font_size_override("font_size", _f(20))
		_auth_chip_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		_auth_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Second guard on the same overflow: however the chip is laid out, one
		# very long account name must not be allowed to set its width.
		_auth_chip_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_auth_chip_label.custom_minimum_size.x = _u(AUTH_NAME_MAX_WIDTH)
		row.add_child(_auth_chip_label)
		_auth_chip_button = UITheme.make_button(
			"Sign In", _row_size(Vector2(150, 44)), _f(20))
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
func _chip_divider() -> Control:
	var divider := ColorRect.new()
	divider.color = Color(UITheme.COLOR_ACCENT, 0.22)
	divider.custom_minimum_size = Vector2(1.0, _u(26.0))
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


func _refresh_auth_chip() -> void:
	if _auth_chip_button == null:
		return
	if LeaderboardClient.signed_in:
		_auth_chip_label.text = _short_account_name(LeaderboardClient.display_name)
		_auth_chip_button.text = "Sign Out"
	else:
		_auth_chip_label.text = "Save progress online"
		_auth_chip_button.text = "Sign In"


## "Mike Doubintchik" -> "Mike D." A full name is the account's, not the
## chip's, and the chip shares a corner with the wordmark.
static func _short_account_name(full: String) -> String:
	var name := full.strip_edges()
	if name.length() <= AUTH_NAME_MAX_CHARS:
		return name
	var parts := name.split(" ", false)
	if parts.size() > 1:
		var shortened := "%s %s." % [parts[0], parts[parts.size() - 1].substr(0, 1)]
		if shortened.length() <= AUTH_NAME_MAX_CHARS:
			return shortened
	return name.substr(0, AUTH_NAME_MAX_CHARS - 1) + "…"


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
