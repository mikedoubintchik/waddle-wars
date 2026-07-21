extends Control
## Achievement gallery plus player level, XP progress, and lifetime stats.


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
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

	layout.add_child(_build_player_panel())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	for id: String in AchievementsDB.ORDER:
		list.add_child(_build_achievement_row(id))

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
	bar_bg.bg_color = Color(0.06, 0.1, 0.17)
	bar_bg.set_corner_radius_all(6)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = UITheme.COLOR_ACCENT
	bar_fill.set_corner_radius_all(6)
	xp_bar.add_theme_stylebox_override("background", bar_bg)
	xp_bar.add_theme_stylebox_override("fill", bar_fill)
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

	var state_label := Label.new()
	state_label.text = "Unlocked" if unlocked else "Locked"
	state_label.add_theme_font_size_override("font_size", 19)
	state_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD if unlocked else UITheme.COLOR_DISABLED)
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
