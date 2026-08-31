extends SceneTree
## Rasterises the app icon to the PNG sizes a web app manifest needs.
##
## The project's icon is an SVG, and a manifest needs real PNGs (Chrome will
## not offer installation without at least a 192 and a 512). Godot can already
## rasterise SVG, so this avoids adding an image-processing dependency to the
## build just to make two squares.
##
##   godot --headless --path . --script tools/make_pwa_icons.gd

const SOURCE := "res://assets/icons/icon.svg"
const SIZES: PackedInt32Array = [192, 512]
const OUT_DIR := "res://web"


func _init() -> void:
	var text := FileAccess.get_file_as_string(SOURCE)
	if text == "":
		push_error("make_pwa_icons: could not read %s" % SOURCE)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for size: int in SIZES:
		var image := Image.new()
		# load_svg_from_string scales by a factor, not to a target, so derive
		# the factor from the SVG's own natural size at scale 1.
		var probe := Image.new()
		if probe.load_svg_from_string(text, 1.0) != OK:
			push_error("make_pwa_icons: SVG parse failed")
			quit(1)
			return
		var natural := maxi(probe.get_width(), 1)
		if image.load_svg_from_string(text, float(size) / float(natural)) != OK:
			push_error("make_pwa_icons: SVG rasterise failed at %d" % size)
			quit(1)
			return
		# Manifest icons are square; pad rather than stretch if the source is not.
		if image.get_width() != size or image.get_height() != size:
			var square := Image.create(size, size, false, Image.FORMAT_RGBA8)
			square.fill(Color(0, 0, 0, 0))
			square.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()),
				Vector2i((size - image.get_width()) / 2, (size - image.get_height()) / 2))
			image = square
		var path := "%s/icon-%d.png" % [OUT_DIR, size]
		if image.save_png(path) != OK:
			push_error("make_pwa_icons: could not write %s" % path)
			quit(1)
			return
		print("[pwa] wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	quit(0)
