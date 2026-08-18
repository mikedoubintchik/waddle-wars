extends Node
## Visual QA for Waddle Run: boots the real mode with the autopilot driving and
## saves a strip of frames spread across the opening of a run, so the track,
## the obstacles, the HUD and the avalanche can all be judged in motion rather
## than from one lucky still. Must run WITH a window.
##
##   godot res://tests/runner_shot.tscn -- out=qa_shots/runner/run.png \
##       [at=3,8,14,22] [w=1600 h=900]

var _out_path: String = "qa_shots/runner/run.png"
var _times: PackedFloat32Array = [2.5, 7.0, 13.0, 20.0]
var _elapsed: float = 0.0
var _shot: int = 0
var _done: bool = false


func _ready() -> void:
	var width := 1600
	var height := 900
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"out": _out_path = parts[1]
			"w": width = int(parts[1])
			"h": height = int(parts[1])
			"at":
				var stamps := PackedFloat32Array()
				for piece: String in parts[1].split(","):
					stamps.append(float(piece))
				_times = stamps
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	# An occluded window never draws, and a harness that waits on
	# frame_post_draw then hangs forever with no output. Raise it.
	DisplayServer.window_move_to_foreground()
	RunnerPlayer.autopilot = true
	var scene: PackedScene = load(Game.SCENE_RUNNER)
	add_child(scene.instantiate())


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed > _times[_times.size() - 1] + 8.0:
		push_error("runner_shot: no frame drawn (window occluded?)")
		get_tree().quit(1)
		return
	if _shot >= _times.size() or _elapsed < _times[_shot]:
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s_%d.png" % [_out_path.get_basename(), _shot]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := image.save_png(path)
	print("[runner_shot] saved %s t=+%.1fs err=%d" % [path, _times[_shot], err])
	_shot += 1
	if _shot >= _times.size():
		_done = true
		get_tree().quit(0 if err == OK else 1)
