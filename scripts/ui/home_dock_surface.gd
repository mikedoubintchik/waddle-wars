extends "res://scripts/ui/painted_menu_surface.gd"
## The phone shelf continues below the window; only its upper corners show.
## Its controls still respect the bottom safe inset.
var bottom_bleed := 0.0
var top_bleed := 0.0
var left_bleed := 0.0
var right_bleed := 0.0

func _draw(canvas: RID, rect: Rect2) -> void:
	super._draw(canvas, Rect2(rect.position - Vector2(left_bleed, top_bleed),
		rect.size + Vector2(left_bleed + right_bleed, top_bleed + bottom_bleed)))
