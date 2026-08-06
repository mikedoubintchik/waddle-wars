extends Node
## Visual QA for the dancing-penguin loading indicator: puts one on a dark
## panel, lets it dance, and saves a PNG. Must run WITH a window.
##   godot res://tests/loader_shot.tscn -- out=qa_shots/loader.png [wait=1.2]

var _out_path: String = "qa_shots/loader.png"
var _wait: float = 1.2
var _elapsed: float = 0.0
var _captured: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"out": _out_path = parts[1]
			"wait": _wait = float(parts[1])
	DisplayServer.window_set_size(Vector2i(720, 480))

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.06, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	bg.add_child(box)
	var dancer := PenguinLoader.new(200.0)
	dancer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(dancer)
	var label := Label.new()
	label.text = "Loading…"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.95))
	box.add_child(label)


func _process(delta: float) -> void:
	_elapsed += delta
	if _captured or _elapsed < _wait:
		return
	_captured = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_out_path)
	print("[loader_shot] saved %s err=%d" % [_out_path, err])
	get_tree().quit(0)
