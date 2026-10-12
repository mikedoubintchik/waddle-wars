extends Node
## Quantitative, real-Compatibility QA for the candidate unique-UV shader.
## Uses only synthetic ImageTextures and a 64px SubViewport; no game scenes,
## assets, saves, wall-clock animation, or live PenguinVisual changes.
##
## ALBEDO tests copy the actual shader code and replace only render_mode with
## unshaded/cull_disabled. This is not a substitute for the original shader's
## real lit character capture. The flat-normal test DOES use the original code.
## Run in an isolated project identity with no autoloads; --headless is SKIP.
## Default expects Compatibility. Optional -- renderer=mobile independently
## verifies the exact same expectations using a real Mobile renderer.

const SHADER_PATH := "res://tests/shaders/hero_v12_atlas_review.gdshader"
const SIZE := Vector2i(64, 64)
const PIXEL_REGION := Rect2i(12, 12, 40, 40)
const BYTE_TOLERANCE: int = 2
const REFERENCES: Array[Vector3] = [
	Vector3(0.017, 0.027, 0.040), Vector3(0.760, 0.665, 0.490),
	Vector3(0.630, 0.270, 0.037), Vector3(0.065, 0.340, 0.380),
]
const TARGETS: Array[Vector3] = [
	Vector3(0.025, 0.019, 0.055), Vector3(0.580, 0.730, 0.640),
	Vector3(0.740, 0.190, 0.060), Vector3(0.090, 0.280, 0.460),
]
const PARAMETER_NAMES: Array[StringName] = [
	&"dorsal_linear", &"ventral_linear", &"patch_linear", &"identity_linear",
]
const MASKS: Array[Color] = [
	Color(0, 0, 0, 1), Color(1, 0, 0, 1), Color(0, 1, 0, 1),
	Color(0, 0, 1, 1), Color(0.25, 0.50, 0.10, 1), Color(0.75, 0.50, 0.25, 1),
]
const REGION_NAMES: Array[String] = ["dorsal", "ivory_R", "gold_G", "identity_B", "mixed", "normalized_overlap"]

var _passes: int = 0
var _failures: int = 0
var _started_usec: int = 0
var _finished: bool = false
var _viewport: SubViewport
var _mesh: MeshInstance3D
var _source_shader: Shader
var _albedo_shader: Shader
var _flat_normal: ImageTexture
var _orm: ImageTexture


func _ready() -> void:
	_started_usec = Time.get_ticks_usec()
	if DisplayServer.get_name() == "headless":
		print("[hero_v12_atlas_shader] SKIP real renderer required; 0 passed, 0 failed")
		_finished = true
		get_tree().quit(0)
		return
	var expected_renderer := "gl_compatibility"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("renderer="):
			expected_renderer = argument.trim_prefix("renderer=")
	if expected_renderer not in ["gl_compatibility", "mobile"] \
		or RenderingServer.get_current_rendering_method() != expected_renderer:
		_check("requires_requested_renderer", false, "expected=%s actual=%s" % [
			expected_renderer, RenderingServer.get_current_rendering_method()])
		_finish()
		return
	get_window().size = Vector2i(240, 120)
	get_window().title = "Waddle atlas shader QA"
	get_window().always_on_top = not OS.get_cmdline_user_args().has("always_on_top=false")
	DisplayServer.window_move_to_foreground()
	_source_shader = load(SHADER_PATH) as Shader
	if _source_shader == null:
		_check("source_shader_load", false, SHADER_PATH)
		_finish()
		return
	print("[hero_v12_atlas_shader] shader_code_sha256=%s renderer=%s" % [
		_source_shader.code.sha256_text(), RenderingServer.get_current_rendering_method()])
	var mode := RegEx.new()
	mode.compile("render_mode[^;]*;")
	_albedo_shader = Shader.new()
	_albedo_shader.code = mode.sub(_source_shader.code, "render_mode unshaded, cull_disabled;", false)
	_build_fixture()
	_flat_normal = _texture(Color(0.5, 0.5, 1.0, 1.0))
	_orm = _texture(Color(1.0, 0.55, 0.0, 1.0))
	await _test_default_palette()
	await _test_feather_masks()
	await _test_hard_regions()
	await _test_linear_data_maps()
	await _test_flat_normal()
	_finish()


func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_usec() - _started_usec > 20_000_000:
		_check("render_timeout", false, "no completed result within 20 seconds")
		_finish()


func _build_fixture() -> void:
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.03, 0.01, 0.03)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.12
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.2
	camera.position.z = 2.0
	camera.near = 0.05
	camera.far = 4.0
	world.add_child(camera)
	camera.make_current()
	var key := DirectionalLight3D.new()
	key.light_energy = 0.65
	key.shadow_enabled = false
	world.add_child(key)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	# Deliberately dark COLOR makes accidental albedo*COLOR multiplication fail.
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([
		Color(0.13, 0.24, 0.36), Color(0.13, 0.24, 0.36),
		Color(0.13, 0.24, 0.36), Color(0.13, 0.24, 0.36),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var quad := ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = quad
	world.add_child(_mesh)


func _texture(color: Color) -> ImageTexture:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _candidate(albedo: ImageTexture, mask: Color, lit: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _source_shader if lit else _albedo_shader
	material.set_shader_parameter("atlas_albedo", albedo)
	material.set_shader_parameter("atlas_masks", _texture(mask))
	material.set_shader_parameter("atlas_normal", _flat_normal)
	material.set_shader_parameter("atlas_orm", _orm)
	return material


func _reference(albedo: ImageTexture) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color.WHITE
	material.albedo_texture = albedo
	material.vertex_color_use_as_albedo = false
	return material


func _draw(material: Material, palette: Array[Vector3] = []) -> Image:
	_mesh.material_override = material
	for index: int in PARAMETER_NAMES.size():
		_mesh.set_instance_shader_parameter(PARAMETER_NAMES[index], null)
		if not palette.is_empty():
			_mesh.set_instance_shader_parameter(PARAMETER_NAMES[index], palette[index])
	# Two completed submissions avoid comparing the previous material's image.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()


func _test_default_palette() -> void:
	var texture := _texture(Color(0.37, 0.52, 0.71, 1.0))
	var expected := await _draw(_reference(texture))
	var texel := texture.get_image().get_pixel(0, 0)
	var reference_pixel := expected.get_pixel(32, 32)
	_check("standard_material_reference_draws", absf(reference_pixel.r - texel.r) < 0.01
		and absf(reference_pixel.g - texel.g) < 0.01 and absf(reference_pixel.b - texel.b) < 0.01,
		"render=%s texel=%s" % [reference_pixel, texel])
	for index: int in MASKS.size():
		var actual := await _draw(_candidate(texture, MASKS[index]))
		_compare("default_preserves_bake_%s" % REGION_NAMES[index], actual, expected)


func _expected_repalette(albedo: ImageTexture, mask_value: Color) -> ImageTexture:
	# Quantize data exactly as the synthetic RGBA8 sampler input is quantized.
	var mask := _texture(mask_value).get_image().get_pixel(0, 0)
	var weights := Vector3(mask.r, mask.g, mask.b)
	weights /= maxf(1.0, weights.x + weights.y + weights.z)
	var dark := maxf(0.0, 1.0 - weights.x - weights.y - weights.z)
	var reference := REFERENCES[0] * dark + REFERENCES[1] * weights.x \
		+ REFERENCES[2] * weights.y + REFERENCES[3] * weights.z
	var desired := TARGETS[0] * dark + TARGETS[1] * weights.x \
		+ TARGETS[2] * weights.y + TARGETS[3] * weights.z
	var ratio := desired / reference.max(Vector3.ONE * 0.0001)
	var feather := smoothstep(0.25, 0.75, mask.a)
	ratio = Vector3.ONE.lerp(ratio, feather)
	var linear := albedo.get_image().get_pixel(0, 0).srgb_to_linear()
	linear = Color(linear.r * ratio.x, linear.g * ratio.y, linear.b * ratio.z, 1.0)
	return _texture(linear.linear_to_srgb())


func _test_feather_masks() -> void:
	var texture := _texture(Color(0.29, 0.34, 0.41, 1.0))
	for index: int in MASKS.size():
		var expected := await _draw(_reference(_expected_repalette(texture, MASKS[index])))
		var actual := await _draw(_candidate(texture, MASKS[index]), TARGETS)
		_compare("repalette_%s_linear_ratio" % REGION_NAMES[index], actual, expected)
	var partial := Color(0.25, 0.5, 0.1, 0.5)
	var expected_partial := await _draw(_reference(_expected_repalette(texture, partial)))
	var actual_partial := await _draw(_candidate(texture, partial), TARGETS)
	_compare("feather_alpha_partial_coverage", actual_partial, expected_partial)


func _test_hard_regions() -> void:
	var texture := _texture(Color(0.18, 0.63, 0.79, 1.0))
	var expected := await _draw(_reference(texture))
	for index: int in MASKS.size():
		var mask := MASKS[index]
		mask.a = 0.0
		var actual := await _draw(_candidate(texture, mask), TARGETS)
		_compare("hard_eye_A0_unchanged_%s" % REGION_NAMES[index], actual, expected)


func _test_linear_data_maps() -> void:
	var material := _candidate(_texture(Color.WHITE), Color(0.25, 0.5, 0.75, 0.5))
	material.set_shader_parameter("atlas_orm", _texture(Color(0.25, 0.5, 0.75, 1.0)))
	var probe := Shader.new()
	var close := _albedo_shader.code.rfind("}")
	var mask_pixel := (material.get_shader_parameter("atlas_masks") as Texture2D).get_image().get_pixel(0, 0)
	var orm_pixel := (material.get_shader_parameter("atlas_orm") as Texture2D).get_image().get_pixel(0, 0)
	var normal_pixel := _flat_normal.get_image().get_pixel(0, 0)
	var assertion := """
	bool raw_masks = distance(texture(atlas_masks, UV), vec4(%.9f, %.9f, %.9f, %.9f)) < 0.001;
	bool raw_orm = distance(texture(atlas_orm, UV).rgb, vec3(%.9f, %.9f, %.9f)) < 0.001;
	bool flat_normal = distance(texture(atlas_normal, UV).rgb, vec3(%.9f, %.9f, %.9f)) < 0.001;
	ALBEDO = vec3(raw_masks ? 1.0 : 0.0, raw_orm ? 1.0 : 0.0, flat_normal ? 1.0 : 0.0);
""" % [mask_pixel.r, mask_pixel.g, mask_pixel.b, mask_pixel.a,
		orm_pixel.r, orm_pixel.g, orm_pixel.b, normal_pixel.r, normal_pixel.g, normal_pixel.b]
	probe.code = _albedo_shader.code.substr(0, close) + assertion + _albedo_shader.code.substr(close)
	material.shader = probe
	var expected := await _draw(_reference(_texture(Color.WHITE)))
	var actual := await _draw(material)
	_compare("ORM_masks_normal_are_linear_data", actual, expected)


func _test_flat_normal() -> void:
	var texture := _texture(Color(0.48, 0.38, 0.29, 1.0))
	var flat := _candidate(texture, Color(0, 0, 0, 1), true)
	flat.set_shader_parameter("normal_strength", 1.0)
	var disabled := _candidate(texture, Color(0, 0, 0, 1), true)
	disabled.set_shader_parameter("normal_strength", 0.0)
	var expected := await _draw(disabled)
	var actual := await _draw(flat)
	_check("original_lit_shader_draws", expected != null and not expected.is_empty()
		and expected.get_pixel(32, 32).r8 > 24, "original lit framebuffer must contain visible geometry")
	_compare("original_lit_flat_normal_matches_disabled", actual, expected)


func _compare(label: String, actual: Image, expected: Image) -> void:
	if actual == null or expected == null or actual.is_empty() or expected.is_empty():
		_check(label, false, "empty render readback")
		return
	var maximum := 0
	for y: int in range(PIXEL_REGION.position.y, PIXEL_REGION.end.y):
		for x: int in range(PIXEL_REGION.position.x, PIXEL_REGION.end.x):
			var a := actual.get_pixel(x, y)
			var e := expected.get_pixel(x, y)
			maximum = maxi(maximum, maxi(absi(a.r8 - e.r8), maxi(absi(a.g8 - e.g8), absi(a.b8 - e.b8))))
	_check(label, maximum <= BYTE_TOLERANCE,
		"max_byte_error=%d actual=%s expected=%s pixels=%d" % [maximum,
		actual.get_pixel(32, 32), expected.get_pixel(32, 32), PIXEL_REGION.get_area()])


func _check(label: String, ok: bool, details: String = "") -> void:
	if ok:
		_passes += 1
	else:
		_failures += 1
	print("[hero_v12_atlas_shader] %s %s %s" % ["PASS" if ok else "FAIL", label, details])


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_viewport.queue_free()
	print("[hero_v12_atlas_shader] DONE: %d passed, %d failed; real_lit_character_capture_still_required=true" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
