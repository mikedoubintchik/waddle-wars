extends Control
## Credits screen with a gentle floating scroll animation.

var _content: VBoxContainer
var _elapsed: float = 0.0
var _base_y: float = 0.0
var _base_y_set: bool = false


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 10)
	center.add_child(_content)

	var logo := UITheme.heading(GameConfig.GAME_NAME.to_upper(), 64)
	logo.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	_content.add_child(logo)
	_content.add_child(UITheme.accent_rule(320.0, UITheme.COLOR_GOLD))

	var studio := UITheme.heading("a %s production" % GameConfig.STUDIO_NAME, 26)
	studio.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_content.add_child(studio)

	_content.add_child(_spacer(24))

	var roles: Array = [
		["Game Design", "Claude"],
		["Programming", "Claude"],
		["Course Design", "Claude"],
		["Procedural Art", "Claude"],
		["Audio & Music", "Claude"],
		["QA & Testing", "Claude"],
	]
	for entry: Array in roles:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 24)
		_content.add_child(row)
		var role_label := Label.new()
		role_label.text = String(entry[0])
		role_label.add_theme_font_size_override("font_size", 23)
		role_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		role_label.custom_minimum_size = Vector2(280, 0)
		role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(role_label)
		var name_label := Label.new()
		name_label.text = String(entry[1])
		name_label.add_theme_font_size_override("font_size", 23)
		name_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
		name_label.custom_minimum_size = Vector2(280, 0)
		row.add_child(name_label)

	_content.add_child(_spacer(24))

	var engine_label := UITheme.heading("Made with Godot Engine", 24)
	engine_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_content.add_child(engine_label)

	var original_label := UITheme.heading("All art, audio and code are original and procedurally generated.", 20)
	original_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_content.add_child(original_label)

	var version_label := UITheme.heading("Version %s" % GameConfig.GAME_VERSION, 18)
	version_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_content.add_child(version_label)

	_content.add_child(_spacer(20))

	var back_button := UITheme.make_button("Back", Vector2(220, 52), 24)
	UITheme.hook_sounds(back_button)
	back_button.pressed.connect(_go_back)
	var button_center := CenterContainer.new()
	button_center.add_child(back_button)
	_content.add_child(button_center)
	back_button.grab_focus()


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _process(delta: float) -> void:
	_elapsed += delta
	if not _base_y_set:
		_base_y = _content.position.y
		_base_y_set = true
	_content.position.y = _base_y + sin(_elapsed * 0.8) * 10.0


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()
