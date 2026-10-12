extends Control

const DetailStyle := preload("res://scripts/ui/menu_detail_style.gd")
const UtilityArt := preload("res://scripts/ui/utility_reference_art.gd")
## Five clear settings destinations. Reads/writes the existing save schema.

const CATEGORIES := [
	["gameplay", "CONTROLS"], ["accessibility", "COMFORT"],
	["audio", "SOUND"], ["online", "ACCOUNT"], ["display", "GRAPHICS"],
]

# Atlas symbols are individually spaced, not five equal-width cells. Tight
# regions exclude the neighbouring controller edge beside the Comfort heart.
const CATEGORY_ICON_REGIONS := [
	Rect2(24, 205, 450, 370), Rect2(493, 205, 384, 350),
	Rect2(908, 207, 376, 364), Rect2(1355, 195, 337, 373),
	Rect2(1762, 211, 380, 358),
]

const OPTIONS := {
	"camera_shake": [["full", "Full"], ["reduced", "Low"], ["off", "Off"]],
	"quality_preset": [["low", "Low"], ["medium", "Medium"], ["high", "High"]],
	"shadow_quality": [["off", "Off"], ["low", "Low"], ["medium", "Medium"], ["high", "High"]],
	"particle_quality": [["low", "Low"], ["medium", "Medium"], ["high", "High"]],
	"msaa": [["off", "Off"], ["2x", "2x"], ["4x", "4x"]],
	"fps_limit": [[0, "Uncapped"], [30, "30"], [60, "60"], [120, "120"]],
	"touch_controls": [["auto", "Auto"], ["on", "On"], ["off", "Off"]],
	"window_mode": [["windowed", "Windowed"], ["fullscreen", "Fullscreen"], ["borderless", "Borderless"]],
	"resolution": [["1280x720", "1280 × 720"], ["1600x900", "1600 × 900"],
		["1920x1080", "1920 × 1080"], ["2560x1440", "2560 × 1440"]],
}

var _page: Control = null
var _active := "accessibility"
var _reset_armed := false
var _advanced := false
var _scale := 1.0
var _portrait := true
var _deletion: AccountDeletionPanel = null
var on_back: Callable = Callable()
var _bindings_panel: Control = null
var _name_prompt: Control = null


func _ready() -> void:
	UITheme.apply_ui_scale(self)
	var art := TextureRect.new()
	art.name = "SettingsCabin"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = ExpeditionMenuStyle._material_texture(
		"res://assets/art/ui/menu/settings_cabin_blank_v2.webp")
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	var sync_background := func() -> void:
		art.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/settings_cabin_blank_v2.webp" if get_viewport_rect().size.y >= get_viewport_rect().size.x else "res://assets/art/ui/menu/settings_wide_v4.webp")
	get_viewport().size_changed.connect(sync_background)
	sync_background.call()
	_build()
	get_viewport().size_changed.connect(_rebuild)
	UITheme.attach_swipe_back(self, _back)
	LeaderboardClient.auth_changed.connect(_refresh_account_auth)


func _rebuild() -> void:
	# Keep any open confirmation and its original account identity on rotation.
	if is_instance_valid(_deletion) and _deletion.get_parent() != self:
		_deletion.reparent(self, false)
		_deletion.hide()
	if is_instance_valid(_page):
		# Button signals may be on the stack. Retire the old tree after dispatch,
		# while removing it now keeps lookups/focus on the new live controls.
		remove_child(_page)
		_page.queue_free()
	_build()


func _build() -> void:
	var profile := LayoutProfile.for_viewport(get_viewport())
	_portrait = profile.is_portrait()
	var safe := Rect2(Vector2.ZERO, profile.viewport_size)
	# Authored composition is viewport based in both orientations. Physical
	# insets constrain hit targets once; rotating touch never shrinks the art.
	var width := safe.size.x * (0.96 if _portrait else 0.64)
	_scale = width / 900.0 if _portrait else safe.size.x / 1672.0
	_page = Control.new()
	_page.name = "SettingsReferenceLayout"
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_page)
	if not _portrait:
		var hero := TextureRect.new()
		hero.name = "SettingsFullBodyHero"
		hero.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/wardrobe_outfits_v1/body_classic__hat_earwarmers__none__scarf_red.webp")
		hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero.size = safe.size * Vector2(0.15, 0.39)
		hero.position = safe.position + safe.size * Vector2(-0.015, 0.59)
		_page.add_child(hero)
	var back_size := _s(108) if _portrait else safe.size.y * 0.115
	var back := ExpeditionMenuStyle.back_button(back_size)
	back.position = safe.position + Vector2(_s(20), _s(22))
	back.position.x = maxf(back.position.x, profile.safe_insets.x)
	back.position.y = maxf(back.position.y, profile.safe_insets.y)
	back.size = Vector2.ONE * back_size
	back.pressed.connect(_back)
	_page.add_child(back)
	var title := TextureRect.new()
	title.name = "SettingsTitleArtwork"
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.texture = ExpeditionMenuStyle.title_texture("settings")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_width := safe.size.x * (0.60 if _portrait else 0.30)
	title.position = safe.position + Vector2(safe.size.x * (0.51 if _portrait else 0.158) - title_width * 0.5, safe.size.y * (0.035 if _portrait else 0.15))
	if _portrait: title.position.y = maxf(title.position.y, profile.safe_insets.y)
	title.size = Vector2(title_width, title_width * 0.28)
	_page.add_child(title)
	UtilityScreenLayout.defer_header_alignment(self, title, back)
	var tabs := VBoxContainer.new()
	tabs.name = "SettingsCategoryTabs"
	tabs.position = safe.position + Vector2(safe.size.x * (0.035 if _portrait else 0.090), safe.size.y * (0.153 if _portrait else 0.32))
	tabs.size = Vector2(safe.size.x * (0.93 if _portrait else 0.195), safe.size.y * (0.13 if _portrait else 0.58))
	if _portrait:
		tabs.position.x = maxf(tabs.position.x, profile.safe_insets.x)
		tabs.size.x = minf(tabs.size.x, safe.size.x - profile.safe_insets.z - tabs.position.x)
	tabs.add_theme_constant_override("separation", roundi(_s(10)))
	_page.add_child(tabs)
	_build_tabs(tabs)
	var panel := PanelContainer.new()
	panel.name = "SettingsReferenceCard"
	panel.position = safe.position + Vector2((safe.size.x - width) * 0.5 if _portrait else safe.size.x * 0.30, safe.size.y * (0.285 if _portrait else 0.070))
	panel.size = Vector2(width, safe.size.y * (0.696 if _portrait else 0.88))
	var panel_surface := ExpeditionMenuStyle.material_card(_s(22), _s(20))
	if not _portrait:
		panel_surface.paint_expand_y = _s(10)
	panel_surface.content_margin_left = maxf(_s(22), profile.safe_insets.x - panel.position.x)
	panel_surface.content_margin_right = maxf(_s(22), profile.safe_insets.z - (safe.size.x - panel.get_rect().end.x))
	panel_surface.content_margin_bottom = maxf(_s(20), profile.safe_insets.w - (safe.size.y - panel.get_rect().end.y))
	panel.add_theme_stylebox_override("panel", panel_surface)
	_page.add_child(panel)
	var section := VBoxContainer.new()
	section.name = "SettingsSection_%s" % _active
	section.add_theme_constant_override("separation", roundi(_s(7)))
	panel.add_child(section)
	_build_section_header(section)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsContentScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	TouchScroll.attach(scroll)
	section.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 1 if _compact_touch_rows() else roundi(_s(6)))
	scroll.add_child(rows)
	match _active:
		"gameplay": _controls(rows)
		"accessibility": _comfort(rows)
		"audio": _sound(rows)
		"online": _account(rows)
		"display": _graphics(rows)
	var rule := HSeparator.new()
	rule.custom_minimum_size.y = _s(6)
	section.add_child(rule)
	var footer: BoxContainer = VBoxContainer.new() if _portrait else HBoxContainer.new()
	footer.name = "SettingsFixedFooter"
	footer.add_theme_constant_override("separation", roundi(_s(6)))
	if _active == "online" and not _portrait:
		footer.custom_minimum_size.y = _s(70)
	section.add_child(footer)
	var note := _label("Settings save automatically.", 23, DetailStyle.MUTED)
	note.add_theme_font_override("font", UITheme.ui_font())
	note.name = "SettingsSaveNote"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)
	if not _portrait:
		note.add_theme_color_override("font_color", DetailStyle.INK)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var note_row := HBoxContainer.new()
		note_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		note_row.add_theme_constant_override("separation", roundi(_s(20)))
		footer.add_child(note_row)
		footer.move_child(note_row, 0)
		var info := TextureRect.new()
		info.texture = _setting_icon("info")
		info.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		info.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		info.custom_minimum_size = Vector2.ONE * _s(48)
		note_row.add_child(info)
		note.reparent(note_row)
	if _active == "online":
		var support := _label("Support: support@waddlewars.io", 23)
		support.add_theme_font_override("font", UITheme.ui_font())
		support.name = "SettingsSupportAddress"
		support.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		support.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		support.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		footer.add_child(support)
		if _portrait: footer.move_child(support, 0)
	if _active != "online":
		var reset := _button("TAP AGAIN TO RESET" if _reset_armed else "RESET %s" % _category_label(), false, 30, 110 if _portrait else 90)
		reset.name = "SettingsReset_%s" % _active
		reset.icon = UtilityArt.icon("reset")
		reset.expand_icon = true
		reset.add_theme_constant_override("icon_max_width", roundi(_s(56)))
		reset.custom_minimum_size.x = _s(390 if _portrait else 350)
		reset.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		reset.add_theme_stylebox_override("normal", ExpeditionMenuStyle.material_box(false, _s(24), _s(10), Color("d5e8ff")))
		reset.pressed.connect(func() -> void:
			if not _reset_armed:
				_reset_armed = true
				reset.text = "TAP AGAIN TO RESET"
				return
			for key: String in (SettingsManager.default_settings()[_active] as Dictionary).keys():
				SettingsManager.set_setting(_active, key, SettingsManager.default_settings()[_active][key])
			_reset_armed = false
			_rebuild())
		footer.add_child(reset)


func _build_tabs(parent: VBoxContainer) -> void:
	var groups: Array = [[0, 1, 2], [3, 4]] if _portrait else [[0], [1], [2], [3], [4]]
	for indexes: Array in groups:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", roundi(_s(12)))
		parent.add_child(row)
		for index: int in indexes:
			var pair: Array = CATEGORIES[index]
			var id := String(pair[0])
			var tab := _button(String(pair[1]), id == _active, 29, 104 if _portrait else 88)
			tab.custom_minimum_size.x = _s((255 if indexes.size() == 3 else 270) if _portrait else 310)
			if _portrait:
				tab.custom_minimum_size.x = minf(tab.custom_minimum_size.x, (parent.size.x - _s(12) * (indexes.size() - 1)) / indexes.size())
			tab.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			var atlas := AtlasTexture.new()
			atlas.atlas = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/settings_category_icons_v1.webp")
			atlas.region = CATEGORY_ICON_REGIONS[index]
			atlas.filter_clip = true
			tab.icon = atlas
			if id == _active:
				var symbol: String = {"gameplay": "controller", "audio": "sound", "display": "hud"}.get(id, "")
				var body := String(UtilityArt.SYMBOLS[symbol]) if not String(symbol).is_empty() else ('<path d="M32 57 8 34C-11 13 17-4 32 14 47-4 75 13 56 34Z"/>' if id == "accessibility" else '<circle cx="32" cy="17" r="13"/><path d="M8 58v-9c0-25 48-25 48 0v9z"/>')
				tab.icon = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><g fill="#fff9ed">'+body.replace("#173c60", "#fff9ed")+'</g></svg>')
				if id == "gameplay":
					tab.icon = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><path d="M14 14C7 14 2 39 3 49c1 13 12 8 20-5h18c8 13 20 18 20 5-1-18-5-35-13-35Z" fill="#fff9ed"/><path d="M19 22v17m-8-8h17" stroke="#f35243" stroke-width="5"/><g fill="#f35243"><circle cx="46" cy="25" r="3"/><circle cx="53" cy="32" r="3"/><circle cx="39" cy="32" r="3"/><circle cx="46" cy="39" r="3"/></g></svg>')
			tab.expand_icon = true
			tab.add_theme_constant_override("icon_max_width", roundi(_s(55)))
			tab.add_theme_constant_override("h_separation", roundi(_s(10)))
			tab.name = "SettingsCategory_%s" % id
			tab.pressed.connect(func() -> void:
				_active = id
				_reset_armed = false
				_rebuild())
			row.add_child(tab)


func _build_section_header(parent: VBoxContainer) -> void:
	var header := Control.new()
	header.custom_minimum_size.y = _s((171 if _active == "online" else (210 if _active == "audio" else 189)) if _portrait else (168 if _active == "online" else (178 if _active == "display" else 206)))
	if _compact_touch_rows():
		header.custom_minimum_size.y = _s(132)
	parent.add_child(header)
	var title := _label(_category_label(), (96 if _active != "online" else 92) if _portrait else 105)
	title.position = Vector2(_s(36 if _portrait else 18), _s(55 if _portrait else 49))
	title.size = Vector2(_s(530), _s(110))
	if _compact_touch_rows():
		title.position.y = _s(12)
		title.add_theme_font_size_override("font_size", _font(76))
	header.add_child(title)
	if _active in ["accessibility", "audio", "display", "gameplay"]:
		var hero := SettingsAccountArt.picture("comfort", Vector2.ZERO)
		if _active == "gameplay":
			hero.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/settings_controls_header_v6.webp")
		hero.name = "ComfortHeroArtwork" if _active == "accessibility" else "SettingsCategoryHeroArtwork"
		hero.position = Vector2(_s(465 if _portrait else 540), -_s(15))
		hero.size = Vector2(_s(385 if _portrait else 420), _s(240))
		if _compact_touch_rows():
			hero.size = Vector2(_s(270), _s(150))
		header.add_child(hero)


func _category_label() -> String:
	for pair: Array in CATEGORIES:
		if pair[0] == _active:
			return String(pair[1])
	return "SETTINGS"


func _controls(parent: VBoxContainer) -> void:
	var first := parent
	var second := parent
	if not _portrait:
		var columns := HBoxContainer.new()
		columns.name = "ControlsTwoColumns"
		columns.add_theme_constant_override("separation", roundi(_s(10)))
		parent.add_child(columns)
		first = VBoxContainer.new()
		second = VBoxContainer.new()
		for column: VBoxContainer in [first, second]:
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.add_theme_constant_override("separation", roundi(_s(8)))
			columns.add_child(column)
	_slider(first, "gameplay", "steer_sensitivity", "Steer sensitivity", 0.5, 1.5, 0.05)
	_toggle(first, "gameplay", "slide_toggle_mode", "SLIDE: TOGGLE MODE", "slide")
	_toggle(first, "gameplay", "tutorial_prompts", "TUTORIAL HINTS", "hint")
	_toggle(first, "gameplay", "vibration", "VIBRATION", "vibration")
	if TiltSteering.supported():
		_toggle(first, "gameplay", "tilt_steering", "TILT STEERING", "tilt")
		_slider(first, "gameplay", "tilt_sensitivity", "Tilt sensitivity", 0.4, 2.0, 0.05)
		_toggle(first, "gameplay", "tilt_invert", "INVERT TILT", "reset")
	_choice(second, "gameplay", "touch_controls", "TOUCH CONTROLS", "touch")
	_slider(second, "gameplay", "touch_scale", "Touch button size", 0.7, 1.4, 0.05)
	_slider(second, "gameplay", "touch_opacity", "Touch button opacity", 0.2, 1.0, 0.05)
	_slider(second, "gameplay", "gamepad_deadzone", "Gamepad deadzone", 0.05, 0.6, 0.05)
	var remap := _button("KEY & GAMEPAD BINDINGS", false, 28, 76)
	remap.name = "SettingsBindingsAction"
	remap.icon = UtilityArt.icon("controller")
	remap.expand_icon = true
	remap.add_theme_constant_override("icon_max_width", roundi(_s(46)))
	remap.custom_minimum_size.x = _s(530)
	remap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	remap.pressed.connect(_open_bindings)
	parent.add_child(remap)


func _comfort(parent: VBoxContainer) -> void:
	var first := parent
	var second := parent
	if not _portrait:
		var columns := HBoxContainer.new()
		columns.name = "ComfortTwoColumns"
		columns.add_theme_constant_override("separation", roundi(_s(8)))
		parent.add_child(columns)
		first = VBoxContainer.new()
		second = VBoxContainer.new()
		for column: VBoxContainer in [first, second]:
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.add_theme_constant_override("separation", roundi(_s(8)))
			columns.add_child(column)
	_choice(first, "accessibility", "camera_shake", "CAMERA SHAKE", "camera")
	_toggle(first, "accessibility", "reduced_flashing", "REDUCE FLASHING", "flash")
	_toggle(first, "accessibility", "high_contrast_pickups", "HIGH CONTRAST PICKUPS", "eye")
	_toggle(first, "accessibility", "colorblind_cues", "COLORBLIND CUES", "colorblind")
	_toggle(second, "accessibility", "audio_visual_cues", "AUDIO VISUAL CUES", "sound")
	_toggle(second, "accessibility", "pause_on_disconnect", "PAUSE ON DISCONNECT", "pause")
	_comfort_slider(second, "hud_scale", "HUD SCALE")
	_comfort_slider(second, "ui_scale", "UI SCALE")


func _comfort_slider(parent: VBoxContainer, key: String, title: String) -> void:
	var row := _setting_row(parent, title, "hud" if key == "hud_scale" else "corners")
	var slider := HSlider.new()
	slider.name = "Settings_accessibility_" + key
	slider.min_value = 0.8
	slider.max_value = 1.4
	slider.step = 0.05
	slider.value = float(SettingsManager.get_setting("accessibility", key))
	slider.custom_minimum_size = Vector2(_s(270 if _portrait else 135), _s(50))
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var thumb := UtilityArt.slider_thumb(roundi(_s(62 if _portrait else 46)))
	slider.add_theme_icon_override("grabber", thumb)
	slider.add_theme_icon_override("grabber_highlight", thumb)
	slider.add_theme_icon_override("grabber_disabled", thumb)
	row.add_child(slider)
	var readout := _label("%d%%" % roundi(slider.value * 100), 27 if _portrait else 20)
	readout.custom_minimum_size.x = _s(76 if _portrait else 55)
	readout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(readout)
	var rail := ExpeditionMenuStyle.surface(Color("d2cbc0"), _font(8), false)
	rail.content_margin_top = _s(7)
	rail.content_margin_bottom = _s(7)
	slider.add_theme_stylebox_override("slider", rail)
	var fill := rail.duplicate() as StyleBoxFlat
	fill.bg_color = ExpeditionMenuStyle.CORAL
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.value_changed.connect(func(value: float) -> void:
		readout.text = "%d%%" % roundi(value * 100)
		SettingsManager.set_setting("accessibility", key, value))


func _sound(parent: VBoxContainer) -> void:
	_slider(parent, "audio", "master_volume", "Master volume", 0.0, 1.0, 0.05)
	_slider(parent, "audio", "music_volume", "Music volume", 0.0, 1.0, 0.05)
	_slider(parent, "audio", "sfx_volume", "Effects volume", 0.0, 1.0, 0.05)
	_toggle(parent, "audio", "muted", "MUTE ALL", "mute")
	_toggle(parent, "audio", "mute_unfocused", "MUTE WHEN UNFOCUSED", "unfocused" if _portrait else "hud")


func _graphics(parent: VBoxContainer) -> void:
	_choice(parent, "display", "quality_preset", "QUALITY PRESET", "hud")
	_choice(parent, "display", "shadow_quality", "SHADOWS", "sun")
	_choice(parent, "display", "particle_quality", "PARTICLES", "particles")
	_choice(parent, "display", "msaa", "ANTI-ALIASING", "aliasing")
	_choice(parent, "display", "fps_limit", "FRAME-RATE LIMIT", "gauge")
	_toggle(parent, "display", "vsync", "V-SYNC", "reset")
	if not GameConfig.is_mobile() and not OS.has_feature("web"):
		_choice(parent, "display", "window_mode", "Window mode")
		_choice(parent, "display", "resolution", "Resolution")


func _account_auth_copy() -> String:
	return AccountAuthPresentation.message("Signed in. Your progress can be backed up." if LeaderboardClient.signed_in else "Guest progress is saved on this device.")


func _refresh_account_auth() -> void:
	if not is_instance_valid(_page):
		return
	var status := _page.find_child("SettingsAccountAuthStatus", true, false) as Label
	if status != null:
		status.text = _account_auth_copy()
	var display_name := _page.find_child("SettingsAccountNameLabel", true, false) as Label
	if display_name != null:
		display_name.text = LeaderboardClient.player_display_name()
	AccountAuthPresentation.update_button(_page.find_child("SettingsAccountAuth", true, false) as Button)


func _account(parent: VBoxContainer) -> void:
	if not AccountAuthPresentation.account_surface_enabled():
		_note(parent, "Progress saves on this device. No account or purchase is required.")
	else:
		var profile := _account_card(parent, "SettingsAccountIdentity")
		profile.custom_minimum_size.y = _s(290 if _portrait else 138)
		profile.custom_minimum_size.y = _s(290 if _portrait else 138)
		var identity := HBoxContainer.new()
		identity.add_theme_constant_override("separation", roundi(_s(20)))
		profile.add_child(identity)
		var identity_style := DetailStyle.inset(_s(28), 0, _s(30))
		profile.add_theme_stylebox_override("panel", identity_style)
		var avatar := SettingsAccountArt.picture("avatar", Vector2.ONE * _s(240 if _portrait else 138))
		identity.add_child(avatar)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		identity.add_child(details)
		var display_name := _label(LeaderboardClient.player_display_name(), 44 if _portrait else 31)
		display_name.name = "SettingsAccountNameLabel"
		details.add_child(display_name)
		var description := _label(_account_auth_copy(), 32 if _portrait else 23, DetailStyle.MUTED)
		description.name = "SettingsAccountAuthStatus"
		description.add_theme_font_override("font", UITheme.ui_font())
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(description)
		if LeaderboardClient.can_sign_in():
			var auth := _button("SIGN OUT" if LeaderboardClient.signed_in else "SIGN IN TO BACK UP", true, 40 if _portrait else 30, 98 if _portrait else 76)
			auth.name = "SettingsAccountAuth"
			auth.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			auth.custom_minimum_size.x = _s(340 if not _portrait else 0)
			auth.pressed.connect(AccountAuthPresentation.activate)
			(details if _portrait else identity).add_child(auth)
			AccountAuthPresentation.update_button(auth)
		var name_panel := _account_card(parent, "SettingsAccountName")
		var name_row: BoxContainer = VBoxContainer.new() if _portrait else HBoxContainer.new()
		name_row.add_theme_constant_override("separation", roundi(_s(8)))
		name_panel.add_child(name_row)
		var caption := _label("LEADERBOARD NAME", 29)
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		caption.custom_minimum_size.x = _s(330 if not _portrait else 0)
		name_row.add_child(caption)
		var name_action := _button("CHANGE NAME", false, 30, 78)
		name_action.name = "SettingsAccountDisplayName"
		name_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_action.pressed.connect(func() -> void:
			if is_instance_valid(_name_prompt): return
			_name_prompt = preload("res://scripts/ui/account_name_prompt.gd").new()
			_name_prompt.dismissed.connect(func() -> void:
				_name_prompt.queue_free()
				_name_prompt = null)
			_name_prompt.name_saved.connect(func() -> void:
				_name_prompt.queue_free()
				_name_prompt = null
				_rebuild())
			add_child(_name_prompt))
		name_row.add_child(name_action)
		parent.add_child(_label("PRIVACY & DATA", 35 if _portrait else 29))
		var privacy := _account_card(parent, "SettingsAccountPrivacy")
		if not is_instance_valid(_deletion):
			_deletion = AccountDeletionPanel.new()
			privacy.add_child(_deletion)
		else:
			_deletion.reparent(privacy, false)
		_deletion.show()
		_style_account_deletion()
	var links: BoxContainer = VBoxContainer.new() if _portrait else HBoxContainer.new()
	links.add_theme_constant_override("separation", roundi(_s(8)))
	parent.add_child(links)
	for link_info: Array in [["PRIVACY POLICY", GameConfig.NATIVE_PRIVACY_URL, "privacy"],
			["SUPPORT WEBSITE", GameConfig.NATIVE_SUPPORT_URL, "support"]]:
		var link := _button(String(link_info[0]), false, 31 if _portrait else 28, 88)
		for state: String in ["normal", "hover", "pressed"]:
			link.add_theme_stylebox_override(state, DetailStyle.inset(_s(36), _s(10), _s(30)))
		link.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		link.alignment = HORIZONTAL_ALIGNMENT_LEFT if _portrait else HORIZONTAL_ALIGNMENT_CENTER
		link.add_theme_constant_override("h_separation", roundi(_s(36)))
		link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		link.icon = _setting_icon(String(link_info[2]))
		link.expand_icon = true
		link.add_theme_constant_override("icon_max_width", roundi(_s(64)))
		var url := String(link_info[1])
		link.pressed.connect(func() -> void: OS.shell_open(url))
		links.add_child(link)
		if _portrait:
			var chevron := TextureRect.new()
			chevron.name = "AccountLinkChevron"
			chevron.texture = _setting_icon("chevron")
			chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
			link.add_child(chevron)
			chevron.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
			chevron.offset_left = -_s(64)
			chevron.offset_right = -_s(28)


func _account_card(parent: Control, node_name: String) -> PanelContainer:
	var panel := ExpeditionMenuStyle.panel(parent)
	panel.name = node_name
	panel.add_theme_stylebox_override("panel", DetailStyle.inset(_s(28), _s(14), _s(30)))
	return panel


func _style_account_deletion() -> void:
	var row := _deletion.get_node_or_null("DeletionReferenceRow") as HBoxContainer
	if row == null:
		var title := _deletion.get_child(0) as Label
		var status := _deletion.get_child(1) as Label
		var action := _deletion.find_child("OpenAccountDeletion", true, false) as Button
		row = HBoxContainer.new()
		row.name = "DeletionReferenceRow"
		row.add_theme_constant_override("separation", roundi(_s(12)))
		_deletion.add_child(row)
		var trash := TextureRect.new()
		trash.texture = _setting_icon("trash")
		trash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		trash.custom_minimum_size = Vector2.ONE * _s(72)
		row.add_child(trash)
		var copy := VBoxContainer.new()
		copy.name = "DeletionReferenceCopy"
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(copy)
		title.reparent(copy)
		status.reparent(copy)
		action.reparent(row)
	var copy := row.get_node("DeletionReferenceCopy") as VBoxContainer
	var title := copy.get_child(0) as Label
	title.text = "ACCOUNT DELETION"
	title.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	title.add_theme_color_override("font_color", ExpeditionMenuStyle.INK)
	title.add_theme_font_size_override("font_size", _font(27))
	var status := copy.get_child(1) as Label
	status.add_theme_font_override("font", UITheme.ui_font())
	status.add_theme_color_override("font_color", ExpeditionMenuStyle.INK_MUTED)
	status.add_theme_font_size_override("font_size", _font(22))
	var action := _deletion.find_child("OpenAccountDeletion", true, false) as Button
	ExpeditionMenuStyle.style_button(action, false, _font(26))
	action.text = "DELETE ACCOUNT"
	action.custom_minimum_size = Vector2(_s(275), _s(88))
	action.add_theme_stylebox_override("disabled", DetailStyle.inset(_s(16), _s(8), _s(36), Color("d6d3cd")))
	action.add_theme_color_override("font_disabled_color", Color("898b90"))
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _toggle(parent: VBoxContainer, section: String, key: String,
		label_text: String, icon: String = "") -> void:
	var row := _setting_row(parent, label_text, icon)
	var button := Button.new()
	button.name = "Settings_%s_%s" % [section, key]
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(_s(128 if _portrait else 106), maxf(44.0, _s(66 if _portrait else 62)))
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.button_pressed = bool(SettingsManager.get_setting(section, key))
	button.accessibility_name = label_text
	var knob := Panel.new()
	knob.name = "SwitchThumb"
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(knob)
	row.add_child(button)
	_style_switch(button, knob)
	button.resized.connect(func() -> void: _style_switch(button, knob))
	button.toggled.connect(func(next: bool) -> void:
		SettingsManager.set_setting(section, key, next)
		_style_switch(button, knob))
	UITheme.hook_sounds(button)


func _style_switch(button: Button, knob: Panel) -> void:
	var value := button.button_pressed
	var fill := Color("ff5142") if value else Color("b9bcc2")
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var box := ExpeditionMenuStyle.surface(fill, roundi(_s(44)), false)
		box.border_color = Color("fbe8d2") if value else Color("98a7b9")
		box.set_border_width_all(maxi(1, roundi(_s(3))))
		box.set_content_margin_all(0)
		button.add_theme_stylebox_override(state, box)
	var focus := ExpeditionMenuStyle.surface(Color.TRANSPARENT, roundi(_s(44)), false)
	focus.draw_center = false
	focus.border_color = ExpeditionMenuStyle.GOLD
	focus.set_border_width_all(3)
	button.add_theme_stylebox_override("focus", focus)
	var diameter := _s(54 if _portrait else 48)
	knob.size = Vector2.ONE * diameter
	knob.position = Vector2(button.size.x - diameter - _s(6) if value else _s(6), (button.size.y - diameter) * 0.5)
	var thumb := ExpeditionMenuStyle.surface(ExpeditionMenuStyle.IVORY, roundi(diameter * 0.5), true)
	thumb.shadow_size = _s(3)
	knob.add_theme_stylebox_override("panel", thumb)
	button.tooltip_text = "%s: %s" % [button.accessibility_name, "On" if value else "Off"]


func _choice(parent: VBoxContainer, section: String, key: String,
		label_text: String, icon: String = "") -> void:
	var row := _setting_row(parent, label_text, icon)
	var choices: Array = OPTIONS[key]
	var current: Variant = SettingsManager.get_setting(section, key)
	if key == "camera_shake" or key in ["quality_preset", "shadow_quality", "particle_quality", "msaa", "fps_limit"]:
		var backing := PanelContainer.new()
		backing.add_theme_stylebox_override("panel", DetailStyle.inset(_s(3), 0.0 if _compact_touch_rows() else _s(3), _s(22)))
		backing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if section == "display" and _portrait:
			# Portrait reference keeps every option visible below its label.
			var caption := row.get_node("SettingTitle") as Label
			var stack := VBoxContainer.new()
			stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			stack.add_theme_constant_override("separation", roundi(_s(3)))
			row.add_child(stack)
			caption.reparent(stack)
			stack.add_child(backing)
		else:
			row.add_child(backing)
		if section != "accessibility":
			backing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			backing.size_flags_stretch_ratio = 1.65
		var segments := HBoxContainer.new()
		segments.name = "Settings_%s_%s" % [section, key]
		segments.add_theme_constant_override("separation", 0)
		segments.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		backing.add_child(segments)
		var group := ButtonGroup.new()
		for item: Array in choices:
			var button := _button(String(item[1]) if key == "msaa" else String(item[1]).to_upper(), item[0] == current, 25 if _portrait else 20, (58 if section == "display" else 66) if _portrait else 58)
			button.name = "Choice_%s" % str(item[0])
			button.custom_minimum_size.x = _s((112 if _portrait else 68) if section == "accessibility" else 62)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.toggle_mode = true
			button.button_group = group
			button.button_pressed = item[0] == current
			button.set_meta("segment_first", item == choices.front())
			button.set_meta("segment_last", item == choices.back())
			_style_segment(button)
			button.pressed.connect(func() -> void:
				SettingsManager.set_setting(section, key, item[0])
				for child: Button in segments.get_children():
					_style_segment(child))
			segments.add_child(button)
		return
	var picker := OptionButton.new()
	picker.name = "Settings_%s_%s" % [section, key]
	picker.custom_minimum_size = Vector2(_s(330 if _portrait else 184), _s(76 if _portrait else 62))
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ExpeditionMenuStyle.style_button(picker, false, _font(28 if _portrait else 24))
	for state: String in ["normal", "hover", "pressed"]:
		picker.add_theme_stylebox_override(state, DetailStyle.inset(_s(20), _s(8), _s(20)))
	picker.add_theme_icon_override("arrow", UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><path d="m4 8 8 8 8-8" fill="none" stroke="#09213f" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/></svg>'))
	for index: int in choices.size():
		var item: Array = choices[index]
		picker.add_item(String(item[1]))
		picker.set_item_metadata(index, item[0])
		if item[0] == current:
			picker.select(index)
	picker.item_selected.connect(func(index: int) -> void:
		SettingsManager.set_setting(section, key, picker.get_item_metadata(index)))
	row.add_child(picker)


func _slider(parent: VBoxContainer, section: String, key: String,
		label_text: String, minimum: float, maximum: float, step: float) -> void:
	var icon := "steer"
	if section == "audio":
		icon = {"master_volume": "sound", "music_volume": "music", "sfx_volume": "flash"}[key]
	elif key == "gamepad_deadzone":
		icon = "deadzone"
	elif key == "tilt_sensitivity":
		icon = "gauge"
	elif key == "touch_scale":
		icon = "expand"
	elif key == "touch_opacity":
		icon = "opacity"
	var row := _setting_row(parent, label_text.to_upper(), icon)
	var caption := row.get_node("SettingTitle") as Label
	_fit_setting_caption(caption, 29 if _portrait else (28 if section == "audio" else 21), 24 if _portrait else 17)
	var slider := HSlider.new()
	slider.name = "Settings_%s_%s" % [section, key]
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(SettingsManager.get_setting(section, key))
	var compact_desktop := not _portrait and key in ["touch_scale", "touch_opacity", "gamepad_deadzone"]
	slider.custom_minimum_size = Vector2(_s((270 if _portrait else 390) if section == "audio" else (260 if _portrait else (115 if compact_desktop else 140))), _s(58))
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(slider)
	row.add_child(slider)
	var readout := _label("%d%%" % roundi(slider.value * 100.0), 29 if _portrait or section == "audio" else 22)
	readout.name = "SettingsValue_%s_%s" % [section, key]
	readout.custom_minimum_size.x = _s(84 if _portrait or section == "audio" else 54)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(readout)
	slider.value_changed.connect(func(next: float) -> void:
		readout.text = "%d%%" % roundi(next * 100.0)
		SettingsManager.set_setting(section, key, next))


func _style_slider(slider: HSlider) -> void:
	var thumb := UtilityArt.slider_thumb(roundi(_s(46 if _active == "gameplay" and not _portrait else 62)))
	for key: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(key, thumb)
	var rail := ExpeditionMenuStyle.surface(Color("e7e0d4"), _font(10), false)
	rail.content_margin_top = _s(8)
	rail.content_margin_bottom = _s(8)
	rail.border_color = Color("d9d2c5")
	rail.set_border_width_all(maxi(1, roundi(_s(2))))
	slider.add_theme_stylebox_override("slider", rail)
	var fill := rail.duplicate() as StyleBoxFlat
	fill.bg_color = ExpeditionMenuStyle.CORAL
	fill.border_color = Color("ff7768")
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)


func _setting_icon(key: String) -> Texture2D:
	if key == "steer" and not _portrait: key = "deadzone"
	if key == "aliasing" and not _portrait: key = "steps"
	if key == "privacy" and not _portrait: key = "privacy_shield"
	if key == "pause" and not _portrait: key = "disconnect"
	if key == "vibration" and not _portrait: key = "controller_vibration"
	var symbols := {
		"pencil": '<path d="m9 44 31-31 12 12-31 31-16 4zM44 9l5-5q3-3 6 0l5 5q3 3 0 6l-5 5z"/>',
		"info": '<circle cx="32" cy="32" r="28"/><circle cx="32" cy="17" r="4" fill="#faf7ef"/><path d="M28 27h8v25h-8z" fill="#faf7ef"/>',
		"privacy_shield": '<path d="M32 2 7 12v22c0 14 13 24 25 29 12-5 25-15 25-29V12Z"/><circle cx="32" cy="19" r="4" fill="#faf7ef"/><path d="M28 29h8v22h-8z" fill="#faf7ef"/>',
		"disconnect": '<path d="M5 20q27-25 54 0M14 30q18-17 36 0M23 41q9-9 18 0" stroke="#173c60" stroke-width="7" fill="none" stroke-linecap="round"/><path d="m43 44 15 15m0-15L43 59" stroke="#f55443" stroke-width="7" stroke-linecap="round"/>',
		"controller_vibration": '<path d="M18 17c-5 0-10 22-9 30 1 8 9 6 15-3h16c6 9 14 11 15 3 1-8-4-30-9-30Z"/><path d="M24 24v15m-7-8h14" stroke="#faf7ef" stroke-width="4"/><circle cx="43" cy="28" r="3" fill="#faf7ef"/><circle cx="48" cy="35" r="3" fill="#faf7ef"/><path d="m5 12-3 8 3 8-3 8 3 8m54-32 3 8-3 8 3 8-3 8" stroke="#173c60" stroke-width="3" fill="none"/>',
		"chevron": '<path d="m22 10 22 22-22 22" fill="none" stroke="#173c60" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>',
		"privacy": '<path d="M13 3h28l12 12v46H13Z"/><path d="M41 3v13h12M23 28h20M23 38h20M23 48h16" stroke="#faf7ef" stroke-width="4" fill="none"/>',
		"steps": '<path d="M5 56V42h14V29h14V16h14V3h14v25H47v13H33v15Z"/>',
		"colorblind": '<path d="M32 4C-5 4-7 60 29 60c12 0 9-9 6-15-3-7 4-10 12-9C65 36 66 4 32 4Z"/><g fill="#faf7ef"><circle cx="15" cy="29" r="5"/><circle cx="22" cy="15" r="5"/><circle cx="39" cy="14" r="5"/><circle cx="49" cy="26" r="5"/></g>',
		"trash": '<path d="M13 19h38l-3 41H16zM8 10h48v6H8zm16-8h16v8H24z"/><path d="M24 27v24m16-24v24" stroke="#faf7ef" stroke-width="4" stroke-linecap="round"/>',
		"pause": '<circle cx="32" cy="32" r="27"/><path d="M22 17h7v30h-7zm13 0h7v30h-7z" fill="#faf7ef"/>',
		"corners": '<path d="M7 23V7h16M41 7h16v16M57 41v16H41M23 57H7V41" fill="none" stroke="#173c60" stroke-width="6" stroke-linecap="round"/>',
		"vibration": '<rect x="22" y="9" width="22" height="46" rx="3" fill="none" stroke="#173c60" stroke-width="5"/><path d="m13 14-5 8 5 8-5 8 5 10m38-34 5 8-5 8 5 8-5 10" fill="none" stroke="#173c60" stroke-width="5" stroke-linejoin="round"/>',
		"tilt": '<rect x="22" y="9" width="22" height="46" rx="3" fill="none" stroke="#173c60" stroke-width="5"/><path d="M16 18Q2 31 16 46m33-28q14 13 0 28" fill="none" stroke="#173c60" stroke-width="5" stroke-linecap="round"/><path d="m7 18 11-3-1 11m40 20-11 3 1-11"/>',
		"expand": '<path d="M9 9h19v6H19l11 11-5 5-11-11v9H8V9m47 46H36v-6h9L34 38l5-5 11 11v-9h6v20"/>',
		"opacity": '<path d="M32 5C21 21 10 29 10 41a22 22 0 0 0 44 0C54 29 43 21 32 5Z" fill="none" stroke="#173c60" stroke-width="5"/><path d="M32 11v48a18 18 0 0 0 18-18C50 30 41 22 32 11Z"/>',
		"deadzone": '<circle cx="32" cy="32" r="24" fill="none" stroke="#173c60" stroke-width="5"/><circle cx="32" cy="32" r="10"/><path d="M32 4v11m0 34v11M4 32h11m34 0h11" stroke="#173c60" stroke-width="5"/>',
		"unfocused": '<path d="M4 32Q32 1 60 32 32 63 4 32Z" fill="none" stroke="#173c60" stroke-width="5"/><circle cx="32" cy="32" r="10"/><path d="m9 55 46-46" stroke="#fff9ed" stroke-width="11"/><path d="m9 55 46-46" stroke="#173c60" stroke-width="6" stroke-linecap="round"/>',
		"particles": '<path d="m25 10 8 16 15 8-15 8-8 16-8-16L2 34l15-8zM51 2l4 8 8 4-8 4-4 8-4-8-8-4 8-4z"/>',
		"aliasing": '<path d="m6 54 22-43 16 31" fill="none" stroke="#173c60" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/><path d="m43 25 18 31H26Z"/>',
		"steer": '<circle cx="32" cy="32" r="23" fill="none" stroke="#173c60" stroke-width="6"/><path d="M10 26h44M32 30v24" fill="none" stroke="#173c60" stroke-width="8"/><circle cx="32" cy="29" r="7"/>',
		"slide": '<path d="M11 40c0-12 19-13 26-29 6 6 13 11 17 17-5 4-10 6-11 13Z"/><path d="M10 48h42" stroke="#173c60" stroke-width="5" stroke-linecap="round"/><circle cx="19" cy="55" r="5"/><circle cx="43" cy="55" r="5"/>',
		"hint": '<path d="M20 44C-2 21 19 1 33 3s30 20 11 41l-3 10H24zM24 57h17v5H24z"/>',
		"touch": '<path d="M25 35V14a5 5 0 0 1 10 0v16l5-4 14 6v20l-8 9H27L11 43q-3-6 3-8l11 8z"/><path d="M15 23a18 18 0 1 1 36 0" fill="none" stroke="#173c60" stroke-width="5"/>',
		"support": '<circle cx="32" cy="32" r="25" fill="none" stroke="#173c60" stroke-width="6"/><circle cx="32" cy="32" r="11" fill="none" stroke="#173c60" stroke-width="5"/><path d="m15 15 10 10m14 14 10 10M15 49l10-10m14-14 10-10" stroke="#173c60" stroke-width="10"/>',
		"music": '<path d="M24 13 54 6v37c0 13-20 15-20 4 0-6 7-10 13-9V19l-16 4v26c0 13-21 15-21 4 0-6 7-10 14-9z"/>',
		"mute": '<path d="M7 23h11L32 10v44L18 41H7z"/><path d="m42 24 15 17m0-17L42 41" fill="none" stroke="#173c60" stroke-width="6" stroke-linecap="round"/>',
		"sun": '<circle cx="32" cy="32" r="13"/><path d="M32 2v8m0 44v8M2 32h8m44 0h8M11 11l6 6m30 30 6 6M11 53l6-6m30-30 6-6" fill="none" stroke="#173c60" stroke-width="5" stroke-linecap="round"/>',
		"gauge": '<path d="M8 49a27 27 0 1 1 48 0" fill="none" stroke="#173c60" stroke-width="7" stroke-linecap="round"/><path d="m32 38 15-20-8 25z"/><circle cx="32" cy="40" r="6"/>'
	}
	if symbols.has(key):
		return UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><g fill="#173c60">'+String(symbols[key])+'</g></svg>', 2.0)
	if UtilityArt.SYMBOLS.has(key):
		return UtilityArt.icon(key)
	return SettingsAccountArt.sprite(key)


func _setting_row(parent: VBoxContainer, label_text: String, icon: String = "") -> HBoxContainer:
	var panel := ExpeditionMenuStyle.panel(parent)
	panel.add_theme_stylebox_override("panel", DetailStyle.inset(_s(34 if _portrait else 22), _s(1 if _compact_touch_rows() else 6), _s(30)))
	panel.custom_minimum_size.y = _s(
		(130 if _portrait else 87) if _active == "audio" else
		((112 if _portrait else 75) if _active == "display" else
		(88 if _portrait else (89 if _active == "gameplay" else 105))))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_s(32 if _portrait else (20 if _active == "audio" else 12))))
	panel.add_child(row)
	if not icon.is_empty():
		var picture := TextureRect.new()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture = _setting_icon(icon)
		picture.custom_minimum_size = Vector2(_s(96 if _portrait else (96 if _active == "audio" else 58)), _s(72 if _portrait else 56))
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(picture)
	var title := _label(label_text, 32 if _portrait else (28 if _active in ["audio", "display"] else 23))
	title.name = "SettingTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	return row


func _fit_setting_caption(label: Label, preferred: int, minimum: int) -> void:
	var resize := func() -> void:
		var points := _font(preferred)
		var floor_size := _font(minimum)
		while points > floor_size and ExpeditionMenuStyle.display_font().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x > label.size.x:
			points -= 1
		label.add_theme_font_size_override("font_size", points)
	label.resized.connect(resize)
	resize.call()


func _style_segment(button: Button) -> void:
	var selected := button.button_pressed
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var box := DetailStyle.inset(_s(6), _s(6), _s(18), Color("ff5142") if selected else Color("faf7ef"))
		box.border_color = Color("ff9c8f") if selected else Color("ffffff")
		box.shadow_size = 1.0
		if not selected:
			if not button.get_meta("segment_first", false):
				box.corner_radius_top_left = 0
				box.corner_radius_bottom_left = 0
			if not button.get_meta("segment_last", false):
				box.corner_radius_top_right = 0
				box.corner_radius_bottom_right = 0
		box.set_content_margin_all(_s(6))
		button.add_theme_stylebox_override(state, box)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE if selected else ExpeditionMenuStyle.INK)


func _button(text: String, primary: bool, font_size: int, height: float) -> Button:
	var result := ExpeditionMenuStyle.button(text, primary, _font(font_size), _s(height))
	result.custom_minimum_size.y = maxf(44.0, _s(height))
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		result.add_theme_stylebox_override(state, ExpeditionMenuStyle.material_box(primary, _s(12), _s(8)))
	return result


func _label(text: String, font_size: int, color: Color = ExpeditionMenuStyle.INK) -> Label:
	var result := ExpeditionMenuStyle.label(text, _font(font_size), color)
	result.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	DetailStyle.clean_label(result, DetailStyle.INK if color == ExpeditionMenuStyle.INK else color)
	return result


func _note(parent: Control, text: String) -> void:
	var note := _label(text, 28, ExpeditionMenuStyle.INK_MUTED)
	note.add_theme_font_override("font", UITheme.ui_font())
	parent.add_child(note)


func _s(value: float) -> float:
	return value * _scale


func _compact_touch_rows() -> bool:
	# At small phone widths, fixed 44px targets consume proportionally more
	# space. Spend less on decoration/gutters, never shrink the touch targets.
	return _portrait and _scale < 0.65 and _active in ["accessibility", "display"]


func get_navigation_state() -> Dictionary:
	var scroll := find_child("SettingsContentScroll", true, false) as ScrollContainer
	return {"category": _active, "advanced": _advanced,
		"scroll": scroll.scroll_vertical if scroll != null else 0}


func restore_navigation_state(state: Dictionary) -> void:
	var category := String(state.get("category", "accessibility"))
	for pair: Array in CATEGORIES:
		if category == pair[0]:
			_active = category
	_advanced = bool(state.get("advanced", false))
	_rebuild()
	var scroll := find_child("SettingsContentScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.set_deferred("scroll_vertical", int(state.get("scroll", 0)))


func _open_bindings() -> void:
	if get_tree().current_scene == self:
		SceneRouter.go_to("res://scenes/menus/controls.tscn")
		return
	if is_instance_valid(_bindings_panel):
		return
	# Embedded settings (Pause) keep their game and pause state alive.
	_bindings_panel = load("res://scenes/menus/controls.tscn").instantiate() as Control
	_bindings_panel.set("on_back", _close_bindings)
	_bindings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bindings_panel.z_index = 1
	_page.hide()
	add_child(_bindings_panel)


func _close_bindings() -> void:
	if is_instance_valid(_bindings_panel):
		_bindings_panel.queue_free()
		_bindings_panel = null
	_page.show()


func _back() -> void:
	if is_instance_valid(_name_prompt):
		_name_prompt.queue_free()
		_name_prompt = null
		return
	if is_instance_valid(_bindings_panel):
		_close_bindings()
		return
	if is_instance_valid(_deletion) and _deletion.consume_back():
		return
	if on_back.is_valid():
		on_back.call()
	else:
		SceneRouter.go_back()


func _font(size: int) -> int:
	return maxi(1, roundi(float(size) * _scale))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_back()
