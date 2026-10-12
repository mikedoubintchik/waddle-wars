extends Node3D
## Visual QA for the crepuscular rays (SunShafts).
##
## The rays only exist when the camera is looking toward the key light, which
## is exactly the frame a race capture almost never gives you: the chase camera
## points down-track, and the sun is usually off to one side. This builds a real
## course, finds its key light, and stands a camera on the racing line looking
## straight into it — the one view the effect is authored for. Run WITH a
## window; there is nothing to capture headless.
##
##   godot res://tests/shaft_shot.tscn -- course=iceberg out=qa_shots/shafts/x.png \
##       [yaw_off=25] [pitch=6] [wait=2.5]

var _course_id: String = "iceberg"
var _out_path: String = "qa_shots/shafts/shaft.png"
var _wait: float = 2.5
## Degrees to swing the camera off the sun bearing, so the fan can be judged
## off-centre as well as head-on.
var _yaw_off: float = 0.0
var _pitch: float = 8.0
var _offset: float = 40.0
var _elapsed: float = 0.0
var _done: bool = false
var _camera: Camera3D = null


func _ready() -> void:
	var width := 1600
	var height := 900
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"course": _course_id = parts[1]
			"out": _out_path = parts[1]
			"w": width = int(parts[1])
			"h": height = int(parts[1])
			"wait": _wait = float(parts[1])
			"yaw_off": _yaw_off = float(parts[1])
			"pitch": _pitch = float(parts[1])
			"offset": _offset = float(parts[1])
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	# An occluded window never draws, and a harness that waits on
	# frame_post_draw then hangs forever with no output. Raise it.
	DisplayServer.window_move_to_foreground()

	var info := CoursesDB.get_item(_course_id)
	var script: GDScript = load(String(info.get("script", "")))
	var course := script.new() as CourseBase
	course.course_id = _course_id
	course.add_to_group(&"course")
	add_child(course)
	await course.build_ready()

	var light: DirectionalLight3D = null
	for child: Node in course.get_children():
		if child is DirectionalLight3D and (child as DirectionalLight3D).shadow_enabled:
			light = child as DirectionalLight3D
			break
	if light == null:
		push_error("shaft_shot: %s built no key light" % _course_id)
		return
	var to_sun := light.global_transform.basis.z.normalized()
	print("[shaft_shot] %s sun bearing %v, shafts node: %s"
		% [_course_id, to_sun, str(course.has_node("SunShafts"))])

	# Stand on the racing line at eye height and look along the sun bearing,
	# swung by yaw_off and held near the horizon so both sky and ground show.
	var track: Vector3 = course.main_guide.position_at(_offset) + Vector3.UP * 2.0
	_camera = Camera3D.new()
	_camera.fov = 68.0
	_camera.position = track
	add_child(_camera)
	var flat := Vector3(to_sun.x, 0.0, to_sun.z).normalized().rotated(Vector3.UP, deg_to_rad(_yaw_off))
	var aim := (flat + Vector3.UP * tan(deg_to_rad(_pitch))).normalized()
	_camera.look_at(track + aim * 100.0, Vector3.UP)
	_camera.current = true


func _process(delta: float) -> void:
	if _done or _camera == null:
		return
	_elapsed += delta
	if _elapsed < _wait:
		return
	_done = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dir := _out_path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	image.save_png(_out_path)
	print("[shaft_shot] saved %s" % _out_path)
	get_tree().quit()
