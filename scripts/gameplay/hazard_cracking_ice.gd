class_name HazardCrackingIce
extends Node3D
## Ice tile that cracks under a racer's weight and breaks after a short
## delay, dropping anyone still on it. Regenerates a few seconds later.
## Speed is safety: fast racers clear it before it breaks.
##
## Visuals: per-tile glass-ice shader. Idle tiles telegraph by PATTERN — faint
## voronoi stress hairlines plus a frosted border band (brightness outline,
## boosted by "accessibility/high_contrast_pickups"). When stepped on, a
## crack web (voronoi veins + radial impact spokes) spreads outward from the
## center over the crack delay, and the dark waterline shows through the
## cracks with a pulsing cold glow — SHAPE + MOTION + BRIGHTNESS, no hue
## reliance. Breaking bursts into ice shard particles over the splash.
## Trigger volume, crack/regen timing, and collision are untouched.

const CRACK_TIME: float = 0.55
const REGEN_TIME: float = 3.5

## Tile shader: crack_amount 0..1 drives the spreading web reveal from the
## tile center. World-space voronoi so neighboring tiles never share a
## pattern. gl_compatibility-safe (no screen/depth reads).
const TILE_SHADER_CODE := """shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float crack_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 half_size = vec2(3.0, 3.0);
uniform float hairline_boost = 0.0;

varying vec3 v_obj;
varying vec3 world_pos;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec2 voronoi_f12(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash22(ip + g) - fp;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec2(sqrt(f1), sqrt(f2));
}

void vertex() {
	v_obj = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 2.6);
	vec3 body = mix(vec3(0.62, 0.85, 0.98), vec3(0.2, 0.44, 0.64), facing * 0.5);
	float top = step(0.24, v_obj.y);
	// Crack veins: voronoi plate borders, widening as crack_amount grows.
	vec2 vor = voronoi_f12(world_pos.xz * 1.4);
	float line = 1.0 - smoothstep(0.0, 0.05 + crack_amount * 0.06, vor.y - vor.x);
	// Spreading reveal: the web grows outward from the stepped tile center.
	float d = length(v_obj.xz / half_size);
	float reveal = smoothstep(crack_amount * 1.6, crack_amount * 1.6 - 0.4, d)
			* step(0.001, crack_amount);
	// Radial impact spokes layered over the voronoi web.
	float ang = atan(v_obj.z, v_obj.x);
	float spoke = pow(0.5 + 0.5 * sin(ang * 5.0 + sin(ang * 3.0 + 1.7) * 1.4), 20.0);
	float web = max(line, spoke * smoothstep(0.1, 0.45, d)) * reveal * top;
	// Waterline through the cracks: dark cold water + pulsing glow.
	body = mix(body, vec3(0.02, 0.09, 0.16), web * 0.9);
	// Idle stress hairlines: the tile's PATTERN identity vs. safe floor.
	float hair = line * top * (0.16 + hairline_boost * 0.24) * (1.0 - reveal);
	body = mix(body, vec3(0.92, 0.97, 1.0), hair);
	// Pale stress whitening while cracking (replaces a flat albedo flash).
	body = mix(body, vec3(0.9, 0.95, 1.0), crack_amount * 0.3 * (1.0 - web));
	// Frosted border band: brightness outline for every color vision.
	vec2 e2 = abs(v_obj.xz) / half_size;
	float border = smoothstep(0.86, 0.97, max(e2.x, e2.y)) * top;
	body = mix(body, vec3(0.96, 0.99, 1.0), border * (0.5 + hairline_boost * 0.4));
	float pulse = 0.6 + 0.4 * sin(TIME * 9.0);
	ALBEDO = body;
	ALPHA = 0.95;
	ROUGHNESS = clamp(0.07 + border * 0.5 + web * 0.3, 0.0, 1.0);
	SPECULAR = 0.55;
	EMISSION = vec3(0.15, 0.7, 0.85) * web * crack_amount * pulse
			+ vec3(0.6, 0.85, 1.0) * fres * 0.15;
}
"""

static var _tile_shader: Shader = null
static var _shard_mesh: ArrayMesh = null
static var _shard_mat: StandardMaterial3D = null

var tile_size: Vector2 = Vector2(6.0, 6.0)

var _visual: MeshInstance3D
var _body: StaticBody3D
var _detector: Area3D
var _state: int = 0  # 0 solid, 1 cracking, 2 broken
var _timer: float = 0.0
var _mat: ShaderMaterial
var _shards: GPUParticles3D = null


func _ready() -> void:
	_visual = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tile_size.x, 0.5, tile_size.y)
	_visual.mesh = mesh
	if _tile_shader == null:
		_tile_shader = Shader.new()
		_tile_shader.code = TILE_SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _tile_shader
	_mat.set_shader_parameter("half_size", tile_size * 0.5)
	_mat.set_shader_parameter("hairline_boost",
			1.0 if bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups")) else 0.0)
	_visual.material_override = _mat
	add_child(_visual)

	_body = StaticBody3D.new()
	_body.collision_layer = GameConfig.LAYER_WORLD
	_body.collision_mask = 0
	_body.set_meta("surface", SurfacesDB.Surface.ICE_SMOOTH)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(tile_size.x, 0.5, tile_size.y)
	shape.shape = box
	_body.add_child(shape)
	add_child(_body)

	_detector = Area3D.new()
	_detector.collision_layer = GameConfig.LAYER_TRIGGERS
	_detector.collision_mask = GameConfig.LAYER_RACERS
	var detector_shape := CollisionShape3D.new()
	var detector_box := BoxShape3D.new()
	detector_box.size = Vector3(tile_size.x, 2.5, tile_size.y)
	detector_shape.shape = detector_box
	detector_shape.position.y = 1.2
	_detector.add_child(detector_shape)
	add_child(_detector)
	_detector.body_entered.connect(_on_stepped)

	if not GameConfig.is_headless():
		_build_shards()


## One-shot shard burst across the tile footprint when it lets go.
func _build_shards() -> void:
	_shards = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(tile_size.x * 0.4, 0.1, tile_size.y * 0.4)
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0.0, -18.0, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.6
	pm.particle_flag_rotate_y = true
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	_shards.process_material = pm
	_shards.draw_pass_1 = _get_shard_mesh()
	_shards.amount = 24
	_shards.lifetime = 0.7
	_shards.one_shot = true
	_shards.explosiveness = 1.0
	_shards.emitting = false
	_shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shards.visibility_range_end = 70.0
	add_child(_shards)


func _on_stepped(body: Node3D) -> void:
	if _state == 0 and body is Racer:
		_state = 1
		_timer = CRACK_TIME
		_mat.set_shader_parameter("crack_amount", 0.08)
		AudioManager.play_sfx_3d("sfx_stumble", global_position, 1.5, -6.0)


func _physics_process(delta: float) -> void:
	match _state:
		1:
			_timer -= delta
			_visual.position.y = sin(_timer * 60.0) * 0.03
			_mat.set_shader_parameter("crack_amount", clampf(1.0 - _timer / CRACK_TIME, 0.0, 1.0))
			if _timer <= 0.0:
				_break()
		2:
			_timer -= delta
			if _timer <= 0.0:
				_restore()


func _break() -> void:
	_state = 2
	_timer = REGEN_TIME
	_visual.visible = false
	_body.get_child(0).set_deferred("disabled", true)
	AudioManager.play_sfx_3d("sfx_shield_break", global_position, 0.8, -4.0)
	if _shards != null:
		_shards.restart()
	var course := get_tree().get_first_node_in_group(&"course") as CourseBase
	if course != null:
		course.spawn_splash(global_position)


func _restore() -> void:
	_state = 0
	_visual.visible = true
	_visual.position.y = 0.0
	_mat.set_shader_parameter("crack_amount", 0.0)
	_body.get_child(0).set_deferred("disabled", false)


## --- Shared visual resources ----------------------------------------------


## Flat glassy plate fragment for the break burst.
static func _get_shard_mesh() -> ArrayMesh:
	if _shard_mesh != null:
		return _shard_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0.0, 0.05, 0.0)
	var bottom := Vector3(0.03, -0.05, 0.02)
	var ring: Array[Vector3] = [
		Vector3(0.2, 0.0, 0.0),
		Vector3(-0.09, 0.0, 0.17),
		Vector3(-0.13, 0.0, -0.12),
	]
	for i: int in 3:
		var a := ring[i]
		var b := ring[(i + 1) % 3]
		st.add_vertex(top)
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(bottom)
		st.add_vertex(b)
		st.add_vertex(a)
	st.generate_normals()
	_shard_mesh = st.commit()
	_shard_mesh.surface_set_material(0, _get_shard_material())
	return _shard_mesh


static func _get_shard_material() -> StandardMaterial3D:
	if _shard_mat == null:
		_shard_mat = StandardMaterial3D.new()
		_shard_mat.albedo_color = Color(0.68, 0.86, 0.98, 0.9)
		_shard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shard_mat.roughness = 0.06
		_shard_mat.rim_enabled = true
		_shard_mat.rim = 0.6
		_shard_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _shard_mat
