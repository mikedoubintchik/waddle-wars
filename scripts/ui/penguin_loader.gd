class_name PenguinLoader
extends Control
## Premium 2D expedition loading indicator.
##
## Public construction remains `PenguinLoader.new(size)`. Former live 3D
## SubViewport is replaced by one authored transparent character texture,
## baked radial glow, and ordinary Controls. Cheap while incoming scene builds;
## introduces no 3D shader programs.

const TEXTURE_PATH: String = \
		"res://assets/art/ui/loader_penguin_expedition_v1.png"
const CYCLE: float = 0.58
const UPDATE_STEP: float = 1.0 / 30.0

static var _loader_texture: Texture2D = null
static var _glow_texture: Texture2D = null

var penguin_size: float = 200.0

var _character_holder: Control = null
var _shadow: TextureRect = null
var _route_dots: Array[Panel] = []
var _start_ms: int = 0
var _time: float = 0.0
var _accumulator: float = 0.0
var _reduced_motion: bool = false
var _progress: float = -1.0


func _init(p_size: float = 200.0) -> void:
	penguin_size = maxf(p_size, 48.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	custom_minimum_size = Vector2(penguin_size, penguin_size)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_reduced_motion = UITheme.reduced_motion()
	_build()
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_update_pivots)
	_on_visibility_changed()
	_update_pivots.call_deferred()


## Optional determinate seam for SceneRouter. Negative returns to indeterminate.
func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0) if value >= 0.0 else -1.0
	_update_route()


func get_progress() -> float:
	return _progress


func set_reduced_motion(reduced: bool) -> void:
	_reduced_motion = reduced
	if reduced:
		_apply_static_pose()
	_update_processing()


func reset_animation() -> void:
	_start_ms = Time.get_ticks_msec()
	_time = 0.0
	_accumulator = 0.0
	if _reduced_motion:
		_apply_static_pose()


func is_motion_active() -> bool:
	return is_processing()


## Public cache seam used by BootWarmup and focused tests.
static func loader_texture() -> Texture2D:
	if _loader_texture == null and ResourceLoader.exists(TEXTURE_PATH):
		_loader_texture = ResourceLoader.load(TEXTURE_PATH) as Texture2D
	return _loader_texture


func _build() -> void:
	var glow := TextureRect.new()
	glow.name = "ExpeditionGlow"
	glow.texture = _radial_glow()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = penguin_size * 0.08
	glow.offset_top = penguin_size * 0.05
	glow.offset_right = -penguin_size * 0.08
	glow.offset_bottom = -penguin_size * 0.10
	glow.modulate = Color(0.38, 0.78, 1.0, 0.32)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	_shadow = TextureRect.new()
	_shadow.name = "ContactShadow"
	_shadow.texture = _radial_glow()
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	_shadow.anchor_left = 0.27
	_shadow.anchor_top = 0.75
	_shadow.anchor_right = 0.73
	_shadow.anchor_bottom = 0.86
	_shadow.modulate = Color(0.005, 0.015, 0.035, 0.62)
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)

	_character_holder = Control.new()
	_character_holder.name = "ExpeditionCourier"
	_character_holder.anchor_left = 0.12
	_character_holder.anchor_top = 0.01
	_character_holder.anchor_right = 0.88
	_character_holder.anchor_bottom = 0.83
	_character_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_character_holder)

	var penguin := TextureRect.new()
	penguin.name = "CourierArt"
	penguin.texture = loader_texture()
	penguin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	penguin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	penguin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	penguin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_holder.add_child(penguin)

	var route := Control.new()
	route.name = "ExpeditionRoute"
	route.anchor_left = 0.18
	route.anchor_top = 0.90
	route.anchor_right = 0.82
	route.anchor_bottom = 0.94
	route.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(route)

	for i: int in 3:
		var dot := Panel.new()
		dot.name = "Waypoint%d" % (i + 1)
		dot.anchor_left = float(i) * 0.5
		dot.anchor_right = float(i) * 0.5
		dot.anchor_top = 0.5
		dot.anchor_bottom = 0.5
		var side := maxf(penguin_size * 0.035, 5.0)
		dot.offset_left = -side * 0.5
		dot.offset_top = -side * 0.5
		dot.offset_right = side * 0.5
		dot.offset_bottom = side * 0.5
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.86, 0.95, 1.0, 0.94)
		style.border_color = Color(0.18, 0.44, 0.68, 0.95)
		style.set_border_width_all(maxi(1, roundi(side * 0.16)))
		style.set_corner_radius_all(roundi(side))
		dot.add_theme_stylebox_override("panel", style)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		route.add_child(dot)
		_route_dots.append(dot)

	_update_route()


func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < UPDATE_STEP:
		return
	_accumulator = fmod(_accumulator, UPDATE_STEP)
	_time = float(Time.get_ticks_msec() - _start_ms) * 0.001
	var phase := _time / CYCLE * TAU
	var lift := pow(absf(sin(phase)), 0.78)
	var hop := penguin_size * 0.034 * lift
	_character_holder.position = Vector2(
		sin(phase * 0.5) * penguin_size * 0.012, -hop)
	_character_holder.rotation = sin(phase * 0.5) * 0.030
	_character_holder.scale = Vector2(1.0 + lift * 0.012, 1.0 - lift * 0.010)

	_shadow.scale = Vector2(1.0 - lift * 0.13, 1.0 - lift * 0.05)
	_shadow.modulate.a = 0.62 - lift * 0.20
	_update_route()


func _update_route() -> void:
	if _route_dots.is_empty():
		return
	var amount := _progress
	if amount < 0.0:
		amount = 0.18 if _reduced_motion else 0.12 + 0.88 * \
			(0.5 + 0.5 * sin(_time * 1.65 - PI * 0.5))
	for i: int in _route_dots.size():
		var threshold := float(i) * 0.5
		var reached := amount + 0.03 >= threshold
		_route_dots[i].modulate = Color.WHITE if reached \
			else Color(0.48, 0.60, 0.74, 0.58)


func _apply_static_pose() -> void:
	if _character_holder != null:
		_character_holder.position = Vector2.ZERO
		_character_holder.rotation = 0.0
		_character_holder.scale = Vector2.ONE
	if _shadow != null:
		_shadow.scale = Vector2.ONE
		_shadow.modulate.a = 0.55
	_update_route()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		reset_animation()
	_update_processing()


func _update_processing() -> void:
	set_process(is_inside_tree() and is_visible_in_tree() \
		and not _reduced_motion and not GameConfig.is_headless())


func _update_pivots() -> void:
	if _character_holder != null:
		_character_holder.pivot_offset = _character_holder.size * Vector2(0.5, 0.82)
	if _shadow != null:
		_shadow.pivot_offset = _shadow.size * 0.5


static func _radial_glow() -> Texture2D:
	if _glow_texture != null:
		return _glow_texture
	var side := 96
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	for y: int in side:
		for x: int in side:
			var p := (Vector2(float(x), float(y)) / float(side - 1)) \
				* 2.0 - Vector2.ONE
			var alpha := pow(clampf(1.0 - p.length(), 0.0, 1.0), 2.2)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_glow_texture = ImageTexture.create_from_image(image)
	return _glow_texture
