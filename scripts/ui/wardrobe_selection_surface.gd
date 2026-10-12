extends StyleBox
## Wardrobe-only selection frame. The supplied rect is the outer white edge;
## callers reserve glow_padding() outside it so a scrolling parent cannot clip it.

const IVORY := Color("fffaf8")
const CORAL := Color("ff5d50")
const HALO := Color("ffb7d1")
const HALO_STEPS := 8

var selected := true:
	set(value):
		selected = value
		emit_changed()
var portrait := true:
	set(value):
		portrait = value
		emit_changed()

var _stroke := StyleBoxFlat.new()


func _init() -> void:
	_stroke.draw_center = false
	_stroke.anti_aliasing = true
	_stroke.anti_aliasing_size = 1.0
	_stroke.corner_detail = 12


func glow_padding(size: Vector2) -> float:
	return maxf(0.0, minf(size.x, size.y) * 0.045) if selected else 0.0


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.grow(glow_padding(rect.size) + 1.0)


func _get_minimum_size() -> Vector2:
	return Vector2.ZERO


func _draw(canvas: RID, rect: Rect2) -> void:
	if not rect.has_area():
		return
	var short_side := minf(rect.size.x, rect.size.y)
	var radius := short_side * (0.18 if portrait else 0.13)
	var white_width := maxf(1.0, roundf(short_side * 0.021))
	if selected:
		var halo_size := glow_padding(rect.size)
		var step := halo_size / float(HALO_STEPS)
		for index: int in range(HALO_STEPS, 0, -1):
			var amount := float(index) / float(HALO_STEPS)
			var expansion := step * float(index)
			var tint := HALO
			tint.a = lerpf(0.13, 0.012, amount * amount)
			_outline(canvas, rect.grow(expansion), radius + expansion,
				maxf(1.0, step + 1.0), tint)
	_outline(canvas, rect, radius, white_width, IVORY)
	if not selected:
		return
	var coral_width := maxf(1.0, roundf(short_side * 0.028))
	var inner_width := maxf(1.0, roundf(short_side * 0.010))
	var coral_rect := rect.grow(-white_width)
	_outline(canvas, coral_rect, maxf(0.0, radius - white_width), coral_width, CORAL)
	var inner_inset := white_width + coral_width
	_outline(canvas, rect.grow(-inner_inset), maxf(0.0, radius - inner_inset),
		inner_width, IVORY)


func _outline(canvas: RID, rect: Rect2, radius: float, width: float, tint: Color) -> void:
	if not rect.has_area():
		return
	_stroke.border_color = tint
	_stroke.set_border_width_all(maxi(1, roundi(minf(width, minf(rect.size.x, rect.size.y) * 0.5))))
	_stroke.set_corner_radius_all(maxi(0, roundi(radius)))
	_stroke.draw(canvas, rect)
