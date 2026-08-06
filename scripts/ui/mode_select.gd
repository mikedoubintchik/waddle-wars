extends Control
## Mode → course → difficulty selection flow, then starts the race.
## Options render as large cards with icon glyphs, title, and description.

const ICON_QUICK_RACE: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M36 4 L14 36 L28 36 L24 60 L50 26 L34 26 Z" fill="#ffd94d" stroke="#c98f1b" stroke-width="2" stroke-linejoin="round"/>
</svg>"""

const ICON_GRAND_PRIX: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M17 12 C7 12 7 28 19 29" stroke="#f5c542" stroke-width="4" fill="none"/>
<path d="M47 12 C57 12 57 28 45 29" stroke="#f5c542" stroke-width="4" fill="none"/>
<path d="M18 8 H46 V22 C46 34 40 40 32 40 C24 40 18 34 18 22 Z" fill="#f5c542" stroke="#c98f1b" stroke-width="2"/>
<rect x="28" y="40" width="8" height="8" fill="#e0b030"/>
<rect x="20" y="48" width="24" height="7" rx="2" fill="#c98f1b"/>
<path d="M24 14 L27 22 L24 30" stroke="#fff2c0" stroke-width="3" fill="none" opacity="0.8"/>
</svg>"""

const ICON_ENDLESS: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M4 56 L24 16 L38 40 L46 26 L60 56 Z" fill="#7fb4d8" stroke="#3d6d94" stroke-width="2" stroke-linejoin="round"/>
<path d="M24 16 L30 28 L27 27 L24 33 L20 27 L18 28 Z" fill="#f2f8ff"/>
<path d="M46 26 L51 36 L48 34 L46 39 L43 34 L41 36 Z" fill="#f2f8ff"/>
<path d="M24 16 V4 L34 8 L24 12" fill="#ff6b57" stroke="#b23a2b" stroke-width="1.5"/>
</svg>"""

const ICON_TIME_TRIAL: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<rect x="27" y="4" width="10" height="7" rx="2" fill="#3d6d94"/>
<path d="M44 14 L50 20" stroke="#3d6d94" stroke-width="4" stroke-linecap="round"/>
<circle cx="32" cy="37" r="21" fill="#9adcf8" stroke="#2b6f9e" stroke-width="3"/>
<circle cx="32" cy="37" r="15" fill="#d7f1fd"/>
<path d="M32 37 L32 25" stroke="#0e2036" stroke-width="4" stroke-linecap="round"/>
<path d="M32 37 L41 42" stroke="#0e2036" stroke-width="3" stroke-linecap="round"/>
<circle cx="32" cy="37" r="2.4" fill="#f5c542"/>
</svg>"""

const ICON_COURSE_GLACIER: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<g stroke="#aee2ff" stroke-width="4" stroke-linecap="round" fill="none">
<path d="M32 6 V58 M10 19 L54 45 M54 19 L10 45"/>
<path d="M32 14 L26 8 M32 14 L38 8 M32 50 L26 56 M32 50 L38 56"/>
</g>
<circle cx="32" cy="32" r="5" fill="#e8f7ff"/>
</svg>"""

const ICON_COURSE_AURORA: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M6 40 Q18 20 30 34 Q42 48 58 24" stroke="#69f0c4" stroke-width="6" fill="none" stroke-linecap="round"/>
<path d="M6 52 Q20 34 32 44 Q44 54 58 36" stroke="#9a7bff" stroke-width="5" fill="none" stroke-linecap="round" opacity="0.85"/>
<circle cx="14" cy="14" r="2" fill="#ffffff"/><circle cx="46" cy="10" r="1.6" fill="#ffffff"/><circle cx="56" cy="52" r="1.8" fill="#ffffff"/>
</svg>"""

const ICON_COURSE_ICEBERG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M12 34 L24 10 L36 26 L44 18 L54 34 Z" fill="#d7f1fd" stroke="#7fb4d8" stroke-width="2"/>
<path d="M8 38 Q16 34 24 38 T40 38 T56 38" stroke="#4a9fd8" stroke-width="4" fill="none" stroke-linecap="round"/>
<path d="M6 48 Q14 44 22 48 T38 48 T54 48" stroke="#2b6f9e" stroke-width="4" fill="none" stroke-linecap="round"/>
</svg>"""

const ICON_BACK: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M38 12 L18 32 L38 52" stroke="#9fc4e0" stroke-width="7" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""

const COURSE_ICONS: Dictionary = {
	"glacier": ICON_COURSE_GLACIER,
	"aurora": ICON_COURSE_AURORA,
	"iceberg": ICON_COURSE_ICEBERG,
}

const DIFFICULTY_COLORS: Dictionary = {
	"chill": "#7fe08f",
	"competitive": "#f5c542",
	"emperor": "#ff6b57",
}

var _step: String = "mode"  # mode | course | difficulty
var _chosen_mode: Game.Mode = Game.Mode.QUICK_RACE
var _chosen_course: String = "glacier"
var _content: VBoxContainer
var _buttons: Array[Button] = []


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", UITheme.spacing(UITheme.SPACE_S))
	center.add_child(_content)
	_show_mode_step()
	UITheme.attach_swipe_back(self, _go_back_step)


func _clear() -> void:
	_buttons.clear()
	for child in _content.get_children():
		child.queue_free()


func _heading(text: String) -> void:
	var label := UITheme.heading(text, 52)
	_content.add_child(label)
	# Shared header treatment: the rule spans the card column and sweeps in,
	# matching every other menu's make_header_rule rhythm.
	_content.add_child(UITheme.make_header_rule())
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_content.add_child(gap)


func _sub(text: String) -> void:
	var label := UITheme.sub_label(text, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(label)


func _show_mode_step() -> void:
	_step = "mode"
	_clear()
	_heading("Choose a Mode")
	var pick_quick := func() -> void:
		_chosen_mode = Game.Mode.QUICK_RACE
		_show_course_step()
	var pick_gp := func() -> void:
		_chosen_mode = Game.Mode.GRAND_PRIX
		_show_difficulty_step()
	var pick_endless := func() -> void:
		Game.start_endless()
	var pick_tt := func() -> void:
		_chosen_mode = Game.Mode.TIME_TRIAL
		_show_course_step()
	var go_back := func() -> void:
		SceneRouter.go_to(Game.SCENE_MAIN_MENU)
	_add_option("Quick Race", "One race, one course, seven rivals.", pick_quick, ICON_QUICK_RACE)
	_add_option("Grand Prix", "Three races. Points decide the cup.", pick_gp, ICON_GRAND_PRIX)
	_add_option("Endless Expedition", "Outrun an ever-faster storm.  Best: %d" % Progression.endless_high_score(), pick_endless, ICON_ENDLESS)
	_add_option("Time Trial", "Race your ghost. No items, pure skill.", pick_tt, ICON_TIME_TRIAL)
	_add_option("Back", "", go_back, ICON_BACK)
	_focus_first()
	_play_entrance()


func _show_course_step() -> void:
	_step = "course"
	_clear()
	_heading("Choose a Course")
	for id: String in CoursesDB.ORDER:
		var info := CoursesDB.get_item(id)
		var best := Progression.best_time(id)
		var desc := String(info.get("desc", ""))
		if best > 0.0:
			desc += "\nBest time: %s" % RaceHUD.format_time(best)
		var course_id := id
		var pick_course := func() -> void:
			_chosen_course = course_id
			if _chosen_mode == Game.Mode.TIME_TRIAL:
				Game.start_time_trial(course_id)
			else:
				_show_difficulty_step()
		_add_option(String(info["name"]), desc, pick_course, String(COURSE_ICONS.get(id, ICON_COURSE_GLACIER)))
	_add_option("Back", "", _show_mode_step, ICON_BACK)
	_focus_first()
	_play_entrance()


func _show_difficulty_step() -> void:
	_step = "difficulty"
	_clear()
	_heading("Choose a Difficulty")
	for i: int in DifficultyDB.ORDER.size():
		var id := String(DifficultyDB.ORDER[i])
		var info := DifficultyDB.get_item(id)
		var difficulty_id := id
		var pick_difficulty := func() -> void:
			if _chosen_mode == Game.Mode.GRAND_PRIX:
				Game.start_grand_prix(difficulty_id)
			else:
				Game.start_quick_race(_chosen_course, difficulty_id)
		_add_option(String(info["name"]), String(info.get("desc", "")), pick_difficulty, _difficulty_icon(id, i + 1))
	_add_option("Back", "", _show_mode_step if _chosen_mode == Game.Mode.GRAND_PRIX else _show_course_step, ICON_BACK)
	_focus_first()
	_play_entrance()


## Chevron-stack glyph: more chevrons and hotter color per difficulty tier.
func _difficulty_icon(id: String, tier: int) -> String:
	var color := String(DIFFICULTY_COLORS.get(id, "#f5c542"))
	var chevrons := ""
	for i: int in tier:
		var y := 46 - i * 13
		chevrons += "<path d=\"M14 %d L32 %d L50 %d\" stroke=\"%s\" stroke-width=\"6\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\" opacity=\"%.2f\"/>" % [
			y + 8, y, y + 8, color, 0.55 + 0.45 * float(i + 1) / float(tier),
		]
	return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" viewBox=\"0 0 64 64\">%s</svg>" % chevrons


func _add_option(title: String, desc: String, action: Callable, icon_svg: String = "") -> void:
	var is_compact := desc == ""
	# 112 tall: room for a two-line wrapped description (see autowrap below).
	var button := UITheme.make_button("", Vector2(660, 64 if is_compact else 112), 24)
	UITheme.hook_sounds(button)
	button.pressed.connect(action)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	button.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(row)

	if icon_svg != "":
		var texture := UITheme.make_icon(icon_svg, 1.0)
		if texture != null:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.custom_minimum_size = Vector2(52, 52)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(icon)

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_override("font", UITheme.bold_font())
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(title_label)

	if not is_compact:
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.add_theme_font_size_override("font_size", 18)
		desc_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Wrap inside the card instead of overflowing its right edge.
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		desc_label.max_lines_visible = 2
		text_box.add_child(desc_label)

	_content.add_child(button)
	_buttons.append(button)


func _focus_first() -> void:
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


## Unified staggered fade+rise entrance whenever a step's cards are rebuilt.
func _play_entrance() -> void:
	var items: Array[Control] = []
	for button: Button in _buttons:
		items.append(button)
	UITheme.play_entrance(self, items)


## One step back through the flow; from the first step, back to the main
## menu. Shared by ui_cancel and the edge-swipe back gesture.
func _go_back_step() -> void:
	match _step:
		"mode":
			SceneRouter.go_to(Game.SCENE_MAIN_MENU)
		"course":
			_show_mode_step()
		"difficulty":
			_show_course_step() if _chosen_mode != Game.Mode.GRAND_PRIX else _show_mode_step()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back_step()
