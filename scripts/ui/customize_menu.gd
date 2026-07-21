extends Control
## Cosmetic shop and locker: live 3D penguin preview on the left, category
## tabs and an item grid on the right. Purchases spend fish via Progression.

var _preview_pivot: Node3D
var _penguin: PenguinVisual
var _fish_label: Label
var _tab_buttons: Dictionary = {}  # category -> Button
var _item_grid: GridContainer
var _current_category: String = "body"


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
	_fish_label = Label.new()
	_fish_label.add_theme_font_size_override("font_size", 28)
	_fish_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_fish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_fish_label)
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

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.84, 0.95)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	viewport.add_child(light)

	var floe := MeshInstance3D.new()
	var floe_mesh := CylinderMesh.new()
	floe_mesh.top_radius = 0.9
	floe_mesh.bottom_radius = 1.05
	floe_mesh.height = 0.25
	floe.mesh = floe_mesh
	floe.material_override = PenguinVisual.get_material(Color(0.93, 0.96, 1.0), 0.0, 0.9)
	floe.position = Vector3(0, -0.125, 0)
	viewport.add_child(floe)

	_preview_pivot = Node3D.new()
	viewport.add_child(_preview_pivot)
	_penguin = PenguinVisual.new()
	_preview_pivot.add_child(_penguin)

	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
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


func _process(delta: float) -> void:
	if _preview_pivot != null:
		_preview_pivot.rotation.y += delta * 0.6
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
	tabs.add_theme_constant_override("separation", 8)
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
	_item_grid.add_theme_constant_override("h_separation", 10)
	_item_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_item_grid)


func _select_category(category: String) -> void:
	_current_category = category
	for cat: String in _tab_buttons.keys():
		var tab: Button = _tab_buttons[cat]
		tab.set_pressed_no_signal(cat == category)
	_rebuild_items()


func _rebuild_items() -> void:
	for child in _item_grid.get_children():
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
		status = "%d <> fish" % int(info.get("cost", 0))
	var text := "%s\n%s" % [String(info.get("name", id)), status]
	var button := UITheme.make_button(text, Vector2(0, 88), 21)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = String(info.get("desc", ""))
	if is_equipped:
		button.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	button.mouse_entered.connect(AudioManager.ui_hover)
	button.focus_entered.connect(AudioManager.ui_hover)
	button.pressed.connect(_on_item_pressed.bind(id))
	return button


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
	var focus_owner := get_viewport().gui_get_focus_owner()
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


func _update_fish_label(total: int) -> void:
	_fish_label.text = "<> %d fish" % total


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()
