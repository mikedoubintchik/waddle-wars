class_name HazardGeyser
extends Node3D
## Ice geyser: bubbles as a telegraph, then erupts on a fixed cycle,
## launching racers upward. Doubles as a jump pad on courses that place it
## under a gap — energetic, not punishing.
##
## Visuals: wet-vent shader base (near-black water throat with a breathing
## waterline glow, dark glossy wet rim, icy outer lip) over a soaked-ground
## disc; the eruption is a layered column — noise-eroded translucent outer
## sheath, bright additive core (refractive-looking center), droplet spray
## riding the column top — plus always-on steam wisps and a warn-phase
## bubble churn at the throat. Telegraphs read as SHAPE + MOTION + BRIGHTNESS
## (base pulse, bubbles, throat glow), colorblind-safe; with
## "accessibility/high_contrast_pickups" an amber/black chevron ring marks
## the launch zone by PATTERN. Cycle timing, launch values, and the trigger
## area are untouched.

var cycle_time: float = 3.2
var warn_time: float = 0.8
var launch_velocity: float = 15.0
var phase_offset: float = 0.0

## Vent base: object-space radial zones — water throat (near-black, breathing
## cyan waterline emission), wet dark glossy rim, mottled icy outer lip.
const VENT_SHADER_CODE := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 v_obj;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float r = length(v_obj.xz);
	float n = value_noise(v_obj.xz * 3.0);
	// Water throat: near-black hole in the middle of the vent.
	float hole = 1.0 - smoothstep(0.42, 0.6, r);
	// Wet dark rim: soaked, glossy ring around the throat.
	float wet = (1.0 - smoothstep(0.6, 1.3, r)) * (1.0 - hole);
	vec3 icy = vec3(0.6, 0.8, 0.93) * (0.88 + n * 0.16);
	vec3 wet_rock = vec3(0.1, 0.13, 0.16) * (0.8 + n * 0.4);
	vec3 water = vec3(0.012, 0.05, 0.09);
	vec3 col = mix(icy, wet_rock, wet);
	col = mix(col, water, hole);
	// Breathing waterline: slow brightness pulse at the throat edge — the
	// geyser's idle BRIGHTNESS telegraph.
	float pulse = 0.5 + 0.5 * sin(TIME * 2.2);
	float lip = smoothstep(0.34, 0.48, r) * (1.0 - smoothstep(0.5, 0.66, r));
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.55, 0.1, wet), 0.05, hole);
	SPECULAR = 0.6;
	EMISSION = vec3(0.08, 0.45, 0.55) * hole * (0.2 + 0.35 * pulse)
			+ vec3(0.18, 0.6, 0.7) * lip * pulse * 0.5;
}
"""

## Outer water sheath: two scrolling noise octaves erode the cylinder into
## streaming water/steam; silhouette edges fade by view angle so the column
## reads volumetric, and the top dissolves instead of ending in a lid.
const SHEATH_SHADER_CODE := """shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

varying vec3 v_obj;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// v_obj is read in fragment(), so it MUST be written here. Without this the
// GLES3 backend fails to link the shader ("Input of fragment shader 'm_v_obj'
// not written by vertex shader") and the mesh renders unshaded.
void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float h = clamp(v_obj.y / 6.0 + 0.5, 0.0, 1.0);
	float ang = atan(v_obj.z, v_obj.x);
	float n = value_noise(vec2(ang * 1.6, h * 5.0 - TIME * 2.8));
	float n2 = value_noise(vec2(ang * 3.2 + 7.0, h * 9.0 - TIME * 4.6));
	float dens = n * 0.6 + n2 * 0.4;
	float ndv = abs(dot(NORMAL, VIEW));
	vec3 col = mix(vec3(0.7, 0.88, 1.0), vec3(0.97, 1.0, 1.0), dens);
	ALBEDO = col;
	ALPHA = clamp((0.28 + dens * 0.5) * ndv, 0.0, 0.85)
			* (1.0 - smoothstep(0.7, 1.0, h)) * smoothstep(0.0, 0.06, h);
}
"""

## Additive inner core: fast-scrolling bright jet — the refractive-looking
## heart of the column that sells pressure.
const CORE_SHADER_CODE := """shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

varying vec3 v_obj;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// v_obj is read in fragment(), so it MUST be written here. Without this the
// GLES3 backend fails to link the shader ("Input of fragment shader 'm_v_obj'
// not written by vertex shader") and the mesh renders unshaded.
void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float h = clamp(v_obj.y / 6.0 + 0.5, 0.0, 1.0);
	float ang = atan(v_obj.z, v_obj.x);
	float n = value_noise(vec2(ang * 1.2, h * 4.0 - TIME * 5.2));
	float glow = (0.3 + n * 0.7) * (1.0 - smoothstep(0.55, 0.95, h)) * smoothstep(0.0, 0.1, h);
	ALBEDO = vec3(0.5, 0.82, 1.0) * glow;
	ALPHA = 1.0;
}
"""

static var _vent_shader: Shader = null
static var _sheath_shader: Shader = null
static var _core_shader: Shader = null
static var _vent_mat: ShaderMaterial = null
static var _sheath_mat: ShaderMaterial = null
static var _core_mat: ShaderMaterial = null
static var _wet_mat: StandardMaterial3D = null
static var _drop_mat: StandardMaterial3D = null
static var _drop_ramp: GradientTexture1D = null
static var _steam_ramp: GradientTexture1D = null
static var _bubble_ramp: GradientTexture1D = null
static var _stripe_tex: ImageTexture = null
static var _hc_ring_mat: StandardMaterial3D = null

var _time: float = 0.0
var _area: Area3D
var _column: MeshInstance3D
var _base: MeshInstance3D
var _bubbles: GPUParticles3D = null
var _erupting: bool = false


func _ready() -> void:
	_time = phase_offset
	_base = MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.4
	base_mesh.bottom_radius = 1.8
	base_mesh.height = 0.4
	base_mesh.radial_segments = 24
	_base.mesh = base_mesh
	_base.material_override = _get_vent_material()
	add_child(_base)

	_column = MeshInstance3D.new()
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = 0.9
	column_mesh.bottom_radius = 1.2
	column_mesh.height = 6.0
	_column.mesh = column_mesh
	_column.material_override = _get_sheath_material()
	_column.position.y = 3.0
	_column.visible = false
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_column)

	var core := MeshInstance3D.new()
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.5
	core_mesh.bottom_radius = 0.7
	core_mesh.height = 6.0
	core.mesh = core_mesh
	core.material_override = _get_core_material()
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.add_child(core)

	if not GameConfig.is_headless():
		_build_wet_ring()
		_build_droplets()
		_build_steam()
		_build_bubbles()
		if bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups")):
			_build_hc_ring()

	_area = Area3D.new()
	_area.collision_layer = GameConfig.LAYER_TRIGGERS
	_area.collision_mask = GameConfig.LAYER_RACERS
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.5
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position.y = 1.5
	_area.add_child(shape)
	add_child(_area)


## Soaked dark halo on the ground around the vent: the wet rim reads by
## BRIGHTNESS against snow and marks the splash zone.
func _build_wet_ring() -> void:
	var ring := MeshInstance3D.new()
	var disc := PlaneMesh.new()
	disc.size = Vector2(5.4, 5.4)
	ring.mesh = disc
	ring.material_override = _get_wet_material()
	ring.position.y = 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visibility_range_end = 70.0
	add_child(ring)


## Droplet spray riding the column top (child of the column, so it rises with
## the eruption ramp and hides with it — no extra state handling).
func _build_droplets() -> void:
	var drops := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.7
	pm.emission_ring_inner_radius = 0.25
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 3.5
	pm.initial_velocity_max = 6.5
	pm.gravity = Vector3(0.0, -18.0, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = _get_drop_ramp()
	drops.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	quad.material = _get_spray_quad_material()
	drops.draw_pass_1 = quad
	drops.amount = 24
	drops.lifetime = 0.7
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.position = Vector3(0.0, 3.0, 0.0)
	_column.add_child(drops)


## Always-on steam wisps: warm vent identity visible from far down the track.
func _build_steam() -> void:
	var steam := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 1.1
	pm.emission_ring_inner_radius = 0.4
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 20.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0.0, 0.4, 0.0)
	pm.scale_min = 1.2
	pm.scale_max = 2.4
	pm.lifetime_randomness = 0.4
	pm.color_ramp = _get_steam_ramp()
	steam.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _get_spray_quad_material()
	steam.draw_pass_1 = quad
	steam.amount = 12
	steam.lifetime = 2.4
	steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	steam.visibility_range_end = 80.0
	steam.position = Vector3(0.0, 0.3, 0.0)
	add_child(steam)


## Warn-phase bubble churn at the throat: bright fast MOTION telegraph.
func _build_bubbles() -> void:
	_bubbles = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.45
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 30.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0.0, 2.0, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	pm.color_ramp = _get_bubble_ramp()
	_bubbles.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.material = _get_spray_quad_material()
	_bubbles.draw_pass_1 = quad
	_bubbles.amount = 18
	_bubbles.lifetime = 0.5
	_bubbles.emitting = false
	_bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubbles.visibility_range_end = 60.0
	_bubbles.position = Vector3(0.0, 0.25, 0.0)
	add_child(_bubbles)


## Amber/black chevron ring marking the launch zone by PATTERN (high-contrast
## accessibility mode only).
func _build_hc_ring() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.0
	torus.outer_radius = 2.3
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = _get_hc_ring_material()
	ring.scale = Vector3(1.0, 0.3, 1.0)
	ring.position.y = 0.25
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


func _physics_process(delta: float) -> void:
	_time += delta
	var t := fmod(_time, cycle_time)
	var erupt_start := cycle_time - 1.0
	var warn_start := erupt_start - warn_time

	if t >= warn_start and t < erupt_start:
		# Telegraph: base pulses + throat bubbles churn.
		var pulse := 1.0 + sin((t - warn_start) * 30.0) * 0.08
		_base.scale = Vector3(pulse, 1.0, pulse)
		_erupting = false
		_column.visible = false
		if _bubbles != null and not _bubbles.emitting:
			_bubbles.emitting = true
	elif t >= erupt_start:
		_base.scale = Vector3.ONE
		if _bubbles != null and _bubbles.emitting:
			_bubbles.emitting = false
		if not _erupting:
			_erupting = true
			AudioManager.play_sfx_3d("sfx_splash", global_position, 0.8, -4.0)
		_column.visible = true
		_column.scale.y = clampf((t - erupt_start) * 6.0, 0.1, 1.0)
		for body: Node3D in _area.get_overlapping_bodies():
			if body is Racer:
				var racer := body as Racer
				if racer.vertical_velocity < launch_velocity * 0.8:
					racer.vertical_velocity = launch_velocity
					AudioManager.play_sfx_3d("sfx_jump", racer.global_position, 0.8)
	else:
		_erupting = false
		_column.visible = false
		_base.scale = Vector3.ONE
		if _bubbles != null and _bubbles.emitting:
			_bubbles.emitting = false


## --- Shared visual resources ----------------------------------------------


static func _get_vent_material() -> ShaderMaterial:
	if _vent_mat == null:
		_vent_shader = Shader.new()
		_vent_shader.code = VENT_SHADER_CODE
		_vent_mat = ShaderMaterial.new()
		_vent_mat.shader = _vent_shader
	return _vent_mat


static func _get_sheath_material() -> ShaderMaterial:
	if _sheath_mat == null:
		_sheath_shader = Shader.new()
		_sheath_shader.code = SHEATH_SHADER_CODE
		_sheath_mat = ShaderMaterial.new()
		_sheath_mat.shader = _sheath_shader
	return _sheath_mat


static func _get_core_material() -> ShaderMaterial:
	if _core_mat == null:
		_core_shader = Shader.new()
		_core_shader.code = CORE_SHADER_CODE
		_core_mat = ShaderMaterial.new()
		_core_mat.shader = _core_shader
	return _core_mat


static func _get_wet_material() -> StandardMaterial3D:
	if _wet_mat == null:
		_wet_mat = StandardMaterial3D.new()
		_wet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wet_mat.albedo_color = Color(0.02, 0.07, 0.12, 0.4)
		_wet_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 1.0)
	return _wet_mat


static func _get_spray_quad_material() -> StandardMaterial3D:
	if _drop_mat == null:
		_drop_mat = StandardMaterial3D.new()
		_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_drop_mat.vertex_color_use_as_albedo = true
		_drop_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
	return _drop_mat


static func _get_drop_ramp() -> GradientTexture1D:
	if _drop_ramp == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
		g.colors = PackedColorArray([
			Color(0.9, 0.97, 1.0, 0.0),
			Color(0.9, 0.97, 1.0, 0.85),
			Color(0.9, 0.97, 1.0, 0.0),
		])
		_drop_ramp = GradientTexture1D.new()
		_drop_ramp.gradient = g
	return _drop_ramp


static func _get_steam_ramp() -> GradientTexture1D:
	if _steam_ramp == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		g.colors = PackedColorArray([
			Color(0.93, 0.96, 1.0, 0.0),
			Color(0.93, 0.96, 1.0, 0.22),
			Color(0.93, 0.96, 1.0, 0.0),
		])
		_steam_ramp = GradientTexture1D.new()
		_steam_ramp.gradient = g
	return _steam_ramp


static func _get_bubble_ramp() -> GradientTexture1D:
	if _bubble_ramp == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		g.colors = PackedColorArray([
			Color(0.9, 1.0, 1.0, 0.0),
			Color(0.9, 1.0, 1.0, 0.85),
			Color(0.9, 1.0, 1.0, 0.0),
		])
		_bubble_ramp = GradientTexture1D.new()
		_bubble_ramp.gradient = g
	return _bubble_ramp


static func _get_stripe_tex() -> ImageTexture:
	if _stripe_tex != null:
		return _stripe_tex
	var img := Image.create(128, 16, false, Image.FORMAT_RGB8)
	var amber := Color(1.0, 0.58, 0.02)
	var dark := Color(0.08, 0.07, 0.06)
	for y: int in 16:
		for x: int in 128:
			var ph := (float(x) / 128.0 + float(y) / 16.0 * 0.06) * 14.0
			img.set_pixel(x, y, amber if int(floor(ph)) % 2 == 0 else dark)
	_stripe_tex = ImageTexture.create_from_image(img)
	return _stripe_tex


static func _get_hc_ring_material() -> StandardMaterial3D:
	if _hc_ring_mat == null:
		_hc_ring_mat = StandardMaterial3D.new()
		_hc_ring_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		_hc_ring_mat.albedo_texture = _get_stripe_tex()
		_hc_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hc_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _hc_ring_mat
