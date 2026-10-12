extends Control
## Live state layered on a clean painted map. Selection never awards progress.
signal region_selected(index: int)

const ROOT := "res://assets/art/ui/menu/mission_map_v7/"
var progress: Dictionary = {}
var points: Array[Vector2] = []
var hero: TextureRect
var selected_region := -1
var _buttons: Array[Button] = []
var _bends: Array = []
var _twilight_landmark: TextureRect

static func background(portrait: bool) -> Texture2D:
	return ExpeditionMenuStyle._material_texture(ROOT + ("missions_background_portrait_v7.webp" if portrait else "missions_background_desktop_v7.webp"))

func configure(portrait: bool, state: Dictionary) -> void:
	progress = state.duplicate(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_twilight_landmark = TextureRect.new()
	_twilight_landmark.name = "TwilightLandmark"
	_twilight_landmark.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/mission_map_v8/twilight_landmark_v8.webp")
	_twilight_landmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_twilight_landmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_twilight_landmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_twilight_landmark)
	points.assign([Vector2(0.141,0.373),Vector2(0.375,0.491),Vector2(0.633,0.535),Vector2(0.884,0.420)] if portrait else \
		[Vector2(0.150,0.424),Vector2(0.382,0.552),Vector2(0.633,0.595),Vector2(0.867,0.494)])
	# Follow the authored dotted route rather than cutting across its bends.
	_bends = [[points[0],Vector2(0.22,0.415),Vector2(0.29,0.49),points[1]],
		[points[1],Vector2(0.51,0.507),Vector2(0.58,0.54),points[2]],
		[points[2],Vector2(0.74,0.545),Vector2(0.80,0.46),points[3]]] if portrait else \
		[[points[0],Vector2(0.22,0.455),Vector2(0.29,0.55),points[1]],
		[points[1],Vector2(0.52,0.57),Vector2(0.60,0.60),points[2]],
		[points[2],Vector2(0.73,0.61),Vector2(0.80,0.535),points[3]]]
	var atlas := ExpeditionMenuStyle._material_texture(ROOT + "mission_route_markers_v7.webp")
	var cell := Vector2(atlas.get_width()/3.0,atlas.get_height())
	for index: int in 4:
		var entry: Dictionary = progress["regions"][index]
		var button := Button.new()
		button.name = "RouteDestination%d" % index
		button.set_meta("region_index",index)
		button.set_meta("unlocked",entry["unlocked"])
		button.accessibility_name = String(entry["name"]) + (" — discovered" if entry["unlocked"] else " — locked: reach %s m in one run" % RunnerMissions._group(int(entry["required_metres"])))
		button.tooltip_text = button.accessibility_name
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for style: String in ["normal","hover","pressed","hover_pressed"]:
			button.add_theme_stylebox_override(style,StyleBoxEmpty.new())
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color(1,1,1,0.12)
		focus.border_color = Color("fff7dc")
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(64)
		button.add_theme_stylebox_override("focus",focus)
		button.pressed.connect(select_region.bind(index))
		add_child(button)
		_buttons.append(button)
		var icon := TextureRect.new()
		icon.name = "RouteStatus"
		var region := AtlasTexture.new()
		region.atlas = atlas
		region.region = Rect2(Vector2(cell.x * (1 if entry["current"] else (0 if entry["unlocked"] else 2)),0),cell)
		region.filter_clip = true
		icon.texture = region
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(icon)
	hero = TextureRect.new()
	hero.name = "MissionMapPenguin"
	hero.texture = ExpeditionMenuStyle._material_texture(ROOT + "mission_penguin_marker_v7.webp")
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.set_meta("route_position",progress["route_position"])
	add_child(hero)
	resized.connect(_place)
	_place()

func _place() -> void:
	if hero == null: return
	# A standalone landmark gives Twilight the same visual presence as the
	# ice, cave and aurora destinations, while leaving its live lock unobscured.
	_twilight_landmark.size = Vector2(size.x * 0.25, size.y * 0.43)
	_twilight_landmark.position = points[1] * size - Vector2(_twilight_landmark.size.x * 0.5, _twilight_landmark.size.y * 1.03)
	var diameter := size.x * 0.091
	for index: int in _buttons.size():
		_buttons[index].size = Vector2.ONE * diameter
		_buttons[index].position = points[index] * size - _buttons[index].size * 0.5
	var position_on_route := float(progress["route_position"])
	var from := mini(floori(position_on_route),2)
	var blend := clampf(position_on_route - from,0.0,1.0)
	var leg: Array = _bends[from]
	var piece := mini(2,floori(blend * 3.0))
	var at: Vector2 = (leg[piece] as Vector2).lerp(leg[piece+1],clampf(blend * 3.0 - piece,0.0,1.0)) * size
	hero.size = Vector2.ONE * size.x * 0.165
	# Source has generous transparent margins. Its feet sit just above the node.
	hero.position = at - Vector2(hero.size.x * 0.5,hero.size.y * 0.86 + diameter * 0.22)

func select_region(index: int) -> void:
	if index < 0 or index >= _buttons.size(): return
	selected_region = index
	set_meta("selected_region",index)
	region_selected.emit(index)
