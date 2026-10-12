extends Node3D
## Runtime still matrix and fixed-timestep facade/AnimationPlayer motion capture.

const HERO_SCENE := preload("res://assets/art/characters/hero_penguin_v1.tscn")

var _hero: HeroPenguinRig
var _facade: PenguinVisual
var _camera: Camera3D
var _view_name: String = "close"
var _orientation_name: String = "landscape"
var _render_name: String = "beauty"
var _role_name: String = "hero"
var _cosmetic_config: Dictionary = {}
var _motion_name: String = ""
var _capture_fps: int = 60
var _capture_seconds: float = 2.0
var _always_on_top: bool = false
var _motion_players: Array[AnimationPlayer] = []
var _capture_failed: bool = false
var _capture_pixel_size: Vector2i = Vector2i(1280, 720)


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
		elif normalized.begins_with("motion="):
			_motion_name = normalized.trim_prefix("motion=").to_lower()
		elif normalized.begins_with("fps="):
			_capture_fps = int(normalized.trim_prefix("fps="))
		elif normalized.begins_with("seconds="):
			_capture_seconds = float(normalized.trim_prefix("seconds="))
		elif normalized == "always_on_top=true":
			_always_on_top = true
	if _orientation_name not in ["landscape", "portrait"]:
		push_error("Capture orientation must be landscape or portrait")
		get_tree().quit(2)
		return
	if _motion_name not in ["", "run"] or _capture_fps not in [30, 60] \
			or not is_finite(_capture_seconds) or _capture_seconds < 0.1 or _capture_seconds > 10.0:
		push_error("Capture requires motion=run, fps=30|60, seconds=0.1..10")
		get_tree().quit(2)
		return
	_capture_pixel_size = Vector2i(720, 1280) if _orientation_name == "portrait" else Vector2i(1280, 720)
	var window := get_window()
	window.size = _capture_pixel_size
	# A physical QA window may be screen-clamped by the OS. Render at the exact
	# requested base size, keeping its aspect instead of expanding or stretching
	# to that smaller window. QA owns this canvas, never game settings.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = _capture_pixel_size
	if _always_on_top:
		get_window().always_on_top = true
		DisplayServer.window_move_to_foreground()
	_build_stage()
	_configure_camera()
	if not _motion_name.is_empty() and not _prepare_motion_clock():
		get_tree().quit(2)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(output_dir)
	if not _motion_name.is_empty():
		await _capture_motion(output_dir)
		print("HERO PENGUIN MOTION: %s %s" % ["FAIL" if _capture_failed else "PASS", output_dir])
		get_tree().quit(1 if _capture_failed else 0)
		return
	await _capture_pose(output_dir, "neutral", PenguinVisual.Pose.IDLE, &"countdown_idle", 0.45)
	await _capture_pose(output_dir, "run", PenguinVisual.Pose.RUN, &"run", 0.43)
	await _capture_pose(output_dir, "jump", PenguinVisual.Pose.AIR, &"jump_air", 0.34)
	await _capture_pose(output_dir, "slide", PenguinVisual.Pose.SLIDE, &"slide_loop", 0.28)
	await _capture_pose(output_dir, "hit", PenguinVisual.Pose.STUN, &"hit_left", 0.16)
	await _capture_pose(output_dir, "celebrate", PenguinVisual.Pose.CELEBRATE, &"celebration", 0.32)
	print("HERO PENGUIN CAPTURE: %s %s" % ["FAIL" if _capture_failed else "PASS", output_dir])
	get_tree().quit(1 if _capture_failed else 0)


func _process(delta: float) -> void:
	# Motion export owns the only presentation clock. Waiting for a PNG upload,
	# shader compile or an occluded macOS window cannot advance a single bone.
	if not _motion_name.is_empty():
		return
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

	if _cosmetic_config.is_empty() and _motion_name.is_empty():
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
		var silhouette_root: Node = _facade if not _motion_name.is_empty() else _hero
		for child: Node in silhouette_root.find_children("*", "GeometryInstance3D", true, false):
			(child as GeometryInstance3D).material_override = silhouette

	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true


func _configure_camera() -> void:
	if _view_name in ["chase", "rear_chase"]:
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
	if not _validate_capture_dimensions(image):
		return
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
		_capture_failed = true
	else:
		print("HERO CAPTURE PIXELS: %s %dx%d" % [path, image.get_width(), image.get_height()])


func _validate_capture_dimensions(image: Image) -> bool:
	if image == null or image.is_empty():
		push_error("Capture produced no image")
		_capture_failed = true
		return false
	if image.get_size() != _capture_pixel_size:
		push_error("Capture pixel dimensions %s differ from requested %s" % [
				image.get_size(), _capture_pixel_size])
		_capture_failed = true
		return false
	return true


func _fit_thumbnail_size(source_size: Vector2i, tile: Vector2i) -> Vector2i:
	var fit := minf(float(tile.x) / source_size.x, float(tile.y) / source_size.y)
	return Vector2i(maxi(1, floori(source_size.x * fit)),
			maxi(1, floori(source_size.y * fit)))


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
		elif _view_name in ["close", "front"]:
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


func _capture_suffix() -> String:
	var suffix := "" if _render_name == "beauty" else "_%s" % _render_name
	for key: String in ["hat", "scarf", "goggles"]:
		if _cosmetic_config.has(key):
			suffix += "_%s" % String(_cosmetic_config[key])
	return suffix


func _prepare_motion_clock() -> bool:
	if _facade == null or _hero == null or not _facade.is_authored_backend_active():
		push_error("Motion capture requires the real PenguinVisual authored backend")
		return false
	for child: Node in _hero.find_children("*", "AnimationPlayer", true, false):
		var player := child as AnimationPlayer
		if not player.has_animation(&"run"):
			push_error("Motion capture AnimationPlayer is missing the real run clip")
			return false
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_motion_players.append(player)
	if _motion_players.is_empty():
		push_error("Motion capture found no actual AnimationPlayer")
		return false
	# Apply the real idle-to-run transition through the facade, never substitute
	# a procedural pose or seek unrelated still frames. tick() owns cadence and
	# cosmetic secondary motion; AnimationPlayer.advance() applies actual clips.
	_facade.set_pose(PenguinVisual.Pose.IDLE)
	for player: AnimationPlayer in _motion_players:
		player.advance(0.0)
	_facade.set_pose(PenguinVisual.Pose.RUN)
	_step_motion(0.0)
	return true


func _step_motion(delta: float) -> void:
	_facade.drive_motion(1.0, 0.0, 0.0, 0.0, true)
	_facade.tick(delta, 1.0)
	for player: AnimationPlayer in _motion_players:
		player.advance(delta)


func _capture_motion(output_dir: String) -> void:
	var sequence_name := "hero_penguin_%s_%s_%s%s_%dfps" % [
		_motion_name, _view_name, _orientation_name, _capture_suffix(), _capture_fps]
	var sequence_dir := output_dir.path_join(sequence_name)
	if DirAccess.dir_exists_absolute(sequence_dir) and not DirAccess.get_files_at(sequence_dir).is_empty():
		push_error("Motion output already contains files; choose a fresh output directory: %s" % sequence_dir)
		_capture_failed = true
		return
	if DirAccess.make_dir_recursive_absolute(sequence_dir) != OK:
		push_error("Could not create motion output: %s" % sequence_dir)
		_capture_failed = true
		return
	var frame_count := maxi(1, roundi(_capture_seconds * float(_capture_fps)))
	var step := 1.0 / float(_capture_fps)
	var samples: Array[Dictionary] = []
	var contact_frames := PackedInt32Array()
	for cell: int in 16:
		contact_frames.append(roundi(float(cell) * float(frame_count - 1) / 15.0))
	var tile := Vector2i(180, 320) if _orientation_name == "portrait" else Vector2i(320, 180)
	var contact := Image.create(tile.x * 4, tile.y * 4, false, Image.FORMAT_RGB8)
	contact.fill(Color("111820"))
	var capture_dimensions := Vector2i.ZERO
	for frame: int in frame_count:
		if frame > 0:
			_step_motion(step)
		# A new process boundary lets the actual skeleton propagate its pose, then
		# the completed draw supplies exactly that timeline sample. Wall time and
		# engine delta are deliberately absent from all animation advancement.
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var screenshot := get_viewport().get_texture().get_image()
		if not _validate_capture_dimensions(screenshot):
			return
		capture_dimensions = screenshot.get_size()
		var filename := "frame_%04d.png" % frame
		if screenshot.save_png(sequence_dir.path_join(filename)) != OK:
			push_error("Could not save motion frame: %s" % filename)
			_capture_failed = true
			return
		var player := _motion_players[0]
		samples.append({
			"frame": frame, "time_seconds": float(frame) / float(_capture_fps),
			"file": filename, "clip": String(player.current_animation),
			"clip_position_seconds": player.current_animation_position,
			"clip_speed_scale": player.speed_scale,
			"pixel_dimensions": [capture_dimensions.x, capture_dimensions.y],
		})
		for cell: int in contact_frames.size():
			if frame != contact_frames[cell]:
				continue
			var thumbnail := screenshot.duplicate() as Image
			thumbnail.convert(Image.FORMAT_RGB8)
			var fitted := _fit_thumbnail_size(screenshot.get_size(), tile)
			thumbnail.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)
			var inset := Vector2i((tile.x - fitted.x) / 2, (tile.y - fitted.y) / 2)
			contact.blit_rect(thumbnail, Rect2i(Vector2i.ZERO, fitted),
					Vector2i(cell % 4, cell / 4) * tile + inset)
	if contact.save_png(sequence_dir.path_join("contact_sheet.png")) != OK:
		push_error("Could not save motion contact sheet")
		_capture_failed = true
	var manifest := {
		"schema_version": 1, "motion": _motion_name, "fps": _capture_fps,
		"duration_seconds": float(frame_count) / float(_capture_fps),
		"frame_count": frame_count, "clock": "fixed_step_facade_and_animation_player",
		"automatic_animation_processing": false, "speed_ratio": 1.0,
		"facade": "PenguinVisual", "role": _role_name, "view": _view_name,
		"orientation": _orientation_name, "render": _render_name,
		"requested_pixel_dimensions": [_capture_pixel_size.x, _capture_pixel_size.y],
		"capture_pixel_dimensions": [capture_dimensions.x, capture_dimensions.y],
		"contact_sheet_tile_dimensions": [tile.x, tile.y],
		"contact_sheet_resize": "aspect_fit_centered",
		"renderer": RenderingServer.get_current_rendering_method(),
		"asset_sha256": FileAccess.get_sha256("res://assets/art/characters/hero_penguin_v1.glb"),
		"cosmetics": _cosmetic_config, "contact_sheet": "contact_sheet.png",
		"contact_sheet_frame_indices": Array(contact_frames), "frames": samples,
	}
	var timeline := FileAccess.open(sequence_dir.path_join("timeline.json"), FileAccess.WRITE)
	if timeline == null:
		push_error("Could not save motion timeline")
		_capture_failed = true
		return
	timeline.store_string(JSON.stringify(manifest, "\t"))
	timeline.close()
	print("HERO MOTION SEQUENCE: %s frames=%d fps=%d" % [sequence_dir, frame_count, _capture_fps])
