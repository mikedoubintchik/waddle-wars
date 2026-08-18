extends Node
## TEMPORARY visual probe: builds RunnerTrack alone and photographs it from the
## real chase-camera pose at chosen distances, so ramps, tunnels, crates and the
## biome bands can be inspected without depending on the autopilot surviving.

const SHOTS: Array = [
	{"z": -150.0, "name": "day"},
	{"z": -430.0, "name": "day2"},
	{"z": -760.0, "name": "dusk"},
	{"z": -1290.0, "name": "cave"},
	{"z": -1560.0, "name": "cave3"},
	{"z": -1930.0, "name": "night"},
	{"z": -2180.0, "name": "night2"},
]

var _track: RunnerTrack = null
var _camera: Camera3D = null
var _shot: int = 0
var _settle: int = 0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	_build_environment()
	_track = RunnerTrack.new()
	add_child(_track)
	_track.setup(4242)
	_camera = Camera3D.new()
	_camera.fov = 74.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.make_current()
	# Stream the whole way to the first target so the streamer's state (ramp
	# corridors, crate spacing, tunnel runs) matches a real run.
	_stream_to(SHOTS[0]["z"])
	_place(SHOTS[0]["z"])


func _stream_to(z: float) -> void:
	var step := RunnerConfig.CHUNK_LENGTH
	var at := 0.0
	while at > z:
		at -= step
		for i: int in 3:
			_track.update_stream(at, clampf(absf(at) / 2600.0, 0.0, 1.0))


func _place(z: float) -> void:
	_camera.position = Vector3(0.0, 2.55, z + 5.9)
	_camera.look_at(Vector3(0.0, 1.35, z - 11.0), Vector3.UP)


func _process(_delta: float) -> void:
	if _shot >= SHOTS.size():
		return
	_settle += 1
	if _settle < 12:
		return
	_settle = 0
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "qa_shots/runner/probe_%s.png" % SHOTS[_shot]["name"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	image.save_png(path)
	print("[probe] saved %s at z=%.0f" % [path, SHOTS[_shot]["z"]])
	_shot += 1
	if _shot >= SHOTS.size():
		get_tree().quit(0)
		return
	_stream_to(SHOTS[_shot]["z"])
	_place(SHOTS[_shot]["z"])


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.26, 0.68)
	sky_mat.sky_horizon_color = Color(0.66, 0.83, 0.98)
	sky_mat.ground_bottom_color = Color(0.44, 0.62, 0.85)
	sky_mat.ground_horizon_color = Color(0.66, 0.83, 0.98)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.74
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.66, 0.86)
	env.fog_density = 0.0022
	env.fog_aerial_perspective = 0.3
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.32
	sun.rotation_degrees = Vector3(-38.0, 152.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
