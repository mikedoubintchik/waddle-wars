extends Control
## Achievement gallery plus player level, XP progress, and lifetime stats.

const BADGE_UNLOCKED_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="44" height="44" viewBox="0 0 44 44">
<path d="M22 3 L26.7 14.3 L38.9 15.3 L29.6 23.2 L32.4 35.1 L22 28.8 L11.6 35.1 L14.4 23.2 L5.1 15.3 L17.3 14.3 Z" fill="#f5c542" stroke="#c98f1b" stroke-width="2" stroke-linejoin="round"/>
<path d="M22 9 L24.8 15.8 L32 16.4 L26.5 21.1 L28.2 28.2 L22 24.4 Z" fill="#fff2c0" opacity="0.65"/>
</svg>"""

const BADGE_LOCKED_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="44" height="44" viewBox="0 0 44 44">
<rect x="10" y="19" width="24" height="18" rx="4" fill="#3a4a5e"/>
<path d="M15 19 V14 a7 7 0 0 1 14 0 V19" stroke="#3a4a5e" stroke-width="4" fill="none"/>
<circle cx="22" cy="27" r="3" fill="#22303f"/>
<rect x="20.6" y="27" width="2.8" height="6" rx="1.2" fill="#22303f"/>
</svg>"""


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UITheme.screen_margin())
	margin.add_theme_constant_override("margin_right", UITheme.screen_margin())
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", UITheme.SPACE_S)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	layout.add_child(header)
	var title := UITheme.heading("Achievements", 48)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	var progress_label := Label.new()
	progress_label.text = "%d / %d" % [Progression.achievements_unlocked_count(), AchievementsDB.ORDER.size()]
	progress_label.add_theme_font_size_override("font_size", 30)
	progress_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(progress_label)
	var back_button := UITheme.make_button("Back", Vector2(160, 48), 22)
	UITheme.hook_sounds(back_button)
	back_button.pressed.connect(_go_back)
	header.add_child(back_button)
	layout.add_child(UITheme.make_header_rule())

	var player_panel := _build_player_panel()
	layout.add_child(player_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", UITheme.spacing(10))
	scroll.add_child(list)

	var entrance_items: Array[Control] = [header, player_panel]
	for id: String in AchievementsDB.ORDER:
		var row := _build_achievement_row(id)
		list.add_child(row)
		entrance_items.append(row)
	UITheme.play_entrance(self, entrance_items)

	UITheme.attach_swipe_back(self, _go_back)
	back_button.grab_focus()


func _build_player_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.make_panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 16)
	box.add_child(level_row)
	var level_label := Label.new()
	level_label.text = "Level %d" % Progression.get_level()
	level_label.add_theme_font_size_override("font_size", 26)
	level_label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	level_row.add_child(level_label)

	var xp_bar := ProgressBar.new()
	xp_bar.min_value = 0.0
	xp_bar.max_value = 1.0
	xp_bar.value = Progression.level_progress()
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(0, 22)
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = UITheme.COLOR_BG_DEEP
	bar_bg.set_corner_radius_all(6)
	bar_bg.set_border_width_all(1)
	bar_bg.border_color = Color(UITheme.COLOR_ACCENT, 0.3)
	xp_bar.add_theme_stylebox_override("background", bar_bg)
	xp_bar.add_theme_stylebox_override("fill",
		UITheme.make_bar_fill(Color(0.30, 0.62, 0.90), Color(0.55, 0.88, 1.0)))
	level_row.add_child(xp_bar)

	var xp_label := Label.new()
	xp_label.text = "%d / %d XP" % [Progression.get_xp() % Progression.XP_PER_LEVEL, Progression.XP_PER_LEVEL]
	xp_label.add_theme_font_size_override("font_size", 19)
	xp_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	level_row.add_child(xp_label)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 28)
	box.add_child(stats_row)
	var stats: Array = [
		["Races Finished", Progression.get_stat("races_finished")],
		["Races Won", Progression.get_stat("races_won")],
		["Fish Collected", Progression.get_stat("fish_total")],
		["Shoves Landed", Progression.get_stat("shoves_landed")],
	]
	for entry: Array in stats:
		var stat_box := VBoxContainer.new()
		stats_row.add_child(stat_box)
		var value_label := Label.new()
		value_label.text = str(entry[1])
		value_label.add_theme_font_size_override("font_size", 26)
		value_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
		stat_box.add_child(value_label)
		var name_label := Label.new()
		name_label.text = String(entry[0])
		name_label.add_theme_font_size_override("font_size", 17)
		name_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		stat_box.add_child(name_label)
	return panel


func _build_achievement_row(id: String) -> PanelContainer:
	var info := AchievementsDB.get_item(id)
	var unlocked := Progression.is_achievement_unlocked(id)
	var panel := PanelContainer.new()
	var style := UITheme.make_panel_style(
		Color(0.125, 0.2, 0.32, 0.95) if unlocked else Color(0.08, 0.13, 0.21, 0.8),
		UITheme.COLOR_GOLD if unlocked else Color(0.16, 0.24, 0.35)
	)
	if unlocked:
		style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var badge_texture := UITheme.make_icon(BADGE_UNLOCKED_SVG if unlocked else BADGE_LOCKED_SVG, 1.0)
	if badge_texture != null:
		var badge := TextureRect.new()
		badge.texture = badge_texture
		badge.custom_minimum_size = Vector2(44, 44)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not unlocked:
			badge.modulate = Color(1.0, 1.0, 1.0, 0.75)
		row.add_child(badge)
	else:
		var badge := Label.new()
		badge.text = "*" if unlocked else "-"
		badge.add_theme_font_size_override("font_size", 34)
		badge.add_theme_color_override("font_color", UITheme.COLOR_GOLD if unlocked else UITheme.COLOR_DISABLED)
		badge.custom_minimum_size = Vector2(44, 0)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(badge)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)
	var name_label := Label.new()
	name_label.text = String(info.get("name", id))
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD if unlocked else UITheme.COLOR_TEXT_DIM)
	text_box.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = String(info.get("desc", ""))
	desc_label.add_theme_font_size_override("font_size", 19)
	desc_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT if unlocked else UITheme.COLOR_DISABLED)
	text_box.add_child(desc_label)

	# Status rendered as a small pill chip (gold-tinted when unlocked) so the
	# row's right edge reads as a badge instead of loose text.
	var state_label := Label.new()
	state_label.text = "Unlocked" if unlocked else "Locked"
	state_label.add_theme_font_override("font", UITheme.bold_font())
	state_label.add_theme_font_size_override("font_size", 17)
	state_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD if unlocked else UITheme.COLOR_TEXT_DIM)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(UITheme.COLOR_GOLD, 0.13) if unlocked else Color(1.0, 1.0, 1.0, 0.05)
	pill.border_color = Color(UITheme.COLOR_GOLD, 0.45) if unlocked else Color(1.0, 1.0, 1.0, 0.10)
	pill.set_border_width_all(1)
	pill.set_corner_radius_all(12)
	pill.content_margin_left = 12.0
	pill.content_margin_right = 12.0
	pill.content_margin_top = 3.0
	pill.content_margin_bottom = 3.0
	state_label.add_theme_stylebox_override("normal", pill)
	state_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(state_label)
	return panel


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()
