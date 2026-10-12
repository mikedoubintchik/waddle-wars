extends StyleBox
## Selected wardrobe tab. Body has the broad outside-left cap; trail mirrors
## it. Shelf padding belongs to the control, not this drawing resource.

const TOP_CORAL := Color("ff7561")
const BOTTOM_CORAL := Color("f34d40")
const EDGE_CORAL := Color("f95a4c")
const LOWER_EDGE := Color("d84940")
const CORNER_STEPS := 12

var category: String = "body":
	set(value):
		category = value
		emit_changed()
var portrait := true:
	set(value):
		portrait = value
		emit_changed()

var _base := StyleBoxFlat.new()
var _face := StyleBoxFlat.new()
var _highlight := StyleBoxFlat.new()


func _init() -> void:
	for surface: StyleBoxFlat in [_base, _face, _highlight]:
		surface.anti_aliasing = true
		surface.anti_aliasing_size = 1.0
		surface.corner_detail = CORNER_STEPS
	_base.bg_color = LOWER_EDGE
	_face.bg_color = EDGE_CORAL
	_highlight.draw_center = false
	_highlight.border_color = Color(1.0, 0.94, 0.90, 0.28)


func _get_minimum_size() -> Vector2:
	return Vector2.ZERO


func _draw(canvas: RID, rect: Rect2) -> void:
	if not rect.has_area():
		return
	var radii := _radii(rect.size)
	_set_radii(_base, radii)
	_base.draw(canvas, rect)
	# A shallow lower bevel stays inside the supplied rect and never changes
	# the tab's hitbox or crowds the neighbouring shelf.
	var bevel := minf(rect.size.y * 0.018, rect.size.y * 0.1)
	var face_rect := Rect2(rect.position, rect.size - Vector2(0.0, bevel))
	var face_radii := _radii(face_rect.size)
	_set_radii(_face, face_radii)
	_face.draw(canvas, face_rect)
	# Keep the polygon just inside the antialiased base. Vertex colours share
	# a linear vertical gradient, including the curved outside caps.
	var inset := minf(1.0, minf(face_rect.size.x, face_rect.size.y) * 0.025)
	var gradient_rect := face_rect.grow(-inset)
	if gradient_rect.has_area():
		var points := _rounded_points(gradient_rect, _inset_radii(face_radii, inset))
		var colors := PackedColorArray()
		for point: Vector2 in points:
			var amount := clampf((point.y - face_rect.position.y) / face_rect.size.y, 0.0, 1.0)
			colors.append(TOP_CORAL.lerp(BOTTOM_CORAL, amount))
		RenderingServer.canvas_item_add_polygon(canvas, points, colors)
	_set_radii(_highlight, face_radii)
	_highlight.set_border_width_all(0)
	_highlight.border_width_top = maxi(1, roundi(rect.size.y * 0.012))
	_highlight.draw(canvas, face_rect)


func _radii(size: Vector2) -> Vector4:
	var limit := minf(size.x, size.y) * 0.5
	var inner := minf(limit, size.y * 0.20)
	var outer := minf(limit, size.y * (0.48 if portrait else 0.32))
	if category == "body":
		return Vector4(outer, inner, inner, outer)
	if category == "trail":
		return Vector4(inner, outer, outer, inner)
	return Vector4(inner, inner, inner, inner)


func _inset_radii(radii: Vector4, inset: float) -> Vector4:
	return Vector4(maxf(0.0, radii.x - inset), maxf(0.0, radii.y - inset),
		maxf(0.0, radii.z - inset), maxf(0.0, radii.w - inset))


func _set_radii(surface: StyleBoxFlat, radii: Vector4) -> void:
	surface.corner_radius_top_left = roundi(radii.x)
	surface.corner_radius_top_right = roundi(radii.y)
	surface.corner_radius_bottom_right = roundi(radii.z)
	surface.corner_radius_bottom_left = roundi(radii.w)


func _rounded_points(rect: Rect2, radii: Vector4) -> PackedVector2Array:
	var result := PackedVector2Array()
	var centers := PackedVector2Array([
		rect.position + Vector2(radii.x, radii.x),
		Vector2(rect.end.x - radii.y, rect.position.y + radii.y),
		rect.end - Vector2(radii.z, radii.z),
		Vector2(rect.position.x + radii.w, rect.end.y - radii.w),
	])
	for corner: int in 4:
		var radius := radii[corner]
		if radius <= 0.0:
			result.append(centers[corner])
			continue
		for segment: int in range(CORNER_STEPS + 1):
			var angle := PI + float(corner) * PI * 0.5 + float(segment) * PI * 0.5 / float(CORNER_STEPS)
			result.append(centers[corner] + Vector2(cos(angle), sin(angle)) * radius)
	return result
