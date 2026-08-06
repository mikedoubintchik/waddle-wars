extends Control
## Title screen: twilight 3D ice-floe diorama — aurora ribbons, star field,
## soft clouds, animated ocean, distant bergs, and idling penguins behind a
## rocking logo. Any input advances to the main menu.
##
## Ambient life on long randomized timers keeps the diorama breathing: a
## penguin dives off the floe (and leaps back on), a distant whale surfaces
## with a spout, a shooting star streaks the sky, sun glints twinkle on the
## water, and the whole floe bobs gently. Every big event is gated behind
## not UITheme.reduced_motion(); all materials are shared/cached and every
## decorative mesh has cast_shadow OFF.
##
## The wordmark is an original SVG logotype generated at runtime (same
## Image.load_svg_from_string technique as the fish icon in main_menu.gd):
## chunky rounded stroke letterforms, ice gradient fill, navy outline, snow
## caps, soft offset shadow. Rendered at 3x so it stays crisp on hi-dpi.

const STAR_COUNT: int = 140

## --- Ambient event tuning ---------------------------------------------------
## Ocean plane rest height in diorama space.
const WATER_Y: float = -0.5
const DIVE_DURATION: float = 0.9
const LEAP_DURATION: float = 0.8
const WHALE_DURATION: float = 7.0
const SHOOTING_STAR_DURATION: float = 0.75
## Floe-edge perch the diver waits on, and its outward dive direction.
const DIVER_PERCH: Vector3 = Vector3(-2.05, 0.0, -0.45)
const DIVER_DIR: Vector3 = Vector3(-0.977, 0.0, -0.215)

enum DiverState { PERCHED, DIVING, UNDER, LEAPING }

## Flat additive sun-glint quads lying on the water, twinkled per instance via
## MultiMesh custom data (phase, speed). ALU-only fragment work — WebGL2-safe,
## zero per-frame CPU. One shader + one material shared across visits.
const GLINT_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_add, fog_disabled, shadows_disabled, depth_draw_never, cull_disabled;
uniform vec3 tint = vec3(1.0, 0.82, 0.55);
uniform float strength = 0.8;
varying vec2 twinkle;
void vertex() {
	twinkle = INSTANCE_CUSTOM.xy;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float mask = max(1.0 - dot(p, p), 0.0);
	float pulse = 0.25 + 0.75 * pow(0.5 + 0.5 * sin(TIME * (0.5 + twinkle.y * 1.6) + twinkle.x * 6.2832), 3.0);
	ALBEDO = tint * (mask * mask * pulse * strength);
}
"""

## Tiny 4-ray twinkle star overlaid on the wordmark's snow caps.
const SPARKLE_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
<path d="M16 2 L18.4 13.6 L30 16 L18.4 18.4 L16 30 L13.6 18.4 L2 16 L13.6 13.6 Z" fill="#ffffff"/>
</svg>"""

## Fractional (x, y) positions of the snow-cap sparkles over the two-line
## wordmark texture (line tops sit near y 0.08 and 0.55).
const LOGO_SPARKLE_POINTS: Array[Vector2] = [
	Vector2(0.105, 0.075), Vector2(0.53, 0.10), Vector2(0.875, 0.06),
	Vector2(0.335, 0.545), Vector2(0.715, 0.575),
]

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

## Cached accessibility state (settings cannot change while on this screen).
var _reduced: bool = false
var _motion_scale: float = 1.0
var _floe_root: Node3D
var _diver: PenguinVisual
var _diver_state: DiverState = DiverState.PERCHED
var _diver_event_start: float = 0.0
var _next_dive: float = 0.0
var _splashed: bool = false
var _splash: GPUParticles3D
var _whale_root: Node3D
var _whale_base: Vector3 = Vector3.ZERO
var _whale_active: bool = false
var _whale_start: float = 0.0
var _next_whale: float = 0.0
var _spouted: bool = false
var _spout: GPUParticles3D
var _shooting_star: MeshInstance3D
var _star_active: bool = false
var _star_start: float = 0.0
var _next_star: float = 0.0
var _star_from: Vector3 = Vector3.ZERO
var _star_vel: Vector3 = Vector3.ZERO
var _prompt_holder: Control

## Shared across title visits: one streak material and one glint shader —
## menus rebuild on every navigation, so statics avoid recompiles (WASM jank).
static var _streak_material: StandardMaterial3D = null
static var _glint_shader: Shader = null
static var _glint_material: ShaderMaterial = null


func _ready() -> void:
	_reduced = UITheme.reduced_motion()
	_motion_scale = 0.5 if _reduced else 1.0
	_next_dive = randf_range(6.0, 11.0)
	_next_whale = randf_range(13.0, 22.0)
	_next_star = randf_range(9.0, 18.0)
	BootProfiler.begin("title")
	_build_diorama()
	_build_foreground()
	BootProfiler.step("foreground")
	_build_tap_catcher()
	AudioManager.play_music("music_title")
	BootProfiler.step("audio")
	BootProfiler.present()


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
	UITheme.crisp_subviewport(viewport, self)

	_build_environment(viewport)
	BootProfiler.step("environment")
	_build_ocean(viewport)
	BootProfiler.step("ocean")
	# Floe, drifts, and the whole penguin cast share one root so the gentle
	# bob in _process moves them together (a single transform per frame).
	_floe_root = Node3D.new()
	viewport.add_child(_floe_root)
	_build_floe()
	BootProfiler.step("floe")
	_build_cast()
	BootProfiler.step("cast")
	if not GameConfig.is_headless():
		_build_aurora(viewport)
		BootProfiler.step("aurora")
		_build_stars(viewport)
		BootProfiler.step("stars")
		_build_clouds(viewport)
		BootProfiler.step("clouds")
		_build_bergs(viewport)
		BootProfiler.step("bergs")
		_build_snowfall(viewport)
		BootProfiler.step("snowfall")
		_build_diver()
		BootProfiler.step("diver")
		_build_splash(viewport)
		_build_whale(viewport)
		BootProfiler.step("whale")
		_build_shooting_star(viewport)
		_build_glints(viewport)
		BootProfiler.step("star+glints")

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
## Parented to _floe_root so everything on the ice bobs as one body.
## NOTE: no ice-crystal prop here — at diorama scale its jagged cyan shards
## read as a glitch artifact next to the penguins (screenshot QA finding).
func _build_floe() -> void:
	var floe := MeshInstance3D.new()
	var floe_mesh := CylinderMesh.new()
	floe_mesh.top_radius = 2.6
	floe_mesh.bottom_radius = 3.0
	floe_mesh.height = 0.4
	floe_mesh.radial_segments = 28
	floe.mesh = floe_mesh
	floe.material_override = VisualLibrary.snow_material(Color(0.94, 0.97, 1.0), 0.7)
	floe.position = Vector3(0, -0.2, 0)
	_floe_root.add_child(floe)

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
	_floe_root.add_child(skirt)

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
		_floe_root.add_child(drift)


## Penguin cast with staggered idle flourishes (occasional celebrate flaps).
func _build_cast() -> void:
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
		_floe_root.add_child(penguin)
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


## Fifth penguin perched on the floe edge; occasionally dives off with a
## splash and later leaps back onto the ice (state machine in _tick_diver).
func _build_diver() -> void:
	var body_info := CosmeticsDB.get_item("body_classic")
	_diver = PenguinVisual.new()
	_floe_root.add_child(_diver)
	_diver.position = DIVER_PERCH
	_diver.rotation.y = 0.5
	_diver.scale = Vector3.ONE * 0.85
	_diver.setup({
		"body_color": body_info.get("body_color", Color(0.13, 0.16, 0.22)),
		"belly_color": body_info.get("belly_color", Color(0.95, 0.94, 0.9)),
	})
	_diver.set_pose(PenguinVisual.Pose.IDLE)
	_diver.anim_speed = randf_range(0.9, 1.1)


## One reusable one-shot splash burst, repositioned for dive entry and the
## leap back out. Shared cached puff material; restart() re-fires it.
func _build_splash(viewport: SubViewport) -> void:
	_splash = GPUParticles3D.new()
	_splash.emitting = false
	_splash.one_shot = true
	_splash.explosiveness = 1.0
	_splash.amount = 18
	_splash.lifetime = 0.7
	var splash_material := ParticleProcessMaterial.new()
	splash_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	splash_material.emission_sphere_radius = 0.18
	splash_material.direction = Vector3(0, 1, 0)
	splash_material.spread = 55.0
	splash_material.initial_velocity_min = 1.6
	splash_material.initial_velocity_max = 3.4
	splash_material.gravity = Vector3(0, -7.0, 0)
	splash_material.scale_min = 0.5
	splash_material.scale_max = 1.1
	_splash.process_material = splash_material
	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.26)
	quad.material = VisualLibrary.billboard_puff_material(Color(0.93, 0.98, 1.0, 0.85), 32, 0.9)
	_splash.draw_pass_1 = quad
	_splash.visibility_aabb = AABB(Vector3(-3.0, -2.0, -3.0), Vector3(6.0, 5.0, 6.0))
	viewport.add_child(_splash)


## Distant whale silhouette (dark back + dorsal fin) that surfaces on a long
## timer with a one-shot spout. Hidden entirely between events.
func _build_whale(viewport: SubViewport) -> void:
	_whale_root = Node3D.new()
	_whale_base = Vector3(-34.0, -3.4, 84.0)
	_whale_root.position = _whale_base
	_whale_root.visible = false
	viewport.add_child(_whale_root)
	var body_material := VisualLibrary.rock_material(Color(0.15, 0.19, 0.27), 0.85)
	var body := MeshInstance3D.new()
	body.mesh = SphereMesh.new()
	body.scale = Vector3(16.0, 4.4, 5.0)
	body.material_override = body_material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_whale_root.add_child(body)
	var fin := MeshInstance3D.new()
	var fin_mesh := PrismMesh.new()
	fin_mesh.size = Vector3(2.2, 1.7, 0.4)
	fin.mesh = fin_mesh
	fin.position = Vector3(0.6, 2.4, 0.0)
	fin.material_override = body_material
	fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_whale_root.add_child(fin)
	_spout = GPUParticles3D.new()
	_spout.emitting = false
	_spout.one_shot = true
	_spout.explosiveness = 0.85
	_spout.amount = 12
	_spout.lifetime = 1.1
	var spout_material := ParticleProcessMaterial.new()
	spout_material.direction = Vector3(0, 1, 0)
	spout_material.spread = 9.0
	spout_material.initial_velocity_min = 4.0
	spout_material.initial_velocity_max = 6.5
	spout_material.gravity = Vector3(0, -3.5, 0)
	spout_material.scale_min = 0.7
	spout_material.scale_max = 1.4
	_spout.process_material = spout_material
	var puff := QuadMesh.new()
	puff.size = Vector2(1.5, 1.5)
	puff.material = VisualLibrary.billboard_puff_material(Color(0.92, 0.97, 1.0, 0.55), 32, 0.7)
	_spout.draw_pass_1 = puff
	_spout.position = Vector3(7.0, 2.0, 0.0)
	_spout.visibility_aabb = AABB(Vector3(-4.0, -2.0, -4.0), Vector3(8.0, 10.0, 8.0))
	_whale_root.add_child(_spout)


## Single additive billboard streak reused for every shooting star. The
## material is static so repeat title visits never recompile or reallocate.
func _build_shooting_star(viewport: SubViewport) -> void:
	if _streak_material == null:
		_streak_material = StandardMaterial3D.new()
		_streak_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_streak_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_streak_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_streak_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_streak_material.billboard_keep_scale = true
		_streak_material.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
		_streak_material.disable_receive_shadows = true
		_streak_material.disable_fog = true
	_shooting_star = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _streak_material
	_shooting_star.mesh = quad
	_shooting_star.visible = false
	_shooting_star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(_shooting_star)


## Band of flat sun-glint quads on the water toward the low sun (+X of +Z).
## Twinkle runs entirely on the GPU via per-instance custom data.
func _build_glints(viewport: SubViewport) -> void:
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	if quality == "low":
		return
	if _glint_material == null:
		_glint_shader = Shader.new()
		_glint_shader.code = GLINT_SHADER_CODE
		_glint_material = ShaderMaterial.new()
		_glint_material.shader = _glint_shader
	_glint_material.set_shader_parameter("strength", 0.5 if _reduced else 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51877
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	plane.material = _glint_material
	var count := 26 if quality == "high" else 16
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = plane
	multimesh.instance_count = count
	for i: int in count:
		var azimuth := deg_to_rad(22.0) + rng.randf_range(-0.24, 0.24)
		var dist := 16.0 + pow(rng.randf(), 1.6) * 120.0
		var pos := Vector3(sin(azimuth) * dist, -0.21, cos(azimuth) * dist)
		# Depth (z) scales far more than width: at grazing view angles the
		# quads compress to thin horizontal dashes — the sun-glint read.
		var glint_scale := Vector3(
			1.2 + dist * rng.randf_range(0.02, 0.04),
			1.0,
			2.0 + dist * rng.randf_range(0.08, 0.12))
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(glint_scale), pos))
		multimesh.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0.0, 0.0))
	var glints := MultiMeshInstance3D.new()
	glints.multimesh = multimesh
	glints.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(glints)


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
	_add_logo_sparkles()

	# Wrapper control carries the placement and the idle breathing pulse; the
	# button inside keeps its own hover/press scale tweens so the two never
	# fight over one scale property.
	_prompt_holder = Control.new()
	_prompt_holder.anchor_left = 0.5
	_prompt_holder.anchor_right = 0.5
	# Pinned a fixed margin above the bottom edge (not a proportional anchor)
	# so the taller 92px button never clips off-screen on landscape phones.
	_prompt_holder.anchor_top = 1.0
	_prompt_holder.anchor_bottom = 1.0
	_prompt_holder.offset_left = -170.0
	_prompt_holder.offset_right = 170.0
	_prompt_holder.offset_top = -132.0
	_prompt_holder.offset_bottom = -40.0
	_prompt_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_holder.resized.connect(func() -> void:
		_prompt_holder.pivot_offset = _prompt_holder.size * 0.5)
	overlay.add_child(_prompt_holder)

	# Real button beats a "press start" prompt on touch devices; the full-rect
	# TapCatcher below it still lets a tap anywhere begin the game.
	_prompt = UITheme.make_button("Begin", Vector2(340, 92), 42)
	_prompt.focus_mode = Control.FOCUS_ALL
	_prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prompt.pressed.connect(_start_game)
	_prompt_holder.add_child(_prompt)
	_prompt_glow = _build_prompt_glow(_prompt)
	_prompt.grab_focus.call_deferred()

	# Version tag styled as a quiet glass chip so the corner reads finished
	# instead of debug-overlay.
	var version_chip := PanelContainer.new()
	var version_style := StyleBoxFlat.new()
	version_style.bg_color = Color(0.04, 0.08, 0.15, 0.55)
	version_style.border_color = Color(UITheme.COLOR_ACCENT, 0.28)
	version_style.set_border_width_all(1)
	version_style.set_corner_radius_all(11)
	version_style.content_margin_left = 12.0
	version_style.content_margin_right = 12.0
	version_style.content_margin_top = 3.0
	version_style.content_margin_bottom = 4.0
	version_chip.add_theme_stylebox_override("panel", version_style)
	version_chip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version_chip.offset_left = -140.0
	version_chip.offset_top = -44.0
	version_chip.offset_right = -14.0
	version_chip.offset_bottom = -14.0
	version_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(version_chip)
	var version := Label.new()
	version.text = "v%s" % GameConfig.GAME_VERSION
	version.add_theme_font_override("font", UITheme.bold_font())
	version.add_theme_font_size_override("font_size", 16)
	version.add_theme_color_override("font_color", Color(0.78, 0.87, 0.98, 0.85))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	version_chip.add_child(version)


## Small twinkling stars pinned (by fractional anchors) to the wordmark's
## snow caps. Looped tweens with randomized rests; static dots when reduced
## motion is on; skipped headless and for the Label fallback logo.
func _add_logo_sparkles() -> void:
	if _logo_rect == null or GameConfig.is_headless():
		return
	var texture := UITheme.make_icon(SPARKLE_SVG, 1.0)
	if texture == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for point: Vector2 in LOGO_SPARKLE_POINTS:
		var star_size := rng.randf_range(13.0, 19.0)
		var sparkle := TextureRect.new()
		sparkle.texture = texture
		sparkle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sparkle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sparkle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sparkle.anchor_left = point.x
		sparkle.anchor_right = point.x
		sparkle.anchor_top = point.y
		sparkle.anchor_bottom = point.y
		sparkle.offset_left = -star_size * 0.5
		sparkle.offset_top = -star_size * 0.5
		sparkle.offset_right = star_size * 0.5
		sparkle.offset_bottom = star_size * 0.5
		sparkle.pivot_offset = Vector2(star_size, star_size) * 0.5
		_logo_rect.add_child(sparkle)
		if _reduced:
			sparkle.modulate.a = 0.55
			continue
		sparkle.modulate.a = 0.15
		sparkle.scale = Vector2(0.8, 0.8)
		var tween := sparkle.create_tween()
		tween.set_loops()
		tween.tween_interval(rng.randf_range(0.4, 2.2))
		tween.tween_property(sparkle, "modulate:a", 0.95, 0.45).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(sparkle, "scale", Vector2(1.25, 1.25), 0.45) \
			.set_trans(Tween.TRANS_SINE)
		tween.tween_property(sparkle, "modulate:a", 0.15, 0.75).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(sparkle, "scale", Vector2(0.8, 0.8), 0.75) \
			.set_trans(Tween.TRANS_SINE)


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
	if _floe_root != null:
		# Gentle floe bob: the ice (and everyone on it) rides a slow swell.
		_floe_root.position.y = sin(_elapsed * 0.5) * 0.035 * _motion_scale
		_floe_root.rotation.z = sin(_elapsed * 0.4 + 1.3) * 0.008 * _motion_scale
	_tick_diver(delta)
	_tick_whale()
	_tick_shooting_star()
	if _camera != null:
		_camera.position.x = sin(_elapsed * 0.22) * 0.35
		_camera.position.y = 1.5 + sin(_elapsed * 0.31) * 0.12
		_camera.look_at(Vector3(0.0, 0.6, 0.0))
	if _logo != null:
		_logo.pivot_offset = _logo.size * 0.5
		_logo.rotation = sin(_elapsed * 0.9) * 0.022
	if _prompt_holder != null and not _reduced:
		# Idle breathing on the wrapper — the button's own hover/press scale
		# tweens run on the child, so nothing fights.
		_prompt_holder.scale = Vector2.ONE * (1.0 + 0.012 * sin(_elapsed * 1.7))
	if _prompt_glow != null:
		var pulse_speed := 1.1 if _reduced else 2.6
		var amp := 0.12 if _reduced else 0.28
		# Pulse only the glow ring; the button itself stays fully opaque so
		# the label is legible over the dark water at every phase.
		_prompt_glow.modulate.a = 0.55 + amp * sin(_elapsed * pulse_speed)


## --- Ambient events ---------------------------------------------------------

## Dive cycle: PERCHED -(timer)-> DIVING (arc off the floe, splash on entry)
## -> UNDER (hidden) -> LEAPING (bursts from the water back onto the perch,
## splash on exit) -> PERCHED. Reduced motion keeps the diver idling forever.
func _tick_diver(delta: float) -> void:
	if _diver == null:
		return
	_diver.tick(delta, 0.0)
	match _diver_state:
		DiverState.PERCHED:
			if not _reduced and _elapsed >= _next_dive:
				_diver_state = DiverState.DIVING
				_diver_event_start = _elapsed
				_splashed = false
				_diver.set_pose(PenguinVisual.Pose.AIR)
				_diver.rotation.y = atan2(-DIVER_DIR.x, -DIVER_DIR.z)
		DiverState.DIVING:
			var u := clampf((_elapsed - _diver_event_start) / DIVE_DURATION, 0.0, 1.0)
			var flat := DIVER_PERCH + DIVER_DIR * 2.0 * u
			var y := 1.1 * u - 2.2 * u * u
			_diver.position = Vector3(flat.x, y, flat.z)
			_diver.rotation.x = -1.9 * u
			if not _splashed and u > 0.3 and y <= WATER_Y:
				_splashed = true
				_fire_splash(Vector3(flat.x, WATER_Y + 0.1, flat.z))
			if u >= 1.0:
				_diver.visible = false
				_diver_state = DiverState.UNDER
				_diver_event_start = _elapsed + randf_range(3.0, 6.0)
		DiverState.UNDER:
			if _elapsed >= _diver_event_start:
				_diver_state = DiverState.LEAPING
				_diver_event_start = _elapsed
				_diver.visible = true
				_diver.set_pose(PenguinVisual.Pose.AIR)
				_diver.rotation.y = atan2(DIVER_DIR.x, DIVER_DIR.z)
				var start := DIVER_PERCH + DIVER_DIR * 1.9
				_fire_splash(Vector3(start.x, WATER_Y + 0.1, start.z))
		DiverState.LEAPING:
			var u := clampf((_elapsed - _diver_event_start) / LEAP_DURATION, 0.0, 1.0)
			var start := DIVER_PERCH + DIVER_DIR * 1.9
			var flat := start.lerp(DIVER_PERCH, u)
			var y := lerpf(-0.7, 0.0, u) + 0.85 * sin(PI * u)
			_diver.position = Vector3(flat.x, y, flat.z)
			_diver.rotation.x = 0.55 * (1.0 - u)
			if u >= 1.0:
				_diver.position = DIVER_PERCH
				_diver.rotation = Vector3(0.0, 0.5, 0.0)
				_diver.set_pose(PenguinVisual.Pose.IDLE)
				_diver_state = DiverState.PERCHED
				_next_dive = _elapsed + randf_range(14.0, 26.0)


func _fire_splash(point: Vector3) -> void:
	if _splash == null:
		return
	_splash.position = point
	_splash.restart()


## Whale surfacing arc: rises, spouts near the top, rolls back under. The
## root is hidden between events so the idle diorama pays nothing for it.
func _tick_whale() -> void:
	if _whale_root == null:
		return
	if not _whale_active:
		if not _reduced and _elapsed >= _next_whale:
			_whale_active = true
			_whale_start = _elapsed
			_spouted = false
			_whale_root.visible = true
		return
	var u := clampf((_elapsed - _whale_start) / WHALE_DURATION, 0.0, 1.0)
	_whale_root.position = _whale_base + Vector3(6.0 * u, 2.8 * sin(PI * u), 0.0)
	_whale_root.rotation.z = 0.14 * cos(PI * u)
	if not _spouted and u >= 0.22:
		_spouted = true
		_spout.restart()
	if u >= 1.0:
		_whale_active = false
		_whale_root.visible = false
		_next_whale = _elapsed + randf_range(26.0, 44.0)


## Shooting star: one billboard streak sweeping a short chord high on the sky
## dome, growing then shrinking (scale, not material alpha — the material is
## shared and never mutated).
func _tick_shooting_star() -> void:
	if _shooting_star == null:
		return
	if not _star_active:
		if not _reduced and _elapsed >= _next_star:
			_star_active = true
			_star_start = _elapsed
			var azimuth := randf_range(-0.85, 0.85)
			var altitude := randf_range(0.75, 1.2)
			_star_from = Vector3(
				cos(altitude) * sin(azimuth), sin(altitude), cos(altitude) * cos(azimuth)) * 260.0
			var tangent := Vector3(cos(azimuth), 0.0, -sin(azimuth)) \
				* (1.0 if randf() < 0.5 else -1.0)
			_star_vel = (tangent + Vector3(0.0, -0.5, 0.0)).normalized() * 80.0
			_shooting_star.visible = true
		return
	var u := clampf((_elapsed - _star_start) / SHOOTING_STAR_DURATION, 0.0, 1.0)
	_shooting_star.position = _star_from + _star_vel * u * SHOOTING_STAR_DURATION
	var fade := sin(PI * u)
	_shooting_star.scale = Vector3(2.0 + 12.0 * fade, 0.25 + 0.75 * fade, 1.0)
	if u >= 1.0:
		_star_active = false
		_shooting_star.visible = false
		_next_star = _elapsed + randf_range(20.0, 40.0)


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
