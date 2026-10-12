extends RefCounted
## Dedicated reference assets for terminal run states. Native labels, actions
## and the catch clock remain authoritative.

const ROOT := "res://assets/art/ui/runner/inrun_v5/"
static var _cache: Dictionary = {}

static func catch_title(portrait: bool) -> Texture2D:
	var key := "catch_title_portrait" if portrait else "catch_title_desktop"
	if not _cache.has(key):
		var atlas := AtlasTexture.new()
		atlas.atlas = load(ROOT + ("avalanche_wordmark_v5.webp" if portrait else "avalanche_wordmark_desktop_v5.webp"))
		atlas.region = Rect2(45, 50, 1007, 292) if portrait else Rect2(28, 82, 1048, 204)
		atlas.filter_clip = true
		_cache[key] = atlas
	return _cache[key]

static func pause_card(unit: float) -> StyleBoxTexture:
	var face := StyleBoxTexture.new()
	if not _cache.has("pause_card"):
		var atlas := AtlasTexture.new()
		atlas.atlas = load(ROOT + "pause_blank_card_v5.webp")
		atlas.region = Rect2(34, 10, 700, 950)
		atlas.filter_clip = true
		_cache["pause_card"] = atlas
	face.texture = _cache["pause_card"]
	# The authored card already matches this tall panel's aspect. Stretch the
	# full face so fixed-pixel corner margins cannot enlarge its alpha gutters.
	for side: int in [SIDE_LEFT, SIDE_RIGHT]:
		face.set_content_margin(side, 38.0 * unit)
	face.content_margin_top = 44.0 * unit
	face.content_margin_bottom = 30.0 * unit
	return face

static func pause_icon(key: String) -> Texture2D:
	var cache_key := "pause_" + key
	if not _cache.has(cache_key):
		var shapes := {
			"play": '<path d="M17 8 57 32 17 56Z" fill="#fffdf6" stroke="#e7e0d0" stroke-width="2" stroke-linejoin="round"/>',
			"retry": '<path d="M38 7 51 17 38 29V20A17 17 0 1 0 48 35" fill="none" stroke="#112b50" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>',
			"settings": '<path d="m26 3 12 0 3 8 8 4 8-1 6 10-5 7 0 9 5 6-6 10-9-1-8 4-2 8-12 0-3-8-8-4-8 1-6-10 5-7 0-9-5-6 6-10 9 1 8-4z" fill="#112b50" transform="translate(1,-2) scale(.95)"/><circle cx="32" cy="31" r="11" fill="#fff9ed"/>',
			"camp": '<path d="m3 58 17-26 11 13 11-22 20 35zM40 23V5l19 7-19 7" fill="#112b50" stroke="#112b50" stroke-width="2" stroke-linejoin="round"/>',
		}
		_cache[cache_key] = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'+String(shapes[key])+'</svg>', 2.0)
	return _cache[cache_key]
