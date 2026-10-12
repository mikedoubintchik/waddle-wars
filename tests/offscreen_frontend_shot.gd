extends Node
## Render the existing frontend capture scene at sizes larger than the display.
## godot --path . res://tests/offscreen_frontend_shot.tscn -- screen=store_menu out=/tmp/menu.png w=1206 h=2622


func _ready() -> void:
	var width := 1206
	var height := 2622
	var capture_scene_path := "res://tests/frontend_shot.tscn"
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"w": width = int(parts[1])
			"h": height = int(parts[1])
			"capture":
				if parts[1] == "runner":
					capture_scene_path = "res://tests/runner_shot.tscn"
				elif parts[1] == "results":
					capture_scene_path = "res://tests/store_results_shot.tscn"
	var capture_viewport := SubViewport.new()
	capture_viewport.size = Vector2i(width, height)
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(capture_viewport)
	var capture_scene := load(capture_scene_path) as PackedScene
	capture_viewport.add_child(capture_scene.instantiate())
