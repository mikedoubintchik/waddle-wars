extends Node3D
## Runtime Mobile-renderer QA capture for authored shared penguin.

const HERO_SCENE := preload("res://assets/art/characters/hero_penguin_v1.tscn")

var _hero: HeroPenguinRig
var _facade: PenguinVisual
var _camera: Camera3D
var _view_name: String = "close"
var _orientation_name: String = "landscape"
var _render_name: String = "beauty"
var _role_name: String = "hero"
var _cosmetic_config: Dictionary = {}


func _ready() -> void:
	var output_dir := "/tmp/waddle-hero-penguin-captures"
	for argument: String in OS.get_cmdline_user_args():
		var normalized := argument.trim_prefix("--")
		if normalized.begins_with("output="):
			output_dir = normalized.trim_prefix("output=")
		elif normalized.begins_with("view="):
			_view_name = normalized.trim_prefix("view=")
		elif normalized.begins_with("orientation="):
			_orientation_name = normalized.trim_prefix("orientation=")
		elif normalized.begins_with("render="):
			_render_name = normalized.trim_prefix("render=")
		elif normalized.begins_with("role="):
			_role_name = normalized.trim_prefix("role=").to_lower()
		elif normalized.begins_with("hat="):
			_cosmetic_config["hat"] = normalized.trim_prefix("hat=")
		elif normalized.begins_with("scarf="):
			_cosmetic_config["scarf"] = normalized.trim_prefix("scarf=")
		elif normalized.begins_with("goggles="):
			_cosmetic_config["goggles"] = normalized.trim_prefix("goggles=")
	get_window().size = Vector2i(720, 1280) if _orientation_name == "portrait" else Vector2i(1280, 720)
	_build_stage()
	_configure_camera()
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _capture_pose(output_dir, "neutral", PenguinVisual.Pose.IDLE, &"countdown_idle", 0.45)
	await _capture_pose(output_dir, "run", PenguinVisual.Pose.RUN, &"run", 0.43)
	await _capture_pose(output_dir, "jump", PenguinVisual.Pose.AIR, &"jump_air", 0.34)
	await _capture_pose(output_dir, "slide", PenguinVisual.Pose.SLIDE, &"slide_loop", 0.28)
	await _capture_pose(output_dir, "hit", PenguinVisual.Pose.STUN, &"hit_left", 0.16)
	await _capture_pose(output_dir, "celebrate", PenguinVisual.Pose.CELEBRATE, &"celebration", 0.32)
	print("HERO PENGUIN CAPTURE: PASS %s" % output_dir)
	get_tree().quit()


func _process(delta: float) -> void:
	if _facade != null:
		_facade.tick(delta, 1.0)
	elif _hero != null:
		_hero.tick(delta)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("3f4b58")
	sky_material.sky_horizon_color = Color("89949d")
	sky_material.ground_bottom_color = Color("48515a")
	sky_material.ground_horizon_color = Color("8f989d")
	sky_material.sun_angle_max = 18.0
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d8dde0")
	# Neutral review light preserves cream detail and dark-feather roughness. The
	# previous hot key/white fill clipped bill and snow values, hiding whether a
	# material was genuinely premium or merely overexposed.
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	ground.mesh = plane
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color("4f5861")
	snow.roughness = 0.82
	snow.metallic = 0.0
	ground.material_override = snow
	ground.position.y = -0.01
	add_child(ground)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key.light_color = Color("fff1cf")
	key.light_energy = 0.54
	key.shadow_enabled = true
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25.0, 145.0, 18.0)
	rim.light_color = Color("b9d8e5")
	rim.light_energy = 0.12
	add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.3, 1.7, 2.8)
	fill.light_color = Color("fff8e8")
	fill.light_energy = 0.12
	fill.omni_range = 6.0
	add_child(fill)

	if _cosmetic_config.is_empty():
		_hero = HERO_SCENE.instantiate() as HeroPenguinRig
		_hero.configure("emperor", Color("2fe0df"))
		add_child(_hero)
		if _role_name == "racer":
			_hero.set_render_role(HeroPenguinRig.RACER_ROLE)
	else:
		_facade = PenguinVisual.new()
		add_child(_facade)
		var look_config := {
			"species": "emperor",
			"accent_color": Color("2fe0df"),
		}
		look_config.merge(_cosmetic_config, true)
		_facade.setup_look(CharacterLook.from_legacy_config(
				look_config, CharacterLook.RenderRole.HERO))
		# Restore source-space review scale; gameplay still owns 0.54 wrapper scale.
		_facade.scale = Vector3.ONE / PenguinVisual.AUTHORED_HERO_GAME_SCALE
		_hero = _facade.find_child("AuthoredHeroPenguin", false, false) as HeroPenguinRig
		if _role_name == "racer":
			_facade.set_render_role(PenguinVisual.RenderRole.RACER)
	if _render_name == "silhouette" and _hero != null:
		var silhouette := StandardMaterial3D.new()
		silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		silhouette.albedo_color = Color("10151e")
		for child: Node in _hero.find_children("*", "GeometryInstance3D", true, false):
			(child as GeometryInstance3D).material_override = silhouette

	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true


func _configure_camera() -> void:
	if _view_name == "chase":
		_camera.position = Vector3(0.0, 2.42, 6.15 if _orientation_name == "portrait" else 5.25)
		_camera.fov = 30.0
	elif _view_name == "side":
		_camera.position = Vector3(4.6, 1.55, 0.0)
		_camera.fov = 30.0
	elif _view_name == "threequarter":
		_camera.position = Vector3(2.1 if _orientation_name == "portrait" else 3.15,
				2.05, -5.25 if _orientation_name == "portrait" else -4.65)
		_camera.fov = 28.0
	else:
		_camera.position = Vector3(0.0, 1.72,
				-4.65 if _orientation_name == "portrait" else -4.05)
		_camera.fov = 27.0
	_camera.look_at_from_position(_camera.position, Vector3(0.0, 0.93, 0.0), Vector3.UP)


func _capture_pose(output_dir: String, label: String, pose: int,
		clip: StringName, settle_seconds: float) -> void:
	_configure_pose_camera(label)
	_hero.set_pose(pose)
	_hero.play_state(clip, clip in HeroPenguinRig.LOOP_CLIPS)
	_hero.position.y = 0.36 if label == "jump" else 0.0
	var frames := maxi(3, ceili(settle_seconds * 60.0))
	for _frame: int in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var suffix := ""
	if _render_name != "beauty":
		suffix += "_%s" % _render_name
	for key: String in ["hat", "scarf", "goggles"]:
		if _cosmetic_config.has(key):
			suffix += "_%s" % String(_cosmetic_config[key])
	var path := output_dir.path_join("hero_penguin_%s_%s_%s%s.png" % [
		label, _view_name, _orientation_name, suffix])
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])


func _configure_pose_camera(label: String) -> void:
	_configure_camera()
	var target := Vector3(0.0, 0.93, 0.0)
	if label == "jump":
		target.y = 1.16
	elif label == "slide":
		target = Vector3(0.0, 0.50, -0.02)
		if _view_name == "side":
			# True orthographic-like profile proves face lift and slide clearance.
			_camera.position = Vector3(4.6, 0.72, 0.0)
			_camera.fov = 29.0
		elif _view_name == "close":
			_camera.position = Vector3(3.7, 0.86, -2.75)
			_camera.fov = 31.0
		else:
			# Rear chase stays recognizable without collapsing into a tail blob.
			_camera.position = Vector3(3.65, 1.30, 3.65)
			_camera.fov = 31.0
	elif label == "hit":
		target.y = 0.90
	elif label == "celebrate":
		target.y = 1.05
	_camera.look_at_from_position(_camera.position, target, Vector3.UP)
