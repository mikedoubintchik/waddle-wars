extends Node
## Temporary agent probe: captures a screen the shared tour has no entry for.

class Monitor extends Node:
	var out_path: String = "qa_shots/mobfix/controls.png"
	var wait_time: float = 3.0
	var _t: float = 0.0
	var _done: bool = false

	func _process(delta: float) -> void:
		if _done:
			return
		_t += delta
		if _t < wait_time:
			return
		_done = true
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var err := image.save_png(out_path)
		print("[probe] saved %s (%dx%d) err=%d" % [
			out_path, image.get_width(), image.get_height(), err])
		get_tree().quit(0 if err == OK else 1)


func _ready() -> void:
	var w := 390
	var h := 844
	var out := "qa_shots/mobfix/controls.png"
	var target := "res://scenes/menus/controls.tscn"
	for arg: String in OS.get_cmdline_user_args():
		var p := arg.split("=")
		if p.size() != 2:
			continue
		match p[0]:
			"w": w = int(p[1])
			"h": h = int(p[1])
			"out": out = p[1]
			"scene": target = p[1]
			"touch": GameConfig.force_touch = p[1] == "1"
	SettingsManager.set_setting("accessibility", "ui_scale", 1.0)
	DisplayServer.window_set_size(Vector2i(w, h))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()
	var monitor := Monitor.new()
	monitor.out_path = out
	get_tree().root.add_child.call_deferred(monitor)
	SceneRouter.go_to.call_deferred(target)
