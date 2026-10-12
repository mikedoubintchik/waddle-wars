extends Node
## Store asset capture of the real Waddle Run results UI with coherent sample data.

var _out: String = "qa_shots/store/results.png"
var _wait: float = 1.5
var _elapsed: float = 0.0
var _captured: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"out": _out = parts[1]
			"wait": _wait = float(parts[1])
	GameConfig.force_touch = true
	GameConfig.force_native_offline_mvp = true
	var hud := RunnerHUD.new()
	add_child(hud)
	hud.setup()
	hud.show_game_over({"distance": 363.0, "fish": 67, "score": 2038,
		"best": 6692, "missions": ["Run 250 m at x2 or better", "Collect 60 fish"]})


func _process(delta: float) -> void:
	_elapsed += delta
	if _captured or _elapsed < _wait:
		return
	_captured = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var error := image.save_png(_out)
	print("[store-results-shot] %s %dx%d err=%d" % [
		_out, image.get_width(), image.get_height(), error])
	get_tree().quit(0 if error == OK else 1)
