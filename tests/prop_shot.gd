extends Node3D
## Visual QA for hazard props in isolation.
##
## Racing past an obstacle on autopilot is a bad way to judge one: you get it
## for a third of a second, at whatever angle the course happens to give, and
## only if the timing lands. This stands a single hazard in a neutral daylight
## set with a fixed camera, so a change to its geometry can actually be looked
## at. Must run WITH a window -- there is nothing to capture headless.
##
##   godot res://tests/prop_shot.tscn -- prop=wind out=qa_shots/props/wind.png \
##       [w=1600 h=900] [wait=2.0] [yaw=35]

var _out_path: String = "qa_shots/props/prop.png"
var _prop: String = "wind"
var _wait: float = 2.0
var _yaw_deg: float = 34.0
var _elapsed: float = 0.0
var _done: bool = false


func _ready() -> void:
	var width := 1600
	var height := 900
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"prop": _prop = parts[1]
			"out": _out_path = parts[1]
			"w": width = int(parts[1])
			"h": height = int(parts[1])
			"wait": _wait = float(parts[1])
			"yaw": _yaw_deg = float(parts[1])
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_set_position(Vector2i(40, 60))

	_build_set()
	match _prop:
		"wind":
			_build_wind()
		"icicle":
			_build_icicle()
		_:
			push_error("prop_shot: unknown prop '%s'" % _prop)


## Neutral overcast-blue daylight and a snow deck, so the prop is judged on its
## own silhouette rather than on a course's grade.
func _build_set() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.38, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.86, 0.98)
	sky_mat.ground_bottom_color = Color(0.6, 0.72, 0.86)
	sky_mat.ground_horizon_color = Color(0.72, 0.86, 0.98)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.92
	e.tonemap_white = 6.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_blur = 1.6
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	floor_mesh.mesh = plane
	floor_mesh.material_override = VisualLibrary.snow_material(
		Color(0.94, 0.96, 1.0), 0.5, 1.0, 0.4)
	add_child(floor_mesh)

	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	add_child(body)


func _build_wind() -> void:
	var zone := HazardWindZone.new()
	zone.configure(Vector3.RIGHT, 6.0, Vector3(16.0, 8.0, 30.0))
	zone.position = Vector3(0.0, 4.0, 0.0)
	add_child(zone)
	_place_camera(Vector3(0.0, 4.5, 0.0), 34.0, 0.42)


func _build_icicle() -> void:
	# An overhang for them to hang from, so the cluster is judged where it
	# actually lives rather than floating in mid-air.
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(14.0, 0.9, 8.0)
	roof.mesh = roof_mesh
	roof.material_override = VisualLibrary.rock_material(Color(0.72, 0.82, 0.95))
	roof.position = Vector3(0.0, 6.05, 0.0)
	add_child(roof)
	for i: int in 3:
		var spike := HazardIcicle.new()
		spike.position = Vector3(-3.0 + float(i) * 3.0, 4.5, 0.0)
		add_child(spike)
	_place_camera(Vector3(0.0, 3.7, 0.0), 7.5, 0.02)


func _place_camera(look_at_point: Vector3, distance: float, lift: float) -> void:
	var camera := Camera3D.new()
	var yaw := deg_to_rad(_yaw_deg)
	var offset := Vector3(sin(yaw), lift, cos(yaw)).normalized() * distance
	camera.position = look_at_point + offset
	camera.fov = 55.0
	add_child(camera)
	camera.look_at(look_at_point, Vector3.UP)
	camera.current = true


func _process(delta: float) -> void:
	if _done:
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
	print("[prop_shot] saved %s" % _out_path)
	get_tree().quit()
