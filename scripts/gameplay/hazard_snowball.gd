class_name HazardSnowball
extends Node3D
## Big rolling snowball that travels down a stretch of track and resets.
## Telegraphed by size, rumble sound, and a consistent lane. Stuns on hit.
##
## Visuals: noise-displaced lumpy packed-snow ball (flat shaded so the lumps
## read as compacted chunks) under a crust shader that darkens crevices by
## radial depth (compacted-snow ambient occlusion) and rolls sparse glitter
## cells with the ball, plus dark grit flecks embedded in the crust — the
## flecks make the rolling motion readable as a PATTERN cue, independent of
## color. A contact snow spray, tumbling ice-chunk debris, and a soft dark
## shadow blob ground the ball against the track; the shadow gains an
## amber/black chevron lane ring when "accessibility/high_contrast_pickups"
## is on. Mesh + materials are built once per radius and shared; collider
## and timings untouched.

var guide: PathGuide = null
var start_offset: float = 0.0
var end_offset: float = 0.0
var lateral: float = 0.0
var speed: float = 14.0
var radius: float = 1.7

const ROLL_SFX_INTERVAL: float = 1.1

## Packed-snow crust shader: crevice shading from radial crust depth (recessed
## = compacted, colder, darker — a pure BRIGHTNESS cue), object-space glitter
## cells so the sparkle tumbles with the roll, and a faint fresnel sky-light
## so the silhouette stays separable from snow track. No textures, gl_compat.
const BODY_SHADER_CODE := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float ball_radius = 1.7;

varying vec3 v_obj;

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float rel = length(v_obj) / max(ball_radius, 0.001);
	// Crust displacement spans ~[0.85, 1.15] radii: low = packed crevice.
	float crevice = smoothstep(1.04, 0.87, rel);
	vec3 bright = vec3(0.965, 0.98, 1.0);
	vec3 packed_col = vec3(0.55, 0.63, 0.78);
	vec3 col = mix(bright, packed_col, crevice * 0.8);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	// Rolling glitter: object-space cells so glints tumble with the ball.
	vec3 cell = floor(v_obj * 13.0);
	vec3 jitter = vec3(hash31(cell), hash31(cell + 1.3), hash31(cell + 2.6)) - 0.5;
	float glint = pow(clamp(dot(normalize(NORMAL + jitter * 1.1), VIEW), 0.0, 1.0), 56.0)
			* step(0.55, hash31(cell + 4.1));
	ALBEDO = col;
	ROUGHNESS = 0.92 - crevice * 0.2;
	SPECULAR = 0.35;
	EMISSION = vec3(1.0) * glint * 0.55 * (1.0 - crevice)
			+ vec3(0.75, 0.85, 1.0) * fres * 0.1;
}
"""

static var _ball_meshes: Dictionary = {}
static var _body_shader: Shader = null
static var _shadow_mat: StandardMaterial3D = null
static var _spray_mat: StandardMaterial3D = null
static var _spray_ramp: GradientTexture1D = null
static var _chunk_mesh: ArrayMesh = null
static var _chunk_mat: StandardMaterial3D = null
static var _stripe_tex: ImageTexture = null
static var _hc_ring_mat: StandardMaterial3D = null

var _offset: float = 0.0
var _visual: MeshInstance3D
var _area: Area3D
var _respawn_wait: float = 0.0
var _hit_cooldown: Dictionary = {}
var _roll_sfx_timer: float = 0.0
var _spray: GPUParticles3D = null
var _chunks: GPUParticles3D = null
var _shadow: MeshInstance3D = null


func configure(p_guide: PathGuide, p_start: float, p_end: float, p_lateral: float, p_speed: float = 14.0) -> void:
	guide = p_guide
	start_offset = p_start
	end_offset = p_end
	lateral = p_lateral
	speed = p_speed
	_offset = p_start


func _ready() -> void:
	add_to_group(&"hazards")
	_visual = MeshInstance3D.new()
	_visual.mesh = _get_ball_mesh(radius)
	add_child(_visual)
	_area = Area3D.new()
	_area.collision_layer = GameConfig.LAYER_HAZARDS
	_area.collision_mask = GameConfig.LAYER_RACERS
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius * 0.9
	shape.shape = sphere
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(_on_hit)
	if not GameConfig.is_headless():
		_build_shadow()
		_build_spray()
		_build_chunks()
	if guide != null:
		global_position = guide.point_at(_offset, lateral, radius)


## Soft dark blob under the contact point: reads as weight and marks the
## danger lane on the ground by BRIGHTNESS (works in any palette). With
## high-contrast pickups on, a flat amber/black chevron ring rides on top of
## the blob so the lane also reads by PATTERN.
func _build_shadow() -> void:
	_shadow = MeshInstance3D.new()
	var disc := PlaneMesh.new()
	disc.size = Vector2(radius * 2.6, radius * 2.6)
	_shadow.mesh = disc
	_shadow.material_override = _get_shadow_material()
	_shadow.position.y = -radius * 0.95 + 0.05
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.visibility_range_end = 70.0
	add_child(_shadow)
	if bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups")):
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius * 1.02
		torus.outer_radius = radius * 1.24
		torus.rings = 24
		torus.ring_segments = 6
		ring.mesh = torus
		ring.material_override = _get_hc_ring_material()
		ring.scale = Vector3(1.0, 0.3, 1.0)
		ring.position.y = 0.05
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shadow.add_child(ring)


## Kicked-up snow at the rolling contact point. Simulated in global space so
## the puffs hang behind the moving ball as a short churned trail.
func _build_spray() -> void:
	_spray = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.45
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 5.5
	pm.gravity = Vector3(0.0, -9.0, 0.0)
	pm.scale_min = 0.55
	pm.scale_max = 1.35
	pm.color_ramp = _get_spray_ramp()
	_spray.process_material = pm
	var puff := QuadMesh.new()
	puff.size = Vector2(0.42, 0.42)
	puff.material = _get_spray_material()
	_spray.draw_pass_1 = puff
	_spray.amount = 30
	_spray.lifetime = 0.7
	_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spray.visibility_range_end = 70.0
	_spray.position = Vector3(0.0, -radius * 0.7, 0.0)
	add_child(_spray)


## Solid packed-snow chunks torn off at the contact point: tumbling low-poly
## debris that gives the spray physical weight (real avalanche balls shed
## chunks, not just powder).
func _build_chunks() -> void:
	_chunks = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.5
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 6.5
	pm.gravity = Vector3(0.0, -14.0, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	pm.particle_flag_rotate_y = true
	pm.angular_velocity_min = -260.0
	pm.angular_velocity_max = 260.0
	_chunks.process_material = pm
	_chunks.draw_pass_1 = _get_chunk_mesh()
	_chunks.amount = 12
	_chunks.lifetime = 0.8
	_chunks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chunks.visibility_range_end = 60.0
	_chunks.position = Vector3(0.0, -radius * 0.7, 0.0)
	add_child(_chunks)


func _physics_process(delta: float) -> void:
	if guide == null:
		return
	if _respawn_wait > 0.0:
		_respawn_wait -= delta
		if _respawn_wait <= 0.0:
			_offset = start_offset
			_visual.visible = true
			if _shadow != null:
				_shadow.visible = true
			if _spray != null:
				_spray.emitting = true
			if _chunks != null:
				_chunks.emitting = true
			_area.monitoring = true
		return
	_offset += speed * delta
	if _offset >= end_offset:
		_visual.visible = false
		if _shadow != null:
			_shadow.visible = false
		if _spray != null:
			_spray.emitting = false
		if _chunks != null:
			_chunks.emitting = false
		_area.set_deferred("monitoring", false)
		_respawn_wait = 2.0
		return
	global_position = guide.point_at(_offset, lateral, radius * 0.95)
	_visual.rotate_x(-speed * delta / radius)
	# Throttled low rumble while rolling: the audible telegraph promised in
	# the class doc, matching the seal/geyser positional-audio pattern.
	_roll_sfx_timer -= delta
	if _roll_sfx_timer <= 0.0:
		_roll_sfx_timer = ROLL_SFX_INTERVAL
		AudioManager.play_sfx_3d("sfx_slide", global_position, 0.5, -4.0)


func _on_hit(body: Node3D) -> void:
	if not body is Racer:
		return
	var racer := body as Racer
	var now := Time.get_ticks_msec()
	if int(_hit_cooldown.get(racer.racer_key, 0)) > now:
		return
	_hit_cooldown[racer.racer_key] = now + 3000
	# Heavy thud layered under apply_stun's sfx_impact; pitched well below
	# the thrown-snowball version so the big hazard reads bigger. The 3s
	# per-racer cooldown above throttles it.
	AudioManager.play_sfx_3d("sfx_snowball_hit", global_position, 0.7, -2.0)
	if racer.apply_stun("snowball_hazard") and racer.is_player:
		var camera := get_viewport().get_camera_3d()
		if camera != null and camera.get_parent() is ChaseCamera:
			(camera.get_parent() as ChaseCamera).add_shake(0.55)


## --- Shared visual resources (built once per radius, shared) --------------


## Displacement of the crust at a surface point: two simplex octaves. Kept in
## one place so vertices and fleck anchors agree exactly.
static func _crust(noise: FastNoiseLite, v: Vector3) -> float:
	return 1.0 + noise.get_noise_3dv(v) * 0.13 \
			+ noise.get_noise_3dv(v * 2.6 + Vector3(31.0, 7.0, 13.0)) * 0.05


static func _get_ball_mesh(p_radius: float) -> ArrayMesh:
	var key := "%.2f" % p_radius
	if _ball_meshes.has(key):
		return _ball_meshes[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 7
	noise.frequency = 1.05 / p_radius
	# Surface 0: lumpy crust. Sphere vertices pushed along their radial
	# direction, then deindexed + renormaled for a faceted packed-snow look.
	var sphere := SphereMesh.new()
	sphere.radius = p_radius
	sphere.height = p_radius * 2.0
	sphere.radial_segments = 22
	sphere.rings = 14
	var arrays: Array = sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i: int in verts.size():
		var v := verts[i]
		if v.length_squared() < 0.000001:
			continue
		verts[i] = v * _crust(noise, v)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var indexed := ArrayMesh.new()
	indexed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(indexed, 0)
	st.deindex()
	st.generate_normals()
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	# Surface 1: grit flecks — small dark tangent triangles seeded on the
	# crust (dirt and gravel picked up while rolling). They double as the
	# rotation-readability pattern.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i: int in 30:
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if dir.length_squared() < 0.05:
			continue
		dir = dir.normalized()
		var center := dir * p_radius * (_crust(noise, dir * p_radius) + 0.012)
		var up := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
		var t1 := dir.cross(up).normalized()
		var t2 := dir.cross(t1)
		var s := rng.randf_range(0.06, 0.15)
		st.add_vertex(center + t1 * s)
		st.add_vertex(center + (t2 - t1 * 0.4) * s)
		st.add_vertex(center - (t1 * 0.5 + t2 * 0.8) * s)
	st.generate_normals()
	st.commit(mesh)
	if _body_shader == null:
		_body_shader = Shader.new()
		_body_shader.code = BODY_SHADER_CODE
	var body_mat := ShaderMaterial.new()
	body_mat.shader = _body_shader
	body_mat.set_shader_parameter("ball_radius", p_radius)
	mesh.surface_set_material(0, body_mat)
	var fleck_mat := StandardMaterial3D.new()
	fleck_mat.albedo_color = Color(0.24, 0.2, 0.17)
	fleck_mat.roughness = 1.0
	fleck_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, fleck_mat)
	_ball_meshes[key] = mesh
	return mesh


static func _get_shadow_material() -> StandardMaterial3D:
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat.albedo_color = Color(0.03, 0.06, 0.1, 0.5)
		_shadow_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 1.0)
	return _shadow_mat


static func _get_spray_material() -> StandardMaterial3D:
	if _spray_mat == null:
		_spray_mat = StandardMaterial3D.new()
		_spray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spray_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_spray_mat.vertex_color_use_as_albedo = true
		_spray_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.85)
	return _spray_mat


static func _get_spray_ramp() -> GradientTexture1D:
	if _spray_ramp == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
		g.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, 0.8),
			Color(1.0, 1.0, 1.0, 0.0),
		])
		_spray_ramp = GradientTexture1D.new()
		_spray_ramp.gradient = g
	return _spray_ramp


## Irregular packed-snow chunk (low-poly tetra) for the contact debris.
static func _get_chunk_mesh() -> ArrayMesh:
	if _chunk_mesh != null:
		return _chunk_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = [
		Vector3(0.11, 0.0, 0.0),
		Vector3(-0.06, 0.09, 0.04),
		Vector3(-0.05, -0.03, -0.09),
		Vector3(0.01, 0.06, -0.07),
	]
	var faces: Array[Vector3i] = [
		Vector3i(0, 1, 2),
		Vector3i(0, 2, 3),
		Vector3i(0, 3, 1),
		Vector3i(1, 3, 2),
	]
	for f: Vector3i in faces:
		st.add_vertex(pts[f.x])
		st.add_vertex(pts[f.y])
		st.add_vertex(pts[f.z])
	st.generate_normals()
	_chunk_mesh = st.commit()
	_chunk_mesh.surface_set_material(0, _get_chunk_material())
	return _chunk_mesh


static func _get_chunk_material() -> StandardMaterial3D:
	if _chunk_mat == null:
		_chunk_mat = StandardMaterial3D.new()
		_chunk_mat.albedo_color = Color(0.9, 0.94, 1.0)
		_chunk_mat.roughness = 1.0
		_chunk_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _chunk_mat


## Amber/black chevron stripes: high luminance contrast so the hazard lane
## pattern reads for every color vision (same language as the seal ring).
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
