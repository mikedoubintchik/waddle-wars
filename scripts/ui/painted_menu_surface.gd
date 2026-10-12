extends StyleBox
## Draw source corners at the destination radius. Fixed-pixel nine-patches
## flattened the rounded ends when the same material was used at phone scale.

var texture: Texture2D
var region := Rect2()
var capsule := true
var modulate_color := Color.WHITE
# Optional painted snow/body outset. Layout and input bounds remain unchanged.
var paint_expand_y := 0.0


func _draw(canvas: RID, rect: Rect2) -> void:
	if texture == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	if paint_expand_y > 0.0:
		rect = rect.grow_individual(0.0, paint_expand_y, 0.0, paint_expand_y)
	var source := region if region.has_area() else Rect2(Vector2.ZERO, texture.get_size())
	var source_radius := source.size.y * 0.52
	if capsule:
		var radius := minf(rect.size.y * 0.52, rect.size.x * 0.5)
		var dx := [0.0, radius, rect.size.x - radius, rect.size.x]
		var sx := [0.0, source_radius, source.size.x - source_radius, source.size.x]
		for x: int in 3:
			texture.draw_rect_region(canvas, Rect2(rect.position + Vector2(dx[x], 0),
				Vector2(dx[x + 1] - dx[x], rect.size.y)),
				Rect2(source.position + Vector2(sx[x], 0),
				Vector2(sx[x + 1] - sx[x], source.size.y)), modulate_color)
	else:
		var radius := minf(80.0, minf(rect.size.x, rect.size.y) * 0.25)
		var dx := [0.0, radius, rect.size.x - radius, rect.size.x]
		var dy := [0.0, radius, rect.size.y - radius, rect.size.y]
		var sx := [0.0, source.size.x * 0.13, source.size.x * 0.87, source.size.x]
		var sy := [0.0, source.size.y * 0.18, source.size.y * 0.82, source.size.y]
		for y: int in 3:
			for x: int in 3:
				texture.draw_rect_region(canvas, Rect2(rect.position + Vector2(dx[x], dy[y]),
					Vector2(dx[x + 1] - dx[x], dy[y + 1] - dy[y])),
					Rect2(source.position + Vector2(sx[x], sy[y]),
					Vector2(sx[x + 1] - sx[x], sy[y + 1] - sy[y])), modulate_color)


func _get_minimum_size() -> Vector2:
	return Vector2.ZERO
