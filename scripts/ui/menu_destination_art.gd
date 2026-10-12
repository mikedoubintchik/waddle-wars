extends RefCounted
## Complete silhouettes share one texture. Regions include transparent breathing
## room around the measured alpha bounds, not an assumed equal cell grid.

const PATH := "res://assets/art/ui/menu/basecamp_home_icons_complete_v1.webp"
const REGIONS := {
	"leaderboard": Rect2(65, 111, 346, 315),
	"achievements": Rect2(472, 78, 317, 347),
	"shop": Rect2(846, 92, 353, 329),
	"settings": Rect2(62, 489, 343, 323),
	"credits": Rect2(457, 474, 348, 336),
	"guest": Rect2(842, 459, 351, 359),
	"home_penguins": Rect2(63, 842, 332, 338),
	"home_missions": Rect2(459, 841, 334, 340),
	"home_more": Rect2(853, 839, 333, 343),
}

static func icon(key: String) -> AtlasTexture:
	assert(REGIONS.has(key), "Unknown destination artwork: " + key)
	var result := AtlasTexture.new()
	result.atlas = ExpeditionMenuStyle._material_texture(PATH)
	result.region = REGIONS[key]
	result.filter_clip = true
	return result
