extends Node
## Windowed capture for title, loader, or pre-route boot.
## godot res://tests/frontend_shot.tscn -- screen=title out=/tmp/title.png w=1920 h=1080

var _screen: String = "title"
var _out: String = "qa_shots/frontend/title.png"
var _wait: float = 1.2
var _elapsed: float = 0.0
var _captured: bool = false


func _ready() -> void:
	var width := 1920
	var height := 1080
	var reduced := false
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"screen": _screen = parts[1]
			"out": _out = parts[1]
			"wait": _wait = float(parts[1])
			"w": width = int(parts[1])
			"h": height = int(parts[1])
			"reduced": reduced = parts[1] == "1"
	SettingsManager.set_setting("accessibility", "reduced_flashing", reduced)
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_move_to_foreground()
	match _screen:
		"loader":
			_build_loader()
		"router_loader":
			# SceneRouter replaces current scene before rich loading card finishes
			# fading in. Root-owned monitor survives that swap long enough to grab
			# actual cached mascot/backdrop composition.
			var monitor := PersistentCapture.new()
			monitor.out_path = _out
			monitor.wait_seconds = _wait
			get_tree().root.add_child.call_deferred(monitor)
			set_process(false)
			SceneRouter.go_to.call_deferred(Game.SCENE_TITLE)
		"boot":
			var boot: Node = (load("res://scenes/ui/main.tscn") as PackedScene).instantiate()
			add_child(boot)
		_:
			var title: Node = (load("res://scenes/ui/title.tscn") as PackedScene).instantiate()
			add_child(title)


func _build_loader() -> void:
	var backdrop := FrontEndBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.set_presentation(FrontEndBackdrop.Context.LOADING, 0.90,
		not UITheme.reduced_motion())
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	center.add_child(column)
	column.add_child(PenguinLoader.new(280.0))
	var label := Label.new()
	label.text = "CHARTING EXPEDITION ROUTE…"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UITheme.bold_font())
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.86, 0.95, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.10))
	label.add_theme_constant_override("outline_size", 7)
	column.add_child(label)


func _process(delta: float) -> void:
	_elapsed += delta
	if _captured or _elapsed < _wait:
		return
	_captured = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var error := image.save_png(_out)
	print("[frontend-shot] %s %dx%d err=%d" % [
		_out, image.get_width(), image.get_height(), error])
	get_tree().quit(0 if error == OK else 1)


class PersistentCapture:
	extends Node

	var out_path: String = ""
	var wait_seconds: float = 0.55
	var elapsed: float = 0.0
	var captured: bool = false

	func _process(delta: float) -> void:
		elapsed += delta
		if captured or elapsed < wait_seconds:
			return
		captured = true
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var error := image.save_png(out_path)
		print("[frontend-shot] %s %dx%d err=%d" % [
			out_path, image.get_width(), image.get_height(), error])
		get_tree().quit(0 if error == OK else 1)
