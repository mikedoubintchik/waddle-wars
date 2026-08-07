extends Control
## The penguin dressing room: a live 3D preview as the hero, the equipped
## loadout beneath it, and a wardrobe of drawn swatch tiles on the right.
##
## Built in the shared menu language established by results.gd and main_menu.gd:
## eyebrow → headline → accent rule, radius-18 cards captioned with a small
## accent tick plus uppercase letter-spaced text, values in the display font
## over quiet captions, and exactly one promoted action in solid glacier blue —
## here the equip/buy button in the detail bar, which always states the fish
## cost of whatever is selected.

## Same drawn fish glyph as the race HUD and main menu currency counters
## (race_hud.gd / main_menu.gd) so fish read identically on every screen.
const FISH_ICON_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="60" height="40" viewBox="0 0 60 40">
<path d="M3 20 L19 8 L19 32 Z" fill="#6fc0ee"/>
<ellipse cx="34" cy="21" rx="21" ry="12" fill="#8fd8f8"/>
<path d="M26 11 Q35 3 44 11 Q35 15 26 11 Z" fill="#5fb0e2"/>
<path d="M20 21 Q34 31 50 22 Q34 27 20 21 Z" fill="#5fb0e2" opacity="0.7"/>
<circle cx="45" cy="17" r="3.2" fill="#0e2036"/>
<circle cx="46.2" cy="15.8" r="1.1" fill="#ffffff"/>
</svg>"""

const LOCK_ICON_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
<path d="M10 15 v-4.5 a6 6 0 0 1 12 0 V15" stroke="#f5c542" stroke-width="3" fill="none" stroke-linecap="round"/>
<rect x="6.5" y="14" width="19" height="13.5" rx="3.5" fill="#f5c542" stroke="#c98f1b" stroke-width="1.5"/>
<circle cx="16" cy="20.4" r="2.1" fill="#7a5a10"/>
<rect x="15" y="20.4" width="2" height="4" rx="1" fill="#7a5a10"/>
</svg>"""

## "Wear nothing" swatch: the only tile with no colour of its own.
const NONE_SWATCH_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<circle cx="32" cy="32" r="18" fill="none" stroke="#7d8ea0" stroke-width="3.5" opacity="0.85"/>
<path d="M19.5 44.5 L44.5 19.5" stroke="#7d8ea0" stroke-width="3.5" stroke-linecap="round" opacity="0.85"/>
</svg>"""

## Corner language, shared with results.gd: cards are soft, rows are tighter.
const RADIUS_CARD: int = 18
const RADIUS_ROW: int = 10

## Promoted-action face, matching the main menu's Play hero and results' Race
## Again, so "the button you probably want" looks identical everywhere.
const PRIMARY_FILL: Color = Color(0.129, 0.361, 0.588)
const PRIMARY_FILL_HOVER: Color = Color(0.192, 0.478, 0.741)

var _preview_pivot: Node3D
var _penguin: PenguinVisual
var _fish_label: Label
var _tab_buttons: Dictionary = {}  # category -> Button
var _item_grid: GridContainer
var _current_category: String = "body"
var _loadout_box: VBoxContainer
## Detail bar: the strip that names the selection and carries the one promoted
## action, so the cost of a locked item is never hidden inside a tooltip.
var _detail_swatch: TextureRect
var _detail_name: Label
var _detail_desc: Label
var _detail_action: Button
var _selected_id: String = ""
var _pending_buy_id: String = ""
## Live purchase-confirmation modal, or null (see _open_buy_dialog).
var _buy_dialog: Control = null
var _preview_trail: GPUParticles3D = null
var _sway_time: float = 0.0
## Extra enlargement for tall/narrow (portrait) viewports — see _tall_boost().
var _boost: float = 1.0
## Rasterize-once cache: switching category rebuilds every tile, and a phone
## re-rasterizing the same swatches on each tab press is pure jank.
static var _icon_cache: Dictionary = {}


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)
	_boost = _tall_boost()
	var portrait := _is_portrait()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var side := roundi(_u(32.0))
	margin.add_theme_constant_override("margin_left", side)
	margin.add_theme_constant_override("margin_right", side)
	margin.add_theme_constant_override("margin_top", _gap(20))
	margin.add_theme_constant_override("margin_bottom", _gap(20))
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	margin.add_child(layout)

	_build_header(layout)

	# Landscape: preview beside the wardrobe. Portrait: preview on top, because
	# two columns inside a phone's width leave neither of them usable.
	var columns: BoxContainer = VBoxContainer.new() if portrait else HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	layout.add_child(columns)
	_build_preview(columns, portrait)
	_build_wardrobe(columns, portrait)
	_build_detail_bar(layout)

	_update_fish_label(Progression.get_fish())
	Progression.fish_changed.connect(_update_fish_label)
	Progression.cosmetics_changed.connect(_on_cosmetics_changed)

	_refresh_preview()
	_refresh_loadout()
	_select_category("body")
	UITheme.attach_swipe_back(self, _go_back)
	var body_tab: Button = _tab_buttons["body"]
	body_tab.grab_focus()


## --- Layout scaling ---------------------------------------------------------
##
## The canvas_items/expand stretch pins the design width, so a portrait window
## keeps 1920 logical units across but gains logical height — every logical
## pixel then renders physically tiny. Enlarge by the ratio of live to design
## height on top of UITheme's touch step, exactly as main_menu/results do.
func _tall_boost() -> float:
	if GameConfig.is_headless() or not is_inside_tree():
		return 1.0
	var view_height := get_viewport_rect().size.y
	if view_height <= 0.0:
		return 1.0
	var design_height := 1080.0
	var window := get_window()
	if window != null and window.content_scale_size.y > 0:
		design_height = float(window.content_scale_size.y)
	return clampf(view_height / design_height, 1.0, 1.85)


func _f(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_font(size)) * _boost))


func _u(value: float) -> float:
	return UITheme.scaled(value) * _boost


func _gap(value: int) -> int:
	return maxi(1, roundi(float(UITheme.spacing(value)) * _boost))


func _is_portrait() -> bool:
	if GameConfig.is_headless() or not is_inside_tree():
		return false
	var view := get_viewport_rect().size
	return view.x > 0.0 and view.y > view.x * 1.05


## --- Shared building blocks -------------------------------------------------

func _caption(parent: Control, text: String, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Card shell: one radius, one border language, one padding rhythm.
func _make_card(parent: Control, pad: float = 16.0) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UITheme.make_panel_style(
		Color(0.063, 0.114, 0.204, 0.90), Color(UITheme.COLOR_ACCENT, 0.22))
	style.set_corner_radius_all(RADIUS_CARD)
	style.content_margin_left = _u(pad)
	style.content_margin_right = _u(pad)
	style.content_margin_top = _u(pad * 0.8)
	style.content_margin_bottom = _u(pad * 0.8)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0.0, 6.0)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


## Card caption: uppercase, letter-spaced, behind a short accent tick, so every
## card on every screen announces itself the same way.
func _card_title(parent: Control, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(10))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var tick := ColorRect.new()
	tick.color = Color(UITheme.COLOR_ACCENT, 0.85)
	tick.custom_minimum_size = Vector2(_u(4.0), _u(17.0))
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tick)
	_caption(row, text, 17, Color(0.72, 0.83, 0.94))


static func _cached_icon(svg: String) -> ImageTexture:
	if _icon_cache.has(svg):
		return _icon_cache[svg] as ImageTexture
	var texture := UITheme.make_icon(svg, 2.0)
	_icon_cache[svg] = texture
	return texture


## --- Header -----------------------------------------------------------------

func _build_header(parent: Control) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	parent.add_child(header)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override("separation", _gap(2))
	header.add_child(titles)
	_caption(titles, "Waddle Wars · Locker", 17, Color(UITheme.COLOR_ACCENT, 0.75))
	var title := UITheme.heading(
		"Dressing Room", roundi(float(UITheme.scaled_heading(46)) * _boost))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	titles.add_child(title)

	header.add_child(_build_fish_chip())

	var back_button := UITheme.make_button(
		"Back", UITheme.scaled_size(Vector2(160.0, 50.0)), _f(20))
	back_button.custom_minimum_size.y = _u(50.0)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_button.add_theme_color_override("font_color", Color(0.78, 0.86, 0.95))
	var back_icon := _cached_icon(UITheme.ICON_BACK)
	if back_icon != null:
		back_button.icon = back_icon
		back_button.expand_icon = true
		back_button.add_theme_constant_override("icon_max_width", roundi(_u(20.0)))
		back_button.add_theme_constant_override("h_separation", roundi(_u(10.0)))
	UITheme.hook_sounds(back_button)
	back_button.pressed.connect(_go_back)
	header.add_child(back_button)

	parent.add_child(UITheme.make_header_rule())


## Rounded glass pill with a soft gold rim — the same currency chip the main
## menu wears, so the wallet looks the same wherever it is shown.
func _build_fish_chip() -> Control:
	var chip := PanelContainer.new()
	var style := UITheme.make_panel_style(
		Color(0.055, 0.10, 0.18, 0.88), Color(UITheme.COLOR_GOLD, 0.5))
	style.set_corner_radius_all(roundi(_u(26.0)))
	style.content_margin_left = _u(20.0)
	style.content_margin_right = _u(20.0)
	style.content_margin_top = _u(7.0)
	style.content_margin_bottom = _u(7.0)
	style.shadow_size = 6
	chip.add_theme_stylebox_override("panel", style)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_u(10.0)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(row)
	var fish_tex := _cached_icon(FISH_ICON_SVG)
	if fish_tex != null:
		var fish_icon := TextureRect.new()
		fish_icon.texture = fish_tex
		fish_icon.custom_minimum_size = Vector2(_u(34.0), _u(23.0))
		fish_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fish_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fish_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(fish_icon)
	_fish_label = Label.new()
	_fish_label.add_theme_font_override("font", UITheme.display_font())
	_fish_label.add_theme_font_size_override("font_size", _f(24))
	_fish_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_fish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_fish_label)
	_caption(row, "fish", 13, Color(UITheme.COLOR_GOLD, 0.65))
	return chip


## --- 3D preview -------------------------------------------------------------

func _build_preview(parent: BoxContainer, portrait: bool) -> void:
	var card := _make_card(parent, 14.0)
	if portrait:
		card.custom_minimum_size.y = _preview_height()
	else:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Touch: the wardrobe carries the enlarged item tiles, so the preview
		# gives up part of its share of a phone's width.
		card.size_flags_stretch_ratio = 0.34 if UITheme.is_touch() else 0.40
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _gap(10))
	card.add_child(column)
	_card_title(column, "Your Penguin")

	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size.y = _u(220.0)
	column.add_child(container)

	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = SettingsManager.msaa_3d_mode() as Viewport.MSAA
	container.add_child(viewport)
	UITheme.crisp_subviewport(viewport, self)

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

	# What the penguin is actually wearing, right under the thing wearing it —
	# the old screen left this column half empty and never named the loadout.
	_loadout_box = VBoxContainer.new()
	_loadout_box.add_theme_constant_override("separation", _gap(4))
	column.add_child(_loadout_box)


## Height the preview card takes on a stacked (portrait) layout: enough to read
## as the hero, never so much that the wardrobe is pushed off screen.
func _preview_height() -> float:
	if GameConfig.is_headless() or not is_inside_tree():
		return 420.0
	return clampf(get_viewport_rect().size.y * 0.30, 320.0, 1100.0)


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


func _process(delta: float) -> void:
	if _preview_pivot != null:
		# Gentle sway instead of a full spin: starts front-facing (sin 0 = 0)
		# and keeps the face toward the camera while showing off the sides.
		_sway_time += delta
		_preview_pivot.rotation.y = sin(_sway_time * 0.55) * 0.55
	if _penguin != null:
		_penguin.tick(delta, 0.0)


## Equipped-loadout list under the preview: one quiet row per slot, so the
## player can read what they are wearing without cycling every tab.
func _refresh_loadout() -> void:
	if _loadout_box == null:
		return
	for child in _loadout_box.get_children():
		_loadout_box.remove_child(child)
		child.queue_free()
	for category: String in CosmeticsDB.CATEGORIES:
		var equipped_id := Progression.get_equipped(category)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _gap(8))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_loadout_box.add_child(row)
		var slot := _caption(row, String(CosmeticsDB.CATEGORY_NAMES.get(category, category)),
			13, Color(0.52, 0.65, 0.80))
		slot.custom_minimum_size.x = _u(96.0)
		var value := Label.new()
		if equipped_id == "":
			value.text = "—"
			value.add_theme_color_override("font_color", Color(0.45, 0.54, 0.66))
		else:
			value.text = String(CosmeticsDB.get_item(equipped_id).get("name", equipped_id))
			value.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
		value.add_theme_font_override("font", UITheme.bold_font())
		value.add_theme_font_size_override("font_size", _f(16))
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.clip_text = true
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(value)


## --- Wardrobe ---------------------------------------------------------------

func _build_wardrobe(parent: BoxContainer, portrait: bool) -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not portrait:
		right.size_flags_stretch_ratio = 0.66 if UITheme.is_touch() else 0.60
	right.add_theme_constant_override("separation", _gap(10))
	parent.add_child(right)

	# Segmented category strip: the active tab is a filled accent pill rather
	# than another identical glass button, so "where am I" is instant.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", _gap(6))
	right.add_child(tabs)
	for category: String in CosmeticsDB.CATEGORIES:
		var tab := Button.new()
		tab.text = String(CosmeticsDB.CATEGORY_NAMES[category])
		tab.custom_minimum_size = Vector2(0.0, _u(46.0))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		tab.add_theme_font_override("font", UITheme.bold_font())
		tab.add_theme_font_size_override("font_size", _f(18))
		_style_tab(tab)
		UITheme.hook_sounds(tab)
		tab.pressed.connect(_select_category.bind(category))
		tabs.add_child(tab)
		_tab_buttons[category] = tab

	var scroll := ScrollContainer.new()
	# Tiles are buttons, which swallow touch drags before the ScrollContainer
	# can see them; this restores dragging the grid on a phone.
	TouchScroll.attach(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	right.add_child(scroll)

	_item_grid = GridContainer.new()
	_item_grid.columns = 2 if portrait else 3
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_grid.add_theme_constant_override("h_separation", _gap(10))
	_item_grid.add_theme_constant_override("v_separation", _gap(10))
	scroll.add_child(_item_grid)


func _style_tab(tab: Button) -> void:
	var radius := roundi(_u(23.0))
	var quiet := StyleBoxFlat.new()
	quiet.bg_color = Color(0.086, 0.149, 0.251, 0.62)
	quiet.border_color = Color(UITheme.COLOR_ACCENT, 0.14)
	quiet.set_border_width_all(1)
	quiet.set_corner_radius_all(radius)
	var hover := quiet.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.145, 0.231, 0.365, 0.85)
	hover.border_color = Color(UITheme.COLOR_ACCENT, 0.55)
	var active := StyleBoxFlat.new()
	active.bg_color = Color(UITheme.COLOR_ACCENT.r, UITheme.COLOR_ACCENT.g, UITheme.COLOR_ACCENT.b, 0.20)
	active.border_color = Color(UITheme.COLOR_ACCENT, 0.85)
	active.set_border_width_all(2)
	active.set_corner_radius_all(radius)
	active.shadow_color = Color(UITheme.COLOR_ACCENT, 0.22)
	active.shadow_size = 6
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(0.72, 0.92, 1.0)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(radius)
	focus.set_expand_margin_all(2.0)
	tab.add_theme_stylebox_override("normal", quiet)
	tab.add_theme_stylebox_override("hover", hover)
	tab.add_theme_stylebox_override("pressed", active)
	tab.add_theme_stylebox_override("hover_pressed", active)
	tab.add_theme_stylebox_override("focus", focus)
	tab.add_theme_color_override("font_color", Color(0.70, 0.80, 0.92))
	tab.add_theme_color_override("font_hover_color", Color.WHITE)
	tab.add_theme_color_override("font_pressed_color", UITheme.COLOR_ACCENT)
	tab.add_theme_color_override("font_hover_pressed_color", Color.WHITE)


func _select_category(category: String) -> void:
	_current_category = category
	for cat: String in _tab_buttons.keys():
		var tab: Button = _tab_buttons[cat]
		tab.set_pressed_no_signal(cat == category)
	_rebuild_items()
	# Open on whatever is currently worn in this slot, so the detail bar always
	# describes something real instead of sitting blank.
	_select_item(Progression.get_equipped(category))


func _rebuild_items() -> void:
	for child: Node in _item_grid.get_children():
		_item_grid.remove_child(child)
		child.queue_free()
	if _current_category != "body":
		_item_grid.add_child(_make_item_tile(""))
	for id: String in CosmeticsDB.items_in_category(_current_category):
		_item_grid.add_child(_make_item_tile(id))


## --- Swatches ---------------------------------------------------------------

static func _hex(color: Color) -> String:
	return "#%s" % color.to_html(false)


## Drawn preview of a cosmetic, tinted by the item's own colour. A wardrobe has
## to show the clothes; a list of names is a settings screen.
func _swatch_svg(id: String) -> String:
	if id == "":
		return NONE_SWATCH_SVG
	var info := CosmeticsDB.get_item(id)
	var category := String(info.get("category", ""))
	match category:
		"body":
			return _body_swatch(info)
		"hat":
			return _hat_swatch(info.get("color", UITheme.COLOR_ACCENT) as Color)
		"scarf":
			return _scarf_swatch(info.get("color", UITheme.COLOR_ACCENT) as Color)
		"goggles":
			return _goggles_swatch(info.get("color", UITheme.COLOR_ACCENT) as Color)
		"trail":
			return _trail_swatch(info.get("color", UITheme.COLOR_ACCENT) as Color)
	return NONE_SWATCH_SVG


## Penguin bust in the species' real dorsal/belly/bill colours, so the body tab
## reads as a row of penguins rather than a row of words.
func _body_swatch(info: Dictionary) -> String:
	var dorsal := info.get("body_color", Color(0.13, 0.16, 0.22)) as Color
	var belly := info.get("belly_color", Color(0.95, 0.94, 0.9)) as Color
	var species := String(info.get("species", ""))
	var sp: Dictionary = PenguinVisual.SPECIES.get(species, {})
	var bill := sp.get("bill_color", Color(0.92, 0.62, 0.20)) as Color
	var crest := ""
	if info.has("crest_color") or sp.has("crest_color"):
		var crest_color := info.get("crest_color", sp.get("crest_color", Color(0.98, 0.82, 0.2))) as Color
		crest = "<path d=\"M17 17 Q25 5 37 10\" stroke=\"%s\" stroke-width=\"4.5\" fill=\"none\" stroke-linecap=\"round\"/>" % _hex(crest_color)
	elif sp.has("patch"):
		var patch := sp.get("patch", Color(0.98, 0.76, 0.22)) as Color
		crest = "<ellipse cx=\"20.5\" cy=\"27\" rx=\"3.6\" ry=\"5\" fill=\"%s\"/>" % _hex(patch)
	return """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<ellipse cx="32" cy="47" rx="20" ry="17" fill="%s"/>
<ellipse cx="32" cy="50" rx="13" ry="14" fill="%s"/>
<circle cx="32" cy="24" r="15" fill="%s"/>
<ellipse cx="33" cy="31" rx="9.5" ry="7" fill="%s"/>
%s
<path d="M27 26 L46 29.5 L27 33 Z" fill="%s"/>
<circle cx="25.5" cy="21.5" r="2.7" fill="#0d131f"/>
<circle cx="26.5" cy="20.6" r="1.0" fill="#ffffff"/>
</svg>""" % [_hex(dorsal), _hex(belly), _hex(dorsal), _hex(belly), crest, _hex(bill)]


func _hat_swatch(color: Color) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<circle cx="32" cy="16" r="5" fill="%s"/>
<path d="M13 41 C13 23 51 23 51 41 Z" fill="%s"/>
<rect x="9" y="39" width="46" height="11" rx="5.5" fill="%s"/>
<path d="M22 41 C22 29 24 25 26 23" stroke="%s" stroke-width="2" fill="none" opacity="0.55"/>
</svg>""" % [_hex(color.lightened(0.35)), _hex(color), _hex(color.lightened(0.22)),
		_hex(color.lightened(0.6))]


func _scarf_swatch(color: Color) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M11 24 Q32 40 53 24 L53 35 Q32 51 11 35 Z" fill="%s"/>
<path d="M36 44 L49 39 L54 55 L41 60 Z" fill="%s"/>
<path d="M11 30 Q32 46 53 30" stroke="%s" stroke-width="1.8" fill="none" opacity="0.5"/>
</svg>""" % [_hex(color), _hex(color.darkened(0.22)), _hex(color.lightened(0.5))]


func _goggles_swatch(color: Color) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<rect x="4" y="28" width="8" height="8" rx="2.5" fill="#2f4256"/>
<rect x="52" y="28" width="8" height="8" rx="2.5" fill="#2f4256"/>
<rect x="8" y="22" width="48" height="20" rx="10" fill="#22303f"/>
<rect x="12" y="26" width="18" height="12" rx="6" fill="%s"/>
<rect x="34" y="26" width="18" height="12" rx="6" fill="%s"/>
<path d="M15 30 L22 27" stroke="#ffffff" stroke-width="2" opacity="0.55" stroke-linecap="round"/>
</svg>""" % [_hex(color), _hex(color)]


func _trail_swatch(color: Color) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M32 9 L36 27 L54 31 L36 35 L32 53 L28 35 L10 31 L28 27 Z" fill="%s"/>
<circle cx="14" cy="14" r="3.2" fill="%s" opacity="0.75"/>
<circle cx="51" cy="47" r="2.6" fill="%s" opacity="0.6"/>
<circle cx="50" cy="13" r="2.0" fill="%s" opacity="0.5"/>
</svg>""" % [_hex(color), _hex(color.lightened(0.3)), _hex(color.lightened(0.3)),
		_hex(color.lightened(0.3))]


func _make_swatch_rect(id: String, side: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = _cached_icon(_swatch_svg(id))
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## --- Item tiles -------------------------------------------------------------

## One wardrobe tile: a drawn swatch over the item's name and its state. Locked
## items dim the swatch, wear a padlock and state their price in a gold fish
## pill, so cost is never hidden behind a hover tooltip.
func _make_item_tile(id: String) -> Button:
	var is_none := id == ""
	var info := CosmeticsDB.get_item(id) if not is_none else {}
	var unlocked := is_none or Progression.is_cosmetic_unlocked(id)
	var equipped_id := Progression.get_equipped(_current_category)
	var is_equipped := equipped_id == id
	var cost := int(info.get("cost", 0))
	var affordable := unlocked or Progression.get_fish() >= cost
	var item_name := "None" if is_none else String(info.get("name", id))
	var desc := "Wear nothing in this category." if is_none else String(info.get("desc", ""))

	var button := Button.new()
	button.set_meta("cosmetic_id", id)
	button.custom_minimum_size = Vector2(0.0, _u(152.0))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = desc
	button.focus_mode = Control.FOCUS_ALL
	var fill := Color(0.063, 0.114, 0.204, 0.90)
	var rim := Color(UITheme.COLOR_ACCENT, 0.20)
	if is_equipped:
		fill = Color(UITheme.COLOR_GOLD.r, UITheme.COLOR_GOLD.g, UITheme.COLOR_GOLD.b, 0.13)
		rim = Color(UITheme.COLOR_GOLD, 0.70)
	elif not unlocked:
		fill = Color(0.047, 0.078, 0.141, 0.85)
		rim = Color(UITheme.COLOR_GOLD, 0.26) if affordable else Color(0.45, 0.52, 0.62, 0.20)
	button.add_theme_stylebox_override("normal", _tile_style(fill, rim, 2 if is_equipped else 1, 8))
	button.add_theme_stylebox_override("hover", _tile_style(
		fill.lightened(0.10), Color(0.90, 0.98, 1.0, 0.95), 2, 14))
	button.add_theme_stylebox_override("pressed", _tile_style(
		fill.darkened(0.30), Color(UITheme.COLOR_GOLD, 0.9), 2, 3))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(0.72, 0.92, 1.0)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(RADIUS_CARD)
	focus.set_expand_margin_all(3.0)
	button.add_theme_stylebox_override("focus", focus)
	UITheme.attach_hover_scale(button, 1.03)
	UITheme.attach_hover_glow(button, UITheme.COLOR_GOLD if not unlocked else UITheme.COLOR_ACCENT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := roundi(_u(10.0))
	margin.add_theme_constant_override("margin_left", inset)
	margin.add_theme_constant_override("margin_right", inset)
	margin.add_theme_constant_override("margin_top", inset)
	margin.add_theme_constant_override("margin_bottom", inset)
	button.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _gap(4))
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var swatch_row := CenterContainer.new()
	swatch_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(swatch_row)
	var swatch := _make_swatch_rect(id, _u(62.0))
	if not unlocked:
		swatch.modulate = Color(1.0, 1.0, 1.0, 0.40)
	swatch_row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = item_name
	name_label.add_theme_font_override("font", UITheme.bold_font())
	name_label.add_theme_font_size_override("font_size", _f(18))
	name_label.add_theme_color_override("font_color",
		UITheme.COLOR_GOLD if is_equipped else (
			UITheme.COLOR_TEXT if unlocked else Color(0.72, 0.80, 0.90)))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	var state := CenterContainer.new()
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(state)
	if is_equipped:
		_state_pill(state, "Equipped", UITheme.COLOR_GOLD, true, false)
	elif unlocked:
		_state_pill(state, "Owned", Color(0.55, 0.68, 0.82), false, false)
	else:
		_state_pill(state, str(cost),
			UITheme.COLOR_GOLD if affordable else UITheme.COLOR_DISABLED, true, true)

	# Padlock badge in the corner: state is readable at a glance even when the
	# tile's text is scanned past.
	if not unlocked:
		var lock_tex := _cached_icon(LOCK_ICON_SVG)
		if lock_tex != null:
			var lock := TextureRect.new()
			lock.texture = lock_tex
			lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lock.anchor_left = 1.0
			lock.anchor_right = 1.0
			lock.offset_left = -_u(32.0)
			lock.offset_right = -_u(10.0)
			lock.offset_top = _u(10.0)
			lock.offset_bottom = _u(32.0)
			lock.modulate = Color(1.0, 1.0, 1.0, 1.0 if affordable else 0.5)
			button.add_child(lock)

	UITheme.hook_sounds(button)
	var focus_item := func() -> void:
		_select_item(id)
	button.mouse_entered.connect(focus_item)
	button.focus_entered.connect(focus_item)
	button.pressed.connect(_on_item_pressed.bind(id))
	return button


static func _tile_style(bg: Color, border: Color, width: int, shadow: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(RADIUS_CARD)
	box.content_margin_left = 0.0
	box.content_margin_right = 0.0
	box.content_margin_top = 0.0
	box.content_margin_bottom = 0.0
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0.0, 4.0)
	return box


## Small status pill under a tile's name. `with_fish` prefixes the shared fish
## glyph, which is what turns "350" into a price.
func _state_pill(parent: Control, text: String, tint: Color, filled: bool,
		with_fish: bool) -> void:
	var pill := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint.r, tint.g, tint.b, 0.18) if filled else Color(1.0, 1.0, 1.0, 0.05)
	style.border_color = Color(tint, 0.55 if filled else 0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(_u(11.0)))
	style.content_margin_left = _u(10.0)
	style.content_margin_right = _u(10.0)
	style.content_margin_top = _u(1.0)
	style.content_margin_bottom = _u(1.0)
	pill.add_theme_stylebox_override("panel", style)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_u(5.0)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	if with_fish:
		var fish_tex := _cached_icon(FISH_ICON_SVG)
		if fish_tex != null:
			var fish := TextureRect.new()
			fish.texture = fish_tex
			fish.custom_minimum_size = Vector2(_u(21.0), _u(14.0))
			fish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fish.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			fish.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			fish.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(fish)
	_caption(row, text, 13, tint)


## --- Detail bar -------------------------------------------------------------

## The strip that names the selection, describes it, and carries the single
## promoted action. Replaces the old hover-only tooltip and the bare
## description line: on touch there is no hover, so the price has to live here.
func _build_detail_bar(parent: Control) -> void:
	var card := _make_card(parent, 16.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(14))
	card.add_child(row)

	_detail_swatch = _make_swatch_rect("", _u(52.0))
	_detail_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_detail_swatch)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", _gap(2))
	row.add_child(text_box)
	_detail_name = Label.new()
	_detail_name.add_theme_font_override("font", UITheme.display_font())
	_detail_name.add_theme_font_size_override("font_size", _f(24))
	_detail_name.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_detail_name.clip_text = true
	text_box.add_child(_detail_name)
	_detail_desc = Label.new()
	_detail_desc.add_theme_font_size_override("font_size", _f(17))
	_detail_desc.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_desc.max_lines_visible = 2
	text_box.add_child(_detail_desc)

	_detail_action = UITheme.make_button(
		"Equip", UITheme.scaled_size(Vector2(250.0, 54.0)), _f(21))
	_detail_action.custom_minimum_size = Vector2(_u(250.0), _u(54.0))
	_detail_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_primary(_detail_action)
	UITheme.hook_sounds(_detail_action)
	_detail_action.pressed.connect(func() -> void:
		_on_item_pressed(_selected_id))
	row.add_child(_detail_action)


## Filled ice-blue treatment for the promoted action, matching the main menu's
## Play hero and results' Race Again so the family stays coherent.
func _style_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal",
		_primary_box(PRIMARY_FILL, Color(UITheme.COLOR_ACCENT, 0.85), 8))
	button.add_theme_stylebox_override("hover",
		_primary_box(PRIMARY_FILL_HOVER, Color(0.90, 0.98, 1.0, 0.95), 14))
	button.add_theme_stylebox_override("pressed",
		_primary_box(PRIMARY_FILL.darkened(0.35), Color(UITheme.COLOR_GOLD, 0.9), 2))
	button.add_theme_stylebox_override("disabled",
		_primary_box(Color(0.10, 0.14, 0.20, 0.75), Color(0.45, 0.52, 0.62, 0.35), 0))
	button.add_theme_color_override("font_color", Color(0.98, 0.995, 1.0))
	button.add_theme_color_override("font_disabled_color", UITheme.COLOR_DISABLED)


static func _primary_box(bg: Color, border: Color, shadow: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	box.content_margin_left = 20.0
	box.content_margin_right = 20.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	box.shadow_color = Color(UITheme.COLOR_ACCENT, 0.30)
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0.0, 3.0)
	return box


## Points the detail bar at an item (or "" for the wear-nothing entry) and
## relabels the promoted action to exactly what pressing it will do.
func _select_item(id: String) -> void:
	_selected_id = id
	if _detail_name == null:
		return
	var is_none := id == ""
	var info := CosmeticsDB.get_item(id) if not is_none else {}
	var slot := String(CosmeticsDB.CATEGORY_NAMES.get(_current_category, _current_category))
	_detail_name.text = "No %s" % slot if is_none else String(info.get("name", id))
	_detail_desc.text = ("Wear nothing in this slot." if is_none
		else String(info.get("desc", "")))
	_detail_swatch.texture = _cached_icon(_swatch_svg(id))
	var unlocked := is_none or Progression.is_cosmetic_unlocked(id)
	var cost := int(info.get("cost", 0))
	var equipped := Progression.get_equipped(_current_category) == id
	_detail_swatch.modulate = Color(1.0, 1.0, 1.0, 1.0 if unlocked else 0.45)
	_detail_action.disabled = false
	if equipped:
		_detail_action.text = "Equipped"
		_detail_action.disabled = true
	elif unlocked:
		_detail_action.text = "Equip"
	elif _pending_buy_id == id:
		_detail_action.text = "Confirm · %d fish" % cost
	elif Progression.get_fish() < cost:
		_detail_action.text = "Need %d more fish" % (cost - Progression.get_fish())
		_detail_action.disabled = true
	else:
		_detail_action.text = "Buy · %d fish" % cost


## Status line override used by the purchase flow ("select again to confirm",
## "not enough fish"). Kept as its own entry point so the buy confirmation can
## talk to the player without rebuilding the whole detail bar.
func _show_item_desc(text: String) -> void:
	if _detail_desc != null:
		_detail_desc.text = text


func _on_item_pressed(id: String) -> void:
	if id == "":
		_pending_buy_id = ""
		AudioManager.ui_click()
		Progression.equip(_current_category, "")
		return
	var info := CosmeticsDB.get_item(id)
	var category := String(info.get("category", _current_category))
	if Progression.is_cosmetic_unlocked(id):
		_pending_buy_id = ""
		AudioManager.ui_click()
		if Progression.get_equipped(category) == id and category != "body":
			Progression.equip(category, "")
		else:
			Progression.equip(category, id)
		return
	# Spending fish is irreversible, so it takes a real confirmation.
	#
	# This used to be "press the same control again", with the question printed
	# in the detail bar at the bottom of the screen. Two presses on a tile is
	# how a player browses -- click to look, click again because nothing
	# obvious happened -- and the question was nowhere near the thing being
	# clicked, so the fish were gone before it had been read. A dialog costs
	# one deliberate action and cannot be triggered by a double click.
	var cost := int(info.get("cost", 0))
	AudioManager.ui_click()
	_select_item(id)
	if Progression.get_fish() < cost:
		_show_item_desc("Not enough fish — %s costs %d." % [String(info.get("name", id)), cost])
		return
	_open_buy_dialog(id, category, String(info.get("name", id)), cost)


## Modal purchase confirmation: what is being bought, what it costs, and what
## the player is left with. Cancel takes focus, so a stray Enter or a tap on
## the scrim backs out rather than spending.
func _open_buy_dialog(id: String, category: String, item_name: String, cost: int) -> void:
	if _buy_dialog != null:
		return
	_pending_buy_id = id

	_buy_dialog = Control.new()
	_buy_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_buy_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_buy_dialog)

	var scrim := ColorRect.new()
	scrim.color = Color(0.01, 0.02, 0.05, 0.72)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_buy_dialog.add_child(scrim)
	scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_close_buy_dialog())

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buy_dialog.add_child(centre)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.make_card_style())
	card.custom_minimum_size.x = _u(430.0)
	centre.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _gap(12))
	card.add_child(column)

	_caption(column, "CONFIRM PURCHASE", 14, Color(UITheme.COLOR_ACCENT, 0.85),
		HORIZONTAL_ALIGNMENT_CENTER)

	var title := Label.new()
	title.text = item_name
	title.add_theme_font_override("font", UITheme.display_font())
	title.add_theme_font_size_override("font_size", _f(30))
	title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)

	var price := Label.new()
	price.text = "%d fish — you'll have %d left" % [cost, maxi(Progression.get_fish() - cost, 0)]
	price.add_theme_font_size_override("font_size", _f(19))
	price.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(price)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", _gap(10))
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)

	var cancel := UITheme.make_button("Cancel", Vector2(_u(170.0), _u(50.0)), _f(20))
	UITheme.hook_sounds(cancel)
	cancel.pressed.connect(_close_buy_dialog)
	buttons.add_child(cancel)

	var confirm := UITheme.make_button("Buy", Vector2(_u(170.0), _u(50.0)), _f(20))
	UITheme.style_primary(confirm)
	UITheme.hook_sounds(confirm)
	confirm.pressed.connect(func() -> void: _commit_buy(id, category))
	buttons.add_child(confirm)

	cancel.grab_focus()


func _close_buy_dialog() -> void:
	_pending_buy_id = ""
	if _buy_dialog == null:
		return
	_buy_dialog.queue_free()
	_buy_dialog = null
	var tile := _tile_for_id(_selected_id)
	if tile != null:
		tile.grab_focus()


func _commit_buy(id: String, category: String) -> void:
	_close_buy_dialog()
	if Progression.try_unlock_cosmetic(id):
		Progression.equip(category, id)
	else:
		# Balance changed underneath the dialog (another screen paid out).
		AudioManager.play_sfx("sfx_ui_select", 0.6, -6.0)
		_show_item_desc("Purchase failed — not enough fish.")


func _tile_for_id(id: String) -> Control:
	if _item_grid == null:
		return null
	for child: Node in _item_grid.get_children():
		if child is Control and (child as Control).has_meta("cosmetic_id") \
				and String((child as Control).get_meta("cosmetic_id")) == id:
			return child as Control
	return null


func _on_cosmetics_changed() -> void:
	_refresh_preview()
	_refresh_loadout()
	var focused_index := -1
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and focus_owner.get_parent() == _item_grid:
		focused_index = focus_owner.get_index()
	_rebuild_items()
	_select_item(_selected_id)
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
	_fish_label.text = "%d" % total
	# Affordability changes what the tiles and the promoted action say.
	if _item_grid != null and _item_grid.is_inside_tree():
		_rebuild_items()
		_select_item(_selected_id)


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		# Escape backs out of the purchase first; leaving the whole screen
		# while a confirmation is open would be a surprising second meaning.
		if _buy_dialog != null:
			_close_buy_dialog()
			return
		_go_back()
