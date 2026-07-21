extends Control
## Title screen shell. Shows logo and routes to the main menu.
## Replaced with the animated diorama version by the UI workstream.

var _elapsed: float = 0.0
var _prompt: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.16, 0.3)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)

	var logo := Label.new()
	logo.text = GameConfig.GAME_NAME.to_upper()
	logo.add_theme_font_size_override("font_size", 110)
	logo.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(logo)

	_prompt = Label.new()
	_prompt.text = "Press Start"
	_prompt.add_theme_font_size_override("font_size", 34)
	_prompt.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_prompt)

	AudioManager.play_music("music_title")


func _process(delta: float) -> void:
	_elapsed += delta
	if _prompt != null:
		_prompt.modulate.a = 0.55 + 0.45 * sin(_elapsed * 3.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("pause") \
			or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed):
		AudioManager.ui_click()
		SceneRouter.go_to(Game.SCENE_MAIN_MENU)
