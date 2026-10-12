extends Node3D
## Windowed pixel proof of production material probe geometry. Positive cases
## use StandardMaterial3D with ordinary back-face culling; reversed winding is
## a negative control. Run through an isolated-user-data test wrapper.
##
## godot --path . --rendering-method gl_compatibility \
##     res://tests/shader_warmup_raster_test.tscn -- out=/tmp/warmup_raster.png

const COLOURS: Array[Color] = [Color.WHITE, Color.CYAN, Color.GREEN, Color.MAGENTA]
const CASE_NAMES: PackedStringArray = [
	"ordinary_back_cull", "billboard_discards_scale", "billboard_keeps_scale",
	"reversed_winding_negative_control",
]

var _out_path: String = "user://qa/shader_warmup_raster.png"
var _camera: Camera3D = null
var _warmup: ShaderWarmup = null
var _probes: Array[MeshInstance3D] = []
var _started_usec: int = 0
var _finished: bool = false


func _ready() -> void:
	_started_usec = Time.get_ticks_usec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_path = arg.trim_prefix("out=")
	if GameConfig.is_headless():
		push_error("shader_warmup_raster requires a rendering window")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_environment.environment = environment
	add_child(world_environment)
	_camera = Camera3D.new()
	_camera.fov = 68.0
	_camera.near = 0.05
	add_child(_camera)
	_camera.make_current()
	# Keep the spawner out of the scene tree so its automatic resource queue
	# cannot add unrelated geometry. These are its real production spawn paths,
	# at its production anchor distance and cell positions.
	_warmup = ShaderWarmup.new()
	_warmup._anchor = Node3D.new()
	_camera.add_child(_warmup._anchor)
	_warmup._anchor.position.z = -ShaderWarmup.ANCHOR_DISTANCE
	for index: int in 3:
		var material := StandardMaterial3D.new()
		material.albedo_color = COLOURS[index]
		material.cull_mode = BaseMaterial3D.CULL_BACK
		material.roughness = 1.0
		if index > 0:
			material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			material.billboard_keep_scale = index == 2
		_warmup._spawn_material(material)
		_probes.append(_warmup._anchor.get_child(index) as MeshInstance3D)
	_add_reversed_winding_control()
	for frame: int in 3:
		await RenderingServer.frame_post_draw
	_verify_pixels()


func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_usec() - _started_usec > 20_000_000:
		_finished = true
		push_error("shader_warmup_raster timed out waiting for rendered frame")
		get_tree().quit(1)


func _add_reversed_winding_control() -> void:
	var source := _probes[0].mesh
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in [0, 2, 1]:
		st.set_normal(Vector3.BACK)
		st.add_vertex(vertices[index])
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOURS[3]
	material.cull_mode = BaseMaterial3D.CULL_BACK
	var control := MeshInstance3D.new()
	control.mesh = mesh
	control.material_override = material
	control.scale = _probes[0].scale
	control.position = ShaderWarmup._probe_cell(3)
	_warmup._anchor.add_child(control)
	_probes.append(control)


func _verify_pixels() -> void:
	_finished = true
	var captured := get_viewport().get_texture().get_image()
	if captured == null or captured.is_empty():
		push_error("shader_warmup_raster received no viewport pixels")
		get_tree().quit(1)
		return
	var success := true
	var results: Array[Dictionary] = []
	var crop_bounds := Rect2()
	for index: int in _probes.size():
		var centre := _camera.unproject_position(_probes[index].global_position)
		var count := 0
		for y: int in range(maxi(0, floori(centre.y) - 16),
				mini(captured.get_height(), ceili(centre.y) + 17)):
			for x: int in range(maxi(0, floori(centre.x) - 16),
					mini(captured.get_width(), ceili(centre.x) + 17)):
				if _matches_colour(captured.get_pixel(x, y), COLOURS[index]):
					count += 1
		var passed := count == 0 if index == 3 else count >= 3 and count <= 100
		success = success and passed
		results.append({"case": CASE_NAMES[index], "pixels": count, "passed": passed,
				"centre": [centre.x, centre.y]})
		print("[shader_warmup_raster] %s %s pixels=%d" % [
				"PASS" if passed else "FAIL", CASE_NAMES[index], count])
		var case_bounds := Rect2(centre - Vector2.ONE * 18.0, Vector2.ONE * 36.0)
		crop_bounds = case_bounds if index == 0 else crop_bounds.merge(case_bounds)
	var absolute_path := ProjectSettings.globalize_path(_out_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var save_error := captured.save_png(absolute_path)
	var crop := captured.get_region(Rect2i(crop_bounds).intersection(
			Rect2i(Vector2i.ZERO, captured.get_size())))
	crop.resize(crop.get_width() * 6, crop.get_height() * 6, Image.INTERPOLATE_NEAREST)
	var zoom_error := crop.save_png(absolute_path.get_basename() + "_zoom.png")
	success = success and save_error == OK and zoom_error == OK
	var report := {
		"passed": success,
		"renderer": RenderingServer.get_current_rendering_method(),
		"viewport": [captured.get_width(), captured.get_height()],
		"image": absolute_path,
		"zoom_nearest_6x": absolute_path.get_basename() + "_zoom.png",
		"cases": results,
	}
	var file := FileAccess.open(absolute_path.get_basename() + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	else:
		success = false
	print("[shader_warmup_raster] DONE passed=%s output=%s" % [success, absolute_path])
	get_tree().quit(0 if success else 1)


func _matches_colour(pixel: Color, expected: Color) -> bool:
	return (pixel.r > 0.45 if expected.r > 0.5 else pixel.r < 0.20) \
			and (pixel.g > 0.45 if expected.g > 0.5 else pixel.g < 0.20) \
			and (pixel.b > 0.45 if expected.b > 0.5 else pixel.b < 0.20)


func _exit_tree() -> void:
	if _warmup != null:
		_warmup._anchor = null
		_warmup.free()
