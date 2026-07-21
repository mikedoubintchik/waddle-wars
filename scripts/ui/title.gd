extends Control
## Title screen: animated 3D ice-floe diorama with idling penguins and
## falling snow behind a rocking logo. Any input advances to the main menu.

var _elapsed: float = 0.0
var _prompt: Label
var _logo: Label
var _camera: Camera3D
var _penguins: Array[PenguinVisual] = []
var _penguin_ratios: Array[float] = []


func _ready() -> void:
	_build_diorama()
	_build_foreground()
	AudioManager.play_music("music_title")


## --- 3D diorama background -------------------------------------------------

func _build_diorama() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(viewport)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.16, 0.28, 0.5)
	sky_material.sky_horizon_color = Color(0.62, 0.76, 0.9)
	sky_material.ground_bottom_color = Color(0.1, 0.16, 0.26)
	sky_material.ground_horizon_color = Color(0.62, 0.76, 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	light.light_energy = 1.25
	light.light_color = Color(1.0, 0.96, 0.9)
	light.shadow_enabled = true
	viewport.add_child(light)

	# Ice floe.
	var floe := MeshInstance3D.new()
	var floe_mesh := CylinderMesh.new()
	floe_mesh.top_radius = 2.6
	floe_mesh.bottom_radius = 3.0
	floe_mesh.height = 0.4
	floe_mesh.radial_segments = 28
	floe.mesh = floe_mesh
	floe.material_override = PenguinVisual.get_material(Color(0.94, 0.97, 1.0), 0.0, 0.85)
	floe.position = Vector3(0, -0.2, 0)
	viewport.add_child(floe)

	# Distant water disc.
	var water := MeshInstance3D.new()
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 30.0
	water_mesh.bottom_radius = 30.0
	water_mesh.height = 0.1
	water.mesh = water_mesh
	water.material_override = PenguinVisual.get_material(Color(0.1, 0.28, 0.42), 0.1, 0.25)
	water.position = Vector3(0, -0.5, 0)
	viewport.add_child(water)

	# Penguin cast.
	var casts: Array = [
		[Vector3(-0.9, 0.0, 0.3), 0.5, "body_classic", PenguinVisual.Pose.IDLE, 0.0],
		[Vector3(0.2, 0.0, -0.4), -0.3, "body_snowy", PenguinVisual.Pose.RUN, 0.55],
		[Vector3(1.1, 0.0, 0.5), 0.9, "body_midnight", PenguinVisual.Pose.IDLE, 0.0],
	]
	for entry: Array in casts:
		var body_info := CosmeticsDB.get_item(String(entry[2]))
		var penguin := PenguinVisual.new()
		viewport.add_child(penguin)
		penguin.position = entry[0] as Vector3
		penguin.rotation.y = float(entry[1])
		penguin.setup({
			"body_color": body_info.get("body_color", Color(0.13, 0.16, 0.22)),
			"belly_color": body_info.get("belly_color", Color(0.95, 0.94, 0.9)),
		})
		penguin.set_pose(entry[3] as PenguinVisual.Pose)
		penguin.anim_speed = randf_range(0.85, 1.15)
		_penguins.append(penguin)
		_penguin_ratios.append(float(entry[4]))

	# Falling snow.
	var snow := GPUParticles3D.new()
	snow.amount = 260
	snow.lifetime = 6.0
	snow.preprocess = 6.0
	var snow_material := ParticleProcessMaterial.new()
	snow_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	snow_material.emission_box_extents = Vector3(6.0, 0.2, 6.0)
	snow_material.direction = Vector3(0, -1, 0)
	snow_material.spread = 12.0
	snow_material.initial_velocity_min = 0.5
	snow_material.initial_velocity_max = 1.1
	snow_material.gravity = Vector3(0, -0.35, 0)
	snow_material.turbulence_enabled = true
	snow_material.turbulence_noise_strength = 0.4
	snow_material.turbulence_noise_scale = 2.0
	snow.process_material = snow_material
	var flake := SphereMesh.new()
	flake.radius = 0.02
	flake.height = 0.04
	flake.radial_segments = 6
	flake.rings = 3
	var flake_material := StandardMaterial3D.new()
	flake_material.albedo_color = Color(0.98, 0.99, 1.0)
	flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake.material = flake_material
	snow.draw_pass_1 = flake
	snow.position = Vector3(0, 4.5, 0)
	viewport.add_child(snow)

	_camera = Camera3D.new()
	viewport.add_child(_camera)
	_camera.current = true
	_camera.look_at_from_position(Vector3(0.0, 1.5, -4.6), Vector3(0.0, 0.6, 0.0), Vector3.UP)


## --- Foreground UI ---------------------------------------------------------

func _build_foreground() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 34)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	_logo = Label.new()
	_logo.text = GameConfig.GAME_NAME.to_upper()
	_logo.add_theme_font_size_override("font_size", 110)
	_logo.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0))
	_logo.add_theme_color_override("font_outline_color", Color(0.05, 0.11, 0.22))
	_logo.add_theme_constant_override("outline_size", 16)
	_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_logo)

	_prompt = Label.new()
	_prompt.text = "Press Start"
	_prompt.add_theme_font_size_override("font_size", 36)
	_prompt.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	_prompt.add_theme_color_override("font_outline_color", Color(0.05, 0.11, 0.22))
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_prompt)

	var version := Label.new()
	version.text = "v%s" % GameConfig.GAME_VERSION
	version.add_theme_font_size_override("font_size", 18)
	version.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.7))
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -120.0
	version.offset_top = -36.0
	version.offset_right = -16.0
	version.offset_bottom = -12.0
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(version)


func _process(delta: float) -> void:
	_elapsed += delta
	for i: int in _penguins.size():
		_penguins[i].tick(delta, _penguin_ratios[i])
	if _camera != null:
		_camera.position.x = sin(_elapsed * 0.22) * 0.35
		_camera.position.y = 1.5 + sin(_elapsed * 0.31) * 0.12
		_camera.look_at(Vector3(0.0, 0.6, 0.0))
	if _logo != null:
		_logo.pivot_offset = _logo.size * 0.5
		_logo.rotation = sin(_elapsed * 0.9) * 0.022
	if _prompt != null:
		var reduced := bool(SettingsManager.get_setting("accessibility", "reduced_flashing"))
		var pulse_speed := 1.2 if reduced else 3.0
		_prompt.modulate.a = 0.55 + 0.45 * sin(_elapsed * pulse_speed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("pause") \
			or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed):
		AudioManager.ui_click()
		SceneRouter.go_to(Game.SCENE_MAIN_MENU)
