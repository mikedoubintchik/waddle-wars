class_name SettingsAccountArt
extends RefCounted
## Reference-derived cutouts. Labels and state remain native controls.

const ATLAS := "res://assets/art/ui/menu/settings_account_reference_atlas_v2.webp"
const REGIONS := {
	"comfort": Rect2(0, 35, 432, 415),
	"avatar": Rect2(435, 30, 382, 416),
	"journal": Rect2(820, 130, 434, 264),
	"camera": Rect2(42, 463, 367, 370),
	"flash": Rect2(450, 454, 350, 382),
	"eye": Rect2(835, 510, 408, 312),
	"privacy": Rect2(52, 845, 340, 372),
	"delete": Rect2(479, 856, 308, 356),
	"mountain": Rect2(810, 850, 444, 394),
}


static func sprite(key: String) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = ExpeditionMenuStyle._material_texture(ATLAS)
	result.region = REGIONS[key]
	result.filter_clip = true
	return result


static func picture(key: String, extent: Vector2) -> TextureRect:
	var result := TextureRect.new()
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.texture = sprite(key)
	result.custom_minimum_size = extent
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func journal(padding: float = 24.0) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = sprite("journal")
	box.texture_margin_left = 52.0
	box.texture_margin_right = 45.0
	box.texture_margin_top = 44.0
	box.texture_margin_bottom = 40.0
	box.content_margin_left = padding * 1.4
	box.content_margin_right = padding * 1.4
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box
