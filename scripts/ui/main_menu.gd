extends Control
## Main menu: themed button stack with staggered entrance animation, a live
## penguin diorama panel, and a fish/level chip.

## Same drawn fish glyph as the race HUD and customize menu currency counters
## (race_hud.gd / customize_menu.gd) so the icon is consistent across screens.
const FISH_ICON_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="60" height="40" viewBox="0 0 60 40">
<path d="M3 20 L19 8 L19 32 Z" fill="#6fc0ee"/>
<ellipse cx="34" cy="21" rx="21" ry="12" fill="#8fd8f8"/>
<path d="M26 11 Q35 3 44 11 Q35 15 26 11 Z" fill="#5fb0e2"/>
<path d="M20 21 Q34 31 50 22 Q34 27 20 21 Z" fill="#5fb0e2" opacity="0.7"/>
<circle cx="45" cy="17" r="3.2" fill="#0e2036"/>
<circle cx="46.2" cy="15.8" r="1.1" fill="#ffffff"/>
</svg>"""

var _buttons: Array[Button] = []
var _fish_label: Label


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)

	# Single centered column filling the screen — the old side diorama shrank
	# the menu into a corner on phones.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title := UITheme.heading(GameConfig.GAME_NAME, 84)
	title.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.25, 0.65, 1.0, 0.35))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_outline_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var rule := UITheme.accent_rule(360.0)
	vbox.add_child(rule)
	var tagline := UITheme.sub_label("Slide. Shove. Snack. Repeat.", 24)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	vbox.add_child(gap)

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

	_build_status_chip()
	UITheme.attach_swipe_back(self, func() -> void:
		SceneRouter.go_to(Game.SCENE_TITLE))
	_play_entrance()

	if not _buttons.is_empty():
		_buttons[0].grab_focus()
	AudioManager.play_music("music_title")


func _add_button(parent: Control, text: String, on_pressed: Callable) -> void:
	var button := UITheme.make_button(text, Vector2(520, 72), 32)
	UITheme.hook_sounds(button)
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	_buttons.append(button)


func _build_status_chip() -> void:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UITheme.make_panel_style(Color(0.06, 0.11, 0.19, 0.9), UITheme.COLOR_GOLD))
	chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	chip.offset_left = -280.0
	chip.offset_top = 16.0
	chip.offset_right = -16.0
	chip.offset_bottom = 70.0
	add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(row)
	var fish_box := HBoxContainer.new()
	fish_box.add_theme_constant_override("separation", 8)
	row.add_child(fish_box)
	var fish_tex := _make_fish_texture()
	if fish_tex != null:
		var fish_icon := TextureRect.new()
		fish_icon.texture = fish_tex
		fish_icon.custom_minimum_size = Vector2(36, 24)
		fish_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fish_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fish_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fish_box.add_child(fish_icon)
	else:
		# SVG module unavailable: fall back to a glyph so the counter
		# still reads correctly.
		var fish_glyph := Label.new()
		fish_glyph.text = "><>"
		fish_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fish_glyph.add_theme_font_size_override("font_size", 22)
		fish_glyph.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95))
		fish_box.add_child(fish_glyph)
	_fish_label = Label.new()
	_fish_label.add_theme_font_size_override("font_size", 22)
	_fish_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_fish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fish_label.text = "%d" % Progression.get_fish()
	fish_box.add_child(_fish_label)
	var level_label := Label.new()
	level_label.add_theme_font_size_override("font_size", 22)
	level_label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	level_label.text = "Lv %d" % Progression.get_level()
	row.add_child(level_label)
	Progression.fish_changed.connect(_on_fish_changed)


func _on_fish_changed(total: int) -> void:
	_fish_label.text = "%d" % total


static func _make_fish_texture() -> ImageTexture:
	var img := Image.new()
	if img.load_svg_from_string(FISH_ICON_SVG, 2.0) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _play_entrance() -> void:
	for button: Button in _buttons:
		button.modulate.a = 0.0
	# Wait one frame so containers finish layout before capturing positions.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	for i: int in _buttons.size():
		var button := _buttons[i]
		var target_x := button.position.x
		var delay := 0.05 + 0.06 * float(i)
		button.position.x = target_x - 40.0
		var fade := create_tween()
		fade.tween_interval(delay)
		fade.tween_property(button, "modulate:a", 1.0, 0.25)
		var slide := create_tween()
		slide.tween_interval(delay)
		slide.tween_property(button, "position:x", target_x, 0.25) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		SceneRouter.go_to(Game.SCENE_TITLE)
