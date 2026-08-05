extends Control
## Title screen: twilight 3D ice-floe diorama — aurora ribbons, star field,
## soft clouds, animated ocean, distant bergs, and idling penguins behind a
## rocking logo. Any input advances to the main menu.
##
## The wordmark is an original SVG logotype generated at runtime (same
## Image.load_svg_from_string technique as the fish icon in main_menu.gd):
## chunky rounded stroke letterforms, ice gradient fill, navy outline, snow
## caps, soft offset shadow. Rendered at 3x so it stays crisp on hi-dpi.

const STAR_COUNT: int = 140

## --- Logo letterform table -------------------------------------------------
## Each glyph is a stroke skeleton on a 100-unit-tall grid (y 10 = top of the
## stroke centerline, y 90 = baseline). Round caps/joins fatten the strokes
## into chunky rounded letterforms; "snow" entries are cap blobs [cx, cy, rx,
## ry] placed on letter tops. Only letters used by GAME_NAME need to exist —
## _build_logo_svg() returns "" (Label fallback) for unknown characters.
const LOGO_LETTERS: Dictionary = {
	"W": {"w": 96.0, "paths": ["M8 10 L30 90 L48 42 L66 90 L88 10"],
			"snow": [[8.0, -1.0, 12.0, 6.0], [88.0, -1.0, 12.0, 6.0]]},
	"A": {"w": 76.0, "paths": ["M8 90 L38 10 L68 90", "M22 62 L54 62"],
			"snow": [[38.0, -1.0, 13.0, 6.5]]},
	"D": {"w": 74.0, "paths": ["M10 90 L10 10 Q64 12 64 50 Q64 88 10 90 Z"],
			"snow": [[30.0, 0.0, 14.0, 6.0]]},
	"L": {"w": 58.0, "paths": ["M10 10 L10 90 L52 90"],
			"snow": [[10.0, -1.0, 11.0, 6.0]]},
	"E": {"w": 60.0, "paths": ["M52 10 L12 10 L12 90 L52 90", "M12 50 L44 50"],
			"snow": [[30.0, -2.0, 16.0, 6.0]]},
	"R": {"w": 70.0, "paths": ["M12 90 L12 10 Q60 10 60 32 Q60 54 12 54", "M34 54 L60 90"],
			"snow": [[28.0, -1.0, 14.0, 6.0]]},
	"S": {"w": 64.0, "paths": ["M54 20 C44 8 16 6 12 26 C9 44 52 48 54 68 C56 90 22 96 10 78"],
			"snow": [[33.0, -2.0, 12.0, 5.5]]},
}
const LOGO_LETTER_GAP: float = 14.0
const LOGO_LINE_H: float = 110.0
const LOGO_LINE_GAP: float = 16.0
const LOGO_MARGIN_X: float = 22.0
const LOGO_MARGIN_Y: float = 24.0
const LOGO_RENDER_SCALE: float = 3.0
## Per-letter playful jitter, cycled by letter index.
const LOGO_ROT: Array[float] = [-2.2, 1.8, -1.5, 2.0, -1.8, 1.6]
const LOGO_DY: Array[float] = [3.0, -2.0, 2.0, -3.0, 2.0, -2.0]
const SKY_TOP: Color = Color(0.1, 0.14, 0.34)
const SKY_HORIZON: Color = Color(0.93, 0.55, 0.47)
const GROUND_BOTTOM: Color = Color(0.07, 0.1, 0.2)
const OCEAN_DEEP: Color = Color(0.05, 0.13, 0.3)
const OCEAN_SHALLOW: Color = Color(0.46, 0.42, 0.66)

var _elapsed: float = 0.0
var _started: bool = false
var _prompt: Button
var _prompt_glow: Panel
var _logo: Control
var _logo_rect: TextureRect
var _logo_aspect: float = 0.5
var _camera: Camera3D
var _penguins: Array[PenguinVisual] = []
var _penguin_ratios: Array[float] = []
var _base_poses: Array[int] = []
var _flourish_until: Array[float] = []
var _next_flourish: Array[float] = []
var _aurora_ribbons: Array[MeshInstance3D] = []


func _ready() -> void:
	_build_diorama()
	_build_foreground()
	_build_tap_catcher()
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

	_build_environment(viewport)
	_build_ocean(viewport)
	_build_floe(viewport)
	_build_cast(viewport)
	if not GameConfig.is_headless():
		_build_aurora(viewport)
		_build_stars(viewport)
		_build_clouds(viewport)
		_build_bergs(viewport)
		_build_snowfall(viewport)

	_camera = Camera3D.new()
	viewport.add_child(_camera)
	_camera.current = true
	_camera.look_at_from_position(Vector3(0.0, 1.5, -4.6), Vector3(0.0, 0.6, 0.0), Vector3.UP)


## Twilight sky, ACES tonemap, warm low key sun + cool fill, gated glow.
func _build_environment(viewport: SubViewport) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = SKY_HORIZON
	sky_material.ground_bottom_color = GROUND_BOTTOM
	sky_material.ground_horizon_color = SKY_HORIZON
	sky_material.sun_angle_max = 24.0
	sky_material.sun_curve = 0.09
	sky_material.sky_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.15
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.36, 0.52)
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.12
	var particle_quality := String(SettingsManager.get_setting("display", "particle_quality"))
	if particle_quality != "low" and not GameConfig.is_headless():
		# High HDR threshold: only emissive peaks (aurora, snow glints) bloom.
		env.glow_enabled = true
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_hdr_threshold = 1.1
		env.glow_intensity = 0.45
		env.glow_bloom = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-17.0, 22.0, 0.0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.76, 0.52)
	var shadow_quality := String(SettingsManager.get_setting("display", "shadow_quality"))
	sun.shadow_enabled = shadow_quality != "off" and not GameConfig.is_headless()
	sun.directional_shadow_max_distance = 30.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.6
	viewport.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-42.0, -155.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.5, 0.66, 1.0)
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	viewport.add_child(fill)


## Large animated ocean plane; low wave_scale suits the big surface.
func _build_ocean(viewport: SubViewport) -> void:
	var ocean := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(700.0, 700.0)
	mesh.subdivide_width = 70
	mesh.subdivide_depth = 70
	ocean.mesh = mesh
	ocean.material_override = VisualLibrary.water_material(OCEAN_DEEP, OCEAN_SHALLOW, 0.26, 0.06)
	ocean.position = Vector3(0, -0.5, 0)
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(ocean)


## Snow-topped floe with an ice skirt at the waterline and soft snow drifts.
## NOTE: no ice-crystal prop here — at diorama scale its jagged cyan shards
## read as a glitch artifact next to the penguins (screenshot QA finding).
func _build_floe(viewport: SubViewport) -> void:
	var floe := MeshInstance3D.new()
	var floe_mesh := CylinderMesh.new()
	floe_mesh.top_radius = 2.6
	floe_mesh.bottom_radius = 3.0
	floe_mesh.height = 0.4
	floe_mesh.radial_segments = 28
	floe.mesh = floe_mesh
	floe.material_override = VisualLibrary.snow_material(Color(0.94, 0.97, 1.0), 0.7)
	floe.position = Vector3(0, -0.2, 0)
	viewport.add_child(floe)

	var skirt := MeshInstance3D.new()
	var skirt_mesh := CylinderMesh.new()
	skirt_mesh.top_radius = 3.05
	skirt_mesh.bottom_radius = 3.45
	skirt_mesh.height = 0.55
	skirt_mesh.radial_segments = 28
	skirt.mesh = skirt_mesh
	skirt.material_override = VisualLibrary.ice_material(Color(0.55, 0.78, 0.97), 0.55)
	skirt.position = Vector3(0, -0.62, 0)
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(skirt)

	var drift_mesh := VisualLibrary.snow_drift_mesh()
	var drift_material := VisualLibrary.rock_material(Color(1.0, 1.0, 1.0))
	var drifts: Array = [
		[Vector3(-1.8, 0.0, 1.2), 0.9],
		[Vector3(1.9, 0.0, -1.1), 0.6],
		[Vector3(-0.5, 0.0, 1.9), 0.5],
	]
	for entry: Array in drifts:
		var drift := MeshInstance3D.new()
		drift.mesh = drift_mesh
		drift.material_override = drift_material
		drift.position = entry[0] as Vector3
		var s := float(entry[1])
		drift.scale = Vector3(s, s * 0.6, s)
		viewport.add_child(drift)


## Penguin cast with staggered idle flourishes (occasional celebrate flaps).
func _build_cast(viewport: SubViewport) -> void:
	var casts: Array = [
		[Vector3(-0.9, 0.0, 0.3), 0.5, "body_classic", PenguinVisual.Pose.IDLE, 0.0, 1.0],
		[Vector3(0.2, 0.0, -0.4), -0.3, "body_snowy", PenguinVisual.Pose.RUN, 0.55, 1.0],
		[Vector3(1.1, 0.0, 0.5), 0.9, "body_midnight", PenguinVisual.Pose.IDLE, 0.0, 1.0],
		[Vector3(0.35, 0.0, 1.05), 0.15, "body_classic", PenguinVisual.Pose.IDLE, 0.0, 0.6],
	]
	for i: int in casts.size():
		var entry: Array = casts[i]
		var body_info := CosmeticsDB.get_item(String(entry[2]))
		var penguin := PenguinVisual.new()
		viewport.add_child(penguin)
		penguin.position = entry[0] as Vector3
		penguin.rotation.y = float(entry[1])
		penguin.scale = Vector3.ONE * float(entry[5])
		penguin.setup({
			"body_color": body_info.get("body_color", Color(0.13, 0.16, 0.22)),
			"belly_color": body_info.get("belly_color", Color(0.95, 0.94, 0.9)),
		})
		penguin.set_pose(entry[3] as PenguinVisual.Pose)
		penguin.anim_speed = randf_range(0.85, 1.15)
		_penguins.append(penguin)
		_penguin_ratios.append(float(entry[4]))
		_base_poses.append(int(entry[3]))
		_flourish_until.append(0.0)
		_next_flourish.append(5.0 + float(i) * 3.5 + randf_range(0.0, 2.0))


## Two additive aurora ribbons arcing across the visible sky.
## UV.x runs along the ribbon, UV.y = 0 at the top edge (shader contract).
func _build_aurora(viewport: SubViewport) -> void:
	var configs: Array = [
		[200.0, 62.0, 46.0, -1.25, 0.55, 3.1],
		[255.0, 88.0, 58.0, -0.25, 1.35, 7.7],
	]
	for cfg: Array in configs:
		var radius := float(cfg[0])
		var y_base := float(cfg[1])
		var height := float(cfg[2])
		var a0 := float(cfg[3])
		var a1 := float(cfg[4])
		var phase := float(cfg[5])
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segments := 30
		var prev_bottom := Vector3.ZERO
		var prev_top := Vector3.ZERO
		var prev_t := 0.0
		for i: int in segments + 1:
			var t := float(i) / float(segments)
			var angle := lerpf(a0, a1, t)
			var wave := sin(t * PI * 3.0 + phase) * 6.0
			var bottom := Vector3(sin(angle) * radius, y_base + wave, cos(angle) * radius)
			var top := bottom + Vector3.UP * (height + sin(t * PI * 5.0 + phase) * 9.0)
			if i > 0:
				st.set_uv(Vector2(prev_t, 1.0)); st.add_vertex(prev_bottom)
				st.set_uv(Vector2(prev_t, 0.0)); st.add_vertex(prev_top)
				st.set_uv(Vector2(t, 0.0)); st.add_vertex(top)
				st.set_uv(Vector2(prev_t, 1.0)); st.add_vertex(prev_bottom)
				st.set_uv(Vector2(t, 0.0)); st.add_vertex(top)
				st.set_uv(Vector2(t, 1.0)); st.add_vertex(bottom)
			prev_bottom = bottom
			prev_top = top
			prev_t = t
		var ribbon := MeshInstance3D.new()
		ribbon.mesh = st.commit()
		ribbon.material_override = VisualLibrary.aurora_material()
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		viewport.add_child(ribbon)
		_aurora_ribbons.append(ribbon)


## Star dome: one MultiMesh of soft additive billboards, brighter overhead
## where the twilight sky is darkest.
func _build_stars(viewport: SubViewport) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 66601
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var star_material := StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	star_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_material.billboard_keep_scale = true
	star_material.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
	star_material.vertex_color_use_as_albedo = true
	star_material.disable_receive_shadows = true
	star_material.disable_fog = true
	quad.material = star_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = STAR_COUNT
	for i: int in STAR_COUNT:
		var azimuth := rng.randf() * TAU
		var altitude := rng.randf_range(0.22, 1.45)
		var dir := Vector3(cos(azimuth) * cos(altitude), sin(altitude), sin(azimuth) * cos(altitude))
		var s := rng.randf_range(0.7, 2.2)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), dir * 300.0))
		var height_fade := clampf((altitude - 0.15) / 1.2, 0.0, 1.0)
		var alpha := rng.randf_range(0.35, 0.95) * (0.3 + 0.7 * height_fade)
		multimesh.set_instance_color(i, Color(0.85 + rng.randf() * 0.15, 0.9 + rng.randf() * 0.1, 1.0, alpha))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = multimesh
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(stars)


## Soft twilight-tinted billboard puff clusters near the horizon.
func _build_clouds(viewport: SubViewport) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 40412
	var cloud_material := StandardMaterial3D.new()
	cloud_material.albedo_color = Color(0.95, 0.68, 0.72, 0.4)
	cloud_material.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.85)
	cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	for _i: int in 5:
		var azimuth := rng.randf_range(-1.5, 1.5)
		var dist := rng.randf_range(150.0, 260.0)
		var cluster := Node3D.new()
		cluster.position = Vector3(sin(azimuth) * dist, rng.randf_range(20.0, 55.0), cos(azimuth) * dist)
		for _j: int in 3:
			var puff := MeshInstance3D.new()
			var quad := QuadMesh.new()
			var size := rng.randf_range(28.0, 60.0)
			quad.size = Vector2(size, size * 0.5)
			puff.mesh = quad
			puff.material_override = cloud_material
			puff.position = Vector3(
				rng.randf_range(-18.0, 18.0),
				rng.randf_range(-5.0, 5.0),
				rng.randf_range(-8.0, 8.0))
			cluster.add_child(puff)
		viewport.add_child(cluster)


## Ring of low-poly iceberg silhouettes for horizon depth.
func _build_bergs(viewport: SubViewport) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 977013
	var berg_material := VisualLibrary.rock_material(Color(0.58, 0.64, 0.84))
	var count := 9
	for i: int in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.2, 0.2)
		var berg := MeshInstance3D.new()
		berg.mesh = VisualLibrary.berg_mesh(rng.randi())
		berg.material_override = berg_material
		var s := rng.randf_range(7.0, 18.0)
		berg.scale = Vector3(s * rng.randf_range(0.9, 1.4), s * rng.randf_range(0.6, 0.95), s)
		var dist := rng.randf_range(130.0, 260.0)
		berg.position = Vector3(cos(angle) * dist, -1.2, sin(angle) * dist)
		berg.rotation.y = rng.randf() * TAU
		berg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		viewport.add_child(berg)


## Falling snow: soft billboard flakes, amount gated by particle quality.
func _build_snowfall(viewport: SubViewport) -> void:
	var snow := GPUParticles3D.new()
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	snow.amount = 240 if quality == "high" else (130 if quality == "medium" else 60)
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
	snow_material.scale_min = 0.6
	snow_material.scale_max = 1.2
	snow.process_material = snow_material
	var flake := QuadMesh.new()
	flake.size = Vector2(0.08, 0.08)
	var flake_material := StandardMaterial3D.new()
	flake_material.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	flake_material.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
	flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.material = flake_material
	snow.draw_pass_1 = flake
	snow.position = Vector3(0, 4.5, 0)
	snow.visibility_aabb = AABB(Vector3(-8.0, -16.0, -8.0), Vector3(16.0, 20.0, 16.0))
	viewport.add_child(snow)


## --- Foreground UI ---------------------------------------------------------

func _build_foreground() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Logo block anchored to the upper third so the penguin diorama stays
	# clear of the wordmark; the prompt sits low near the ice floe.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.anchor_bottom = 0.42
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	_logo = _build_logo()
	if _logo == null:
		# Fallback: bold outlined Label so the title never disappears even if
		# the SVG module rejects the generated wordmark.
		var label := Label.new()
		label.text = GameConfig.GAME_NAME.to_upper()
		label.add_theme_font_size_override("font_size", 110)
		label.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0))
		label.add_theme_color_override("font_outline_color", Color(0.05, 0.11, 0.22))
		label.add_theme_constant_override("outline_size", 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_logo = label
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_logo)

	# Real button beats a "press start" prompt on touch devices; the full-rect
	# TapCatcher below it still lets a tap anywhere begin the game.
	_prompt = UITheme.make_button("Begin", Vector2(340, 92), 42)
	_prompt.focus_mode = Control.FOCUS_ALL
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	# Pinned a fixed margin above the bottom edge (not a proportional anchor)
	# so the taller 92px button never clips off-screen on landscape phones.
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -170.0
	_prompt.offset_right = 170.0
	_prompt.offset_top = -132.0
	_prompt.offset_bottom = -40.0
	_prompt.pressed.connect(_start_game)
	overlay.add_child(_prompt)
	_prompt_glow = _build_prompt_glow(_prompt)
	_prompt.grab_focus.call_deferred()

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


## --- Logo ------------------------------------------------------------------

## Rasterize the generated SVG wordmark into a TextureRect. Returns null on
## any failure so the caller can fall back to a plain Label.
func _build_logo() -> Control:
	var svg := _build_logo_svg()
	if svg.is_empty():
		return null
	var img := Image.new()
	if img.load_svg_from_string(svg, LOGO_RENDER_SCALE) != OK:
		return null
	var texture := ImageTexture.create_from_image(img)
	if texture == null:
		return null
	_logo_rect = TextureRect.new()
	_logo_rect.texture = texture
	_logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_update_logo_size()
	get_viewport().size_changed.connect(_update_logo_size)
	return _logo_rect


## Display size tracks the viewport so the wordmark fills a portrait phone
## width yet never dwarfs the diorama on wide desktop windows. Height is also
## capped to the upper-third logo band so landscape phones keep the penguin
## diorama and Begin button clear of the wordmark.
func _update_logo_size() -> void:
	if _logo_rect == null:
		return
	var vp := get_viewport_rect().size
	var width := clampf(vp.x * 0.86, 280.0, 620.0)
	var height_cap := vp.y * 0.40
	if width * _logo_aspect > height_cap:
		width = height_cap / _logo_aspect
	_logo_rect.custom_minimum_size = Vector2(width, width * _logo_aspect)


## Compose the full wordmark SVG: one line per word of GAME_NAME, four draw
## layers (offset shadow, navy outline, ice-gradient fill, snow caps).
## Returns "" if any character is missing from LOGO_LETTERS.
func _build_logo_svg() -> String:
	var words: PackedStringArray = GameConfig.GAME_NAME.to_upper().split(" ", false)
	if words.is_empty():
		return ""
	var line_widths: Array[float] = []
	var max_width := 0.0
	for word: String in words:
		var w := 0.0
		for ci: int in word.length():
			if not LOGO_LETTERS.has(word[ci]):
				return ""
			w += float((LOGO_LETTERS[word[ci]] as Dictionary)["w"])
		w += LOGO_LETTER_GAP * float(word.length() - 1)
		line_widths.append(w)
		max_width = maxf(max_width, w)

	# Flat per-letter layout: [glyph: Dictionary, tx: float, ty: float, rot: float]
	var layout: Array[Array] = []
	var glyph_index := 0
	for li: int in words.size():
		var x := LOGO_MARGIN_X + (max_width - line_widths[li]) * 0.5
		var y := LOGO_MARGIN_Y + 4.0 + float(li) * (LOGO_LINE_H + LOGO_LINE_GAP)
		for ci: int in words[li].length():
			var glyph := LOGO_LETTERS[words[li][ci]] as Dictionary
			layout.append([
				glyph, x,
				y + LOGO_DY[glyph_index % LOGO_DY.size()],
				LOGO_ROT[glyph_index % LOGO_ROT.size()],
			])
			x += float(glyph["w"]) + LOGO_LETTER_GAP
			glyph_index += 1

	var canvas_w := max_width + LOGO_MARGIN_X * 2.0
	var canvas_h := LOGO_MARGIN_Y * 2.0 + float(words.size()) * LOGO_LINE_H \
			+ float(words.size() - 1) * LOGO_LINE_GAP
	_logo_aspect = canvas_h / canvas_w

	var parts: PackedStringArray = []
	parts.append(
		'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
		% [int(canvas_w), int(canvas_h), int(canvas_w), int(canvas_h)])
	parts.append(
		'<defs><linearGradient id="ice" gradientUnits="userSpaceOnUse" x1="0" y1="-4" x2="0" y2="104">'
		+ '<stop offset="0" stop-color="#ffffff"/><stop offset="0.42" stop-color="#d9edff"/>'
		+ '<stop offset="1" stop-color="#7cc4ff"/></linearGradient></defs>')
	_append_stroke_layer(parts, layout, "#06132b", 30.0, 0.38, 9.0)  # drop shadow
	_append_stroke_layer(parts, layout, "#0e2244", 28.0, 1.0, 0.0)  # navy outline
	_append_stroke_layer(parts, layout, "url(#ice)", 16.0, 1.0, 0.0)  # gradient fill
	for entry: Array in layout:  # snow caps: shaded underside + lumpy white top
		var glyph := entry[0] as Dictionary
		var tf := _letter_transform(entry, 0.0)
		for blob: Array in glyph["snow"] as Array:
			var cx := float(blob[0])
			var cy := float(blob[1])
			var rx := float(blob[2])
			var ry := float(blob[3])
			parts.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="#a8cdec" transform="%s"/>'
					% [cx, cy + 1.5, rx, ry, tf])
			parts.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="#ffffff" transform="%s"/>'
					% [cx, cy - 1.5, rx, ry, tf])
			parts.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="#ffffff" transform="%s"/>'
					% [cx + rx * 0.6, cy - 1.0, rx * 0.5, ry * 0.9, tf])
	parts.append('</svg>')
	return "".join(parts)


func _letter_transform(entry: Array, extra_dy: float) -> String:
	var glyph := entry[0] as Dictionary
	return "translate(%.1f %.1f) rotate(%.1f %.1f 50)" % [
		float(entry[1]), float(entry[2]) + extra_dy,
		float(entry[3]), float(glyph["w"]) * 0.5,
	]


func _append_stroke_layer(parts: PackedStringArray, layout: Array[Array],
		stroke: String, width: float, opacity: float, dy: float) -> void:
	for entry: Array in layout:
		var glyph := entry[0] as Dictionary
		var tf := _letter_transform(entry, dy)
		for d: String in glyph["paths"] as Array:
			parts.append(
				('<path d="%s" transform="%s" fill="none" stroke="%s" stroke-opacity="%.2f"'
				+ ' stroke-width="%.1f" stroke-linecap="round" stroke-linejoin="round"/>')
				% [d, tf, stroke, opacity, width])


## Rounded glow ring parented to the button (show_behind_parent) so it tracks
## position, focus scale, and press dips automatically; _process pulses its
## modulate alpha.
func _build_prompt_glow(button: Button) -> Panel:
	var glow := Panel.new()
	glow.name = "BeginGlow"
	glow.show_behind_parent = true
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -7.0
	glow.offset_top = -7.0
	glow.offset_right = 7.0
	glow.offset_bottom = 7.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = Color(UITheme.COLOR_ACCENT, 0.85)
	box.set_border_width_all(3)
	box.set_corner_radius_all(18)
	box.shadow_color = Color(UITheme.COLOR_ACCENT, 0.45)
	box.shadow_size = 14
	glow.add_theme_stylebox_override("panel", box)
	button.add_child(glow)
	return glow


func _process(delta: float) -> void:
	_elapsed += delta
	for i: int in _penguins.size():
		var penguin := _penguins[i]
		penguin.tick(delta, _penguin_ratios[i])
		if _elapsed >= _next_flourish[i]:
			penguin.set_pose(PenguinVisual.Pose.CELEBRATE)
			_flourish_until[i] = _elapsed + randf_range(1.5, 2.3)
			_next_flourish[i] = _elapsed + randf_range(9.0, 16.0)
		elif penguin.pose == PenguinVisual.Pose.CELEBRATE and _elapsed >= _flourish_until[i]:
			penguin.set_pose(_base_poses[i] as PenguinVisual.Pose)
	for i: int in _aurora_ribbons.size():
		_aurora_ribbons[i].position.y = sin(_elapsed * 0.18 + float(i) * 2.1) * 3.0
	if _camera != null:
		_camera.position.x = sin(_elapsed * 0.22) * 0.35
		_camera.position.y = 1.5 + sin(_elapsed * 0.31) * 0.12
		_camera.look_at(Vector3(0.0, 0.6, 0.0))
	if _logo != null:
		_logo.pivot_offset = _logo.size * 0.5
		_logo.rotation = sin(_elapsed * 0.9) * 0.022
	if _prompt_glow != null:
		var reduced := bool(SettingsManager.get_setting("accessibility", "reduced_flashing"))
		var pulse_speed := 1.1 if reduced else 2.6
		var amp := 0.12 if reduced else 0.28
		# Pulse only the glow ring; the button itself stays fully opaque so
		# the label is legible over the dark water at every phase.
		_prompt_glow.modulate.a = 0.55 + amp * sin(_elapsed * pulse_speed)


## Topmost full-rect invisible control: guarantees taps reach the start
## routine even when another Control or browser quirk would swallow the
## event before _unhandled_input (mobile-web tap-to-start QA finding).
func _build_tap_catcher() -> void:
	var catcher := Control.new()
	catcher.name = "TapCatcher"
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(_on_tap_catcher_input)
	add_child(catcher)


func _on_tap_catcher_input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed):
		_start_game()


## Single start path; safe to call from multiple input handlers. The same
## gesture that unlocks web audio must also start the game, so nothing here
## waits on or is gated by any audio call succeeding.
func _start_game() -> void:
	if _started:
		return
	_started = true
	AudioManager.ui_click()
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("pause") \
			or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed):
		_start_game()
