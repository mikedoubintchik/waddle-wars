class_name RunnerHUDArt
extends RefCounted
## ImageGen-painted sprites shared by live runner controls. Atlas regions keep
## source pixels intact; all captions, values and progress remain native UI.

const ATLAS := "res://assets/art/ui/runner/runner_hud_icons_v1.webp"
const FISH := "res://assets/art/ui/menu/home_fish_symbol_clean_v2.png"
const PAINTED_SURFACE = preload("res://scripts/ui/painted_menu_surface.gd")
const ART_ROOT := "res://assets/art/ui/runner/inrun_v4/"
const CHROME := ART_ROOT + "runner_surfaces_v4.webp"
const POWDER := ART_ROOT + "avalanche_front_v2.webp"
const POWDER_CREST := 0.344
const PAUSED := ART_ROOT + "paused_wordmark_v1.webp"
const CAUGHT_PORTRAIT := "res://assets/art/ui/runner/inrun_v5/caught_background_portrait_v5.webp"
const CAUGHT_DESKTOP := "res://assets/art/ui/runner/inrun_v5/caught_background_desktop_v5.webp"
const CHROME_REGIONS := {
	"card": Rect2(40, 106, 475, 476),
	"gauge": Rect2(539, 245, 651, 219),
	"powerup": Rect2(1234, 236, 259, 277),
	"track": Rect2(31, 766, 533, 129),
	"ice_fill": Rect2(591, 765, 598, 133),
	"chip": Rect2(1228, 765, 279, 133),
}
const CELLS := {"heart": Vector2i(0, 0), "magnet": Vector2i(1, 0),
	"shield": Vector2i(2, 0), "double": Vector2i(0, 1),
	"pause": Vector2i(1, 1), "avalanche": Vector2i(2, 1)}
const END_ICONS := "res://assets/art/ui/runner/runner_end_icons_v3.webp"
const END_REGIONS := {
	"trophy": Rect2(63, 69, 438, 399),
	"pin": Rect2(616, 65, 302, 403),
	"camp": Rect2(1059, 65, 416, 403),
	"play": Rect2(97, 590, 324, 367),
	"retry": Rect2(591, 554, 355, 397),
	"settings": Rect2(1085, 571, 374, 379),
}
const ICON_BOUNDS := {
	"heart": Rect2(46, 76, 420, 371), "magnet": Rect2(68, 80, 374, 381),
	"shield": Rect2(60, 46, 383, 423), "double": Rect2(47, 47, 406, 392),
	"pause": Rect2(94, 60, 321, 367), "avalanche": Rect2(48, 50, 436, 390),
}
static var _sprites: Dictionary = {}

static func catch_surround(portrait: bool) -> Texture2D:
	var key := "catch_surround_portrait" if portrait else "catch_surround_desktop"
	if not _sprites.has(key):
		_sprites[key] = load("res://assets/art/ui/runner/inrun_v10/avalanche_surround_%s_v1.webp" % ("portrait" if portrait else "desktop"))
	return _sprites[key] as Texture2D


static func chrome(key: String) -> Texture2D:
	var cache_key := "chrome_" + key
	if not _sprites.has(cache_key) and CHROME_REGIONS.has(key):
		var region := AtlasTexture.new()
		region.atlas = load(CHROME) as Texture2D
		region.region = CHROME_REGIONS[key]
		region.filter_clip = true
		_sprites[cache_key] = region
	return _sprites.get(cache_key) as Texture2D


static func panel(key: String, horizontal: float, top: float, bottom: float,
		tint: Color = Color.WHITE) -> StyleBox:
	var style := PAINTED_SURFACE.new()
	style.texture = chrome(key)
	style.capsule = key not in ["card", "powerup"]
	style.modulate_color = tint
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = top
	style.content_margin_bottom = bottom
	return style


const HUD_CHROME := "res://assets/art/ui/runner/inrun_v5/hud_reference_surfaces_v1.webp"
const HUD_SURFACE = preload("res://scripts/ui/runner_hud_surface.gd")
const HUD_ICONS := "res://assets/art/ui/runner/inrun_v5/hud_reference_icons_v1.webp"
const HUD_ICON_REGIONS := {
	"heart": Rect2(77, 110, 401, 341),
	"magnet": Rect2(598, 86, 372, 386),
	"shield": Rect2(1106, 81, 350, 387),
	"double": Rect2(80, 554, 385, 368),
	"pause": Rect2(633, 607, 272, 300),
	"fish": Rect2(1048, 612, 450, 311),
}
const HUD_REGIONS := {
	"card": Rect2(69, 74, 515, 447),
	"gauge": Rect2(696, 190, 857, 247),
	"powerup": Rect2(1767, 204, 247, 237),
	"chip": Rect2(97, 567, 463, 117),
	"track": Rect2(680, 574, 749, 106),
	"ice_fill": Rect2(1511, 575, 613, 90),
}

static func hud_chrome(key: String) -> Texture2D:
	var cache_key := "reference_hud_" + key
	if not _sprites.has(cache_key) and HUD_REGIONS.has(key):
		var region := AtlasTexture.new()
		region.atlas = load(HUD_CHROME) as Texture2D
		region.region = HUD_REGIONS[key]
		region.filter_clip = true
		_sprites[cache_key] = region
	return _sprites.get(cache_key) as Texture2D

static func hud_sprite(key: String) -> Texture2D:
	var cache_key := "reference_icon_" + key
	if key == "heart_spent" and not _sprites.has(cache_key):
		var region := AtlasTexture.new()
		region.atlas = load("res://assets/art/ui/runner/inrun_v5/hud_heart_spent_v1.webp") as Texture2D
		region.region = Rect2(136, 165, 1039, 872)
		region.filter_clip = true
		_sprites[cache_key] = region
	if not _sprites.has(cache_key) and HUD_ICON_REGIONS.has(key):
		var region := AtlasTexture.new()
		region.atlas = load(HUD_ICONS) as Texture2D
		region.region = HUD_ICON_REGIONS[key]
		region.filter_clip = true
		_sprites[cache_key] = region
	return _sprites.get(cache_key) as Texture2D

static func hud_panel(key: String, horizontal: float, top: float, bottom: float,
		tint: Color = Color.WHITE) -> StyleBox:
	var style := HUD_SURFACE.new()
	style.texture = hud_chrome(key)
	style.capsule = key not in ["card", "powerup"]
	style.modulate_color = tint
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = top
	style.content_margin_bottom = bottom
	return style


static func caught_background(portrait: bool) -> Texture2D:
	var key := "caught_portrait" if portrait else "caught_desktop"
	if not _sprites.has(key):
		_sprites[key] = load(CAUGHT_PORTRAIT if portrait else CAUGHT_DESKTOP) as Texture2D
	return _sprites[key] as Texture2D


static func paused_wordmark() -> Texture2D:
	if not _sprites.has("paused_wordmark"):
		var region := AtlasTexture.new()
		region.atlas = load(PAUSED) as Texture2D
		region.region = Rect2(108, 123, 2001, 472)
		region.filter_clip = true
		_sprites["paused_wordmark"] = region
	return _sprites["paused_wordmark"] as Texture2D

static func sprite(key: String) -> Texture2D:
	if not _sprites.has(key):
		if END_REGIONS.has(key):
			var region := AtlasTexture.new()
			region.atlas = load(END_ICONS) as Texture2D
			region.region = END_REGIONS[key]
			region.filter_clip = true
			_sprites[key] = region
		elif key == "fish":
			_sprites[key] = load(FISH) as Texture2D
		elif CELLS.has(key):
			var region := AtlasTexture.new()
			region.atlas = load(ATLAS) as Texture2D
			var bounds: Rect2 = ICON_BOUNDS[key]
			region.region = Rect2(Vector2(CELLS[key]) * 512.0 + bounds.position, bounds.size)
			region.filter_clip = true
			_sprites[key] = region
	return _sprites.get(key) as Texture2D
