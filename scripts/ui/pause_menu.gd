class_name PauseMenu
extends CanvasLayer
## In-race pause overlay with resume / restart / quick settings / a control
## reference (shared with RaceHUD's onboarding strip) / quit.

var _panel: Control = null
var _settings_panel: Control = null
var _paused: bool = false
var _buttons: Array[Button] = []
var _quit_button: Button = null
var _quit_armed: bool = false
var _mute_button_ref: Button = null
var _profile: LayoutProfile = null
var _panel_scroll: ScrollContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_profile = UtilityScreenLayout.bind_view_class(self, _on_view_class_changed)


func _on_view_class_changed(next: LayoutProfile) -> void:
	_profile = next
	if _paused and _settings_panel == null:
		_rebuild_panel(next, UtilityScreenLayout.scroll_fraction(_panel_scroll))


func _exit_tree() -> void:
	# Never leave the tree paused if the menu is torn down mid-pause (e.g. the
	# race scene is freed by a scene swap).
	if _paused:
		get_tree().paused = false
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if not connected and not _paused and not GameConfig.is_headless() \
			and bool(SettingsManager.get_setting("accessibility", "pause_on_disconnect")):
		_open()


func _unhandled_input(event: InputEvent) -> void:
	# While settings is up it owns the back/cancel gesture, and pause must not
	# also fire -- Escape would otherwise close settings and unpause the race in
	# the same press.
	if _settings_panel != null:
		return
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _settings_panel != null:
		return
	if _paused:
		_close()
	else:
		_open()


func _open(profile_override: LayoutProfile = null, scroll_fraction: float = 0.0,
		preserve_quit: bool = false, quiet: bool = false) -> void:
	# Refuse to open during a scene transition: SceneRouter unpauses only at
	# transition start, so pausing mid-fade would soft-lock the next scene.
	if _paused or SceneRouter.is_busy():
		return
	_paused = true
	get_tree().paused = true
	if not quiet:
		AudioManager.ui_click()
	_profile = profile_override if profile_override != null \
		else LayoutProfile.for_viewport(get_viewport())
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.012, 0.028, 0.060, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)

	_panel_scroll = ScrollContainer.new()
	_panel_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	UtilityScreenLayout.bind_safe_rect(_panel, _panel_scroll)
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_panel_scroll.follow_focus = true
	TouchScroll.attach(_panel_scroll)
	_panel.add_child(_panel_scroll)
	UtilityScreenLayout.style_scrollbar(_panel_scroll, 9.0)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_scroll.add_child(center)
	var page_pad := MarginContainer.new()
	page_pad.add_theme_constant_override("margin_left", _metric(18.0))
	page_pad.add_theme_constant_override("margin_right", _metric(18.0))
	page_pad.add_theme_constant_override("margin_top", _metric(18.0))
	page_pad.add_theme_constant_override("margin_bottom", _metric(18.0))
	center.add_child(page_pad)

	var box := PanelContainer.new()
	box.name = &"PauseExpeditionCard"
	box.custom_minimum_size.x = _pause_width()
	var style := UITheme.make_panel_style(
		Color(0.035, 0.075, 0.142, 0.975), Color(UITheme.COLOR_ACCENT, 0.62))
	style.set_corner_radius_all(UITheme.RADIUS_CARD)
	style.content_margin_left = _metric(28.0 if not _profile.is_portrait() else 20.0)
	style.content_margin_right = _metric(28.0 if not _profile.is_portrait() else 20.0)
	style.content_margin_top = _metric(24.0)
	style.content_margin_bottom = _metric(24.0)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0.0, 8.0)
	box.add_theme_stylebox_override("panel", style)
	page_pad.add_child(box)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.spacing(12))
	box.add_child(vbox)

	_build_pause_header(vbox)

	_buttons.clear()
	var body: BoxContainer = VBoxContainer.new() if _profile.is_portrait() \
		else HBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.spacing(16))
	vbox.add_child(body)

	var actions := _pause_section(body, "Race Control", UITheme.COLOR_GOLD)
	var resume := _add_button(actions, "Resume Expedition", _close, UITheme.ICON_PLAY)
	UITheme.style_primary(resume)
	_add_button(actions, "Restart Race", func() -> void:
		get_tree().paused = false
		SceneRouter.go_to(Game.SCENE_RACE))
	_add_button(actions, "Settings", _open_settings, UITheme.ICON_GEAR)
	if Game.mode == Game.Mode.QUICK_RACE or Game.mode == Game.Mode.TIME_TRIAL:
		_add_button(actions, "Change Course", func() -> void:
			get_tree().paused = false
			Game.setup_entry_step = "course"
			Game.quit_race_to_setup())
	if not preserve_quit:
		_quit_armed = false
	_quit_button = _add_button(
		actions, "Quit to Menu", _on_quit_pressed, UITheme.ICON_DOOR)
	if preserve_quit and _quit_armed:
		_quit_button.text = "Really Quit? GP is lost"
	_quit_button.add_theme_color_override("font_color", Color(0.98, 0.70, 0.64))

	var field_guide := _pause_section(body, "Field Guide", UITheme.COLOR_ACCENT)
	_build_quick_audio(field_guide)
	field_guide.add_child(_section_rule())
	var controls_label := UITheme.sub_label("LIVE CONTROLS", 16)
	controls_label.add_theme_font_override("font", UITheme.caption_font())
	controls_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	field_guide.add_child(controls_label)
	var hud_scale := float(SettingsManager.get_setting("accessibility", "hud_scale"))
	var hints_per_row := 3 if _profile.view_class \
		== LayoutProfile.ViewClass.LANDSCAPE_WIDE else 2
	var strip := RaceHUD.build_controls_strip(hud_scale, hints_per_row)
	strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	field_guide.add_child(strip)
	# Edge swipe resumes, mirroring the Resume button for touch players.
	UITheme.attach_swipe_back(_panel, _close)
	# Unified fade+rise entrance; the PauseMenu layer processes while the
	# tree is paused, so the tween runs normally.
	var entrance_items: Array[Control] = [box]
	if not quiet:
		UITheme.play_entrance(_panel, entrance_items, 16.0)
	UtilityScreenLayout.restore_scroll_fraction(self, _panel_scroll, scroll_fraction)
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _metric(value: float) -> int:
	return maxi(1, roundi(UITheme.scaled(value)))


func _pause_width() -> float:
	if _profile == null:
		return 760.0
	var authored := 1040.0 if _profile.view_class \
		== LayoutProfile.ViewClass.LANDSCAPE_WIDE else 720.0
	return maxf(UtilityScreenLayout.page_width(
		_profile, authored, 300.0, 0.72) - 36.0, 280.0)


func _build_pause_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.spacing(14))
	parent.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var eyebrow := Label.new()
	eyebrow.text = "EXPEDITION PAUSED"
	eyebrow.add_theme_font_override("font", UITheme.caption_font())
	eyebrow.add_theme_font_size_override("font_size", UITheme.scaled_font(15))
	eyebrow.add_theme_color_override("font_color", Color(UITheme.COLOR_GOLD, 0.90))
	titles.add_child(eyebrow)
	var title := UITheme.heading("Take a Breather",
		UITheme.scaled_heading(34 if _profile.is_portrait() else 40))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(title)
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(UITheme.COLOR_ACCENT, 0.12)
	chip_style.border_color = Color(UITheme.COLOR_ACCENT, 0.40)
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(12)
	chip_style.content_margin_left = _metric(12.0)
	chip_style.content_margin_right = _metric(12.0)
	chip_style.content_margin_top = _metric(6.0)
	chip_style.content_margin_bottom = _metric(6.0)
	chip.add_theme_stylebox_override("panel", chip_style)
	header.add_child(chip)
	var chip_label := Label.new()
	chip_label.text = "SAFE" if UtilityScreenLayout.is_phone(_profile) else "RACE SAFE"
	chip_label.add_theme_font_override("font", UITheme.caption_font())
	chip_label.add_theme_font_size_override("font_size", UITheme.scaled_font(13))
	chip_label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	chip.add_child(chip_label)
	parent.add_child(UITheme.make_header_rule())


func _pause_section(parent: Control, title_text: String, accent: Color) -> VBoxContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UITheme.make_panel_style(
		Color(0.055, 0.104, 0.185, 0.84), Color(accent, 0.30))
	style.content_margin_left = _metric(16.0)
	style.content_margin_right = _metric(16.0)
	style.content_margin_top = _metric(14.0)
	style.content_margin_bottom = _metric(16.0)
	style.shadow_size = 7
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.spacing(9))
	card.add_child(body)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", UITheme.spacing(8))
	body.add_child(title_row)
	var tick := ColorRect.new()
	tick.color = accent
	tick.custom_minimum_size = Vector2(_metric(4.0), _metric(17.0))
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(tick)
	var label := Label.new()
	label.text = title_text.to_upper()
	label.add_theme_font_override("font", UITheme.caption_font())
	label.add_theme_font_size_override("font_size", UITheme.scaled_font(15))
	label.add_theme_color_override("font_color", Color(0.76, 0.86, 0.96))
	title_row.add_child(label)
	body.add_child(_section_rule())
	return body


func _section_rule() -> Control:
	var rule := ColorRect.new()
	rule.color = Color(UITheme.COLOR_ACCENT, 0.16)
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _build_quick_audio(parent: VBoxContainer) -> void:
	for bus_info: Array in [["Music", "music_volume"], ["Sound", "sfx_volume"]]:
		var row := HBoxContainer.new()
		# Compatibility renderer can let the HSlider's left/right style-box
		# borders escape a vertically stacked row on narrow touch canvases. Keep
		# every slider primitive inside its actual 44 px interaction row.
		row.clip_contents = true
		row.add_theme_constant_override("separation", UITheme.spacing(10))
		parent.add_child(row)
		var label := Label.new()
		label.text = String(bus_info[0])
		label.custom_minimum_size.x = UITheme.scaled(76.0)
		label.add_theme_font_override("font", UITheme.bold_font())
		label.add_theme_font_size_override("font_size", UITheme.scaled_font(18))
		label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(UITheme.scaled(150.0),
			UtilityScreenLayout.MIN_TOUCH_TARGET)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UITheme.style_slider(slider)
		# StyleBoxFlat side borders render as tall caps in the Compatibility
		# renderer's narrow HSlider path. Preserve the inset top edge, but let the
		# rounded track silhouette provide both ends.
		var pause_track := slider.get_theme_stylebox("slider") as StyleBoxFlat
		if pause_track != null:
			pause_track.border_width_left = 0
			pause_track.border_width_right = 0
			pause_track.border_width_bottom = 0
		slider.value = float(SettingsManager.get_setting("audio", String(bus_info[1])))
		var key := String(bus_info[1])
		slider.value_changed.connect(func(value: float) -> void:
			SettingsManager.set_setting("audio", key, value))
		row.add_child(slider)
	var mute_button := _add_button(parent, _mute_label(), func() -> void:
		var now_muted := not bool(SettingsManager.get_setting("audio", "muted"))
		SettingsManager.set_setting("audio", "muted", now_muted)
		if is_instance_valid(_mute_button_ref):
			_mute_button_ref.text = _mute_label())
	_mute_button_ref = mute_button


func _add_button(parent: Control, text: String, action: Callable,
		icon_svg: String = "") -> Button:
	var button := UITheme.make_button(text,
		UITheme.scaled_size(Vector2(0.0, 52.0)), UITheme.scaled_font(22))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UtilityScreenLayout.enforce_target(button)
	if not icon_svg.is_empty():
		var icon := UITheme.make_icon(icon_svg, 1.0)
		if icon != null:
			button.icon = icon
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", _metric(22.0))
			button.add_theme_constant_override("h_separation", _metric(10.0))
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)
	return button


func _on_quit_pressed() -> void:
	# Quitting mid-Grand-Prix abandons all standings; require a second press.
	if Game.mode == Game.Mode.GRAND_PRIX and not _quit_armed:
		_quit_armed = true
		if _quit_button != null:
			_quit_button.text = "Really Quit? GP is lost"
		return
	get_tree().paused = false
	Game.quit_race_to_menu()


## The full settings screen, mounted over the paused race instead of routed to.
##
## Routing would unload the race, which is the one thing a player adjusting
## their controls mid-race cannot afford. The settings scene is otherwise
## self-contained -- its only tie to being the current scene was where Back
## went, and that is now an injectable callback.
##
## The pause panel is hidden rather than freed, so returning restores it with
## its quit-confirm state and focus intact.
func _open_settings() -> void:
	if _settings_panel != null:
		return
	var packed: PackedScene = load(Game.SCENE_SETTINGS) as PackedScene
	if packed == null:
		return
	var screen := packed.instantiate() as Control
	if screen == null:
		return
	if _panel != null:
		_panel.visible = false
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Instanced under this CanvasLayer, which is PROCESS_MODE_ALWAYS, so the
	# inherited mode keeps the screen live while the tree is paused.
	screen.set("on_back", Callable(self, "_close_settings"))
	_settings_panel = screen
	add_child(screen)


func _close_settings() -> void:
	if _settings_panel != null:
		_settings_panel.queue_free()
		_settings_panel = null
	if _panel != null:
		_panel.visible = true
	# Settings can change hud_scale, ui_scale or the control scheme, and the
	# pause panel was built against the old values. Rebuilding it is cheaper
	# than teaching every widget to refresh, and it is the only screen the
	# player is looking at when they come back.
	if _paused:
		_rebuild_panel()
	elif not _buttons.is_empty():
		_buttons[0].grab_focus()


## Tears the pause panel down and builds it again at current settings, without
## touching the paused state around it.
func _rebuild_panel(profile_override: LayoutProfile = null,
		scroll_fraction: float = -1.0) -> void:
	var fraction := UtilityScreenLayout.scroll_fraction(_panel_scroll) \
		if scroll_fraction < 0.0 else scroll_fraction
	var keep_quit := _quit_armed
	if _panel != null:
		_panel.free()
		_panel = null
	_panel_scroll = null
	_paused = false
	_open(profile_override, fraction, keep_quit, true)


func _close() -> void:
	_paused = false
	get_tree().paused = false
	if _settings_panel != null:
		_settings_panel.queue_free()
		_settings_panel = null
	if _panel != null:
		_panel.queue_free()
		_panel = null
	_panel_scroll = null
	_quit_button = null
	_quit_armed = false


func _notification(what: int) -> void:
	# Auto-pause when focus is lost or a controller disconnects mid-race.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _paused and is_inside_tree():
		if not GameConfig.is_headless():
			_open()


## Mute button caption, with the M hotkey advertised on keyboard devices.
func _mute_label() -> String:
	var muted := bool(SettingsManager.get_setting("audio", "muted"))
	var base := "Unmute" if muted else "Mute All"
	if UITheme.is_touch():
		return base
	return "%s  (M)" % base
