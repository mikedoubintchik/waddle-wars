extends Node
## Windowed visual QA harness.
## godot res://tests/utility_frontend_shot.tscn -- \
##     screen=settings out=/tmp/settings.png w=540 h=960 touch=1

const SCENES: Dictionary = {
	"achievements": "res://scenes/menus/achievements.tscn",
	"settings": "res://scenes/menus/settings.tscn",
	"leaderboard": "res://scenes/menus/leaderboard.tscn",
	"controls": "res://scenes/menus/controls.tscn",
	"controls_capture": "res://scenes/menus/controls.tscn",
	"credits": "res://scenes/menus/credits.tscn",
}

var _screen: String = "settings"
var _out: String = "qa_shots/utility/settings.png"
var _wait: float = 1.2
var _elapsed: float = 0.0
var _captured: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var width := 1920
	var height := 1080
	var reduced := false
	var emulate_touch := false
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
			"touch": emulate_touch = parts[1].to_lower() in ["1", "true", "yes"]
	# Match a real phone's two coupled paths: touch metrics plus the
	# orientation-aware canvas shrink from SettingsManager.
	GameConfig.force_touch = emulate_touch
	var display: Dictionary = SettingsManager.settings.get("display", {}).duplicate(true)
	display["window_mode"] = "windowed"
	display["resolution"] = "%dx%d" % [width, height]
	SettingsManager.settings["display"] = display
	var accessibility: Dictionary = SettingsManager.settings.get(
		"accessibility", {}).duplicate(true)
	accessibility["ui_scale"] = 1.0
	accessibility["reduced_flashing"] = reduced
	SettingsManager.settings["accessibility"] = accessibility
	SettingsManager.apply_all()
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_move_to_foreground()
	if _screen == "pause":
		_build_pause_stage()
		return
	var path := String(SCENES.get(_screen, SCENES["settings"]))
	var packed := load(path) as PackedScene
	if packed == null:
		get_tree().quit(2)
		return
	var screen := packed.instantiate()
	add_child(screen)
	if _screen == "controls_capture":
		screen.call_deferred("_begin_capture", "jump", "key")


func _build_pause_stage() -> void:
	var stage := ColorRect.new()
	stage.color = Color(0.08, 0.18, 0.30)
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stage)
	var menu := PauseMenu.new()
	add_child(menu)
	menu.call_deferred("toggle")


func _process(delta: float) -> void:
	_elapsed += delta
	if _captured or _elapsed < _wait:
		return
	_captured = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var error := image.save_png(_out)
	print("[utility-shot] %s %dx%d err=%d" % [
		_out, image.get_width(), image.get_height(), error])
	if get_tree().paused:
		get_tree().paused = false
	get_tree().quit(0 if error == OK else 1)
