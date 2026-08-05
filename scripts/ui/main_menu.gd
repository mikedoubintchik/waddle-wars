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
var _penguin: PenguinVisual
var _fish_label: Label


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)

	var columns := HBoxContainer.new()
	columns.set_anchors_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 30)
	add_child(columns)

	# Left: title + buttons.
	var left := CenterContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.6
	columns.add_child(left)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	left.add_child(vbox)

	var title := UITheme.heading(GameConfig.GAME_NAME, 62)
	title.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0))
	vbox.add_child(title)
	vbox.add_child(UITheme.accent_rule(300.0))
	var tagline := UITheme.sub_label("Slide. Shove. Snack. Repeat.", 20)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
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

	# Right: penguin diorama panel.
	var right := CenterContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.4
	columns.add_child(right)
	right.add_child(_build_diorama_panel())

	_build_status_chip()
	_play_entrance()

	if not _buttons.is_empty():
		_buttons[0].grab_focus()
	AudioManager.play_music("music_title")


func _add_button(parent: Control, text: String, on_pressed: Callable) -> void:
	var button := UITheme.make_button(text, Vector2(360, 56), 28)
	UITheme.hook_sounds(button)
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	_buttons.append(button)


func _build_diorama_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.make_panel_style(Color(0.06, 0.11, 0.19, 0.95)))
	panel.custom_minimum_size = Vector2(340, 420)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(container)

	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.68, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.84, 0.95)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	viewport.add_child(light)

	var floe := MeshInstance3D.new()
	var floe_mesh := CylinderMesh.new()
	floe_mesh.top_radius = 1.0
	floe_mesh.bottom_radius = 1.15
	floe_mesh.height = 0.25
	floe.mesh = floe_mesh
	floe.material_override = PenguinVisual.get_material(Color(0.93, 0.96, 1.0), 0.0, 0.9)
	floe.position = Vector3(0, -0.125, 0)
	viewport.add_child(floe)

	var body_info := CosmeticsDB.get_item(Progression.get_equipped("body"))
	_penguin = PenguinVisual.new()
	viewport.add_child(_penguin)
	_penguin.rotation.y = 0.4
	var config := {
		"body_color": body_info.get("body_color", Color(0.13, 0.16, 0.22)),
		"belly_color": body_info.get("belly_color", Color(0.95, 0.94, 0.9)),
		"hat": Progression.get_equipped("hat"),
		"scarf": Progression.get_equipped("scarf"),
		"goggles": Progression.get_equipped("goggles"),
	}
	if body_info.has("crest_color"):
		config["crest_color"] = body_info["crest_color"]
	_penguin.setup(config)
	_penguin.set_pose(PenguinVisual.Pose.IDLE)

	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	camera.look_at_from_position(Vector3(0.0, 1.0, -2.4), Vector3(0.0, 0.55, 0.0), Vector3.UP)
	return panel


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


func _process(delta: float) -> void:
	if _penguin != null:
		_penguin.tick(delta, 0.0)
		_penguin.rotation.y = 0.4 + sin(Time.get_ticks_msec() / 1000.0 * 0.4) * 0.25


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		SceneRouter.go_to(Game.SCENE_TITLE)
