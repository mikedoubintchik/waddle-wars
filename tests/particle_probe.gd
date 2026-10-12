extends Node3D
## Prints the live state of a course's atmospheric emitters (snowfall,
## spindrift): whether they exist, where they are relative to the camera, and
## whether they are actually emitting. A particle layer that is present in the
## scene tree but invisible on screen is otherwise a guessing game.
##
##   godot res://tests/particle_probe.tscn -- course=glacier

var _course_id: String = "glacier"
var _elapsed: float = 0.0
var _done: bool = false
var _course: CourseBase = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("course="):
			_course_id = arg.trim_prefix("course=")
	var info := CoursesDB.get_item(_course_id)
	var script: GDScript = load(String(info.get("script", "")))
	_course = script.new() as CourseBase
	_course.course_id = _course_id
	_course.add_to_group(&"course")
	add_child(_course)
	await _course.build_ready()
	var camera := Camera3D.new()
	camera.position = _course.main_guide.position_at(40.0) + Vector3.UP * 3.0
	add_child(camera)
	camera.look_at(_course.main_guide.position_at(90.0) + Vector3.UP * 2.0, Vector3.UP)
	camera.current = true


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed < 3.0:
		return
	_done = true
	var camera := get_viewport().get_camera_3d()
	for child: Node in _course.get_children():
		if child is not GPUParticles3D:
			continue
		var p := child as GPUParticles3D
		var mesh := p.draw_pass_1
		var mat := mesh.surface_get_material(0) if mesh != null else null
		print("[particle_probe] %s emitting=%s amount=%d pos=%v cam=%v dist=%.1f visible=%s mesh=%s mat=%s"
			% [p.name, str(p.emitting), p.amount, p.global_position,
				camera.global_position if camera != null else Vector3.ZERO,
				p.global_position.distance_to(camera.global_position) if camera != null else -1.0,
				str(p.visible), "yes" if mesh != null else "NONE",
				"yes" if mat != null else "NONE"])
	# No capture here on purpose: screenshot_tour and shaft_shot own that, and
	# awaiting frame_post_draw from inside _process on the way to quit() hung
	# this harness. It reports state; the other two draw pictures.
	get_tree().quit()
