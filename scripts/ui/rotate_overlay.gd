class_name RotateOverlay
extends CanvasLayer
## Full-screen "rotate your device" prompt for touchscreen devices held in
## portrait. Self-contained: any scene (race or menus) can simply
## add_child(RotateOverlay.new()) with no further wiring.
##
## Shows itself while the viewport aspect ratio is portrait (< 1.0) on a
## touchscreen device, hides automatically in landscape, and never activates
## on desktop or headless. When hidden it swallows no input (the invisible
## Control tree receives none); when shown its backdrop blocks input so taps
## do not reach the game underneath. The glyph is drawn procedurally: no
## assets.

const PORTRAIT_ASPECT: float = 1.0

var _root: Control = null
var _glyph: RotateGlyph = null
var _time: float = 0.0


## Procedurally drawn phone outline with a curved rotation arrow.
class RotateGlyph:
	extends Control

	var rock: float = 0.0  ## Rocking angle (radians), animated by the overlay.

	var _body_style := StyleBoxFlat.new()
	var _screen_style := StyleBoxFlat.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body_style.bg_color = Color(0.10, 0.14, 0.22)
		_body_style.set_corner_radius_all(18)
		_body_style.set_border_width_all(5)
		_body_style.border_color = Color(0.92, 0.96, 1.0)
		_screen_style.bg_color = Color(0.30, 0.55, 0.85, 0.5)
		_screen_style.set_corner_radius_all(8)

	func _draw() -> void:
		var center := size * 0.5
		var accent := Color(0.92, 0.96, 1.0)
		# Phone body, rocked around its centre to suggest rotation.
		draw_set_transform(center, rock, Vector2.ONE)
		var body := Vector2(size.x * 0.30, size.y * 0.54)
		draw_style_box(_body_style, Rect2(-body * 0.5, body))
		var screen := Vector2(body.x * 0.74, body.y * 0.68)
		draw_style_box(_screen_style, Rect2(-screen * 0.5 - Vector2(0, body.y * 0.04), screen))
		draw_circle(Vector2(0, body.y * 0.38), body.x * 0.07, accent)
		# Curved rotation arrow around the phone (screen space, not rocked).
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var radius := minf(size.x, size.y) * 0.44
		var arc_start := -2.55
		var arc_end := -0.75
		draw_arc(center, radius, arc_start, arc_end, 32, accent, 8.0, true)
		var tip_base := center + Vector2(cos(arc_end), sin(arc_end)) * radius
		var tangent := Vector2(-sin(arc_end), cos(arc_end))
		var normal := Vector2(cos(arc_end), sin(arc_end))
		var head := PackedVector2Array([
			tip_base + tangent * 26.0,
			tip_base - tangent * 4.0 + normal * 14.0,
			tip_base - tangent * 4.0 - normal * 14.0,
		])
		draw_colored_polygon(head, accent)


func _ready() -> void:
	layer = 100  # Above the HUD, touch controls, and pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep working while paused.
	set_process(false)
	if GameConfig.is_headless() or not GameConfig.has_touchscreen():
		return  # Never appears on desktop or in sims.
	_build()
	var viewport := get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_update_visibility)
	_update_visibility()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.06, 0.9)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 24)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)

	_glyph = RotateGlyph.new()
	_glyph.custom_minimum_size = Vector2(260, 260)
	_glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_glyph)

	var title := Label.new()
	title.text = "Rotate your device"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "This game plays in landscape"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 26)
	subtitle.modulate.a = 0.7
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(subtitle)


func _update_visibility() -> void:
	if _root == null:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	var portrait := viewport_size.y > 0.0 \
		and (viewport_size.x / viewport_size.y) < PORTRAIT_ASPECT
	_root.visible = portrait
	set_process(portrait)


func _process(delta: float) -> void:
	_time += delta
	if _glyph != null:
		_glyph.rock = -0.45 + sin(_time * 2.4) * 0.14
		_glyph.queue_redraw()
