extends "res://scripts/ui/main_menu.gd"
## Art-led home. Uses automatic account sync and replaces
## its dock hierarchy with one run action and three clear destinations.

const DestinationArt := preload("res://scripts/ui/menu_destination_art.gd")
const MissionRoute := preload("res://scripts/ui/mission_route_view.gd")

var _premium_overlay: Control = null
var _active_menu_panel := "home"
var _panel_history: Array[String] = []
var _portrait_logo: TextureRect = null
var _landscape_logo: TextureRect = null
var _top_status: MarginContainer = null
var _profile_button: Button = null
var _fish_panel: PanelContainer = null
var _fish_art: TextureRect = null
var _destination_shelf: PanelContainer
var _name_prompt: Control = null


func _ready() -> void:
	if BootProfiler.enabled():
		print("[ww-startup] menu_ready_begin_ms=", Time.get_ticks_msec())
	UITheme.apply_ui_scale(self)
	_profile = LayoutProfile.for_viewport(get_viewport())
	_boost = minf(_tall_boost(), 1.85)
	_column_width = _hub_width()
	ExpeditionMenuStyle.add_backdrop(self, "home")
	_build_home()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	Progression.fish_changed.connect(_on_fish_changed)
	TiltSteering.arm_permission_on_first_gesture(self)
	UITheme.attach_swipe_back(self, _on_back)
	if not UITheme.is_touch() and not _buttons.is_empty():
		_buttons[0].grab_focus()
	AudioManager.play_music("music_title")
	_schedule_save_prompt()
	# Keep the single web startup cover until this menu has actually drawn.
	# engine.startGame() resolves earlier, while Boot and router can still be
	# preparing resources; removing the cover then exposes a second loader.
	if OS.has_feature("web"):
		_reveal_web_startup_cover.call_deferred()
	if LeaderboardClient.can_sign_in():
		LeaderboardClient.cloud_sync_changed.connect(_refresh_account_copy)
		LeaderboardClient.public_name_changed.connect(_refresh_account_copy)
		LeaderboardClient.auth_changed.connect(_refresh_account_copy)
		LeaderboardClient.cloud_save_restored.connect(_refresh_account_copy)
	if BootProfiler.enabled():
		print("[ww-startup] menu_ready_end_ms=", Time.get_ticks_msec())


func _reveal_web_startup_cover() -> void:
	# Menu _ready/first draw can precede SceneRouter's final fade. Removing the
	# browser cover there briefly exposes a second Godot loader. Keep one visible
	# startup surface until the router has uncovered the final menu frame.
	while SceneRouter.is_presenting() and not SceneRouter.is_loading_recovery_active():
		await get_tree().process_frame
		if not is_inside_tree():
			return
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	if BootProfiler.enabled():
		print("[ww-startup] menu_first_draw_ms=", Time.get_ticks_msec())
	JavaScriptBridge.eval(
		"if (typeof window.__wwBootReady === 'function') "
		+ "window.__wwBootReady();", true)


func _build_home() -> void:
	_safe_scroll = ScrollContainer.new()
	_safe_scroll.name = "HomeSafeScroll"
	_safe_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_safe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_safe_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_safe_scroll.follow_focus = true
	TouchScroll.attach(_safe_scroll)
	add_child(_safe_scroll)

	_composition = BoxContainer.new()
	_composition.name = "HomeComposition"
	_composition.vertical = _profile.is_portrait()
	_composition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_composition.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_composition.add_theme_constant_override("separation", 0)
	_safe_scroll.add_child(_composition)

	_art_space = Control.new()
	_art_space.name = "HeroArtStage"
	_art_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_art_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_composition.add_child(_art_space)
	_portrait_logo = _make_logo(_art_space)
	_portrait_logo.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_portrait_logo.anchor_left = 0.115
	_portrait_logo.anchor_right = 0.885
	_portrait_logo.anchor_top = -0.005
	_portrait_logo.anchor_bottom = 0.355
	_portrait_logo.offset_left = 0.0
	_portrait_logo.offset_right = 0.0
	_portrait_logo.offset_top = 0.0
	_portrait_logo.offset_bottom = 0.0

	_hub_dock = PanelContainer.new()
	_hub_dock.name = "HomeActionDock"
	var clear := StyleBoxEmpty.new()
	_hub_dock.add_theme_stylebox_override("panel", clear)
	_hub_dock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hub_dock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_composition.add_child(_hub_dock)
	var dock_column := VBoxContainer.new()
	dock_column.alignment = BoxContainer.ALIGNMENT_CENTER
	dock_column.add_theme_constant_override("separation", roundi(_u(12.0)))
	_hub_dock.add_child(dock_column)
	_landscape_logo = _make_logo(dock_column)
	_landscape_logo.custom_minimum_size.y = _u(220.0 if _profile.is_compact()
		else 470.0)

	var depart := ExpeditionMenuStyle.button("WADDLE RUN", true, _f(40),
		maxf(_row_size(Vector2(0.0, 128.0)).y, _physical_height_floor(110.0)))
	depart.name = "RunDeparture"
	depart.accessibility_name = "Start Waddle Run: outrun the avalanche"
	# The approved concept already has the final penguin, wordmark and arrow.
	# Keep the native Button hit area and accessibility label beneath its art.
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		depart.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	depart.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		depart.add_theme_color_override(state, Color.TRANSPARENT)
	depart.pressed.connect(func() -> void: Game.start_runner())
	dock_column.add_child(depart)
	_add_run_button_art(depart)
	_buttons.append(depart)

	var nav_panel := ExpeditionMenuStyle.panel(dock_column)
	_destination_shelf = nav_panel
	nav_panel.name = "IvoryDestinationShelf"
	var nav_style := ExpeditionMenuStyle.material_box(false)
	nav_style.content_margin_left = _u(7.0)
	nav_style.content_margin_right = _u(7.0)
	nav_style.content_margin_top = _u(6.0)
	nav_style.content_margin_bottom = _u(6.0)
	nav_panel.add_theme_stylebox_override("panel", nav_style)
	var nav := HBoxContainer.new()
	nav.name = "DestinationDock"
	nav.add_theme_constant_override("separation", roundi(_u(3.0)))
	nav_panel.add_child(nav)
	_add_nav(nav, "PENGUINS", UITheme.ICON_PALETTE, func() -> void:
		SceneRouter.go_to(Game.SCENE_CUSTOMIZE))
	_add_nav(nav, "MISSIONS", UITheme.ICON_SCHOOL, _show_missions)
	_add_nav(nav, "MORE", UITheme.ICON_GEAR, _show_base_camp)

	_top_status = MarginContainer.new()
	_top_status.name = "HomeTopStatus"
	_top_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_status.offset_bottom = _u(100.0)
	_top_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_status)
	var top_row := HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_status.add_child(top_row)
	_fish_panel = ExpeditionMenuStyle.currency_pill(Progression.get_fish(), false)
	_fish_panel.name = "HomeFishBalance"
	_fish_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top_row.add_child(_fish_panel)
	_fish_art = _fish_panel.find_child("FishSymbol", true, false) as TextureRect
	_fish_label = _fish_panel.find_child("FishAmount", true, false) as Label
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(space)
	var profile_size := 76.0 if _profile.is_portrait() else 112.0
	_profile_button = ExpeditionMenuStyle.button("", false, _f(17), _u(profile_size))
	_profile_button.name = "HomeAccountButton"
	_profile_button.accessibility_name = "Account and cloud save"
	_profile_button.custom_minimum_size.x = _u(profile_size)
	_profile_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_profile_button.icon = ExpeditionMenuStyle._material_texture(
		"res://assets/art/ui/menu/home_profile_icon_exact_v1.webp")
	_profile_button.expand_icon = true
	_profile_button.add_theme_constant_override("icon_max_width", roundi(_u(
		55.0 if _profile.is_portrait() else 88.0)))
	_profile_button.pressed.connect(_show_account)
	top_row.add_child(_profile_button)


func _make_logo(parent: Control) -> TextureRect:
	var logo := TextureRect.new()
	logo.texture = ResourceLoader.load(
		"res://assets/art/ui/menu/home_logo_v1.webp") as Texture2D
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(logo)
	return logo


func _hub_width() -> float:
	if _profile.is_portrait():
		return _profile.safe_rect.size.x
	return minf(_profile.safe_rect.size.x * 0.445, _u(960.0))


func _add_run_button_art(button: Button) -> void:
	var art := TextureRect.new()
	art.name = "ApprovedRunArtwork"
	art.texture = ExpeditionMenuStyle._material_texture(
		"res://assets/art/ui/menu/home_run_button_exact_v1.webp")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(art)
	button.focus_entered.connect(func() -> void:
		art.modulate = Color(1.0, 0.95, 0.85))
	button.focus_exited.connect(func() -> void: art.modulate = Color.WHITE)
	button.button_down.connect(func() -> void: art.modulate = Color(0.86, 0.89, 0.93))
	button.button_up.connect(func() -> void:
		if button.has_focus():
			art.modulate = Color(1.0, 0.95, 0.85)
		else:
			art.modulate = Color.WHITE)


func _add_nav(parent: HBoxContainer, title: String, svg: String,
		action: Callable) -> void:
	var button := Button.new()
	button.accessibility_name = title.capitalize()
	button.tooltip_text = title.capitalize()
	button.custom_minimum_size.y = maxf(_u(155.0 if _profile.is_portrait() else
		(105.0 if _profile.is_compact() else 210.0)),
		_physical_height_floor(128.0))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "pressed", "hover", "hover_pressed"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = ExpeditionMenuStyle.CORAL
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(25)
	button.add_theme_stylebox_override("focus", focus)
	var approved_icon: String = {
		"PENGUINS": "res://assets/art/ui/menu/home_penguins_icon_exact_v1.webp",
		"MISSIONS": "res://assets/art/ui/menu/home_missions_icon_exact_v1.webp",
		"MORE": "res://assets/art/ui/menu/home_more_icon_exact_v1.webp",
	}.get(title, "")
	var icon_texture: Texture2D = ExpeditionMenuStyle._material_texture(approved_icon) if not approved_icon.is_empty() \
		else UITheme.make_icon(svg)
	var visual := VBoxContainer.new()
	visual.name = "DestinationVisual"
	visual.set_anchors_preset(Control.PRESET_FULL_RECT)
	visual.alignment = BoxContainer.ALIGNMENT_CENTER
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(visual)
	var image := TextureRect.new()
	image.name = "DestinationIcon"
	image.texture = icon_texture
	image.custom_minimum_size = Vector2(_physical_height_floor(72.0),
		_physical_height_floor(72.0)) if _profile.is_portrait() else \
		Vector2(_u(55.0 if _profile.is_compact() else 102.0),
			_u(55.0 if _profile.is_compact() else 102.0))
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(image)
	var caption := ExpeditionMenuStyle.label(title, _f(24 if _profile.is_portrait()
		else (22 if _profile.is_compact() else 29)), ExpeditionMenuStyle.INK)
	caption.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(caption)
	caption.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	# Keep hover inside the illustrated roundel; no flat blue tile over the shelf.
	button.mouse_entered.connect(func() -> void: image.modulate = Color(1.04, 1.04, 1.04))
	button.mouse_exited.connect(func() -> void: image.modulate = Color.WHITE)
	button.button_down.connect(func() -> void: image.modulate = Color(0.93, 0.95, 0.97))
	button.button_up.connect(func() -> void: image.modulate = Color.WHITE)
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)


func _apply_safe_area() -> void:
	if _safe_scroll == null:
		return
	_profile = LayoutProfile.for_viewport(get_viewport())
	var insets := _profile.safe_insets
	_safe_scroll.offset_left = insets.x
	_safe_scroll.offset_top = insets.y
	_safe_scroll.offset_right = -insets.z - (_profile.safe_rect.size.x * 0.03 if not _profile.is_portrait() else 0.0)
	_safe_scroll.offset_bottom = 0.0 if _profile.is_portrait() else -insets.w
	# The painted phone shelf reaches the window edges; its controls remain
	# inside the safe-area layout above.
	_safe_scroll.clip_contents = not _profile.is_portrait()
	_column_width = _hub_width()
	_composition.vertical = _profile.is_portrait()
	_composition.custom_minimum_size = Vector2(0.0, _profile.safe_rect.size.y + (insets.w if _profile.is_portrait() else 0.0))
	_art_space.custom_minimum_size = Vector2(0.0,
		_profile.safe_rect.size.y * 0.53 if _profile.is_portrait() else 0.0)
	_hub_dock.custom_minimum_size = Vector2(_column_width, 0.0)
	var shelf_height := _profile.safe_rect.size.y * (0.150 if _profile.is_portrait() else 0.213)
	# Expand the desktop shelf downward without pulling the already aligned
	# logo/Run action upward through the vertically centered parent container.
	var dock_skin := StyleBoxEmpty.new()
	dock_skin.content_margin_top = 0.0 if _profile.is_portrait() else _profile.safe_rect.size.y * 0.028
	_hub_dock.add_theme_stylebox_override("panel", dock_skin)
	var shelf_skin: StyleBox
	if _profile.is_portrait():
		var bottom_shelf := preload("res://scripts/ui/home_dock_surface.gd").new()
		bottom_shelf.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/ivory_card_v4.webp")
		bottom_shelf.region = Rect2(15, 32, 1420, 1025)
		bottom_shelf.capsule = false
		bottom_shelf.bottom_bleed = shelf_height
		bottom_shelf.left_bleed = insets.x
		bottom_shelf.right_bleed = insets.z
		shelf_skin = bottom_shelf
	else:
		var original_skin := ExpeditionMenuStyle.material_box(false)
		var desktop_shelf := preload("res://scripts/ui/home_dock_surface.gd").new()
		desktop_shelf.texture = original_skin.texture
		desktop_shelf.region = original_skin.region
		# Snow in the painted source precedes its opaque cream body. Raise only
		# the backing so the roundels sit inside the body; preserve its bottom,
		# layout height and the already aligned Run action above it.
		desktop_shelf.top_bleed = _profile.safe_rect.size.y * 0.016
		shelf_skin = desktop_shelf
	shelf_skin.content_margin_left = _column_width * (0.018 if _profile.is_portrait() else 0.065)
	shelf_skin.content_margin_right = _column_width * (0.018 if _profile.is_portrait() else 0.065)
	shelf_skin.content_margin_top = shelf_height * (0.09 if _profile.is_portrait() else 0.040)
	shelf_skin.content_margin_bottom = shelf_height * (0.09 if _profile.is_portrait() else 0.170) + (insets.w if _profile.is_portrait() else 0.0)
	_destination_shelf.add_theme_stylebox_override("panel", shelf_skin)
	(_hub_dock.get_child(0) as VBoxContainer).add_theme_constant_override("separation", roundi(_profile.safe_rect.size.y * (0.022 if _profile.is_portrait() else 0.030)))
	_landscape_logo.custom_minimum_size.y = _profile.safe_rect.size.y * 0.40
	if not _buttons.is_empty():
		_buttons[0].custom_minimum_size = Vector2(_column_width * (0.88 if _profile.is_portrait() else 0.95), _column_width * (0.225 if _profile.is_portrait() else 0.25))
		_buttons[0].size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for index: int in range(1, mini(_buttons.size(), 4)):
		var destination := _buttons[index] as Button
		var height := shelf_height * (0.82 if _profile.is_portrait() else 0.79)
		destination.custom_minimum_size.y = height
		var visual := destination.get_child(0) as VBoxContainer
		if visual != null and visual.get_child_count() >= 2:
			# A Button does not inherit its child VBox minimum. Reserve the caption
			# first, then let the icon fit the remaining height inside the shelf.
			visual.offset_top = 0.0 if _profile.is_portrait() else shelf_height * 0.050
			visual.offset_bottom = 0.0
			visual.add_theme_constant_override("separation", roundi(height * 0.035))
			var image := visual.get_child(0) as TextureRect
			var caption := visual.get_child(1) as Label
			image.custom_minimum_size = Vector2.ZERO
			caption.add_theme_font_size_override("font_size", roundi(shelf_height * 0.13 if _profile.is_portrait() else _profile.safe_rect.size.y * 0.032))
			caption.add_theme_color_override("font_color", ExpeditionMenuStyle.INK if _profile.is_portrait() else Color("061833"))
	if _fish_panel != null:
		var pill_height := _profile.safe_rect.size.y * (0.054 if _profile.is_portrait() else 0.09)
		_fish_panel.custom_minimum_size = Vector2(0.0, pill_height)
		_fish_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_fish_panel.add_theme_stylebox_override("panel",
			ExpeditionMenuStyle.material_box(false, pill_height * 0.22, pill_height * 0.10))
		_fish_art.custom_minimum_size = Vector2(pill_height * 1.18, pill_height * 0.78)
		_fish_label.custom_minimum_size.x = 0.0
		_fish_label.add_theme_font_size_override("font_size", roundi(pill_height * 0.47))
	if _profile_button != null:
		var profile_size := _profile.safe_rect.size.y * (0.066 if _profile.is_portrait() else 0.12)
		_profile_button.custom_minimum_size = Vector2.ONE * profile_size
		_profile_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_profile_button.add_theme_constant_override("icon_max_width", roundi(profile_size))
		for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
			_profile_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_hub_dock.size_flags_vertical = Control.SIZE_SHRINK_END \
		if _profile.is_portrait() else Control.SIZE_SHRINK_CENTER
	_portrait_logo.visible = _profile.is_portrait()
	_landscape_logo.visible = not _profile.is_portrait()
	_top_status.offset_left = insets.x + _u(14.0)
	_top_status.offset_right = -insets.z - _u(14.0)
	_top_status.offset_top = insets.y + _u(8.0)
	# Row height is the actual avatar height, not an unrelated design-unit box
	# that stretches the avatar downward while the currency stays at its top.
	_top_status.offset_bottom = _top_status.offset_top + _profile_button.custom_minimum_size.y
	if _premium_overlay != null:
		# Rotation/layout changes redraw the current page without navigation.
		_clear_premium_overlay()
		_redraw_active_panel.call_deferred()


func _redraw_active_panel() -> void:
	# A Back press can arrive before deferred layout work runs.
	if _active_menu_panel != "home":
		_open_premium_overlay(_active_menu_panel)


func _on_fish_changed(total: int) -> void:
	if _fish_label != null:
		_fish_label.text = _grouped(total)
	_refresh_account_copy()


func _on_back() -> void:
	if is_instance_valid(_name_prompt):
		_dismiss_name_prompt()
	elif _cloud_choice != null:
		_dismiss_cloud_choice()
	elif _save_prompt != null:
		_dismiss_save_prompt()
	elif _active_menu_panel != "home":
		var deletion: AccountDeletionPanel = null
		if is_instance_valid(_premium_overlay):
			deletion = _premium_overlay.find_child("AccountPrivacyDeletion", true, false) as AccountDeletionPanel
		if deletion != null and deletion.consume_back():
			return
		_close_premium_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_on_back()


func get_navigation_state() -> Dictionary:
	return {"panel": _active_menu_panel, "panel_history": _panel_history.duplicate()}


func restore_navigation_state(state: Dictionary) -> void:
	_panel_history.clear()
	for panel: String in state.get("panel_history", []):
		if panel in ["home", "base_camp", "missions", "account"]:
			_panel_history.append(panel)
	_active_menu_panel = String(state.get("panel", "home"))
	if not _active_menu_panel in ["home", "base_camp", "missions", "account"]:
		_active_menu_panel = "home"
	_clear_premium_overlay()
	if _active_menu_panel != "home":
		_open_premium_overlay(_active_menu_panel)


func _navigate_panel(kind: String) -> void:
	if kind != _active_menu_panel:
		_panel_history.append(_active_menu_panel)
	_active_menu_panel = kind
	_open_premium_overlay(kind)


func _show_missions() -> void:
	_navigate_panel("missions")


func _show_base_camp() -> void:
	_navigate_panel("base_camp")


func _show_account() -> void:
	_navigate_panel("account")


func _close_premium_overlay() -> void:
	_clear_premium_overlay()
	_active_menu_panel = _panel_history.pop_back() if not _panel_history.is_empty() else "home"
	if _active_menu_panel != "home":
		_open_premium_overlay(_active_menu_panel)


func _clear_premium_overlay() -> void:
	if _premium_overlay != null:
		_premium_overlay.queue_free()
		_premium_overlay = null
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _open_premium_overlay(kind: String) -> void:
	if kind == "base_camp":
		_open_base_camp_reference_overlay()
		return
	if kind == "missions":
		_open_missions_reference_overlay()
		return
	if kind == "account":
		_open_account_reference_overlay()
		return
	if _premium_overlay != null:
		_clear_premium_overlay()
	_premium_overlay = Control.new()
	_premium_overlay.name = "%sOverlay" % kind.capitalize()
	_premium_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_premium_overlay)
	var overlay_art := ExpeditionMenuStyle.add_backdrop(_premium_overlay, kind)
	if kind == "missions" and not _profile.is_portrait():
		# A clean wide environment supports the route inset without duplicating
		# a giant cropped route across the whole landscape canvas.
		overlay_art.texture = ExpeditionMenuStyle.background_texture("penguins", false)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UtilityScreenLayout.bind_safe_rect(self, margin)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, _gap(12))
	_premium_overlay.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	TouchScroll.attach(scroll)
	margin.add_child(scroll)
	var center := HBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var left_space := Control.new()
	left_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(left_space)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = minf(_profile.safe_rect.size.x *
		(0.44 if not _profile.is_portrait() and kind == "base_camp" else \
		0.52 if not _profile.is_portrait() else \
		(0.86 if kind == "base_camp" else 0.94)),
		_u(760.0))
	column.add_theme_constant_override("separation", _gap(5 if kind == "base_camp" else 10))
	center.add_child(column)
	var right_space := Control.new()
	right_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL \
		if _profile.is_portrait() else Control.SIZE_SHRINK_END
	if not _profile.is_portrait():
		right_space.custom_minimum_size.x = _gap(12)
	center.add_child(right_space)
	var back_size := maxf(_physical_height_floor(54.0),
		_profile.safe_rect.size.x * 0.15) if _profile.is_portrait() \
		else maxf(_u(58.0), _profile.safe_rect.size.y * 0.12)
	var back := ExpeditionMenuStyle.back_button(back_size)
	back.name = "OverlayBack"
	back.z_index = 2
	back.accessibility_name = "Back to previous page"
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_close_premium_overlay)
	column.add_child(back)
	match kind:
		"missions":
			_build_missions_overlay(column)
		"account":
			_build_account_overlay(column)
		_:
			_build_base_camp_overlay(column)
	var back_slot := Control.new()
	back_slot.custom_minimum_size.y = _physical_height_floor(55.0) \
		if _profile.is_portrait() else 0.0
	column.add_child(back_slot)
	column.move_child(back_slot, 0)
	# Back shares the top safe row with each illustrated title.
	back.reparent(_premium_overlay)
	back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back.offset_left = _profile.safe_rect.position.x + _gap(10)
	back.offset_top = _profile.safe_rect.position.y + _gap(8)
	back.offset_right = back.offset_left + back_size
	back.offset_bottom = back.offset_top + back_size
	if kind == "base_camp":
		var balance := ExpeditionMenuStyle.currency_pill(Progression.get_fish(), false)
		balance.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		balance.offset_right = -_gap(24)
		balance.offset_left = balance.offset_right - _profile.safe_rect.size.x * (0.21 if _profile.is_portrait() else 0.13)
		balance.offset_top = _profile.safe_rect.position.y + _gap(18)
		balance.offset_bottom = balance.offset_top + _profile.safe_rect.size.y * (0.055 if _profile.is_portrait() else 0.088)
		var fish_icon := balance.find_child("FishSymbol", true, false) as TextureRect
		fish_icon.custom_minimum_size = Vector2.ONE * _profile.safe_rect.size.y * (0.044 if _profile.is_portrait() else 0.065)
		var fish_amount := balance.find_child("FishAmount", true, false) as Label
		fish_amount.add_theme_font_size_override("font_size", _f(25 if _profile.is_portrait() else 40))
		_premium_overlay.add_child(balance)
	if not UITheme.is_touch():
		back.grab_focus()


func _open_missions_reference_overlay() -> void:
	if _premium_overlay != null:
		_clear_premium_overlay()
	_premium_overlay = Control.new()
	_premium_overlay.name = "MissionsOverlay"
	_premium_overlay.set_meta("menu_kind", "missions")
	_premium_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_premium_overlay)
	var portrait := _profile.is_portrait()
	var bounds := _profile.safe_rect
	var canvas := get_viewport_rect().size
	var scale := canvas.x / 941.0 if portrait else minf(canvas.x / 1672.0, canvas.y / 941.0)
	var art := TextureRect.new()
	art.name = "MissionBackdrop"
	art.texture = MissionRoute.background(portrait)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_premium_overlay.add_child(art)
	var content := Control.new()
	content.name = "MissionComposition"
	content.position = Vector2.ZERO
	content.size = canvas
	_premium_overlay.add_child(content)
	var w := canvas.x
	var h := canvas.y
	var title := TextureRect.new()
	title.name = "ApprovedOverlayTitle"
	title.texture = ExpeditionMenuStyle.title_texture("missions")
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)
	_mission_place(title, Rect2(w * (0.23 if portrait else 0.3375), h * (0.011 if portrait else 0.020),
		w * (0.54 if portrait else 0.325), h * (0.079 if portrait else 0.145)))
	var back_extent := Vector2.ONE * h * (0.072 if portrait else 0.12)
	var back := ExpeditionMenuStyle.back_button(back_extent.y)
	back.custom_minimum_size = back_extent
	back.name = "OverlayBack"
	back.pressed.connect(_close_premium_overlay)
	content.add_child(back)
	var back_origin := Vector2(w * (0.038 if portrait else 0.025),h * 0.015).max(bounds.position)
	_mission_place(back, Rect2(back_origin,back_extent))

	# This illustrated menu adapts to the full canvas. Cover-cropping a wide
	# painting at 3:2 removed DAY ICE and its label. Map markers share exactly
	# the same normalized transform as the background, so no region is lost.
	var route := RunnerMissions.map_progress()
	var map := MissionRoute.new()
	map.name = "MissionRouteMap"
	content.add_child(map)
	var map_rect := Rect2(Vector2(0, h * 0.195), canvas * Vector2(1, 0.34)) if portrait else \
		Rect2(Vector2(0, h * 0.285), canvas * Vector2(0.60, 0.62))
	_mission_place(map, map_rect)
	map.configure(portrait, route)
	var positions := [Vector2(0.14, 0.48), Vector2(0.38, 0.605),
		Vector2(0.63, 0.67), Vector2(0.875, 0.53)]
	if not portrait:
		positions = [Vector2(0.15, 0.52), Vector2(0.385, 0.66), Vector2(0.633, 0.70), Vector2(0.867, 0.59)]
	for index: int in positions.size():
		var plaque := PanelContainer.new()
		plaque.name = "RouteName%d" % index
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plaque.add_theme_stylebox_override("panel", _mission_wood_box(0.0, false))
		map.add_child(plaque)
		var label_size := Vector2(map.size.x * (0.16 if portrait else 0.17), map.size.y * (0.10 if portrait else 0.09))
		_mission_place(plaque, Rect2(map.size * positions[index] - label_size * 0.5, label_size))
		var label := _mission_reference_label(String(["DAY ICE", "TWILIGHT", "CAVES", "AURORA"][index]),
			maxi(12, roundi(map.size.x * (0.024 if portrait else 0.027))))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		plaque.add_child(label)

	var missions := RunnerMissions.new()
	# The first displayed board must be the same board the next run loads.
	missions.load_state()
	var badge := PanelContainer.new()
	badge.name = "MissionStarBalance"
	badge.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_box(false, scale * 14.0, scale * 6.0))
	content.add_child(badge)
	_mission_place(badge, Rect2(w * (0.786 if portrait else 0.877), h * (0.024 if portrait else 0.035), w * (0.183 if portrait else 0.104), h * (0.052 if portrait else 0.095)))
	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	badge.add_child(star_row)
	var star_art := TextureRect.new()
	var star_region := AtlasTexture.new()
	star_region.atlas = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/controls_icons_v2.webp")
	star_region.region = Rect2(836, 836, 418, 418)
	star_region.filter_clip = true
	star_art.texture = star_region
	star_art.custom_minimum_size = Vector2.ONE * scale * 78.0
	star_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star_row.add_child(star_art)
	var amount := _mission_reference_label(str(missions.stars()), roundi(scale * 42.0))
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	star_row.add_child(amount)
	UtilityScreenLayout.defer_header_alignment(self, title, back, [badge])

	var milestone := int(route["current_region"])
	var milestone_text := "NEXT: %s\n%s M · ONE RUN" % [String(route["regions"][milestone + 1]["name"]), RunnerMissions._group(int(route["next_metres"]))] if milestone < 3 else "ALL REGIONS\nDISCOVERED"
	var status := PanelContainer.new()
	status.name = "MilestonePlaque"
	status.add_theme_stylebox_override("panel", _mission_wood_box(scale * 5.0))
	content.add_child(status)
	_mission_place(status, Rect2(w * (0.08 if portrait else 0.045), h * (0.427 if portrait else 0.755),
		w * (0.38 if portrait else 0.22), h * (0.095 if portrait else 0.16)))
	status.rotation = -0.07
	var next_label := _mission_reference_label(milestone_text, roundi(scale * (25.0 if portrait else 30.0)))
	next_label.rotation = 0.0
	next_label.name = "MilestoneText"
	next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	next_label.tooltip_text = "Reach this distance in one run to discover the next region. Every new run starts at Day Ice; discoveries stay saved."
	# Container layout resets direct children's rotation on every sort. Keep
	# the live lettering inside a plain Control so its painted slope persists.
	var lettering := Control.new()
	lettering.name = "MilestoneLettering"
	status.add_child(lettering)
	lettering.add_child(next_label)
	next_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The plaque painting already rises 123 source pixels over 1530 pixels.
	# Account for nonuniform destination scaling before matching the lettering
	# to that painted edge; the parent adds its own authored rotation as well.
	var align_plaque_text := func() -> void:
		next_label.pivot_offset = next_label.size * 0.5
		next_label.rotation = atan2(-123.0 * status.size.y / 750.0,
			1530.0 * status.size.x / 1830.0)
	next_label.resized.connect(align_plaque_text)
	align_plaque_text.call_deferred()
	map.region_selected.connect(func(selected: int) -> void:
		var destination: Dictionary = route["regions"][selected]
		next_label.text = String(destination["name"]) + ("\nDISCOVERED" if destination["unlocked"] else "\n%s M · ONE RUN" % RunnerMissions._group(int(destination["required_metres"])))
		next_label.tooltip_text = "Reach this distance in one run to discover the region. Selection does not change the start of your run."
	)

	# Scroll is confined to live mission cards; it cannot move under map labels.
	var scroll := ScrollContainer.new()
	scroll.name = "MissionCardsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	TouchScroll.attach(scroll)
	content.add_child(scroll)
	_mission_place(scroll, Rect2(w * (0.015 if portrait else 0.596), h * (0.536 if portrait else 0.267),
		w * (0.97 if portrait else 0.39), minf(h * (0.442 if portrait else 0.69),bounds.end.y - h * (0.536 if portrait else 0.267))))
	var cards := VBoxContainer.new()
	cards.name = "MissionCards"
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", roundi(h * (0.006 if portrait else 0.018)))
	scroll.add_child(cards)
	var index := 0
	for item: Dictionary in missions.rows():
		var card := PanelContainer.new()
		card.name = "MissionStrip%d" % index
		card.custom_minimum_size.y = h * 0.108 if portrait else scale * 141.0
		var card_skin := ExpeditionMenuStyle.material_card(scale * 20.0, scale * 8.0)
		card_skin.paint_expand_y = scale * 8.0
		card.add_theme_stylebox_override("panel", card_skin)
		cards.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", roundi(scale * 16.0))
		card.add_child(row)
		var icon := TextureRect.new()
		icon.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/mission_%s_icon_exact_v1.webp" % _mission_icon_name(String(item["text"]), index))
		var icon_size := h * 0.092 if portrait else scale * 108.0
		icon.custom_minimum_size = Vector2.ONE * icon_size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var stack := VBoxContainer.new()
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.add_theme_constant_override("separation", roundi(scale * 6.0))
		row.add_child(stack)
		var label := _mission_reference_label(String(item["text"]).to_upper(), roundi(scale * (36.0 if portrait else 30.0)))
		label.name = "MissionDescription"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = String(item["text"])
		stack.add_child(label)
		var bar := ProgressBar.new()
		bar.name = "MissionProgress"
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.0
		bar.value = float(item["progress"])
		bar.custom_minimum_size.y = h * 0.026 if portrait else scale * 32.0
		var trough := ExpeditionMenuStyle.surface(Color("c8dce8"), roundi(scale * 20.0), false)
		trough.border_color = Color("fff9ee")
		trough.set_border_width_all(maxi(2, roundi(scale * 4.0)))
		trough.shadow_color = Color(0.24,0.34,0.40,0.18)
		trough.shadow_size = maxi(1,roundi(scale * 2.0))
		bar.add_theme_stylebox_override("background", trough)
		if bool(item["done"]):
			# Multiplying the cyan texture by yellow produces green. Completed
			# missions use the reference's warm gold instead.
			var gold := ExpeditionMenuStyle.surface(ExpeditionMenuStyle.GOLD, roundi(scale * 18.0), false)
			gold.border_color = Color("ffe39b")
			gold.set_border_width_all(maxi(1, roundi(scale * 2.0)))
			bar.add_theme_stylebox_override("fill", gold)
		else:
			# The mission reference uses a smooth blue inset fill. The runner's
			# icy HUD sprite includes its own metal frame and doubles this rail.
			var fill := ExpeditionMenuStyle.surface(Color("3d94dd"), roundi(scale * 18.0), false)
			fill.border_color = Color("86bfee")
			fill.set_border_width_all(maxi(1,roundi(scale * 2.0)))
			fill.set_expand_margin_all(-scale * 3.0)
			bar.add_theme_stylebox_override("fill", fill)
		stack.add_child(bar)
		index += 1
	var run := ExpeditionMenuStyle.button("RUN NOW", true, roundi(scale * 48.0), h * (0.098 if portrait else 0.165))
	run.name = "MissionRunNow"
	run.custom_minimum_size = Vector2(w * (0.68 if portrait else 0.378), h * (0.098 if portrait else 0.165))
	run.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ExpeditionMenuStyle.illustrated_action(run, "RUN NOW", ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/run_action_icon_v5.webp"), roundi(scale * 64.0), run.custom_minimum_size.y)
	run.pressed.connect(Game.start_runner)
	cards.add_child(run)
	if not UITheme.is_touch():
		back.grab_focus()


func _mission_place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _mission_reference_label(text: String, font_size: int) -> Label:
	var label := ExpeditionMenuStyle.label(text, maxi(font_size, 12))
	label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_missions_overlay(_column: VBoxContainer) -> void:
	# Compatibility hook: all mission composition is owned by its dedicated page.
	pass


func _mission_wood_box(padding: float, milestone: bool = true) -> StyleBoxTexture:
	var material := AtlasTexture.new()
	material.atlas = ExpeditionMenuStyle._material_texture(
		"res://assets/art/ui/menu/mission_plaque_v3.webp" if milestone else "res://assets/art/ui/menu/mission_wood_plaque_v2.webp")
	material.region = Rect2(120, 0, 1830, 750) if milestone else Rect2(20, 35, 984, 255)
	material.filter_clip = true
	var box := StyleBoxTexture.new()
	box.texture = material
	box.texture_margin_left = 0.0
	box.texture_margin_right = 0.0
	box.content_margin_left = padding + _u(12.0)
	box.content_margin_right = padding + _u(12.0)
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box


func _mission_icon_name(description: String, index: int) -> String:
	var lower := description.to_lower()
	if lower.contains("fish"):
		return "fish"
	if lower.contains("jump") or lower.contains("obstacle") \
			or lower.contains("dodge") or lower.contains("ramp") \
			or lower.contains("slide") or lower.contains("power-up") or lower.contains("hazard"):
		return "ice"
	if lower.contains("run") or lower.contains("distance"):
		return "flag"
	return String(["fish", "ice", "flag"][index % 3])


func _open_base_camp_reference_overlay() -> void:
	if _premium_overlay != null:
		_clear_premium_overlay()
	_premium_overlay = Control.new()
	_premium_overlay.name = "Base_campOverlay"
	_premium_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_premium_overlay)
	ExpeditionMenuStyle.add_backdrop(_premium_overlay, "base_camp")
	var safe := _profile.safe_rect
	var portrait := _profile.is_portrait()
	var w := safe.size.x
	var h := safe.size.y
	var back := ExpeditionMenuStyle.back_button(h * (0.065 if portrait else 0.115))
	back.name = "OverlayBack"
	back.position = safe.position + Vector2(w * 0.022, h * 0.026)
	back.pressed.connect(_close_premium_overlay)
	_premium_overlay.add_child(back)
	_add_overlay_title("base_camp_sign", 0.54)
	var balance := ExpeditionMenuStyle.currency_pill(Progression.get_fish())
	balance.position = safe.position + Vector2(w * (0.76 if portrait else 0.82), h * 0.032)
	balance.size = Vector2(w * (0.215 if portrait else 0.155), h * (0.052 if portrait else 0.088))
	_premium_overlay.add_child(balance)
	var amount := balance.find_child("FishAmount", true, false) as Label
	amount.add_theme_font_size_override("font_size", roundi(h * (0.022 if portrait else 0.044)))
	var fish := balance.find_child("FishSymbol", true, false) as TextureRect
	fish.custom_minimum_size = Vector2(h * 0.052, h * 0.037) if portrait else Vector2(h * 0.095, h * 0.067)
	UtilityScreenLayout.defer_header_alignment(self,
		_premium_overlay.find_child("ApprovedOverlayTitle", true, false) as Control, back, [balance])
	var column := VBoxContainer.new()
	column.name = "BaseCampDestinations"
	column.position = safe.position + Vector2(w * (0.12 if portrait else 0.625), h * (0.367 if portrait else 0.176))
	column.size = Vector2(w * (0.76 if portrait else 0.348), h * (0.595 if portrait else 0.78))
	column.add_theme_constant_override("separation", roundi(h * (0.006 if portrait else 0.008)))
	_premium_overlay.add_child(column)
	var account_h := h * (0.091 if portrait else 0.13)
	var row_h := h * (0.077 if portrait else 0.103)
	var account := PanelContainer.new()
	account.name = "GuestExplorerRow"
	account.custom_minimum_size.y = account_h
	account.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_box(false, account_h * 0.08, account_h * 0.06))
	column.add_child(account)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(account_h * 0.08))
	account.add_child(row)
	var avatar := TextureRect.new()
	avatar.name = "BaseCampAvatar"
	avatar.texture = DestinationArt.icon("guest")
	avatar.custom_minimum_size = Vector2.ONE * account_h * 0.90
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(avatar)
	var name_label := _mission_reference_label(LeaderboardClient.display_name if LeaderboardClient.signed_in else "GUEST EXPLORER", roundi(account_h * 0.245))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(name_label)
	var signin := ExpeditionMenuStyle.button("ACCOUNT" if LeaderboardClient.signed_in else "SIGN IN", true, roundi(account_h * 0.23), account_h * 0.62)
	signin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	signin.size_flags_horizontal = Control.SIZE_SHRINK_END
	signin.custom_minimum_size = Vector2(column.size.x * 0.28, account_h * 0.65)
	signin.pressed.connect(_show_account)
	row.add_child(signin)
	for entry: Array in [["LEADERBOARD", "leaderboard", Game.SCENE_LEADERBOARD],
		["ACHIEVEMENTS", "achievements", Game.SCENE_ACHIEVEMENTS],
		["SHOP", "shop", Game.SCENE_COSMETIC_SHOP],
		["SETTINGS", "settings", Game.SCENE_SETTINGS],
		["CREDITS", "credits", Game.SCENE_CREDITS], ["FEEDBACK", "feedback", ""]]:
		if GameConfig.native_offline_mvp() and entry[0] == "SHOP":
			continue
		var button := ExpeditionMenuStyle.button(entry[0], false, roundi(row_h * (0.31 if portrait else 0.385)), row_h)
		button.name = "BaseCampFeedback" if entry[1] == "feedback" else "BaseCamp" + String(entry[1]).capitalize()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = row_h
		for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
			var tint := Color(1.025, 1.02, 1.01) if state == "hover" else Color.WHITE
			if state in ["pressed", "hover_pressed"]: tint = Color(0.96, 0.97, 0.98)
			var skin := ExpeditionMenuStyle.material_box(false, 18.0, 10.0, tint)
			skin.paint_expand_y = h * 0.006
			skin.content_margin_left = column.size.x * (0.36 if portrait else 0.32)
			skin.content_margin_right = row_h * 0.65
			button.add_theme_stylebox_override(state, skin)
		var icon := TextureRect.new()
		icon.name = "BaseCampDestinationIcon"
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if entry[1] == "feedback":
			icon.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/feedback_mailbox_icon_v3.webp")
		else:
			icon.texture = DestinationArt.icon(entry[1])
		icon.position = Vector2(column.size.x * 0.07, row_h * 0.03)
		icon.size = Vector2(row_h * 0.94, row_h * 0.94)
		button.add_child(icon)
		var arrow := _mission_reference_label("›", roundi(row_h * 0.65))
		arrow.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		arrow.offset_left = -column.size.x * 0.145
		arrow.offset_right = -column.size.x * 0.06
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_child(arrow)
		if entry[1] == "feedback":
			button.pressed.connect(func() -> void: preload("res://scripts/ui/feedback_form.gd").new().open(self))
		else:
			button.pressed.connect(func() -> void: SceneRouter.go_to(String(entry[2])))
		column.add_child(button)
	if not UITheme.is_touch():
		back.grab_focus()


func _build_base_camp_overlay(column: VBoxContainer) -> void:
	# Use the actual carved sign from the approved concept. The prior flat text
	# was the most visible mismatch on Base Camp despite the matching cabin art.
	_add_overlay_title("base_camp_sign", 0.60)
	var space := Control.new()
	var space_fraction := 0.0
	if _profile.is_portrait():
		space_fraction = 0.30
	else:
		space_fraction = 0.16
	space.custom_minimum_size.y = _profile.safe_rect.size.y * space_fraction
	column.add_child(space)
	var account := ExpeditionMenuStyle.panel(column)
	var account_pill := ExpeditionMenuStyle.material_box(false)
	account_pill.content_margin_top = 2.0
	account_pill.content_margin_bottom = 2.0
	account.add_theme_stylebox_override("panel", account_pill)
	account.custom_minimum_size.y = _profile.safe_rect.size.y * (0.070 \
		if _profile.is_portrait() else 0.11)
	var account_row := HBoxContainer.new()
	account_row.alignment = BoxContainer.ALIGNMENT_CENTER
	account_row.add_theme_constant_override("separation", _gap(7))
	account.add_child(account_row)
	var avatar := TextureRect.new()
	avatar.texture = DestinationArt.icon("guest")
	var avatar_size := _profile.safe_rect.size.y * (0.065 if _profile.is_portrait() \
		else 0.10)
	avatar.custom_minimum_size = Vector2(avatar_size, avatar_size)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	account_row.add_child(avatar)
	var account_name := ExpeditionMenuStyle.label(
		LeaderboardClient.player_display_name(), _f(25 if _profile.is_portrait() else 30))
	account_name.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	account_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_row.add_child(account_name)
	var account_action := ExpeditionMenuStyle.button(
		"ACCOUNT" if LeaderboardClient.signed_in else "SIGN IN", true,
		_f(25 if _profile.is_portrait() else 30), _physical_height_floor(50.0) if _profile.is_portrait() \
		else _u(50.0))
	account_action.custom_minimum_size.x = _physical_height_floor(86.0) \
		if _profile.is_portrait() else _u(104.0)
	account_action.size_flags_horizontal = Control.SIZE_SHRINK_END
	account_action.pressed.connect(_show_account)
	account_row.add_child(account_action)
	var destinations := VBoxContainer.new()
	destinations.name = "BaseCampDestinations"
	destinations.add_theme_constant_override("separation", roundi(_profile.safe_rect.size.y * 0.012))
	column.add_child(destinations)
	for entry: Dictionary in [
		{"label": "LEADERBOARD", "scene": Game.SCENE_LEADERBOARD, "icon": "leaderboard"},
		{"label": "ACHIEVEMENTS", "scene": Game.SCENE_ACHIEVEMENTS, "icon": "achievements"},
		{"label": "SHOP", "scene": Game.SCENE_COSMETIC_SHOP, "icon": "shop"},
		{"label": "SETTINGS", "scene": Game.SCENE_SETTINGS, "icon": "settings"},
		{"label": "CREDITS", "scene": Game.SCENE_CREDITS, "icon": "credits"},
	]:
		if GameConfig.native_offline_mvp() and entry["label"] == "SHOP":
			continue
		var button := ExpeditionMenuStyle.button(String(entry["label"]), false,
			_f(30 if _profile.is_portrait() else 38),
			_physical_height_floor(46.0) if _profile.is_portrait() else _u(70.0))
		button.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
		# Every state shares the same painted silhouette and content margins.
		# A flat normal pill plus textured hover shrank the visible button.
		for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
			button.add_theme_stylebox_override(state,
				ExpeditionMenuStyle.material_box(false, 18.0, 10.0,
				Color(1.05, 1.05, 1.05) if state == "hover" else Color.WHITE))
		button.custom_minimum_size.y = _profile.safe_rect.size.y * (0.084 \
			if _profile.is_portrait() else 0.112)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
			var row_style := button.get_theme_stylebox(state)
			row_style.content_margin_left = _profile.safe_rect.size.y * (0.105 \
				if _profile.is_portrait() else 0.15)
		var icon := TextureRect.new()
		icon.texture = DestinationArt.icon(String(entry["icon"]))
		var icon_size := _profile.safe_rect.size.y * (0.078 if _profile.is_portrait() \
			else 0.108)
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.anchor_top = 0.0
		icon.anchor_bottom = 1.0
		icon.offset_left = _u(13.0)
		icon.offset_right = _u(13.0) + icon_size
		button.add_child(icon)
		var arrow := TextureRect.new()
		arrow.texture = UITheme.arrow_texture("right", ExpeditionMenuStyle.INK, 36)
		arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow.anchor_left = 1.0
		arrow.anchor_right = 1.0
		arrow.anchor_top = 0.0
		arrow.anchor_bottom = 1.0
		arrow.offset_left = -(_physical_height_floor(37.0) \
			if _profile.is_portrait() else _u(48.0))
		arrow.offset_right = -_u(8.0)
		button.add_child(arrow)
		var scene := String(entry["scene"])
		button.pressed.connect(func() -> void: SceneRouter.go_to(scene))
		destinations.add_child(button)
	var feedback := ExpeditionMenuStyle.button("FEEDBACK", false,
		roundi(_profile.safe_rect.size.y * (0.019 if _profile.is_portrait() else 0.03)),
		_profile.safe_rect.size.y * (0.048 if _profile.is_portrait() else 0.07))
	feedback.name = "BaseCampFeedback"
	feedback.accessibility_name = "Share feedback or report a problem"
	feedback.custom_minimum_size.y = _profile.safe_rect.size.y * (0.048 if _profile.is_portrait() else 0.07)
	feedback.pressed.connect(func() -> void:
		preload("res://scripts/ui/feedback_form.gd").new().open(self))
	column.add_child(feedback)


func _add_overlay_title(asset_name: String, portrait_width: float) -> void:
	# The title stays independent of the scrollable live cards.
	var sign := TextureRect.new()
	sign.name = "ApprovedOverlayTitle"
	var art_path := "res://assets/art/ui/menu/%s_title_v1.webp" % asset_name
	if asset_name == "base_camp_sign":
		art_path = "res://assets/art/ui/menu/base_camp_sign_v1.webp"
	sign.texture = ExpeditionMenuStyle._material_texture(art_path)
	if asset_name != "base_camp_sign":
		sign.texture = ExpeditionMenuStyle.title_texture(asset_name)
	sign.accessibility_name = asset_name.replace("_", " ").capitalize()
	sign.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sign.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.set_anchors_preset(Control.PRESET_CENTER_TOP)
	if not _profile.is_portrait():
		sign.anchor_left = 0.49 if asset_name == "base_camp_sign" else 0.25
		sign.anchor_right = sign.anchor_left
	var sign_width := minf(_profile.safe_rect.size.x *
		(portrait_width if _profile.is_portrait() else 0.34), _u(560.0))
	sign.offset_left = -sign_width * 0.5
	sign.offset_right = sign_width * 0.5
	sign.offset_top = -_u(5.0) - (_profile.safe_rect.size.y * 0.043 if not _profile.is_portrait() else 0.0)
	sign.offset_bottom = sign.offset_top + sign_width * \
		(0.67 if asset_name == "base_camp_sign" else 0.34)
	_premium_overlay.add_child(sign)


func _open_account_reference_overlay() -> void:
	if _premium_overlay != null:
		_clear_premium_overlay()
	_premium_overlay = Control.new()
	_premium_overlay.name = "AccountOverlay"
	_premium_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_premium_overlay)
	var backdrop := ExpeditionMenuStyle.add_backdrop(_premium_overlay, "account")
	if not _profile.is_portrait():
		backdrop.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/account_background_landscape_v2.webp")
	# Painted composition uses the full reference canvas; actual safe insets
	# constrain controls once, rather than shrinking every nested card.
	var safe := Rect2(Vector2.ZERO, _profile.viewport_size)
	var portrait := _profile.is_portrait()
	var width := safe.size.x * (0.95 if portrait else 0.44)
	var scale := width / 890.0
	_premium_overlay.set_meta("account_reference_scale", scale)
	var back_size := 110.0 * scale if portrait else safe.size.y * 0.12
	var back := ExpeditionMenuStyle.back_button(back_size)
	back.name = "OverlayBack"
	back.position = safe.position + Vector2(22, 24) * scale
	back.position.x = maxf(back.position.x, _profile.safe_insets.x)
	back.position.y = maxf(back.position.y, _profile.safe_insets.y)
	back.size = Vector2.ONE * back_size
	back.pressed.connect(func() -> void:
		var deletion := _premium_overlay.find_child("AccountPrivacyDeletion", true, false) as AccountDeletionPanel
		if deletion != null and deletion.consume_back():
			return
		_close_premium_overlay())
	_premium_overlay.add_child(back)
	var title := TextureRect.new()
	title.name = "AccountTitleArtwork"
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.texture = ExpeditionMenuStyle.title_texture("account")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_width := safe.size.x * (0.48 if portrait else 0.35)
	title.position = safe.position + Vector2(safe.size.x * (0.5 if portrait else 0.30) - title_width * 0.5, (36 if portrait else 70) * scale)
	title.size = Vector2(title_width, title_width * 0.28)
	_premium_overlay.add_child(title)
	UtilityScreenLayout.defer_header_alignment(self, title, back)
	var scroll := ScrollContainer.new()
	scroll.name = "AccountReferenceScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	TouchScroll.attach(scroll)
	var top := safe.size.y * (0.345 if portrait else 0.052)
	scroll.position = safe.position + Vector2((safe.size.x - width) * 0.5 if portrait
		else safe.size.x * 0.50, top)
	scroll.size = Vector2(width, safe.size.y - top - maxf(18.0 * scale, _profile.safe_insets.w))
	_premium_overlay.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", roundi(8 * scale))
	scroll.add_child(column)
	_build_account_overlay(column)
	if not UITheme.is_touch():
		back.grab_focus()


func _build_account_overlay(column: VBoxContainer) -> void:
	var detail_style := preload("res://scripts/ui/menu_detail_style.gd")
	var scale := _account_scale()
	var portrait := _profile.is_portrait()
	var panel := ExpeditionMenuStyle.panel(column)
	panel.name = "AccountIdentityCard"
	var identity_skin := ExpeditionMenuStyle.material_card(28 * scale, 24 * scale)
	identity_skin.paint_expand_y = 16 * scale
	panel.add_theme_stylebox_override("panel", identity_skin)
	panel.custom_minimum_size.y = (330 if portrait else 304) * scale
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", roundi(20 * scale))
	panel.add_child(identity)
	var avatar := SettingsAccountArt.picture("avatar", Vector2.ONE * (275 if portrait else 265) * scale)
	avatar.name = "AccountExplorerPortrait"
	identity.add_child(avatar)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", roundi(8 * scale))
	identity.add_child(stack)
	var name_label := _account_label(LeaderboardClient.player_display_name(), 49 if portrait else 47)
	name_label.name = "AccountDisplayName"
	_account_single_line(name_label)
	name_label.tooltip_text = LeaderboardClient.player_display_name()
	stack.add_child(name_label)
	var status := _account_label(_account_sync_copy(), 28, ExpeditionMenuStyle.INK_MUTED)
	status.name = "AccountSyncStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_override("font", UITheme.ui_font())
	stack.add_child(status)
	var change_name := _account_button("CHANGE NAME", false, 29, 64)
	change_name.name = "AccountChangeName"
	change_name.icon = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><path fill="#173c60" d="m9 44 31-31 12 12-31 31-16 4zM44 9l5-5q3-3 6 0l5 5q3 3 0 6l-5 5z"/></svg>')
	change_name.expand_icon = true
	change_name.add_theme_constant_override("icon_max_width", roundi(38 * scale))
	change_name.add_theme_constant_override("h_separation", roundi(14 * scale))
	change_name.pressed.connect(_show_name_prompt)
	stack.add_child(change_name)
	if LeaderboardClient.can_sign_in():
		var auth := _account_button("SIGN OUT" if LeaderboardClient.signed_in else "SIGN IN TO BACK UP", true, 36, 118 if portrait else 108)
		auth.name = "AccountAuthAction"
		if not LeaderboardClient.signed_in:
			var person := UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><circle cx="25" cy="17" r="12" fill="#fff9eb"/><path d="M5 55v-8c0-20 40-20 40 0v8z" fill="#fff9eb"/><path d="M51 28v23m-11-12h22" fill="none" stroke="#fff9eb" stroke-width="7" stroke-linecap="round"/></svg>')
			ExpeditionMenuStyle.illustrated_action(auth, "SIGN IN TO BACK UP", person,
				roundi(36 * scale), auth.custom_minimum_size.y * 0.60, false)
		# Keep this page mounted while the secure sheet opens/cancels so its
		# pending state and retry errors remain visible on return to the game.
		auth.pressed.connect(AccountAuthPresentation.activate)
		stack.add_child(auth)
		AccountAuthPresentation.update_button(auth)
	var summary := PanelContainer.new()
	summary.name = "AccountJournalStats"
	var journal_style := SettingsAccountArt.journal((30 if portrait else 24) * scale)
	# The illustrated leather binding occupies the bottom of the panel rect.
	# Keep live values on the paper, above that binding in both orientations.
	journal_style.content_margin_bottom = (50 if portrait else 42) * scale
	journal_style.expand_margin_top = 22 * scale
	journal_style.expand_margin_bottom = 6 * scale
	summary.add_theme_stylebox_override("panel", journal_style)
	summary.custom_minimum_size.y = (302 if portrait else 302) * scale
	column.add_child(summary)
	var metrics := HBoxContainer.new()
	metrics.name = "AccountMetricColumns"
	metrics.add_theme_constant_override("separation", roundi(10 * scale))
	summary.add_child(metrics)
	_account_metric(metrics, "BEST RUN", _grouped(Progression.runner_high_score()), "mountain")
	_account_divider(metrics)
	_account_metric(metrics, "FISH", _grouped(Progression.get_fish()),
		"res://assets/art/ui/menu/home_fish_symbol_clean_v2.png")
	_account_divider(metrics)
	_account_metric(metrics, "MISSIONS", str(int(SaveManager.get_value(RunnerMissions.SAVE_KEY_STARS, 0))),
		"res://assets/art/ui/menu/home_missions_icon_exact_v1.webp")
	if not portrait:
		for cell: Node in metrics.get_children():
			if cell is VBoxContainer:
				(cell.get_child(0) as TextureRect).custom_minimum_size.y = 124 * scale
				(cell.get_child(2) as Label).add_theme_font_size_override("font_size", roundi(40 * scale))
				_account_single_line(cell.get_child(2) as Label)
	var privacy_card := ExpeditionMenuStyle.panel(column)
	privacy_card.name = "AccountPrivacyCard"
	privacy_card.add_theme_stylebox_override("panel", detail_style.inset(44 * scale, 24 * scale, 44 * scale))
	var privacy_rows := VBoxContainer.new()
	privacy_rows.add_theme_constant_override("separation", roundi(12 * scale))
	privacy_card.add_child(privacy_rows)
	privacy_rows.add_child(_account_label("PRIVACY & DATA", 38 if portrait else 34))
	var privacy := _account_button("PRIVACY POLICY", false, 34, 108 if portrait else 96)
	privacy.name = "AccountPrivacyPolicy"
	_account_action_icon(privacy, "privacy")
	privacy.pressed.connect(func() -> void: OS.shell_open(GameConfig.NATIVE_PRIVACY_URL))
	privacy_rows.add_child(privacy)
	var deletion := AccountDeletionPanel.new()
	deletion.name = "AccountPrivacyDeletion"
	privacy_rows.add_child(deletion)
	(deletion.get_child(0) as Control).hide()
	(deletion.get_child(1) as Control).hide()
	var delete_button := deletion.find_child("OpenAccountDeletion", true, false) as Button
	delete_button.text = "DELETE ACCOUNT"
	ExpeditionMenuStyle.style_button(delete_button, false, roundi(34 * scale))
	delete_button.custom_minimum_size.y = (108 if portrait else 96) * scale
	_account_action_icon(delete_button, "delete")



func _account_metric(parent: HBoxContainer, title: String, value: String, icon_path: String) -> void:
	var scale := _account_scale()
	var cell := VBoxContainer.new()
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_stretch_ratio = 1.0
	cell.name = "AccountMetric" + title.replace(" ", "")
	cell.custom_minimum_size.x = 0.0
	parent.add_child(cell)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = SettingsAccountArt.sprite(icon_path) if SettingsAccountArt.REGIONS.has(icon_path) \
		else ExpeditionMenuStyle._material_texture(icon_path)
	icon.custom_minimum_size.y = (138 if _profile.is_portrait() else 106) * scale
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	for text_value: String in [title, value]:
		var label := _account_label(text_value, 32 if text_value == title else 27)
		label.name = "Caption" if text_value == title else "Value"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_account_single_line(label)
		label.tooltip_text = text_value
		cell.add_child(label)


## These rows have fixed columns, so ellipsis must operate on one explicit
## line. Inherited smart-wrap plus ellipsis can yield a zero-height web label.
func _account_single_line(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.y = ceilf(label.get_theme_font("font").get_height(label.get_theme_font_size("font_size")))


func _account_divider(parent: HBoxContainer) -> void:
	var line := ColorRect.new()
	line.color = Color("e1d2ba")
	line.custom_minimum_size.x = 2.0 * _account_scale()
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


func _account_action_icon(button: Button, key: String) -> void:
	var scale := _account_scale()
	button.icon = SettingsAccountArt.sprite(key)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width", roundi(80 * scale))
	button.add_theme_constant_override("h_separation", roundi(32 * scale))
	var arrow := _account_label("›", 58)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	arrow.offset_left = -65 * scale
	arrow.offset_right = -20 * scale
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(arrow)


func _account_scale() -> float:
	return float(_premium_overlay.get_meta("account_reference_scale", 1.0))


func _account_label(text: String, size: int, color: Color = ExpeditionMenuStyle.INK) -> Label:
	var label := ExpeditionMenuStyle.label(text, roundi(size * _account_scale()), color)
	label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	preload("res://scripts/ui/menu_detail_style.gd").clean_label(label, color)
	return label


func _account_button(text: String, primary: bool, size: int, height: float) -> Button:
	var result := ExpeditionMenuStyle.button(text, primary, roundi(size * _account_scale()), height * _account_scale())
	result.custom_minimum_size.y = height * _account_scale()
	return result


func _account_sync_copy() -> String:
	var auth_message := AccountAuthPresentation.message()
	if not auth_message.is_empty():
		return auth_message
	match LeaderboardClient.cloud_sync_status():
		"syncing": return "Backing up your progress…"
		"saved": return "Progress backed up online"
		"offline", "pending": return "Saved here · online backup pending"
		"unavailable": return "Saved here · online backup unavailable"
	return "Progress saved on this device"


func _refresh_account_copy() -> void:
	if not is_instance_valid(_premium_overlay):
		return
	var title := _premium_overlay.find_child("AccountDisplayName", true, false) as Label
	if title != null:
		title.text = LeaderboardClient.player_display_name()
		title.tooltip_text = title.text
	var status := _premium_overlay.find_child("AccountSyncStatus", true, false) as Label
	if status != null:
		status.text = _account_sync_copy()
	AccountAuthPresentation.update_button(_premium_overlay.find_child("AccountAuthAction", true, false) as Button)
	var values := {"BESTRUN": _grouped(Progression.runner_high_score()),
		"FISH": _grouped(Progression.get_fish()),
		"MISSIONS": str(int(SaveManager.get_value(RunnerMissions.SAVE_KEY_STARS, 0)))}
	for key: String in values:
		var cell := _premium_overlay.find_child("AccountMetric" + key, true, false)
		if cell != null:
			var value := cell.get_node("Value") as Label
			value.text = values[key]
			value.tooltip_text = value.text


func _show_name_prompt() -> void:
	if is_instance_valid(_name_prompt):
		return
	_name_prompt = preload("res://scripts/ui/account_name_prompt.gd").new()
	_name_prompt.dismissed.connect(_dismiss_name_prompt)
	_name_prompt.name_saved.connect(func() -> void:
		_dismiss_name_prompt()
		_refresh_account_copy())
	add_child(_name_prompt)


func _dismiss_name_prompt() -> void:
	if is_instance_valid(_name_prompt):
		_name_prompt.queue_free()
	_name_prompt = null
	if is_instance_valid(_premium_overlay):
		var action := _premium_overlay.find_child("AccountChangeName", true, false) as Button
		if action != null and not UITheme.is_touch():
			action.grab_focus()
