extends Control
## Mode → course → difficulty selection flow, then starts the race.

var _step: String = "mode"  # mode | course | difficulty
var _chosen_mode: Game.Mode = Game.Mode.QUICK_RACE
var _chosen_course: String = "glacier"
var _content: VBoxContainer
var _buttons: Array[Button] = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.14, 0.26)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 14)
	center.add_child(_content)
	_show_mode_step()


func _clear() -> void:
	_buttons.clear()
	for child in _content.get_children():
		child.queue_free()


func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 52)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(label)


func _sub(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.92))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(label)


func _show_mode_step() -> void:
	_step = "mode"
	_clear()
	_heading("Choose a Mode")
	_add_option("Quick Race", "One race, one course, seven rivals.", func() -> void:
		_chosen_mode = Game.Mode.QUICK_RACE
		_show_course_step())
	_add_option("Grand Prix", "Three races. Points decide the cup.", func() -> void:
		_chosen_mode = Game.Mode.GRAND_PRIX
		_show_difficulty_step())
	_add_option("Endless Expedition", "Survive an ever-faster obstacle run.  Best: %d" % Progression.endless_high_score(), func() -> void:
		Game.start_endless())
	_add_option("Time Trial", "Race your ghost. No items, pure skill.", func() -> void:
		_chosen_mode = Game.Mode.TIME_TRIAL
		_show_course_step())
	_add_option("Back", "", func() -> void:
		SceneRouter.go_to(Game.SCENE_MAIN_MENU))
	_focus_first()


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
		_add_option(String(info["name"]), desc, func() -> void:
			_chosen_course = course_id
			if _chosen_mode == Game.Mode.TIME_TRIAL:
				Game.start_time_trial(course_id)
			else:
				_show_difficulty_step())
	_add_option("Back", "", _show_mode_step)
	_focus_first()


func _show_difficulty_step() -> void:
	_step = "difficulty"
	_clear()
	_heading("Choose a Difficulty")
	for id: String in DifficultyDB.ORDER:
		var info := DifficultyDB.get_item(id)
		var difficulty_id := id
		_add_option(String(info["name"]), String(info.get("desc", "")), func() -> void:
			if _chosen_mode == Game.Mode.GRAND_PRIX:
				Game.start_grand_prix(difficulty_id)
			else:
				Game.start_quick_race(_chosen_course, difficulty_id))
	_add_option("Back", "", _show_mode_step if _chosen_mode == Game.Mode.GRAND_PRIX else _show_course_step)
	_focus_first()


func _add_option(title: String, desc: String, action: Callable) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(560, 64 if desc == "" else 84)
	button.text = title if desc == "" else "%s\n%s" % [title, desc]
	button.add_theme_font_size_override("font_size", 26)
	button.clip_text = false
	button.pressed.connect(func() -> void:
		AudioManager.ui_click()
		action.call())
	button.mouse_entered.connect(AudioManager.ui_hover)
	button.focus_entered.connect(AudioManager.ui_hover)
	_content.add_child(button)
	_buttons.append(button)


func _focus_first() -> void:
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		match _step:
			"mode":
				SceneRouter.go_to(Game.SCENE_MAIN_MENU)
			"course":
				_show_mode_step()
			"difficulty":
				_show_course_step() if _chosen_mode != Game.Mode.GRAND_PRIX else _show_mode_step()
