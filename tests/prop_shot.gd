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
var _pose: String = "stand"
var _wait: float = 2.0
var _yaw_deg: float = 34.0
var _dist: float = 0.0   # 0 keeps each prop's authored framing
var _lift: float = -99.0
var _look_y: float = -99.0
var _look_z: float = -99.0
var _idx: int = 0
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
			"pose": _pose = parts[1]
			"out": _out_path = parts[1]
			"w": width = int(parts[1])
			"h": height = int(parts[1])
			"wait": _wait = float(parts[1])
			"yaw": _yaw_deg = float(parts[1])
			"dist": _dist = float(parts[1])
			"lift": _lift = float(parts[1])
			"look_y": _look_y = float(parts[1])
			"look_z": _look_z = float(parts[1])
			"idx": _idx = int(parts[1])
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_set_position(Vector2i(40, 60))

	# bearcourse brings its own world (the real course lights, sky and deck), so
	# the neutral studio set is skipped for it.
	if _prop != "bearcourse":
		_build_set()
	match _prop:
		"wind":
			_build_wind()
		"icicle":
			_build_icicle()
		"bear":
			_build_bear()
		"bearcourse":
			_build_bear_course()
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


## Trackside wildlife. The bear faces -Z, so yaw=180 is a face-on shot, yaw=90
## a broadside and yaw=0 a rear view. A 1 m scale post stands beside it: a
## procedural animal that reads fine in isolation is easy to build at completely
## the wrong size for the course.
##
##   godot res://tests/prop_shot.tscn -- prop=bear pose=sit yaw=145 \
##       out=qa_shots/props/bear_sit.png
func _build_bear() -> void:
	var bear := PolarBear.new()
	match _pose:
		"sit":
			bear.configure(PolarBear.Pose.SITTING)
		"lie":
			bear.configure(PolarBear.Pose.LYING)
		_:
			bear.configure(PolarBear.Pose.STANDING)
	add_child(bear)

	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.06, 1.0, 0.06)
	post.mesh = post_mesh
	post.material_override = VisualLibrary.rock_material(Color(0.85, 0.25, 0.2))
	post.position = Vector3(1.9, 0.5, 0.6)
	add_child(post)

	_place_camera(Vector3(0.0, 0.78, -0.2), 4.6, 0.30)


## In-course placement check: builds the REAL glacier course and frames the
## idx-th trackside bear from the racing line. Judging a prop in a studio set
## says nothing about whether it is bedded on the shoulder, clear of the deck
## and clear of the cliff runs; this does.
##
##   godot res://tests/prop_shot.tscn -- prop=bearcourse idx=2 wait=6 \
##       out=qa_shots/props/bear_course2.png
func _build_bear_course() -> void:
	var script: GDScript = load("res://scripts/courses/course_glacier.gd")
	var course := script.new() as Node3D
	course.add_to_group(&"course")
	add_child(course)
	var bears: Array[Node] = []
	for child: Node in course.get_children():
		if child is PolarBear:
			bears.append(child)
	if bears.is_empty():
		push_error("prop_shot: the glacier built no bears")
		return
	print("[prop_shot] bears on course: %d" % bears.size())
	var bear := bears[clampi(_idx, 0, bears.size() - 1)] as Node3D
	var guide: PathGuide = course.get("main_guide")
	var offset := float(guide.nearest(bear.global_position, -1)["offset"])
	var track := guide.position_at(offset)
	var tangent := guide.transform_at(offset).basis.z
	# Ground check: a shoulder prop that is bedded at deck height but has no
	# collidable floor under it is standing on thin air, which a 2.5 m animal
	# shows and a 40 cm drift mound hides. Probe under the bear's four corners.
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var report := PackedStringArray()
	for probe: Vector3 in [Vector3.ZERO, Vector3(0.45, 0, 0), Vector3(-0.45, 0, 0),
			Vector3(0, 0, 1.2), Vector3(0, 0, -1.2)]:
		var origin := track if probe == Vector3.ZERO and _idx < 0 else bear.global_position
		var from := origin + bear.global_transform.basis * probe + Vector3.UP * 4.0
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 25.0)
		var hit := space.intersect_ray(query)
		report.append("none" if hit.is_empty() else "%.2f" % (bear.global_position.y - float((hit["position"] as Vector3).y)))
	var ctrl_query := PhysicsRayQueryParameters3D.create(
		track + Vector3.UP * 4.0, track + Vector3.DOWN * 25.0)
	var ctrl_hit := space.intersect_ray(ctrl_query)
	print("[prop_shot] control probe on the racing line: %s"
		% ("MISS (harness fault)" if ctrl_hit.is_empty() else "hit"))
	print("[prop_shot] bear %d at %v, track centre %v, lateral %.2f m, drop %.2f m, ground under [%s]"
		% [_idx, bear.global_position, track,
			Vector2(bear.global_position.x - track.x, bear.global_position.z - track.z).length(),
			track.y - bear.global_position.y, ", ".join(report)])
	var camera := Camera3D.new()
	# Eye height and standoff of a racer coming down the track at it.
	var outward := (bear.global_position - track)
	outward.y = 0.0
	if _pose == "aerial":
		# Raised three-quarter from outside the shoulder: shows the bear, the
		# ground under it AND the deck edge it must be clear of, in one frame.
		camera.position = bear.global_position + Vector3.UP * 4.0 \
			+ outward.normalized() * 5.5 + tangent * 7.0
	else:
		# Default: a racer's eye on the racing line. This is the view that
		# actually ships, so it is the one placement is judged from.
		camera.position = track + Vector3.UP * 2.2 + tangent * 9.0 \
			+ outward.normalized() * 2.0
	camera.fov = 60.0
	add_child(camera)
	camera.look_at(bear.global_position + Vector3.UP * 0.7, Vector3.UP)
	camera.current = true


## dist / lift / look_y from the command line override the prop's authored
## framing, which is how a head close-up is taken without editing this file.
func _place_camera(look_at_point: Vector3, distance: float, lift: float) -> void:
	if _dist > 0.0:
		distance = _dist
	if _lift > -90.0:
		lift = _lift
	if _look_y > -90.0:
		look_at_point.y = _look_y
	if _look_z > -90.0:
		look_at_point.z = _look_z
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
