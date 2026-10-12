extends RefCounted
## Clean inset controls used inside the painted menu panels. Reference rows
## have an ivory bevel, not a second snowy panel around every setting.

const INK := Color("09213f")
const MUTED := Color("57718c")

static func inset(padding_x: float, padding_y: float, radius: float = 28.0,
		fill: Color = Color("faf7ef")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(roundi(radius))
	box.set_border_width_all(2)
	box.border_color = Color("ffffff")
	box.border_blend = true
	box.shadow_color = Color(0.34, 0.29, 0.20, 0.16)
	box.shadow_size = 3.0
	box.shadow_offset = Vector2(0, 2)
	box.content_margin_left = padding_x
	box.content_margin_right = padding_x
	box.content_margin_top = padding_y
	box.content_margin_bottom = padding_y
	return box

static func clean_label(label: Label, color: Color = INK) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)

static func progress(fill: Color, radius: int = 10) -> StyleBoxFlat:
	var box := inset(0, 0, radius, fill)
	box.border_color = fill.lightened(0.26)
	box.shadow_size = 0
	return box
