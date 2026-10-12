extends SceneTree
## Derive web brand sizes from the same premium penguin art used for store icons.

const ICON_SOURCE := "res://assets/icons/waddle_wars_app_icon_v4.png"
const FEATURE_SOURCE := "res://web/oauth-feature.png"
const OUTPUT_DIR := "res://web"


func _init() -> void:
	var icon := Image.load_from_file(ICON_SOURCE)
	var feature := Image.load_from_file(FEATURE_SOURCE)
	if icon == null or icon.get_size() != Vector2i(1024, 1024) \
			or feature == null or feature.get_size() != Vector2i(1024, 500):
		push_error("brand assets: source image missing or wrong size")
		quit(1)
		return
	for size in [16, 32, 48, 180]:
		var output := icon.duplicate()
		output.resize(size, size, Image.INTERPOLATE_LANCZOS)
		var name := "apple-touch-icon.png" if size == 180 else "favicon-%d.png" % size
		if output.save_png("%s/%s" % [OUTPUT_DIR, name]) != OK:
			push_error("brand assets: failed to write %s" % name)
			quit(1)
			return
	var maskable := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	maskable.fill(Color("#0757ae"))
	var inset_icon := icon.duplicate()
	inset_icon.resize(410, 410, Image.INTERPOLATE_LANCZOS)
	inset_icon.convert(Image.FORMAT_RGBA8)
	maskable.blit_rect(inset_icon, Rect2i(Vector2i.ZERO, inset_icon.get_size()), Vector2i(51, 51))
	if maskable.save_png("%s/icon-maskable-512.png" % OUTPUT_DIR) != OK:
		push_error("brand assets: failed to write maskable icon")
		quit(1)
		return
	var card := Image.create(1200, 630, false, Image.FORMAT_RGB8)
	card.fill(Color("#071725"))
	var feature_scaled := feature.duplicate()
	feature_scaled.resize(1200, 586, Image.INTERPOLATE_LANCZOS)
	feature_scaled.convert(Image.FORMAT_RGB8)
	card.blit_rect(feature_scaled, Rect2i(Vector2i.ZERO, feature_scaled.get_size()), Vector2i(0, 22))
	if card.save_png("%s/share.png" % OUTPUT_DIR) != OK:
		push_error("brand assets: failed to write social card")
		quit(1)
		return
	print("[brand] wrote favicon, touch icon, maskable icon, and social card")
	quit(0)
