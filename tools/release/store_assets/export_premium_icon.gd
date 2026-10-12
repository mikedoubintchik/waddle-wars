extends SceneTree
## Deterministic store sizes from the approved opaque premium icon source.
## Historical vector icon and its receipt are kept for rollback.

const SOURCE := "res://assets/icons/waddle_wars_app_icon_v4.png"
const OUT_DIR := "res://tools/release/store_assets"
const RECEIPT := "res://tools/release/store_assets/icon_v4_receipt.json"


func _init() -> void:
	var image := Image.load_from_file(SOURCE)
	if image == null or image.get_width() != 1024 or image.get_height() != 1024:
		push_error("premium icon source must be 1024x1024")
		quit(1)
		return
	if image.detect_alpha() != Image.ALPHA_NONE:
		push_error("premium icon source must be opaque")
		quit(1)
		return
	var outputs: Array[Dictionary] = []
	for size: int in [512, 1024]:
		var result := image.duplicate()
		if size != 1024:
			result.resize(size, size, Image.INTERPOLATE_LANCZOS)
		var play := size == 512
		result.convert(Image.FORMAT_RGBA8 if play else Image.FORMAT_RGB8)
		var name := "icon-%d-v4.png" % size
		var path := "%s/%s" % [OUT_DIR, name]
		if result.save_png(path) != OK:
			push_error("could not write %s" % path)
			quit(1)
			return
		outputs.append({"path": "tools/release/store_assets/%s" % name,
			"sha256": FileAccess.get_sha256(path), "width": size,
			"height": size, "format": "RGBA8" if play else "RGB8",
			"alpha": play, "opaque": true})
	var receipt := {"schema_version": 1, "state": "generated_unsubmitted",
		"store_ready": false, "source": {"path": "assets/icons/waddle_wars_app_icon_v4.png",
			"sha256": FileAccess.get_sha256(SOURCE)},
		"generator": {"path": "tools/release/store_assets/export_premium_icon.gd",
			"sha256": FileAccess.get_sha256(get_script().resource_path),
			"godot_version": String(Engine.get_version_info().get("string", "unknown"))},
		"outputs": outputs}
	var file := FileAccess.open(RECEIPT, FileAccess.WRITE)
	if file == null:
		push_error("could not write icon receipt")
		quit(1)
		return
	file.store_string(JSON.stringify(receipt, "\t") + "\n")
	file.close()
	print("[premium-icon] generated_unsubmitted; store_ready=false")
	quit(0)
