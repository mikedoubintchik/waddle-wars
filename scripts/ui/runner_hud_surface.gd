extends StyleBox
## Reference HUD surfaces: small fixed snow corners, independent of card height.
var texture: Texture2D
var capsule := true
var modulate_color := Color.WHITE

func _draw(canvas: RID, rect: Rect2) -> void:
	if texture == null or not rect.has_area():
		return
	var source := Rect2(Vector2.ZERO, texture.get_size())
	if capsule:
		var radius := minf(rect.size.y * 0.5, rect.size.x * 0.5)
		var source_radius := minf(source.size.y * 0.5, source.size.x * 0.5)
		var dx := [0.0, radius, rect.size.x - radius, rect.size.x]
		var sx := [0.0, source_radius, source.size.x - source_radius, source.size.x]
		for x: int in 3:
			texture.draw_rect_region(canvas, Rect2(rect.position + Vector2(dx[x], 0),
				Vector2(dx[x + 1] - dx[x], rect.size.y)),
				Rect2(Vector2(sx[x], 0), Vector2(sx[x + 1] - sx[x], source.size.y)), modulate_color)
	else:
		var radius := minf(42.0, minf(rect.size.x, rect.size.y) * 0.26)
		var dx := [0.0, radius, rect.size.x - radius, rect.size.x]
		var dy := [0.0, radius, rect.size.y - radius, rect.size.y]
		var sx := [0.0, source.size.x * 0.18, source.size.x * 0.82, source.size.x]
		var sy := [0.0, source.size.y * 0.20, source.size.y * 0.80, source.size.y]
		for y: int in 3:
			for x: int in 3:
				texture.draw_rect_region(canvas, Rect2(rect.position + Vector2(dx[x], dy[y]),
					Vector2(dx[x + 1] - dx[x], dy[y + 1] - dy[y])),
					Rect2(Vector2(sx[x], sy[y]), Vector2(sx[x + 1] - sx[x], sy[y + 1] - sy[y])), modulate_color)

func _get_minimum_size() -> Vector2:
	return Vector2.ZERO
