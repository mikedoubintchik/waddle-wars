extends SceneTree
## Resizes the premium app icon to the PNG sizes a web app manifest needs.
##
## Historical --store-icons mode still reproduces the archived vector draft.
## Current PWA icons derive from the same premium source as mobile store art.
##
##   godot --headless --path . --script tools/make_pwa_icons.gd
##   godot --headless --path . --script tools/make_pwa_icons.gd -- --store-icons
## Store mode rasterises the same vector directly at 512/1024, compositing onto
## opaque #2a6fc9 before Play RGBA8 / iOS RGB8 encoding. It refuses to replace
## existing outputs. Play's alpha channel is retained with every alpha at 255.

const SOURCE := "res://assets/icons/icon.svg"
const PWA_SOURCE := "res://assets/icons/waddle_wars_app_icon_v4.png"
const SIZES: PackedInt32Array = [192, 512]
const OUT_DIR := "res://web"
const STORE_SIZES: PackedInt32Array = [512, 1024]
const STORE_OUT_DIR := "res://tools/release/store_assets"
const STORE_RECEIPT := "generation_receipt.json"
const STORE_BACKGROUND := Color("#2a6fc9")


func _init() -> void:
	if OS.get_cmdline_user_args().has("--store-icons"):
		_make_store_icons()
		return
	var source_image := Image.load_from_file(PWA_SOURCE)
	if source_image == null or source_image.get_width() != 1024 \
			or source_image.get_height() != 1024:
		push_error("make_pwa_icons: premium source must be 1024x1024")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for size: int in SIZES:
		var image := source_image.duplicate()
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
		var path := "%s/icon-%d.png" % [OUT_DIR, size]
		if image.save_png(path) != OK:
			push_error("make_pwa_icons: could not write %s" % path)
			quit(1)
			return
		print("[pwa] wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	quit(0)


func _make_store_icons() -> void:
	# Fresh outputs only; neither web icons nor an earlier store delivery changes.
	var output_names: PackedStringArray = [STORE_RECEIPT]
	for size: int in STORE_SIZES:
		output_names.append("icon-%d.png" % size)
	for name: String in output_names:
		var path := "%s/%s" % [STORE_OUT_DIR, name]
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			push_error("make_pwa_icons: store output already exists: %s" % path)
			quit(1)
			return
	var text := FileAccess.get_file_as_string(SOURCE)
	var probe := Image.new()
	if text.is_empty() or probe.load_svg_from_string(text, 1.0) != OK \
		or probe.get_width() <= 0 or probe.get_height() <= 0:
		push_error("make_pwa_icons: store SVG read/parse failed")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STORE_OUT_DIR)) != OK:
		push_error("make_pwa_icons: could not create store output directory")
		quit(1)
		return
	var outputs: Array[Dictionary] = []
	for size: int in STORE_SIZES:
		var vector_image := Image.new()
		# Rasterise the vector at final resolution, never resize a small bitmap.
		var scale := float(size) / float(maxi(probe.get_width(), probe.get_height()))
		if vector_image.load_svg_from_string(text, scale) != OK \
			or vector_image.get_width() > size or vector_image.get_height() > size:
			push_error("make_pwa_icons: store SVG rasterise failed at %d" % size)
			quit(1)
			return
		vector_image.convert(Image.FORMAT_RGBA8)
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
		image.fill(STORE_BACKGROUND)
		var offset := Vector2i((size - vector_image.get_width()) / 2,
			(size - vector_image.get_height()) / 2)
		# blend_rect composites antialiased edges; blit_rect would retain alpha.
		image.blend_rect(vector_image, Rect2i(Vector2i.ZERO, vector_image.get_size()), offset)
		var play_icon := size == 512
		var format_name := "RGBA8" if play_icon else "RGB8"
		if not play_icon:
			image.convert(Image.FORMAT_RGB8)
		var name := "icon-%d.png" % size
		var path := "%s/%s" % [STORE_OUT_DIR, name]
		if image.save_png(path) != OK:
			push_error("make_pwa_icons: could not write store icon at %d" % size)
			quit(1)
			return
		outputs.append({"path": "tools/release/store_assets/%s" % name,
			"sha256": FileAccess.get_sha256(path), "width": size, "height": size,
			"format": format_name, "alpha": play_icon, "opaque": true})
		print("[store] wrote %s (%dx%d %s, opaque)" % [path, size, size, format_name])
	var receipt := {"schema_version": 1, "state": "generated_unsubmitted",
		"store_ready": false, "source": {"path": "assets/icons/icon.svg",
			"sha256": FileAccess.get_sha256(SOURCE)},
		"generator": {"path": "tools/make_pwa_icons.gd",
			"sha256": FileAccess.get_sha256(get_script().resource_path),
			"godot_version": String(Engine.get_version_info().get("string", "unknown")),
			"mode": "--store-icons"},
		"background": "#2a6fc9", "rasterization": "vector_at_output_resolution",
		"outputs": outputs}
	var receipt_path := "%s/%s" % [STORE_OUT_DIR, STORE_RECEIPT]
	var file := FileAccess.open(receipt_path, FileAccess.WRITE)
	if file == null:
		push_error("make_pwa_icons: could not write store generation receipt")
		quit(1)
		return
	file.store_string(JSON.stringify(receipt, "\t") + "\n")
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_error("make_pwa_icons: store generation receipt write failed")
		quit(1)
		return
	print("[store] generated_unsubmitted; store_ready=false")
	quit(0)
