extends Node3D
## Visual QA for boost pads: one pad on a snow slab, angled camera, PNG after
## a short delay so the arrow animation is mid-scroll. Run WITH a window:
##   godot res://tests/pad_shot.tscn -- out=qa_shots/pad.png [wait=1.3]

var _out_path: String = "qa_shots/pad.png"
var _wait: float = 1.3
var _elapsed: float = 0.0
var _done: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"out": _out_path = parts[1]
			"wait": _wait = float(parts[1])
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var floor_body := StaticBody3D.new()
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	floor_mesh.material_override = TrackBuilder.surface_material(SurfacesDB.Surface.PACKED_SNOW)
	floor_body.add_child(floor_mesh)
	add_child(floor_body)

	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, 20))
	curve.add_point(Vector3(0, 0, -20))
	var guide := PathGuide.new(curve)
	TrackBuilder.add_boost_pad(self, guide, guide.length * 0.5)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.3
	add_child(light)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.5, 0.7, 0.9)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.85, 0.95)
	environment.ambient_light_energy = 0.7
	env.environment = environment
	add_child(env)

	var camera := Camera3D.new()
	var topdown := false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "topdown=1":
			topdown = true
	if topdown:
		# Screen-up = world -Z = travel direction: arrows must point up.
		camera.look_at_from_position(Vector3(0, 11.0, 0.001), Vector3.ZERO, Vector3(0, 0, -1))
	else:
		camera.look_at_from_position(Vector3(3.5, 5.5, 8.0), Vector3(0, 0, -1.0), Vector3.UP)
	add_child(camera)
	camera.make_current()


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed < _wait:
		return
	_done = true
	_capture()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var err := image.save_png(_out_path)
	print("[pad_shot] saved %s err=%d" % [_out_path, err])
	get_tree().quit(0 if err == OK else 1)
