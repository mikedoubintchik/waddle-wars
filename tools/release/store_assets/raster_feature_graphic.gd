extends SceneTree
## Isolated vector layer only. Run in a minimal copied project, without game
## autoloads/imports. make_feature_graphic.py adds the shipped font lettering.

const BASE := "res://tools/release/store_assets/"
const OUTPUT := BASE + "feature-vector-raster.png"
const METADATA := BASE + "feature-vector-raster.json"
const INPUTS: PackedStringArray = [
	"assets/icons/icon.svg", "scripts/ui/main_menu.gd",
	"tools/release/store_assets/feature_graphic.template.svg",
	"tools/release/store_assets/raster_feature_graphic.gd",
]


func _init() -> void:
	if FileAccess.file_exists(OUTPUT) or FileAccess.file_exists(METADATA):
		push_error("feature graphic: fresh vector outputs required")
		quit(1)
		return
	var input_hashes := _input_hashes()
	if input_hashes.size() != INPUTS.size():
		push_error("feature graphic: missing vector source input")
		quit(1)
		return
	var template := FileAccess.get_file_as_string(BASE + "feature_graphic.template.svg")
	var icon := FileAccess.get_file_as_string("res://assets/icons/icon.svg")
	var menu := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	var start := menu.find('const RUN_ICON_SVG := """')
	if start < 0:
		push_error("feature graphic: shipped avalanche glyph missing")
		quit(1)
		return
	start += 'const RUN_ICON_SVG := """'.length()
	var end := menu.find('"""', start)
	var avalanche := menu.substr(start, end - start) if end > start else ""
	if template.count("{{PENGUIN_ICON}}") != 1 \
		or template.count("{{AVALANCHE_GLYPH}}") != 1 \
		or not icon.begins_with("<svg ") or not avalanche.begins_with("<svg "):
		push_error("feature graphic: malformed vector inputs")
		quit(1)
		return
	var icon_inner := icon.substr(icon.find(">") + 1)
	icon_inner = icon_inner.substr(0, icon_inner.rfind("</svg>"))
	var avalanche_inner := avalanche.substr(avalanche.find(">") + 1)
	avalanche_inner = avalanche_inner.substr(0, avalanche_inner.rfind("</svg>"))
	var svg := template.replace("{{PENGUIN_ICON}}", icon_inner) \
		.replace("{{AVALANCHE_GLYPH}}", avalanche_inner)
	var image := Image.new()
	if image.load_svg_from_string(svg, 1.0) != OK or image.get_size() != Vector2i(1024, 500):
		push_error("feature graphic: vector rasterization failed")
		quit(1)
		return
	if input_hashes != _input_hashes():
		push_error("feature graphic: vector source changed during rasterization")
		quit(1)
		return
	image.convert(Image.FORMAT_RGB8)
	if image.save_png(OUTPUT) != OK:
		push_error("feature graphic: vector raster write failed")
		quit(1)
		return
	var file := FileAccess.open(METADATA, FileAccess.WRITE)
	if file == null:
		push_error("feature graphic: vector metadata write failed")
		quit(1)
		return
	file.store_string(JSON.stringify({"inputs_sha256": input_hashes,
		"godot_version": Engine.get_version_info().get("string"),
		"raster_sha256": FileAccess.get_sha256(OUTPUT), "width": 1024, "height": 500}, "\t") + "\n")
	var error := file.get_error()
	file.close()
	if error != OK:
		push_error("feature graphic: vector metadata incomplete")
		quit(1)
		return
	print("[feature] isolated vector raster 1024x500 RGB8")
	quit(0)


func _input_hashes() -> Dictionary:
	var hashes := {}
	for path: String in INPUTS:
		var digest := FileAccess.get_sha256("res://" + path)
		if digest.is_empty():
			return {}
		hashes[path] = digest
	return hashes
