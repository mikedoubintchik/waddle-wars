extends Control
## Cosmetic shop and locker: live 3D penguin preview on the left, category
## tabs and an item grid on the right. Purchases spend fish via Progression.

## Same drawn fish glyph as the race HUD currency counter (race_hud.gd).
const FISH_ICON_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="60" height="40" viewBox="0 0 60 40">
<path d="M3 20 L19 8 L19 32 Z" fill="#6fc0ee"/>
<ellipse cx="34" cy="21" rx="21" ry="12" fill="#8fd8f8"/>
<path d="M26 11 Q35 3 44 11 Q35 15 26 11 Z" fill="#5fb0e2"/>
<path d="M20 21 Q34 31 50 22 Q34 27 20 21 Z" fill="#5fb0e2" opacity="0.7"/>
<circle cx="45" cy="17" r="3.2" fill="#0e2036"/>
<circle cx="46.2" cy="15.8" r="1.1" fill="#ffffff"/>
</svg>"""

var _preview_pivot: Node3D
var _penguin: PenguinVisual
var _fish_label: Label
var _tab_buttons: Dictionary = {}  # category -> Button
var _item_grid: GridContainer
var _current_category: String = "body"
var _desc_label: Label


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	layout.add_child(header)
	var title := UITheme.heading("Customize", 48)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)
	var fish_box := HBoxContainer.new()
	fish_box.add_theme_constant_override("separation", 8)
	header.add_child(fish_box)
	var fish_tex := _make_fish_texture()
	if fish_tex != null:
		var fish_icon := TextureRect.new()
		fish_icon.texture = fish_tex
		fish_icon.custom_minimum_size = Vector2(42, 28)
		fish_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fish_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fish_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fish_box.add_child(fish_icon)
	_fish_label = Label.new()
	_fish_label.add_theme_font_size_override("font_size", 28)
	_fish_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_fish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fish_box.add_child(_fish_label)
	var back_button := UITheme.make_button("Back", Vector2(160, 48), 22)
	UITheme.hook_sounds(back_button)
	back_button.pressed.connect(_go_back)
	header.add_child(back_button)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	layout.add_child(columns)

	_build_preview(columns)
	_build_shop(columns)

	_update_fish_label(Progression.get_fish())
	Progression.fish_changed.connect(_update_fish_label)
	Progression.cosmetics_changed.connect(_on_cosmetics_changed)

	_refresh_preview()
	_select_category("body")
	UITheme.attach_swipe_back(self, _go_back)
	var body_tab: Button = _tab_buttons["body"]
	body_tab.grab_focus()


## --- 3D preview -----------------------------------------------------------

func _build_preview(parent: HBoxContainer) -> void:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.make_panel_style(Color(0.06, 0.11, 0.19, 0.95)))
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 0.42
	parent.add_child(frame)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(container)

	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(viewport)

	# Soft daytime gradient sky instead of a flat blue fill.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.34, 0.55, 0.83)
	sky_material.sky_horizon_color = Color(0.79, 0.88, 0.96)
	sky_material.sky_curve = 0.12
	sky_material.ground_horizon_color = Color(0.79, 0.88, 0.96)
	sky_material.ground_bottom_color = Color(0.5, 0.64, 0.8)
	sky_material.sun_angle_max = 20.0
	sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	# Soft warm key from camera-left. Penguin front faces -Z and the camera
	# sits on -Z, so the key must shine toward +Z (yaw ~150) to light the face.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 152.0, 0.0)
	key.light_energy = 1.0
	key.light_color = Color(1.0, 0.97, 0.9)
	var shadow_quality := String(SettingsManager.get_setting("display", "shadow_quality"))
	key.shadow_enabled = shadow_quality != "off" and not GameConfig.is_headless()
	key.shadow_bias = 0.03
	key.shadow_normal_bias = 1.6
	viewport.add_child(key)

	# Cool sky fill from camera-right lifts the shadow side without blowing out.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -155.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.62, 0.76, 1.0)
	fill.shadow_enabled = false
	viewport.add_child(fill)

	var floe := MeshInstance3D.new()
	var floe_mesh := CylinderMesh.new()
	floe_mesh.top_radius = 0.9
	floe_mesh.bottom_radius = 1.05
	floe_mesh.height = 0.25
	floe.mesh = floe_mesh
	floe.material_override = VisualLibrary.snow_material(Color(0.9, 0.94, 1.0), 0.3)
	floe.position = Vector3(0, -0.125, 0)
	viewport.add_child(floe)

	_preview_pivot = Node3D.new()
	viewport.add_child(_preview_pivot)
	_penguin = PenguinVisual.new()
	_preview_pivot.add_child(_penguin)

	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	# Camera on -Z looks at the penguin's face (model front is -Z); the pivot
	# starts at rotation 0 so the preview opens front-facing.
	camera.look_at_from_position(Vector3(0.0, 1.0, -2.3), Vector3(0.0, 0.55, 0.0), Vector3.UP)


func _refresh_preview() -> void:
	var body_info := CosmeticsDB.get_item(Progression.get_equipped("body"))
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
	# Preview the equipped trail as gentle ambient particles around the floe.
	if _preview_trail != null:
		_preview_trail.queue_free()
		_preview_trail = null
	var trail_id := Progression.get_equipped("trail")
	if trail_id != "":
		_preview_trail = TrailEffect.create(trail_id)
		if _preview_trail != null:
			_preview_trail.position = Vector3(0, 0.3, 0.5)
			_preview_trail.emitting = true
			_penguin.add_child(_preview_trail)


var _preview_trail: GPUParticles3D = null
var _sway_time: float = 0.0


func _process(delta: float) -> void:
	if _preview_pivot != null:
		# Gentle sway instead of a full spin: starts front-facing (sin 0 = 0)
		# and keeps the face toward the camera while showing off the sides.
		_sway_time += delta
		_preview_pivot.rotation.y = sin(_sway_time * 0.55) * 0.55
	if _penguin != null:
		_penguin.tick(delta, 0.0)


## --- Shop -----------------------------------------------------------------

func _build_shop(parent: HBoxContainer) -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.58
	right.add_theme_constant_override("separation", 10)
	parent.add_child(right)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", UITheme.spacing(8))
	right.add_child(tabs)
	for category: String in CosmeticsDB.CATEGORIES:
		var tab := UITheme.make_button(String(CosmeticsDB.CATEGORY_NAMES[category]), Vector2(0, 44), 19)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		UITheme.hook_sounds(tab)
		tab.pressed.connect(_select_category.bind(category))
		tabs.add_child(tab)
		_tab_buttons[category] = tab

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	right.add_child(scroll)

	_item_grid = GridContainer.new()
	_item_grid.columns = 2
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_grid.add_theme_constant_override("h_separation", UITheme.spacing(10))
	_item_grid.add_theme_constant_override("v_separation", UITheme.spacing(10))
	scroll.add_child(_item_grid)

	# Description strip: tooltips are hover-only, so touch (and keyboard)
	# players read the focused/tapped item's flavor text here instead.
	_desc_label = UITheme.sub_label("", 18)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(0, 26)
	right.add_child(_desc_label)


func _select_category(category: String) -> void:
	_current_category = category
	for cat: String in _tab_buttons.keys():
		var tab: Button = _tab_buttons[cat]
		tab.set_pressed_no_signal(cat == category)
	_rebuild_items()


func _rebuild_items() -> void:
	for child: Node in _item_grid.get_children():
		_item_grid.remove_child(child)
		child.queue_free()
	if _current_category != "body":
		_item_grid.add_child(_make_none_button())
	for id: String in CosmeticsDB.items_in_category(_current_category):
		_item_grid.add_child(_make_item_button(id))


func _make_none_button() -> Button:
	var equipped_id := Progression.get_equipped(_current_category)
	var text := "None"
	if equipped_id == "":
		text += "\nEquipped"
	var button := UITheme.make_button(text, Vector2(0, 88), 21)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_entered.connect(AudioManager.ui_hover)
	button.focus_entered.connect(AudioManager.ui_hover)
	var show_desc := func() -> void:
		_show_item_desc("Wear nothing in this category.")
	button.mouse_entered.connect(show_desc)
	button.focus_entered.connect(show_desc)
	button.pressed.connect(func() -> void:
		AudioManager.ui_click()
		Progression.equip(_current_category, ""))
	return button


func _make_item_button(id: String) -> Button:
	var info := CosmeticsDB.get_item(id)
	var unlocked := Progression.is_cosmetic_unlocked(id)
	var is_equipped := Progression.get_equipped(_current_category) == id
	var status := ""
	if is_equipped:
		status = "Equipped"
	elif unlocked:
		status = "Owned"
	else:
		status = "%d fish" % int(info.get("cost", 0))
	var text := "%s\n%s" % [String(info.get("name", id)), status]
	var button := UITheme.make_button(text, Vector2(0, 88), 21)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var desc := String(info.get("desc", ""))
	button.tooltip_text = desc
	if is_equipped:
		button.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	button.mouse_entered.connect(AudioManager.ui_hover)
	button.focus_entered.connect(AudioManager.ui_hover)
	var show_desc := func() -> void:
		_show_item_desc(desc)
	button.mouse_entered.connect(show_desc)
	button.focus_entered.connect(show_desc)
	button.pressed.connect(_on_item_pressed.bind(id))
	return button


func _show_item_desc(text: String) -> void:
	if _desc_label != null:
		_desc_label.text = text


func _on_item_pressed(id: String) -> void:
	var category := String(CosmeticsDB.get_item(id).get("category", _current_category))
	if Progression.is_cosmetic_unlocked(id):
		AudioManager.ui_click()
		if Progression.get_equipped(category) == id and category != "body":
			Progression.equip(category, "")
		else:
			Progression.equip(category, id)
		return
	if Progression.try_unlock_cosmetic(id):
		Progression.equip(category, id)
	else:
		AudioManager.play_sfx("sfx_ui_select", 0.6, -6.0)


func _on_cosmetics_changed() -> void:
	_refresh_preview()
	var focused_index := -1
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and focus_owner.get_parent() == _item_grid:
		focused_index = focus_owner.get_index()
	_rebuild_items()
	if focused_index >= 0:
		call_deferred("_restore_item_focus", focused_index)


func _restore_item_focus(index: int) -> void:
	var count := _item_grid.get_child_count()
	if count == 0:
		return
	var target := _item_grid.get_child(clampi(index, 0, count - 1))
	if target is Control:
		(target as Control).grab_focus()


static func _make_fish_texture() -> ImageTexture:
	var img := Image.new()
	if img.load_svg_from_string(FISH_ICON_SVG, 2.0) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _update_fish_label(total: int) -> void:
	_fish_label.text = "%d fish" % total


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()
