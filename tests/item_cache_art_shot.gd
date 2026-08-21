extends Node3D
## Windowed Compatibility visual QA for the authored expedition item cache.
##
## godot --rendering-method gl_compatibility --path . \
##   res://tests/item_cache_art_shot.tscn -- \
##   mode=bright out=qa_shots/interactives/item_cache/bright_1920x1080.png
## Modes: bright, dark, distance. Use wait>=1.5 to review authored hover motion.

var _mode := "bright"
var _out := "qa_shots/interactives/item_cache/bright_1920x1080.png"
var _wait := 1.8
var _elapsed := 0.0
var _captured := false


func _ready() -> void:
	var width := 1920
	var height := 1080
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", false, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"mode": _mode = parts[1]
			"out": _out = parts[1]
			"wait": _wait = float(parts[1])
			"w": width = int(parts[1])
			"h": height = int(parts[1])
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()
	SettingsManager.set_setting("display", "particle_quality", "high")
	Game.mode = Game.Mode.QUICK_RACE
	_build_world(_mode == "dark")
	match _mode:
		"distance": _build_distance_set()
		"dark": _build_close_set(true)
		_:
			_build_close_set(false)


func _build_world(dark: bool) -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	if dark:
		sky_material.sky_top_color = Color(0.008, 0.020, 0.060)
		sky_material.sky_horizon_color = Color(0.035, 0.090, 0.160)
		sky_material.ground_bottom_color = Color(0.008, 0.015, 0.030)
		sky_material.ground_horizon_color = Color(0.025, 0.055, 0.095)
	else:
		sky_material.sky_top_color = Color(0.10, 0.30, 0.62)
		sky_material.sky_horizon_color = Color(0.63, 0.80, 0.91)
		sky_material.ground_bottom_color = Color(0.37, 0.55, 0.68)
		sky_material.ground_horizon_color = Color(0.65, 0.79, 0.88)
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.48 if dark else 0.82
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05 if dark else 0.92
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.04, 0.09, 0.16) if dark \
		else Color(0.52, 0.69, 0.80)
	environment.fog_density = 0.006 if dark else 0.003
	environment_node.environment = environment
	add_child(environment_node)

	var key := DirectionalLight3D.new()
	key.light_color = Color(0.68, 0.80, 1.0) if dark else Color(1.0, 0.94, 0.82)
	key.light_energy = 0.72 if dark else 1.35
	key.rotation_degrees = Vector3(-44.0, -34.0, 0.0)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 90.0
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.34, 0.22, 0.62) if dark else Color(0.30, 0.57, 0.75)
	fill.light_energy = 0.45 if dark else 0.28
	fill.rotation_degrees = Vector3(-24.0, 142.0, 0.0)
	fill.shadow_enabled = false
	add_child(fill)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(140.0, 180.0)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.025, 0.055, 0.095) if dark \
		else Color(0.76, 0.84, 0.88)
	floor_material.roughness = 0.80
	floor.material_override = floor_material
	add_child(floor)


func _build_close_set(dark: bool) -> void:
	for index: int in 3:
		var cache := ItemBox.new()
		cache.position = Vector3(-2.35 + index * 2.35, 1.1,
			-0.25 - abs(index - 1) * 0.20)
		add_child(cache)
	var camera := Camera3D.new()
	camera.fov = 44.0
	camera.position = Vector3(5.4, 3.35, 7.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.05, -0.2), Vector3.UP)
	camera.make_current()
	if dark:
		var cave_mass := MeshInstance3D.new()
		var cave_mesh := BoxMesh.new()
		cave_mesh.size = Vector3(16.0, 7.0, 1.0)
		cave_mass.mesh = cave_mesh
		var cave_material := StandardMaterial3D.new()
		cave_material.albedo_color = Color(0.015, 0.035, 0.075)
		cave_material.roughness = 0.72
		cave_mass.material_override = cave_material
		cave_mass.position = Vector3(0.0, 3.0, -4.0)
		add_child(cave_mass)


func _build_distance_set() -> void:
	for placement: Vector3 in [
		Vector3(-2.4, 1.1, -3.0),
		Vector3(1.8, 1.1, -20.0),
		Vector3(-1.4, 1.1, -52.0),
	]:
		var cache := ItemBox.new()
		cache.position = placement
		add_child(cache)
	for lane: float in [-3.7, 3.7]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(0.18, 0.28, 72.0)
		rail.mesh = rail_mesh
		var rail_material := StandardMaterial3D.new()
		rail_material.albedo_color = Color(0.045, 0.17, 0.28)
		rail_material.roughness = 0.65
		rail.material_override = rail_material
		rail.position = Vector3(lane, 0.14, -28.0)
		add_child(rail)
	var camera := Camera3D.new()
	camera.fov = 50.0
	camera.position = Vector3(0.0, 3.2, 8.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -30.0), Vector3.UP)
	camera.make_current()


func _process(delta: float) -> void:
	_elapsed += delta
	if _captured or _elapsed < _wait:
		return
	_captured = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var output := _absolute_output(_out)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var error := image.save_png(output)
	print("[item-cache-shot] mode=%s out=%s %dx%d err=%d" % [
		_mode, output, image.get_width(), image.get_height(), error])
	get_tree().quit(0 if error == OK else 1)


func _absolute_output(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)
