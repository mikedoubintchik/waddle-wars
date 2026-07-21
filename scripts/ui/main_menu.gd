extends Control
## Main menu shell: Play, Waddle School, Customize, Achievements, Settings,
## Credits, Quit. Replaced with the themed version by the UI workstream.

var _buttons: Array[Button] = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.14, 0.26)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title := Label.new()
	title.text = GameConfig.GAME_NAME
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_add_button(vbox, "Play", func() -> void:
		SceneRouter.go_to(Game.SCENE_MODE_SELECT))
	_add_button(vbox, "Waddle School", func() -> void:
		Game.start_tutorial())
	_add_button(vbox, "Customize", func() -> void:
		SceneRouter.go_to(Game.SCENE_CUSTOMIZE))
	_add_button(vbox, "Achievements", func() -> void:
		SceneRouter.go_to(Game.SCENE_ACHIEVEMENTS))
	_add_button(vbox, "Settings", func() -> void:
		SceneRouter.go_to(Game.SCENE_SETTINGS))
	_add_button(vbox, "Credits", func() -> void:
		SceneRouter.go_to(Game.SCENE_CREDITS))
	if not GameConfig.is_mobile():
		_add_button(vbox, "Quit", func() -> void:
			get_tree().quit())

	if not _buttons.is_empty():
		_buttons[0].grab_focus()
	AudioManager.play_music("music_title")


func _add_button(parent: Control, text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 56)
	button.add_theme_font_size_override("font_size", 30)
	button.pressed.connect(func() -> void:
		AudioManager.ui_click()
		on_pressed.call())
	button.mouse_entered.connect(AudioManager.ui_hover)
	button.focus_entered.connect(AudioManager.ui_hover)
	parent.add_child(button)
	_buttons.append(button)
