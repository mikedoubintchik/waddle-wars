class_name FrontEndBackdrop
extends Control
## Lightweight premium front-end backdrop.
##
## One authored, opaque image is selected for portrait or landscape geometry,
## cropped around its landmark focal point, and drawn through Godot's built-in
## Canvas shader. There is no SubViewport, Node3D, particle system, or custom
## shader. A very small camera drift runs at 30 Hz; reduced-motion mode is
## completely static.

enum Context {
	TITLE,
	MENU,
	LOADING,
}

const LANDSCAPE_PATH: String = \
		"res://assets/art/ui/title_expedition_landscape_v1.png"
const PORTRAIT_PATH: String = \
		"res://assets/art/ui/title_expedition_portrait_v1.png"
const MOTION_STEP: float = 1.0 / 30.0
const MOTION_FOCAL_RANGE: Vector2 = Vector2(0.0045, 0.0030)
const MOTION_ZOOM: float = 0.009

static var _landscape_texture: Texture2D = null
static var _portrait_texture: Texture2D = null
static var _shade_texture: ImageTexture = null

@export var presentation_context: Context = Context.TITLE:
	set(value):
		presentation_context = value
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var shade_strength: float = 0.72:
	set(value):
		shade_strength = clampf(value, 0.0, 1.0)
		queue_redraw()
@export var motion_enabled: bool = true:
	set(value):
		motion_enabled = value
		_update_processing()
		queue_redraw()

var _elapsed: float = 0.0
var _motion_accumulator: float = 0.0
var _reduced_motion: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_reduced_motion = UITheme.reduced_motion()
	preload_assets()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_update_processing()
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	_motion_accumulator += delta
	if _motion_accumulator < MOTION_STEP:
		return
	_motion_accumulator = fmod(_motion_accumulator, MOTION_STEP)
	queue_redraw()


## Reconfigures one shared backdrop without rebuilding its tree.
func set_presentation(context: Context, dim: float = 0.72,
		allow_motion: bool = true) -> void:
	presentation_context = context
	shade_strength = dim
	motion_enabled = allow_motion


func set_reduced_motion(reduced: bool) -> void:
	_reduced_motion = reduced
	_update_processing()
	queue_redraw()


func is_motion_active() -> bool:
	return is_processing()


func is_using_portrait_art() -> bool:
	return _is_portrait(size)


func selected_texture_path() -> String:
	return PORTRAIT_PATH if is_using_portrait_art() else LANDSCAPE_PATH


## Public cache seam used by BootWarmup and focused asset tests.
static func preload_assets() -> Array[Texture2D]:
	if _landscape_texture == null and ResourceLoader.exists(LANDSCAPE_PATH):
		_landscape_texture = ResourceLoader.load(LANDSCAPE_PATH) as Texture2D
	if _portrait_texture == null and ResourceLoader.exists(PORTRAIT_PATH):
		_portrait_texture = ResourceLoader.load(PORTRAIT_PATH) as Texture2D
	return [_landscape_texture, _portrait_texture]


static func textures_ready() -> bool:
	return _landscape_texture != null and _portrait_texture != null


## Deterministic cover-crop helper. Exposed for headless contract tests.
static func cover_source_rect(texture_size: Vector2, target_size: Vector2,
		focal: Vector2 = Vector2(0.5, 0.5), zoom: float = 1.0) -> Rect2:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 \
			or target_size.x <= 0.0 or target_size.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var target_aspect := target_size.x / target_size.y
	var texture_aspect := texture_size.x / texture_size.y
	var source_size := texture_size
	if texture_aspect > target_aspect:
		source_size.x = texture_size.y * target_aspect
	else:
		source_size.y = texture_size.x / target_aspect
	var safe_zoom := maxf(zoom, 1.0)
	source_size /= safe_zoom
	var half := source_size * 0.5
	var center := Vector2(texture_size.x * clampf(focal.x, 0.0, 1.0),
		texture_size.y * clampf(focal.y, 0.0, 1.0))
	center.x = clampf(center.x, half.x, texture_size.x - half.x)
	center.y = clampf(center.y, half.y, texture_size.y - half.y)
	return Rect2(center - half, source_size)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var portrait := _is_portrait(size)
	var texture := _texture_for_orientation(portrait)
	if texture == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.055, 0.105), true)
		return

	var focal := Vector2(0.5, 0.50 if portrait else 0.52)
	var zoom := 1.0
	if is_motion_active():
		focal += Vector2(
			sin(_elapsed * 0.19) * MOTION_FOCAL_RANGE.x,
			cos(_elapsed * 0.16 + 0.7) * MOTION_FOCAL_RANGE.y)
		zoom += (0.5 + 0.5 * sin(_elapsed * 0.13 + 1.4)) * MOTION_ZOOM
	var source := cover_source_rect(Vector2(texture.get_size()), size, focal, zoom)
	draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), source,
		Color.WHITE, false, true)

	var context_scale := 1.0
	match presentation_context:
		Context.MENU:
			context_scale = 1.12
		Context.LOADING:
			context_scale = 1.28
	var shade_alpha := clampf(shade_strength * context_scale, 0.0, 1.0)
	if shade_alpha > 0.001:
		draw_texture_rect(_shade(), Rect2(Vector2.ZERO, size), false,
			Color(1.0, 1.0, 1.0, shade_alpha))


func _update_processing() -> void:
	set_process(is_inside_tree() and motion_enabled and not _reduced_motion \
		and not GameConfig.is_headless())


func _on_resized() -> void:
	queue_redraw()


static func _texture_for_orientation(portrait: bool) -> Texture2D:
	preload_assets()
	return _portrait_texture if portrait else _landscape_texture


static func _is_portrait(view_size: Vector2) -> bool:
	var view_class := LayoutProfile.classify(Vector2(maxf(view_size.x, 1.0),
		maxf(view_size.y, 1.0)))
	return view_class == LayoutProfile.ViewClass.PORTRAIT_NARROW \
		or view_class == LayoutProfile.ViewClass.PORTRAIT_TABLET


## One 1x128 baked luminance/alpha strip: light through the visual middle,
## dark behind top branding and bottom controls. Built once, shared forever.
static func _shade() -> ImageTexture:
	if _shade_texture != null:
		return _shade_texture
	var height := 128
	var image := Image.create_empty(1, height, false, Image.FORMAT_RGBA8)
	for y: int in height:
		var v := float(y) / float(height - 1)
		var top := pow(clampf(1.0 - v / 0.34, 0.0, 1.0), 1.6) * 0.42
		var bottom := pow(clampf((v - 0.56) / 0.44, 0.0, 1.0), 1.35) * 0.72
		var alpha := clampf(top + bottom, 0.0, 0.82)
		image.set_pixel(0, y, Color(0.015, 0.035, 0.075, alpha))
	_shade_texture = ImageTexture.create_from_image(image)
	return _shade_texture
