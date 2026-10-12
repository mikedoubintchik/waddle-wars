extends Control
## Main menu: destination artwork, one departure action, then a compact dock.
## Secondary progression, settings and support live behind Base Camp instead
## of competing with play on the first screen.

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

## Waddle Run's hero glyph: the avalanche, with speed lines running ahead of it.
## Drawn here rather than added to UITheme's ICON_* set because it names one
## mode rather than a shared menu concept, and it is the only screen that offers
## the mode. Same pen weight and palette as the UITheme icons so the two hero
## rows read as one set.
const RUN_ICON_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M7 42 H21 M3 52 H17 M13 32 H23" stroke="#f5c542" stroke-width="5" stroke-linecap="round"/>
<path d="M31 55 C23 55 20 47 25 41 C21 33 30 25 37 30 C40 19 55 20 56 31 C63 34 62 45 55 47 C54 53 47 56 41 53 Z" fill="#eaf4ff" stroke="#7fa8cc" stroke-width="2.5" stroke-linejoin="round"/>
<circle cx="38" cy="39" r="3.2" fill="#c4dcf2"/>
<circle cx="50" cy="36" r="2.4" fill="#c4dcf2"/>
<circle cx="45" cy="47" r="2" fill="#c4dcf2"/>
</svg>"""

## Authored width of the button column on the 1920x1080 desktop canvas.
const COLUMN_BASE: float = 520.0
## Account name budget in the status chip: characters before it is shortened to
## "First L.", and the logical width it is finally trimmed to with an ellipsis.
const AUTH_NAME_MAX_CHARS: int = 16
const AUTH_NAME_MAX_WIDTH: float = 170.0
const SAVE_PROMPT_COOLDOWN: int = 7 * 24 * 60 * 60
const SAVE_PROMPT_SETTING: String = "save_prompt_last_shown_unix"
static var _save_prompt_session_shown: bool = false
## Test seam for phone CSS width when the web framebuffer is DPR-scaled.
static var forced_css_width: float = -1.0

## Hero-button face: the saturated glacier blue of the menu icon set, one step
## deeper than UITheme's hover fill so Play reads as solid rather than washed.
const PRIMARY_FILL: Color = Color(0.129, 0.361, 0.588)
const PRIMARY_FILL_HOVER: Color = Color(0.192, 0.478, 0.741)

var _buttons: Array[Button] = []
var _fish_label: Label
var _level_label: Label
var _xp_bar: ProgressBar
var _auth_chip_label: Label = null
var _auth_chip_button: Button = null
## Width of the button stack: authored on desktop, most of the screen on touch
## and on portrait windows.
var _column_width: float = COLUMN_BASE
## Extra enlargement for tall/narrow (portrait) viewports — see _tall_boost().
var _boost: float = 1.0
var _safe_scroll: ScrollContainer = null
var _profile: LayoutProfile = null
var _composition: BoxContainer = null
var _art_space: Control = null
var _brand_logo: TextureRect = null
var _hub_dock: PanelContainer = null
var _mode_grid: GridContainer = null
var _secondary_grid: GridContainer = null
var _status_chip: PanelContainer = null
var _status_row: BoxContainer = null
var _status_auth_divider: Control = null
var _status_chip_stacked: bool = false
var _save_prompt: Control = null
var _save_prompt_panel: PanelContainer = null
var _save_prompt_previous_focus: WeakRef
var _save_prompt_timer: Timer = null
var _save_prompt_polls: int = 0
var _cloud_choice: Control = null
var _cloud_choice_panel: PanelContainer = null
var _cloud_choice_actions: GridContainer = null
var _base_camp_overlay: Control = null


func _ready() -> void:
	Telemetry.app_open_once()
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)
	_profile = LayoutProfile.for_viewport(get_viewport())
	_boost = minf(_tall_boost(), 1.85)
	_column_width = _hub_width()

	# Expedition hub: authored destination art remains dominant while one
	# high-contrast glass dock carries every action. Portrait uses a lower dock;
	# landscape uses a right rail. Both are separate compositions, not a stretch.
	_safe_scroll = ScrollContainer.new()
	_safe_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Inset to the safe area. The backdrop behind this stays full bleed — art
	# under the notch is the point — but everything a thumb has to reach lives
	# in here, and anchoring it to the raw viewport put the landscape rail 26
	# units past the safe edge, under the home indicator.
	_safe_scroll.offset_left = _profile.safe_insets.x
	_safe_scroll.offset_top = _profile.safe_insets.y
	_safe_scroll.offset_right = -_profile.safe_insets.z
	_safe_scroll.offset_bottom = -_profile.safe_insets.w
	_safe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if _is_narrow_portrait():
		# Mobile hub scrolls by touch/focus; desktop-style scrollbar chrome cuts
		# through the key art and is unnecessary on a 540px-wide screen.
		_safe_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_safe_scroll.follow_focus = true
	TouchScroll.attach(_safe_scroll)
	add_child(_safe_scroll)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_safe_area):
		viewport.size_changed.connect(_apply_safe_area)
	_apply_safe_area()

	# A mutable axis reuses these authored portrait/landscape compositions on
	# rotation without rebuilding controls or replaying their entrance.
	_composition = BoxContainer.new()
	var composition := _composition
	composition.vertical = _profile.is_portrait()
	# ScrollContainer owns available width, including any vertical scrollbar.
	# A viewport-wide child floor would force its parent beyond the safe edge.
	composition.custom_minimum_size = Vector2(0.0, _profile.safe_rect.size.y)
	composition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composition.size_flags_vertical = Control.SIZE_EXPAND_FILL
	composition.add_theme_constant_override("separation", _gap(18))
	# Apply physical safe insets exactly once, on the scroll above. Reapplying
	# them around a safe-width child added both gutters to its minimum width.
	_safe_scroll.add_child(composition)

	_art_space = Control.new()
	var art_space := _art_space
	art_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# On a narrow phone the art must NOT take the slack. Expanding, it absorbed
	# every spare unit and pushed the dock down with it — the navigation then
	# ran off the bottom of the screen while the sky above it grew. The art
	# keeps its floor and the rows get the rest.
	art_space.size_flags_vertical = Control.SIZE_SHRINK_BEGIN \
		if _is_narrow_portrait() else Control.SIZE_EXPAND_FILL
	if _profile.is_portrait():
		art_space.custom_minimum_size.y = _portrait_art_height()
	else:
		# The art panel expands into whatever is left; giving it a large MINIMUM
		# too meant art-min plus rail-min could exceed the safe width, and the
		# row then overflowed to the right with the rail's buttons landing past
		# the screen edge. The rail is the part a thumb needs, so it keeps its
		# width and the art takes the remainder.
		art_space.custom_minimum_size.x = 0.0
	composition.add_child(art_space)
	var header_center := CenterContainer.new()
	header_center.name = "ExpeditionBrandStage"
	header_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_space.add_child(header_center)
	var header := VBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", _gap(2))
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_center.add_child(header)
	var eyebrow := UITheme.sub_label("PENGUIN PANIC  ·  ANTARCTICA", _f(16))
	eyebrow.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(eyebrow)
	var title_art := TextureRect.new()
	title_art.name = "WaddleWarsWordmark"
	title_art.texture = TitleScreen.logo_texture()
	_brand_logo = title_art
	title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_art.custom_minimum_size = Vector2(_column_width if _profile.is_portrait() else _u(400.0),
		_u(116.0 if _profile.is_portrait() else 210.0))
	title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title_art)
	var tagline := UITheme.sub_label("THE MOUNTAIN IS MOVING. SO ARE YOU.", _f(16))
	tagline.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0))
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(tagline)

	_hub_dock = _make_hub_dock()
	var dock := _hub_dock
	dock.custom_minimum_size.x = _column_width
	if _is_narrow_portrait():
		# The dock sizes to its own content here rather than claiming a fixed
		# 60% of the screen. With the art panel's 35% on top of it, 60% put the
		# hub over 95% of the height before margins and separations, so the last
		# row of buttons was sliced off the bottom of a real phone — reachable
		# only by scrolling a menu that should simply fit.
		dock.custom_minimum_size.y = 0.0
	elif not _profile.is_portrait():
		dock.custom_minimum_size.y = maxf(
			_profile.safe_rect.size.y - _gap(32), _u(680.0))
		dock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	composition.add_child(dock)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", _gap(5 if _is_narrow_portrait() else 9))
	dock.add_child(vbox)

	# One destination, one decision. The old card/grid dumped every screen onto
	# this view and buried the illustrated world under menu chrome. The departure
	# action is a floating capsule; three destinations form a compact dock.
	var kicker := UITheme.sub_label("READY FOR THE TRAIL?", _f(16))
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0))
	vbox.add_child(kicker)
	var depart := UITheme.make_button("WADDLE RUN   ›", Vector2(0, 96), _f(34))
	depart.name = "RunDeparture"
	depart.accessibility_name = "Start Waddle Run: outrun the avalanche"
	depart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	depart.custom_minimum_size.y = maxf(_row_size(Vector2(0, 96)).y,
		_physical_height_floor(68.0))
	for state: String in ["normal", "hover", "pressed"]:
		var face := StyleBoxFlat.new()
		face.bg_color = Color(0.93, 0.99, 0.94) if state == "normal" \
			else Color(1.0, 1.0, 0.96) if state == "hover" \
			else Color(0.65, 0.91, 0.83)
		face.set_corner_radius_all(roundi(_u(64.0)))
		face.set_border_width_all(0)
		face.shadow_color = Color(0.02, 0.12, 0.18, 0.36)
		face.shadow_size = roundi(_u(16.0 if state == "hover" else 9.0))
		face.content_margin_left = _u(20.0)
		face.content_margin_right = _u(20.0)
		depart.add_theme_stylebox_override(state, face)
	depart.add_theme_color_override("font_color", Color(0.05, 0.22, 0.27))
	depart.add_theme_color_override("font_hover_color", Color(0.03, 0.18, 0.23))
	depart.add_theme_color_override("font_focus_color", Color(0.05, 0.22, 0.27))
	depart.add_theme_color_override("font_pressed_color", Color(0.03, 0.18, 0.23))
	depart.add_theme_color_override("font_hover_pressed_color", Color(0.03, 0.18, 0.23))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.draw_center = false
	focus.border_color = Color(1.0, 0.78, 0.29, 0.96)
	focus.set_border_width_all(roundi(_u(3.0)))
	focus.set_corner_radius_all(roundi(_u(64.0)))
	focus.anti_aliasing = true
	depart.add_theme_stylebox_override("focus", focus)
	depart.add_theme_font_override("font", UITheme.bold_font())
	UITheme.hook_sounds(depart)
	depart.pressed.connect(func() -> void: Game.start_runner())
	vbox.add_child(depart)
	_buttons.append(depart)
	var record := UITheme.sub_label(_runner_record_line(), _f(17))
	record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record.add_theme_color_override("font_color", Color(0.91, 0.97, 1.0))
	vbox.add_child(record)
	var dock_nav := HBoxContainer.new()
	dock_nav.name = "DestinationDock"
	dock_nav.add_theme_constant_override("separation", _gap(8))
	vbox.add_child(dock_nav)
	_add_destination(dock_nav, "Penguin", UITheme.ICON_PALETTE, func() -> void:
		SceneRouter.go_to(Game.SCENE_CUSTOMIZE))
	_add_destination(dock_nav, "Ranks", UITheme.ICON_PODIUM, func() -> void:
		SceneRouter.go_to(Game.SCENE_LEADERBOARD))
	_add_destination(dock_nav, "Base Camp", UITheme.ICON_GEAR, _show_base_camp)

	var chip := _build_status_chip(vbox)
	_apply_safe_area()
	# Spend the one motion-permission ask on the player's next tap, whatever it
	# happens to be. Tilt steering is on by default on a phone, but iOS will
	# not grant the sensor to a page that has not asked from inside a real user
	# gesture -- so without this the setting would be on and doing nothing.
	TiltSteering.arm_permission_on_first_gesture(self)
	_maybe_announce_tilt()
	UITheme.attach_swipe_back(self, func() -> void:
		if _cloud_choice != null:
			_dismiss_cloud_choice()
		elif _save_prompt != null:
			_dismiss_save_prompt()
		elif _base_camp_overlay != null:
			_dismiss_base_camp()
		# Main menu is root; swiping back does not reopen the old title screen.
		)
	var entrance_items: Array[Control] = [eyebrow, title_art, tagline]
	for button: Button in _buttons:
		entrance_items.append(button)
	entrance_items.append(chip)
	UITheme.play_entrance(self, entrance_items)

	if not _buttons.is_empty() and not UITheme.is_touch():
		_buttons[0].grab_focus()
	AudioManager.play_music("music_title")
	_schedule_save_prompt()
	if LeaderboardClient.can_sign_in():
		LeaderboardClient.cloud_sync_changed.connect(_refresh_auth_chip)
		LeaderboardClient.public_name_changed.connect(_refresh_auth_chip)


## Device settings, not cloud/save ownership: dismissing never changes earned
## progress, and a repeated home visit cannot nag more than once per session.
static func save_prompt_due(progress: Dictionary, last_shown: int, now: int) -> bool:
	return LeaderboardClient.has_played_progress(progress) and now > 0 \
		and (last_shown <= 0 or now - last_shown >= SAVE_PROMPT_COOLDOWN)


func _schedule_save_prompt() -> void:
	# Strict platform guard; the layout-only force_available seam is not web.
	if not OS.has_feature("web") or GameConfig.is_headless() \
			or GameConfig.native_offline_mvp() or _save_prompt_session_shown:
		return
	_save_prompt_timer = Timer.new()
	_save_prompt_timer.wait_time = 0.5
	_save_prompt_timer.timeout.connect(_poll_save_prompt)
	add_child(_save_prompt_timer)
	_save_prompt_timer.start()


func _poll_save_prompt() -> void:
	_save_prompt_polls += 1
	if LeaderboardClient.signed_in or LeaderboardClient.sign_in_pending \
			or _save_prompt_session_shown or _save_prompt_polls >= 60:
		_stop_save_prompt_timer()
		return
	# Clerk lazy-loads after startup. Do not tell a restored signed-in player
	# to sign in while the bridge is still fetching that account's first token.
	if not LeaderboardClient.auth_ready or LeaderboardClient.identity_pending:
		return
	_stop_save_prompt_timer()
	var stored: Variant = SettingsManager.get_setting("online", SAVE_PROMPT_SETTING)
	var last_shown := int(stored) if stored is int or stored is float else 0
	var now := int(Time.get_unix_time_from_system())
	if not save_prompt_due(SaveManager.data, last_shown, now):
		return
	_save_prompt_session_shown = true
	SettingsManager.set_setting("online", SAVE_PROMPT_SETTING, now)
	_show_save_prompt()


func _stop_save_prompt_timer() -> void:
	if _save_prompt_timer != null:
		_save_prompt_timer.stop()
		_save_prompt_timer.queue_free()
		_save_prompt_timer = null


func _show_save_prompt() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	_save_prompt_previous_focus = weakref(focus) if focus != null else null
	var prompt := preload("res://scripts/ui/save_progress_prompt.gd").new()
	prompt.name = "ReturningPlayerSavePrompt"
	_save_prompt = prompt
	prompt.sign_in_requested.connect(func() -> void:
		_dismiss_save_prompt()
		LeaderboardClient.sign_in())
	prompt.dismissed.connect(_dismiss_save_prompt)
	add_child(prompt)


func _dismiss_save_prompt() -> void:
	if _save_prompt == null:
		return
	_save_prompt.queue_free()
	_save_prompt = null
	_save_prompt_panel = null
	var previous := _save_prompt_previous_focus.get_ref() as Control if _save_prompt_previous_focus != null else null
	_save_prompt_previous_focus = null
	if is_instance_valid(previous) and previous.is_visible_in_tree():
		previous.grab_focus()
	elif not _buttons.is_empty() and _buttons[0].is_visible_in_tree():
		_buttons[0].grab_focus()


func _show_cloud_choice() -> void:
	# Compatibility callback for older saved navigation state. Reconciliation
	# is automatic in LeaderboardClient; no save-replacement choice is shown.
	_dismiss_cloud_choice()
	_refresh_auth_chip()


func _dismiss_cloud_choice() -> void:
	if _cloud_choice == null:
		return
	_cloud_choice.queue_free()
	_cloud_choice = null
	_cloud_choice_panel = null
	_cloud_choice_actions = null
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _cloud_touch_floor(pixels: float) -> float:
	if not UITheme.is_touch() or _profile == null:
		return 0.0
	var window := get_window()
	if window == null or window.size.y <= 0:
		return pixels
	return pixels * _profile.viewport_size.y / float(window.size.y)


func _hub_width() -> float:
	if _is_narrow_portrait():
		return _profile.safe_rect.size.x * 0.90
	match _profile.view_class:
		LayoutProfile.ViewClass.PORTRAIT_TABLET:
			return minf(_profile.safe_rect.size.x * 0.90, _u(1260.0))
		LayoutProfile.ViewClass.LANDSCAPE_COMPACT:
			return minf(_profile.safe_rect.size.x * 0.52, _u(720.0))
		_:
			return minf(_profile.safe_rect.size.x * 0.42, _u(680.0))


func _portrait_art_height() -> float:
	if _is_narrow_portrait():
		# The art stage takes what is left after the dock, with a floor rather
		# than a fixed share. At 35% plus a 60% dock the hub needed more than
		# the screen had and the bottom row of buttons fell off a real phone;
		# the dock now sizes to its content and the art fills the remainder.
		# A floor, not a share: the art panel expands into whatever the dock
		# leaves, so on a tall phone it still fills most of the top. At 24% the
		# dock's own content pushed the last row 107 units past the bottom of a
		# 390x844 screen; the floor has to leave room for the navigation itself.
		return _profile.safe_rect.size.y * 0.43
	match _profile.view_class:
		_:
			return _profile.safe_rect.size.y * 0.40


func _secondary_columns() -> int:
	if _is_narrow_portrait():
		return 2
	match _profile.view_class:
		LayoutProfile.ViewClass.PORTRAIT_TABLET:
			return 3
		LayoutProfile.ViewClass.LANDSCAPE_COMPACT:
			return 2
		_:
			return 3


func _hub_title_size() -> int:
	var authored := 54 if _profile.is_portrait() else 48
	return roundi(float(UITheme.scaled_heading(authored)) * minf(_boost, 1.28))


## Project stretch exposes a 1920-wide logical canvas even inside a 540-wide
## phone window, which classifies as PORTRAIT_TABLET. Fold physical phone
## geometry back into the LayoutProfile contract so narrow composition is used
## on-device and in the windowed QA matrix.
func _is_narrow_portrait() -> bool:
	if _profile == null or not _profile.is_portrait():
		return false
	if _profile.view_class == LayoutProfile.ViewClass.PORTRAIT_NARROW:
		return true
	# Web window.size is the canvas framebuffer on high-DPR phones. A 390 CSS
	# pixel handset can report 1170 here and incorrectly get the tablet grid.
	var css_width := forced_css_width
	if css_width <= 0.0 and OS.has_feature("web"):
		var measured: Variant = JavaScriptBridge.eval(
			"Math.min(window.innerWidth || 99999, document.documentElement.clientWidth || 99999)", true)
		if measured is float or measured is int:
			css_width = float(measured)
	if css_width > 0.0:
		return css_width <= 700.0
	var window := get_window()
	return window != null and window.size.y >= window.size.x \
		and window.size.x <= 700


func _physical_height_floor(pixels: float) -> float:
	if not _is_narrow_portrait():
		return 0.0
	var window := get_window()
	if window == null or window.size.y <= 0:
		return pixels
	return pixels * _profile.viewport_size.y / float(window.size.y)


func _make_hub_dock() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UITheme.make_panel_style(
		Color.TRANSPARENT, Color.TRANSPARENT)
	style.set_border_width_all(0)
	style.content_margin_left = _u(8.0)
	style.content_margin_right = _u(8.0)
	style.content_margin_top = _u(3.0)
	style.content_margin_bottom = _u(3.0)
	style.shadow_size = 0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _add_destination(parent: HBoxContainer, label: String, icon_svg: String,
		action: Callable) -> void:
	var button := UITheme.make_menu_button(label, icon_svg, Vector2(0, 62), 19)
	button.name = "Destination" + label.replace(" ", "")
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.custom_minimum_size = Vector2(0.0, maxf(
		_row_size(Vector2(0, 62)).y, _physical_height_floor(48.0)))
	button.add_theme_constant_override("icon_max_width", roundi(_u(23.0)))
	button.add_theme_constant_override("h_separation", roundi(_u(5.0)))
	button.add_theme_font_size_override("font_size", _f(19))
	for state: String in ["normal", "hover", "pressed"]:
		var face := StyleBoxFlat.new()
		face.bg_color = Color(0.025, 0.09, 0.14, 0.87) if state == "normal" \
			else Color(0.08, 0.24, 0.30, 0.96)
		face.set_corner_radius_all(roundi(_u(30.0)))
		face.set_border_width_all(0)
		face.content_margin_left = _u(7.0)
		face.content_margin_right = _u(7.0)
		button.add_theme_stylebox_override(state, face)
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)


func _show_base_camp() -> void:
	if _base_camp_overlay != null:
		return
	_base_camp_overlay = Control.new()
	_base_camp_overlay.name = "BaseCampOverlay"
	_base_camp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_base_camp_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.035, 0.07, 0.87)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_base_camp_overlay.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UtilityScreenLayout.bind_safe_rect(self, margin)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, _gap(12))
	_base_camp_overlay.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	TouchScroll.attach(scroll)
	margin.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minf(_profile.safe_rect.size.x - _gap(48), _u(620.0))
	var paper := UITheme.make_panel_style(Color(0.035, 0.09, 0.14, 0.98),
		Color(0.57, 0.86, 0.87, 0.45))
	paper.content_margin_left = _u(20)
	paper.content_margin_right = _u(20)
	paper.content_margin_top = _u(18)
	paper.content_margin_bottom = _u(18)
	panel.add_theme_stylebox_override("panel", paper)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _gap(9))
	panel.add_child(column)
	var title := UITheme.heading("Base Camp", _f(36))
	column.add_child(title)
	var intro := UITheme.sub_label("Your expedition, gear and support.", _f(18))
	column.add_child(intro)
	_add_expedition_log(column)
	_add_base_action(column, "Achievements", UITheme.ICON_TROPHY,
		func() -> void: SceneRouter.go_to(Game.SCENE_ACHIEVEMENTS))
	if not GameConfig.native_offline_mvp():
		_add_base_action(column, "Cosmetic bundles", UITheme.ICON_PALETTE,
			func() -> void: SceneRouter.go_to(Game.SCENE_COSMETIC_SHOP))
	if GameConfig.RACE_VISIBLE_IN_MVP:
		_add_base_action(column, "Waddle Race", UITheme.ICON_PLAY,
			func() -> void: SceneRouter.go_to(Game.SCENE_MODE_SELECT))
		_add_base_action(column, "Waddle School", UITheme.ICON_SCHOOL,
			func() -> void: Game.start_tutorial())
	_add_base_action(column, "Settings & access", UITheme.ICON_GEAR,
		func() -> void: SceneRouter.go_to(Game.SCENE_SETTINGS))
	_add_base_action(column, "Credits", UITheme.ICON_FILM,
		func() -> void: SceneRouter.go_to(Game.SCENE_CREDITS))
	var close := UITheme.make_button("Back to the trail", Vector2(0, 52), _f(20))
	UITheme.hook_sounds(close)
	close.pressed.connect(_dismiss_base_camp)
	column.add_child(close)
	close.grab_focus()


func _add_base_action(parent: VBoxContainer, label: String, icon_svg: String,
		action: Callable) -> void:
	var button := UITheme.make_menu_button(label, icon_svg, Vector2(0, 54), 21)
	button.custom_minimum_size.y = maxf(_row_size(Vector2(0, 54)).y,
		_physical_height_floor(44.0))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	parent.add_child(button)


func _dismiss_base_camp() -> void:
	if _base_camp_overlay == null:
		return
	_base_camp_overlay.queue_free()
	_base_camp_overlay = null
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


## Route map: one objective and one destination, not a terminal status dump.
## Missions already persist across runs; this card only reads their state.
func _add_expedition_log(parent: VBoxContainer) -> void:
	var mission_state := RunnerMissions.new()
	var first := "Start a run to discover your first mission"
	if SaveManager.get_value(RunnerMissions.SAVE_KEY_SET, null) is Array:
		mission_state.load_state(false)
		var row_data: Array = mission_state.rows()
		for item: Dictionary in row_data:
			if not bool(item.get("done", false)):
				first = String(item.get("text", first))
				break
	var next_band := int(SaveManager.get_value("runner_biome_milestone", 0)) + 1
	var destinations: PackedStringArray = ["Twilight Pass  ·  600 m", "Crystal Caves  ·  1,200 m", "Aurora Night  ·  1,800 m"]
	var next_text: String = destinations[next_band - 1] if next_band <= 3 else "All four destinations discovered"
	var log := PanelContainer.new()
	log.name = "ExpeditionRouteMap"
	var paper := UITheme.make_panel_style(Color(0.96, 0.94, 0.84, 0.98), Color.TRANSPARENT)
	paper.set_border_width_all(0)
	paper.set_corner_radius_all(roundi(_u(24.0)))
	paper.content_margin_left = _u(16.0)
	paper.content_margin_right = _u(16.0)
	paper.content_margin_top = _u(12.0)
	paper.content_margin_bottom = _u(12.0)
	paper.shadow_color = Color(0.01, 0.10, 0.18, 0.33)
	paper.shadow_size = roundi(_u(6.0))
	log.add_theme_stylebox_override("panel", paper)
	parent.add_child(log)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(13))
	log.add_child(row)
	var route_art := TextureRect.new()
	route_art.texture = UITheme.make_icon("<svg xmlns='http://www.w3.org/2000/svg' width='96' height='96' viewBox='0 0 96 96'><circle cx='48' cy='48' r='45' fill='#cae9df'/><path d='M18 75 Q38 58 28 49 Q17 36 44 34 Q71 31 73 17' fill='none' stroke='#2c7485' stroke-width='5' stroke-linecap='round' stroke-dasharray='2 9'/><path d='M57 76 71 47 86 76Z' fill='#6296a3'/><path d='M65 60 71 47 77 60Z' fill='#f6f5e6'/><circle cx='25' cy='71' r='7' fill='#eda54c' stroke='#fff8df' stroke-width='3'/><path d='M73 16V4 M73 5 88 10 73 16Z' fill='#e7754c' stroke='#624840' stroke-width='2'/></svg>", 1.0)
	route_art.custom_minimum_size = Vector2(_u(82.0), _u(82.0))
	route_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	route_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	route_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(route_art)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", _gap(3))
	row.add_child(stack)
	var heading := Label.new()
	heading.text = "TRAIL MAP    ★ %d" % int(SaveManager.get_value(
		RunnerMissions.SAVE_KEY_STARS, 0))
	heading.add_theme_font_override("font", UITheme.bold_font())
	heading.add_theme_font_size_override("font_size", _f(15))
	heading.add_theme_color_override("font_color", Color(0.12, 0.38, 0.40))
	stack.add_child(heading)
	var objective := UITheme.sub_label(first, _f(18))
	objective.add_theme_color_override("font_color", Color(0.08, 0.20, 0.24))
	objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(objective)
	var destination := UITheme.sub_label("Next: %s" % next_text, _f(15))
	destination.add_theme_color_override("font_color", Color(0.19, 0.39, 0.42))
	destination.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(destination)


func _add_mode_card(parent: Control, heading: String, detail: String,
		icon_svg: String, tint: Color, action: Callable, featured: bool = false) -> void:
	var button := Button.new()
	button.name = "RunModeCard" if featured else "RaceModeCard"
	button.text = heading
	button.accessibility_name = "%s: %s" % [heading, detail]
	button.tooltip_text = button.accessibility_name
	button.custom_minimum_size = Vector2(0.0, maxf(
		_row_size(Vector2(0.0, 216.0 if featured else 128.0)).y,
		_physical_height_floor(114.0 if featured else 52.0)))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Button owns input/focus; child typography gives each mode a true hierarchy.
	# Retain text for keyboard/accessibility contracts but draw it in the overlay.
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color.TRANSPARENT)
	button.add_theme_stylebox_override("normal", _play_tile_box(false) if featured else _mode_card_box(
		Color(0.075, 0.14, 0.25, 0.94), Color(tint, 0.45), 3))
	button.add_theme_stylebox_override("hover", _play_tile_box(true) if featured else _mode_card_box(
		Color(0.10, 0.20, 0.33, 0.98), Color(0.92, 0.98, 1.0, 0.95), 12))
	button.add_theme_stylebox_override("pressed", _play_tile_box(true) if featured else _mode_card_box(
		Color(tint.darkened(0.60), 0.97), UITheme.COLOR_GOLD, 2))
	var focus_ring := StyleBoxFlat.new()
	focus_ring.bg_color = Color.TRANSPARENT
	focus_ring.draw_center = false
	focus_ring.border_color = UITheme.COLOR_GOLD
	focus_ring.set_border_width_all(roundi(_u(3.0)))
	focus_ring.set_corner_radius_all(roundi(_u(30.0 if featured else 16.0)))
	button.add_theme_stylebox_override("focus", focus_ring)
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.add_theme_constant_override("margin_left", _gap(16))
	inset.add_theme_constant_override("margin_right", _gap(14))
	inset.add_theme_constant_override("margin_top", _gap(8))
	inset.add_theme_constant_override("margin_bottom", _gap(8))
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(inset)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(13))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(row)
	if not featured:
		var icon_plate := PanelContainer.new()
		icon_plate.custom_minimum_size = Vector2(_u(48.0), _u(48.0))
		icon_plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_plate.add_theme_stylebox_override("panel", _mode_card_box(
			Color(tint, 0.19), Color(tint, 0.39), 0))
		icon_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon_plate)
		var glyph := TextureRect.new()
		glyph.texture = UITheme.make_icon(icon_svg)
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_plate.add_child(glyph)
	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", _gap(1))
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(labels)
	var kicker := UITheme.sub_label("THE AVALANCHE IS COMING" if featured else "CIRCUITS & CUPS", _f(15))
	kicker.add_theme_color_override("font_color", Color(0.10, 0.44, 0.48) if featured else UITheme.COLOR_ACCENT)
	kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(kicker)
	var title := Label.new()
	title.text = heading
	title.add_theme_font_override("font", UITheme.display_font())
	title.add_theme_font_size_override("font_size", _f(34 if featured else 21))
	title.add_theme_color_override("font_color", Color(0.04, 0.17, 0.26) if featured else UITheme.COLOR_TEXT)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(title)
	var description := UITheme.sub_label(detail, _f(16))
	if featured:
		description.add_theme_color_override("font_color", Color(0.17, 0.37, 0.43))
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(description)
	if featured:
		var courier := TextureRect.new()
		courier.name = "RunnerCourierArt"
		courier.texture = PenguinLoader.loader_texture()
		courier.custom_minimum_size = Vector2(_u(142.0), _u(142.0))
		courier.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		courier.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		courier.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		courier.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(courier)
	else:
		var arrow := TextureRect.new()
		arrow.texture = UITheme.arrow_texture("right", UITheme.COLOR_TEXT, 32)
		arrow.custom_minimum_size = Vector2(_u(22.0), _u(22.0))
		arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(arrow)
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)


func _mode_card_box(bg: Color, border: Color, shadow: int) -> StyleBoxFlat:
	var box := UITheme.make_panel_style(bg, border)
	box.set_corner_radius_all(roundi(_u(16.0)))
	box.content_margin_left = _u(18.0)
	box.content_margin_right = _u(14.0)
	box.content_margin_top = _u(12.0)
	box.content_margin_bottom = _u(12.0)
	box.shadow_color = Color(border, 0.22)
	box.shadow_size = shadow
	return box


func _play_tile_box(hovered: bool) -> StyleBoxFlat:
	var box := UITheme.make_panel_style(
		Color(0.98, 0.96, 0.86, 1.0) if hovered else Color(0.91, 0.96, 0.92, 1.0),
		Color.TRANSPARENT)
	box.set_border_width_all(0)
	box.set_corner_radius_all(roundi(_u(30.0)))
	box.shadow_color = Color(0.01, 0.10, 0.19, 0.36)
	box.shadow_size = roundi(_u(9.0))
	return box


func _add_hub_nav(parent: Control, text: String, icon_svg: String,
		action: Callable) -> void:
	var button := UITheme.make_menu_button(text, icon_svg, Vector2.ZERO, 18)
	button.add_theme_stylebox_override("normal", _mode_card_box(
		Color(0.035, 0.085, 0.16, 0.94), Color(0.60, 0.81, 0.96, 0.55), 3))
	button.add_theme_stylebox_override("hover", _mode_card_box(
		Color(0.08, 0.19, 0.29, 0.98), UITheme.COLOR_ACCENT, 7))
	button.custom_minimum_size = Vector2(0.0, maxf(
		_row_size(Vector2(0.0, 52.0)).y, _physical_height_floor(44.0)))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", _f(17))
	button.add_theme_constant_override("icon_max_width", roundi(_u(22.0)))
	button.add_theme_constant_override("h_separation", roundi(_u(8.0)))
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)


func _runner_record_line() -> String:
	var best := Progression.runner_high_score()
	return "Outrun the avalanche" if best <= 0 else "Best %s · Outrun the avalanche" % _grouped(best)


func _apply_safe_area() -> void:
	if _safe_scroll == null:
		return
	_profile = LayoutProfile.for_viewport(get_viewport())
	var insets := _profile.safe_insets
	if _save_prompt_panel != null:
		_save_prompt_panel.custom_minimum_size.x = maxf(1.0, minf(_profile.safe_rect.size.x - 32.0, _u(620.0)))
	if _cloud_choice_panel != null:
		_cloud_choice_panel.custom_minimum_size.x = maxf(1.0, minf(_profile.safe_rect.size.x - 32.0, _u(620.0)))
	if _cloud_choice_actions != null:
		_cloud_choice_actions.columns = 1 if _profile.is_portrait() else 2
	_safe_scroll.offset_left = insets.x
	_safe_scroll.offset_top = insets.y
	_safe_scroll.offset_right = -insets.z
	_safe_scroll.offset_bottom = -insets.w
	var narrow := _is_narrow_portrait()
	_safe_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER \
		if narrow else ScrollContainer.SCROLL_MODE_AUTO
	_column_width = _hub_width()
	# The first call precedes construction; later calls rebudget the same dock
	# against live geometry rather than retaining its opening width/axis.
	if _composition == null:
		return
	if _composition.vertical != _profile.is_portrait():
		_composition.vertical = _profile.is_portrait()
	_composition.custom_minimum_size = Vector2(0.0, _profile.safe_rect.size.y)
	_art_space.custom_minimum_size = Vector2(0.0,
		_portrait_art_height() if _profile.is_portrait() else 0.0)
	_art_space.size_flags_vertical = Control.SIZE_SHRINK_BEGIN \
		if narrow else Control.SIZE_EXPAND_FILL
	_hub_dock.custom_minimum_size = Vector2(_column_width, 0.0 \
		if _profile.is_portrait() else maxf(_profile.safe_rect.size.y - _gap(32), _u(680.0)))
	_hub_dock.size_flags_vertical = Control.SIZE_FILL \
		if _profile.is_portrait() else Control.SIZE_SHRINK_CENTER
	if _mode_grid != null:
		_mode_grid.columns = 1
	if _brand_logo != null:
		_brand_logo.custom_minimum_size = Vector2(_column_width if _profile.is_portrait()
			else _u(400.0), _u(116.0 if _profile.is_portrait() else 210.0))
	if _secondary_grid != null:
		_secondary_grid.columns = _secondary_columns()
	_update_status_chip_layout()


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
## The runner's button carries its own record, so the mode advertises its
## progression from the menu rather than only inside itself.
func _runner_label() -> String:
	var best := Progression.runner_high_score()
	if best <= 0:
		return "Waddle Run"
	return "Waddle Run · Best %s" % _grouped(best)


## 12480 -> "12,480". A bare five-digit score reads as a phone number.
func _grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if value < 0 else "") + out


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
	# Rows are a little shorter on a narrow phone. The hub has seven of them
	# plus a chip and a title block, and at the authored heights the stack came
	# out taller than the screen — the last row was sliced against the browser
	# toolbar. A few units per row is invisible; a missing row is not.
	var narrow := _is_narrow_portrait()
	var authored := Vector2(COLUMN_BASE,
		(84.0 if narrow else 92.0) if primary else (62.0 if narrow else 70.0))
	# make_menu_button already applies the touch enlargement; the width is then
	# widened to the viewport-relative column so the stack fills a phone screen.
	var button := UITheme.make_menu_button(text, icon_svg, authored, 38 if primary else 30)
	button.custom_minimum_size = Vector2(_column_width, _row_size(authored).y)
	# A Button's text sets a minimum width the container cannot go under, and
	# at touch sizes these labels asked for 890 units inside a 680-unit rail —
	# so the rail grew and pushed its own buttons past the screen edge. Clipping
	# lets the row take the width it is given; the label ellipsizes instead of
	# dictating the layout.
	button.clip_text = true
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
	button.add_theme_stylebox_override("normal", _mode_card_box(
		Color(0.025, 0.066, 0.12, 0.94), Color(0.60, 0.81, 0.96, 0.48), 2))
	button.add_theme_stylebox_override("hover", _mode_card_box(
		Color(0.08, 0.18, 0.28, 0.98), UITheme.COLOR_ACCENT, 6))
	button.custom_minimum_size = Vector2(0.0, maxf(
		_row_size(authored).y, _physical_height_floor(44.0)))
	button.add_theme_font_size_override("font_size", _f(20))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = text
	button.accessibility_name = text
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
	_status_chip = chip
	_status_chip_stacked = stacked
	# Rounded glass pill with a soft gold rim — quieter than the old full-
	# strength gold border, and the pill shape reads as a status chip.
	var chip_style := UITheme.make_panel_style(
		Color(0.055, 0.10, 0.18, 0.88), Color(UITheme.COLOR_GOLD, 0.5))
	chip_style.set_corner_radius_all(27)
	chip_style.content_margin_left = _u(12.0 if _is_narrow_portrait() else 22.0)
	chip_style.content_margin_right = _u(12.0 if _is_narrow_portrait() else 22.0)
	chip_style.content_margin_top = _u(8.0)
	chip_style.content_margin_bottom = _u(8.0)
	chip_style.shadow_size = 6
	chip.add_theme_stylebox_override("panel", chip_style)
	# Whatever the contents ask for, the chip cannot be wider than the column.
	# Without this the row's minimums win and the panel grows past the screen.
	if _is_narrow_portrait():
		chip.custom_minimum_size.x = 0.0
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chip.clip_contents = true
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
		# Inset by the safe area, not just a fixed 16. A phone held sideways
		# puts the notch and the home indicator on the short edges, so a chip
		# pinned to the raw viewport corner sits under them: measured at 26
		# units past the safe edge in landscape.
		chip.offset_right = -(16.0 + _profile.safe_insets.z)
		chip.offset_top = 16.0 + _profile.safe_insets.y
		chip.offset_bottom = 0.0
		add_child(chip)
	# Keep the existing one-line spacing while grouping stats/auth so only
	# those two groups reflow when their intrinsic width exceeds the safe dock.
	_status_row = BoxContainer.new()
	var row := _status_row
	row.add_theme_constant_override("separation", roundi(_u(16.0)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(row)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", roundi(_u(16.0)))
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(stats)
	var fish_box := HBoxContainer.new()
	fish_box.add_theme_constant_override("separation", roundi(_u(8.0)))
	stats.add_child(fish_box)
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
	stats.add_child(_chip_divider())
	var rank := VBoxContainer.new()
	rank.name = "ExpeditionRank"
	rank.alignment = BoxContainer.ALIGNMENT_CENTER
	rank.add_theme_constant_override("separation", _gap(2))
	stats.add_child(rank)
	_level_label = Label.new()
	_level_label.add_theme_font_override("font", UITheme.bold_font())
	_level_label.add_theme_font_size_override("font_size", _f(17))
	_level_label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	_level_label.text = "EXPEDITION  ·  LV %d" % Progression.get_level()
	rank.add_child(_level_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.name = "LevelProgress"
	_xp_bar.custom_minimum_size = Vector2(_u(130.0), _u(7.0))
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = 1.0
	_xp_bar.value = Progression.level_progress()
	_xp_bar.show_percentage = false
	_xp_bar.tooltip_text = "%s / %s XP to next level" % [
		_grouped(Progression.get_xp() % Progression.XP_PER_LEVEL),
		_grouped(Progression.XP_PER_LEVEL)]
	var xp_track := StyleBoxFlat.new()
	xp_track.bg_color = Color(0.018, 0.043, 0.08, 0.94)
	xp_track.set_corner_radius_all(5)
	_xp_bar.add_theme_stylebox_override("background", xp_track)
	_xp_bar.add_theme_stylebox_override("fill", UITheme.make_bar_fill(
		Color(0.24, 0.76, 0.85), Color(0.82, 0.97, 1.0)))
	rank.add_child(_xp_bar)
	Progression.fish_changed.connect(_on_fish_changed)
	Progression.xp_changed.connect(_on_xp_changed)
	# Web: offer sign-in right on the menu — it backs up progress to the cloud
	# and unlocks leaderboard posting. Chip widens to fit.
	if AccountAuthPresentation.account_surface_enabled() and (LeaderboardClient.can_sign_in() or not GameConfig.is_mobile()):
		_status_auth_divider = _chip_divider()
		row.add_child(_status_auth_divider)
		var auth := HBoxContainer.new()
		auth.add_theme_constant_override("separation", roundi(_u(16.0)))
		auth.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(auth)
		_auth_chip_label = Label.new()
		_auth_chip_label.add_theme_font_size_override("font_size", _f(20))
		_auth_chip_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		_auth_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Second guard on the same overflow: however the chip is laid out, one
		# very long account name must not be allowed to set its width.
		_auth_chip_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		# A minimum width is a floor the container cannot go under, so on a
		# phone this label plus the button set the chip's width and the chip
		# then overflowed the column: measured on an iPhone, the chip wanted 856
		# units inside a 752-unit safe area, which is why Sign In sat off the
		# right edge of the screen. On a narrow portrait the name gets no floor
		# at all and simply takes what is left.
		if _is_narrow_portrait():
			_auth_chip_label.custom_minimum_size.x = 0.0
			_auth_chip_label.clip_text = true
			_auth_chip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			_auth_chip_label.custom_minimum_size.x = _u(AUTH_NAME_MAX_WIDTH)
		auth.add_child(_auth_chip_label)
		_auth_chip_button = UITheme.make_button(
			"Sign In",
			_row_size(Vector2(110 if _is_narrow_portrait() else 150, 44)), _f(20))
		UITheme.hook_sounds(_auth_chip_button)
		_auth_chip_button.pressed.connect(func() -> void:
			if not LeaderboardClient.can_sign_in():
				var native_auth := get_node_or_null("/root/NativeAuthClient")
				if native_auth != null:
					if bool(native_auth.call("signed_in")):
						native_auth.call("sign_out")
					elif not bool(native_auth.get("pending")):
						_auth_chip_button.text = "Opening…"
						native_auth.call("sign_in")
					else:
						native_auth.call("cancel_sign_in")
			elif LeaderboardClient.signed_in:
				if LeaderboardClient.has_cloud_save_conflict():
					_show_cloud_choice()
				else:
					LeaderboardClient.sign_out()
			else:
				AccountAuthPresentation.activate())
		auth.add_child(_auth_chip_button)
		_refresh_auth_chip()
		LeaderboardClient.auth_changed.connect(_refresh_auth_chip)
		if not LeaderboardClient.can_sign_in():
			var native_auth := get_node_or_null("/root/NativeAuthClient")
			if native_auth != null:
				native_auth.connect("auth_changed", _refresh_auth_chip)
				native_auth.connect("status_changed", func(message: String) -> void:
					if _auth_chip_label != null:
						_auth_chip_label.text = message
						_auth_chip_label.tooltip_text = message)
		# A restored cloud save changes fish/level: reload the menu to reflect it.
		LeaderboardClient.cloud_save_restored.connect(func() -> void:
			if is_inside_tree():
				SceneRouter.go_to(Game.SCENE_MAIN_MENU))
	return host


## A CenterContainer still propagates its child's minimum. Clipping a chip
## therefore cannot fix overflow: keep stats and the complete auth action,
## stack their groups when needed, and let only the name yield its width.
func _update_status_chip_layout() -> void:
	if _status_chip == null or _status_row == null or _profile == null:
		return
	var narrow := _is_narrow_portrait()
	var chip_style := _status_chip.get_theme_stylebox("panel") as StyleBoxFlat
	if chip_style != null:
		chip_style.content_margin_left = _u(12.0 if narrow else 22.0)
		chip_style.content_margin_right = _u(12.0 if narrow else 22.0)
	if _auth_chip_label != null:
		_auth_chip_label.custom_minimum_size.x = 0.0 if narrow else _u(AUTH_NAME_MAX_WIDTH)
		_auth_chip_label.clip_text = narrow
		_auth_chip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL \
			if narrow else Control.SIZE_FILL
		_auth_chip_button.custom_minimum_size.x = _row_size(
			Vector2(110.0 if narrow else 150.0, 44.0)).x
	if _status_row.vertical:
		_status_row.vertical = false
	if _status_auth_divider != null:
		_status_auth_divider.show()
	_status_chip.custom_minimum_size.x = 0.0
	# Never use dock.size.x here: an overflowing chip has already enlarged it.
	var available := _profile.safe_rect.size.x - 32.0
	if _status_chip_stacked and _hub_dock != null:
		available = (_profile.safe_rect.size.x if _profile.is_portrait() else _column_width) \
			- _hub_dock.get_theme_stylebox("panel").get_minimum_size().x
		if _profile.is_portrait() \
				and _safe_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_SHOW_NEVER:
			available -= _safe_scroll.get_v_scroll_bar().get_minimum_size().x \
				+ _safe_scroll.get_theme_constant("scrollbar_h_separation")
	available = maxf(available, 1.0)
	if _status_chip.get_combined_minimum_size().x <= available:
		return
	_status_row.vertical = true
	if _status_auth_divider != null:
		_status_auth_divider.hide()
	if _auth_chip_label != null:
		_auth_chip_label.custom_minimum_size.x = 0.0
		_auth_chip_label.clip_text = true
		_auth_chip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_chip.custom_minimum_size.x = available


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
	if not LeaderboardClient.can_sign_in():
		var native_auth := get_node_or_null("/root/NativeAuthClient")
		if native_auth != null and bool(native_auth.call("signed_in")):
			_auth_chip_label.text = "Connected for shop"
			_auth_chip_button.text = "Sign Out"
		elif native_auth != null and bool(native_auth.get("pending")):
			_auth_chip_label.text = String(native_auth.get("status"))
			_auth_chip_button.text = "Cancel"
		else:
			_auth_chip_label.text = "Optional shop account"
			_auth_chip_button.text = "Sign In"
		_update_status_chip_layout()
		return
	if LeaderboardClient.signed_in:
		_dismiss_save_prompt()
		if LeaderboardClient.has_cloud_save_conflict():
			_auth_chip_label.text = "Backing up progress…"
			_auth_chip_button.text = "Sign Out"
		else:
			_auth_chip_label.text = "Online save paused" if LeaderboardClient.cloud_sync_error \
				else _short_account_name(LeaderboardClient.player_display_name())
			_auth_chip_button.text = "Sign Out"
	else:
		_auth_chip_label.text = AccountAuthPresentation.message("Cloud save")
	AccountAuthPresentation.update_button(_auth_chip_button, "Sign In")
	_auth_chip_label.tooltip_text = _auth_chip_label.text
	_update_status_chip_layout()


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
	_update_status_chip_layout()


func _on_xp_changed(xp: int, level: int) -> void:
	if _level_label == null or _xp_bar == null:
		return
	_level_label.text = "EXPEDITION  ·  LV %d" % level
	_xp_bar.value = Progression.level_progress()
	_xp_bar.tooltip_text = "%s / %s XP to next level" % [
		_grouped(xp % Progression.XP_PER_LEVEL), _grouped(Progression.XP_PER_LEVEL)]
	_update_status_chip_layout()


static func _make_fish_texture() -> ImageTexture:
	var img := Image.new()
	if img.load_svg_from_string(FISH_ICON_SVG, 2.0) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		if _cloud_choice != null:
			_dismiss_cloud_choice()
			return
		if _save_prompt != null:
			_dismiss_save_prompt()
			return
		# Main menu is the root destination; Back only dismisses its overlays.


## One-time line telling a phone player that leaning steers, and where to turn
## it off. A toast rather than a modal: the feature is already on and working,
## so there is nothing to decide -- interrupting them to say so would be worse
## than saying nothing.
func _maybe_announce_tilt() -> void:
	if GameConfig.is_headless() or not TiltSteering.supported():
		return
	if bool(SettingsManager.get_setting("gameplay", "tilt_seen")):
		return
	if not bool(SettingsManager.get_setting("gameplay", "tilt_steering")):
		return
	SettingsManager.set_setting("gameplay", "tilt_seen", true)

	var toast := PanelContainer.new()
	var style := UITheme.make_panel_style(
		Color(0.055, 0.10, 0.18, 0.94), Color(UITheme.COLOR_ACCENT, 0.45))
	style.set_corner_radius_all(14)
	style.content_margin_left = _u(20.0)
	style.content_margin_right = _u(20.0)
	style.content_margin_top = _u(14.0)
	style.content_margin_bottom = _u(14.0)
	style.shadow_size = 10
	toast.add_theme_stylebox_override("panel", style)
	toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast.offset_bottom = -_u(28.0)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.modulate.a = 0.0
	add_child(toast)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_u(12.0)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(row)
	row.add_child(UITheme.arrow_icon("both", _u(26.0), UITheme.COLOR_ACCENT))
	var text := Label.new()
	text.text = "Tilt to steer is on — lean your phone. Change it in Settings."
	text.add_theme_font_size_override("font_size", _f(18))
	text.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Inset from the column so the toast reads as a card sitting on the
	# screen rather than a bar welded to both edges.
	text.custom_minimum_size.x = minf(_u(430.0), _column_width * 0.82)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)

	var tween := create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, 0.3)
	tween.tween_interval(5.5)
	tween.tween_property(toast, "modulate:a", 0.0, 0.5)
	tween.tween_callback(toast.queue_free)
