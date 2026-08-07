class_name HazardIcicle
extends Node3D
## Falling icicle: hangs above the track, shivers as a warning when a racer
## approaches, drops, shatters, then regrows. Readable and fair.
##
## Visuals: shared flat-shaded lathe cluster (rippled main spike + two side
## spikes + frost collar) under a crystalline shader — fresnel rim, milky
## root -> glassy tip internal gradient, object-space glint cells. Telegraphs
## are SHAPE + MOTION + BRIGHTNESS, never hue: the warning shiver, a
## flickering drip glint sliding down the tip, and a floor target ring that
## flips to an amber/black chevron while the spike is armed
## ("accessibility/high_contrast_pickups" brightens both rings). Impact
## bursts into refractive shard particles. Collider, trigger distance, and
## all timings untouched.

const TRIGGER_DISTANCE: float = 26.0
const WARN_TIME: float = 0.85

## Crystalline ice shader: translucent body with an internal density gradient
## (milky compacted root -> clear blue tip), growth-ripple striations, dense
## bright core seen face-on (fake subsurface), fresnel rim glow, and sparse
## glint cells. cull_disabled + depth_draw_always keeps the transparent lathe
## self-sorting cleanly. gl_compatibility-safe (no screen/depth reads).
const CRYSTAL_SHADER_CODE := """shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

varying vec3 v_obj;

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.4);
	// 0 at the root (ceiling), 1 at the hanging tip.
	float t = clamp((1.1 - v_obj.y) / 2.2, 0.0, 1.0);
	// Internal gradient: milky compacted root -> clear glassy blue tip.
	vec3 root_col = vec3(0.88, 0.94, 1.0);
	vec3 tip_col = vec3(0.5, 0.76, 0.97);
	vec3 col = mix(root_col, tip_col, smoothstep(0.1, 0.85, t));
	// Growth-ripple striations: faint vertical banding over the lathe ridges.
	// Anything stronger than this crosses into looking like a printed pattern.
	float stri = 0.5 + 0.5 * sin(atan(v_obj.z, v_obj.x) * 7.0 + v_obj.y * 3.0);
	col *= 0.96 + stri * 0.05;
	// Dense bright core face-on near the root: fake subsurface scatter.
	col = mix(col, vec3(0.97, 0.995, 1.0), pow(ndv, 2.0) * 0.35 * (1.0 - t));
	// No procedural sparkle field.
	//
	// Two attempts at one made this prop worse, not better: object-space cells
	// drew white RECTANGLES across the spike, and a striation-following vein
	// drew a criss-cross net that read as wireframe. Ice reads as ice from its
	// silhouette, a hard specular and a bright wet rim -- so that is all it
	// gets, and it finally looks like ice.
	ALBEDO = col;
	// Solid, with the rim going glassy. The root stays the most opaque part,
	// which is where compacted meltwater actually clouds up.
	ALPHA = clamp(0.86 - fres * 0.22 + (1.0 - t) * 0.1, 0.0, 1.0);
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	EMISSION = vec3(0.72, 0.9, 1.0) * fres * 0.45;
}
"""

static var _cluster_mesh: ArrayMesh = null
static var _crystal_shader: Shader = null
static var _collar_mat: StandardMaterial3D = null
static var _drip_mat: StandardMaterial3D = null
static var _shard_mesh: ArrayMesh = null
static var _shard_mat: StandardMaterial3D = null
static var _ring_mesh: TorusMesh = null
static var _ring_mats: Dictionary = {}
static var _stripe_tex: ImageTexture = null

var _visual: MeshInstance3D
var _area: Area3D
var _state: int = 0  # 0 idle, 1 warning, 2 falling, 3 regrow
var _timer: float = 0.0
var _fall_speed: float = 0.0
var _rest_y: float = 0.0
var _floor_y: float = 0.0
var _drip: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _ring_hot: MeshInstance3D = null
var _shards: GPUParticles3D = null


func _ready() -> void:
	add_to_group(&"hazards")
	_rest_y = position.y
	_floor_y = position.y - 12.0
	var space_check := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * 30.0, GameConfig.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(space_check)
	if not hit.is_empty():
		_floor_y = (hit["position"] as Vector3).y

	_visual = MeshInstance3D.new()
	_visual.mesh = _get_cluster_mesh()
	# Random yaw so a row of icicles never reads as copy-paste clones.
	_visual.rotation.y = randf() * TAU
	add_child(_visual)

	_area = Area3D.new()
	_area.collision_layer = GameConfig.LAYER_HAZARDS
	_area.collision_mask = GameConfig.LAYER_RACERS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 2.2, 0.8)
	shape.shape = box
	_area.add_child(shape)
	_area.monitoring = false
	add_child(_area)
	_area.body_entered.connect(_on_hit)

	if not GameConfig.is_headless():
		_build_drip()
		_build_rings()
		_build_shards()


## Drip glint at the tip: a small additive billboard that flickers and slides
## down during the warning — the "about to let go" droplet catching light.
func _build_drip() -> void:
	_drip = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.26)
	_drip.mesh = quad
	_drip.material_override = _get_drip_material()
	_drip.position = Vector3(0.0, -1.06, 0.0)
	_drip.visible = false
	_drip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(_drip)


## Floor target rings under the drop point. The faint ring marks the landing
## zone at all times (SHAPE cue); the chevron ring lights while armed/falling
## (PATTERN + BRIGHTNESS). Both are top-level so the fall never drags them.
func _build_rings() -> void:
	var hc := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	_ring = MeshInstance3D.new()
	_ring.mesh = _get_ring_mesh()
	_ring.material_override = _get_ring_material("idle_hc" if hc else "idle")
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visibility_range_end = 60.0
	_ring.top_level = true
	add_child(_ring)
	_ring.global_position = Vector3(global_position.x, _floor_y + 0.04, global_position.z)
	_ring.scale = Vector3(1.0, 0.25, 1.0)
	_ring_hot = MeshInstance3D.new()
	_ring_hot.mesh = _get_ring_mesh()
	_ring_hot.material_override = _get_ring_material("hot_hc" if hc else "hot")
	_ring_hot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_hot.visibility_range_end = 60.0
	_ring_hot.top_level = true
	_ring_hot.visible = false
	add_child(_ring_hot)
	_ring_hot.global_position = Vector3(global_position.x, _floor_y + 0.06, global_position.z)
	_ring_hot.scale = Vector3(1.0, 0.25, 1.0)


## One-shot shard burst at the impact point (top-level: fires at the floor
## while the hidden icicle snaps back to its rest height).
func _build_shards() -> void:
	_shards = GPUParticles3D.new()
	_shards.top_level = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.5
	pm.gravity = Vector3(0.0, -22.0, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.particle_flag_rotate_y = true
	pm.angular_velocity_min = -420.0
	pm.angular_velocity_max = 420.0
	_shards.process_material = pm
	_shards.draw_pass_1 = _get_shard_mesh()
	_shards.amount = 16
	_shards.lifetime = 0.6
	_shards.one_shot = true
	_shards.explosiveness = 1.0
	_shards.emitting = false
	_shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shards.visibility_range_end = 60.0
	add_child(_shards)


func _physics_process(delta: float) -> void:
	match _state:
		0:
			# Watch for approaching racers below/ahead.
			for node: Node in get_tree().get_nodes_in_group(GameConfig.GROUP_RACERS):
				var racer := node as Racer
				if racer == null:
					continue
				var flat := Vector2(global_position.x - racer.global_position.x, global_position.z - racer.global_position.z)
				if flat.length() < TRIGGER_DISTANCE:
					_state = 1
					_timer = WARN_TIME
					AudioManager.play_sfx_3d("sfx_checkpoint", global_position, 1.6, -10.0)
					break
		1:
			_timer -= delta
			_visual.position.x = sin(_timer * 45.0) * 0.06
			if _drip != null:
				_drip.visible = true
				var flick := 0.55 + 0.45 * absf(sin(_timer * 26.0))
				_drip.scale = Vector3.ONE * flick
				_drip.position.y = -1.06 - (WARN_TIME - _timer) * 0.06
			if _ring_hot != null:
				_ring_hot.visible = true
				var p := 1.0 + 0.1 * sin(_timer * 22.0)
				_ring_hot.scale = Vector3(p, 0.25, p)
			if _timer <= 0.0:
				_state = 2
				_fall_speed = 0.0
				if _drip != null:
					_drip.visible = false
				_area.set_deferred("monitoring", true)
		2:
			_fall_speed += 34.0 * delta
			position.y -= _fall_speed * delta
			if position.y - 1.0 <= _floor_y:
				_shatter()
		3:
			_timer -= delta
			var grow := clampf(1.0 - _timer / 3.0, 0.05, 1.0)
			_visual.scale = Vector3(grow, grow, grow)
			if _timer <= 0.0:
				_state = 0
				_visual.scale = Vector3.ONE


func _shatter() -> void:
	AudioManager.play_sfx_3d("sfx_shield_break", global_position, 1.2, -8.0)
	if _shards != null:
		_shards.global_position = Vector3(global_position.x, _floor_y + 0.5, global_position.z)
		_shards.restart()
	if _ring_hot != null:
		_ring_hot.visible = false
		_ring_hot.scale = Vector3(1.0, 0.25, 1.0)
	if _drip != null:
		_drip.visible = false
	var course := get_tree().get_first_node_in_group(&"course") as CourseBase
	if course != null:
		course.spawn_land_puff(global_position)
	position.y = _rest_y
	_visual.position.x = 0.0
	_area.set_deferred("monitoring", false)
	_state = 3
	_timer = 3.0


func _on_hit(body: Node3D) -> void:
	if body is Racer:
		(body as Racer).apply_stun("icicle")
		_shatter()


## --- Shared visual resources ----------------------------------------------


## Lathe one rippled spike hanging from top_center down `length` meters.
## Radius profile: power falloff + growth-ripple rings + per-ring jitter,
## with a slight lateral drift so the spike hangs organically, not machined.
static func _lathe_spike(st: SurfaceTool, rng: RandomNumberGenerator, top: Vector3, length: float, base_r: float) -> void:
	# 7 radial segments left a visibly heptagonal silhouette on a prop the
	# player is meant to be reading at a glance; 13 is round enough that the
	# facets read as crystal cleavage instead of low-poly.
	var rings := 20
	var segs := 13
	var ring_pts: Array[PackedVector3Array] = []
	var drift := Vector3(rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.05, 0.05))
	# One ripple phase per spike so a cluster does not show the same rings at
	# the same heights on every member.
	var ripple_phase := rng.randf() * TAU
	for i: int in rings + 1:
		var t := float(i) / float(rings)
		# Near-conical with a flare into the ceiling.
		#
		# A power falloff alone gives a fat shoulder that runs most of the
		# length before needling at the very end -- which reads as a carrot,
		# not an icicle. Real ones are close to a cone, thickest right at the
		# root where meltwater keeps refreezing, with a rapid flare in the last
		# few centimetres where they meet the overhang.
		var r := base_r * pow(1.0 - t, 0.92)
		r *= 1.0 + 0.075 * sin(t * 16.0 + ripple_phase) + rng.randf_range(-0.03, 0.03)
		if t < 0.06:
			r *= 1.0 + (0.06 - t) * 3.0
		r = maxf(r, 0.0)
		var center := top + Vector3.DOWN * (length * t) + drift * (t * t * length)
		var pts := PackedVector3Array()
		for j: int in segs:
			var a := TAU * float(j) / float(segs)
			pts.append(center + Vector3(cos(a) * r, 0.0, sin(a) * r))
		ring_pts.append(pts)
	for i: int in rings:
		for j: int in segs:
			var jn := (j + 1) % segs
			var a := ring_pts[i][j]
			var b := ring_pts[i][jn]
			var c := ring_pts[i + 1][jn]
			var d := ring_pts[i + 1][j]
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)


static func _get_cluster_mesh() -> ArrayMesh:
	if _cluster_mesh != null:
		return _cluster_mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	# Surface 0: crystalline spikes (main + two companions), flat shaded.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe_spike(st, rng, Vector3(0.0, 1.1, 0.0), 2.2, 0.36)
	_lathe_spike(st, rng, Vector3(0.27, 1.1, 0.11), 1.05, 0.17)
	_lathe_spike(st, rng, Vector3(-0.24, 1.1, -0.13), 0.8, 0.14)
	# Two stubby late-growth spikes off the collar. A cluster of three all
	# pointing the same way reads as a decoration; five at mixed lengths reads
	# as something that grew.
	_lathe_spike(st, rng, Vector3(0.11, 1.12, -0.29), 0.52, 0.10)
	_lathe_spike(st, rng, Vector3(-0.09, 1.12, 0.31), 0.38, 0.085)
	st.generate_normals()
	var mesh := st.commit()
	# Surface 1: frost collar where the cluster meets the overhang.
	#
	# This used to be a fan of triangles whose rim radius and height were drawn
	# fresh for EACH face, so neighbouring faces did not share an edge and the
	# collar rendered as a heap of intersecting flat plates -- the single worst
	# thing about the prop close up. Vertices are now generated once around the
	# ring and shared, and the collar is a skirt of two rings rather than a
	# flat disc, so it has a rim you can see thickness in.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 15
	var crown := Vector3(0.0, 1.17, 0.0)
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	for i: int in sides:
		var a := TAU * float(i) / float(sides)
		var dir := Vector3(cos(a), 0.0, sin(a))
		# One jitter per ANGLE, reused by both faces that meet on it.
		var wobble := rng.randf_range(-0.07, 0.12)
		inner.append(crown + dir * (0.15 + wobble * 0.3) + Vector3.DOWN * 0.02)
		# The rim hangs below the crown: frost creeps down off an overhang.
		# Kept tight -- a wide skirt turned the whole prop into a trumpet.
		outer.append(crown + dir * (0.32 + wobble * 0.6)
			+ Vector3.DOWN * (0.10 + rng.randf_range(0.0, 0.06)))
	for i: int in sides:
		var j := (i + 1) % sides
		# Crown cap.
		st.add_vertex(crown)
		st.add_vertex(inner[j])
		st.add_vertex(inner[i])
		# Skirt.
		st.add_vertex(inner[i])
		st.add_vertex(inner[j])
		st.add_vertex(outer[j])
		st.add_vertex(inner[i])
		st.add_vertex(outer[j])
		st.add_vertex(outer[i])
	st.generate_normals()
	st.commit(mesh)
	if _crystal_shader == null:
		_crystal_shader = Shader.new()
		_crystal_shader.code = CRYSTAL_SHADER_CODE
	var crystal := ShaderMaterial.new()
	crystal.shader = _crystal_shader
	mesh.surface_set_material(0, crystal)
	mesh.surface_set_material(1, _get_collar_material())
	_cluster_mesh = mesh
	return _cluster_mesh


static func _get_collar_material() -> StandardMaterial3D:
	if _collar_mat == null:
		_collar_mat = StandardMaterial3D.new()
		_collar_mat.albedo_color = Color(0.94, 0.96, 1.0)
		_collar_mat.roughness = 0.9
		_collar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _collar_mat


static func _get_drip_material() -> StandardMaterial3D:
	if _drip_mat == null:
		_drip_mat = StandardMaterial3D.new()
		_drip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_drip_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_drip_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_drip_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_drip_mat.albedo_color = Color(0.85, 0.97, 1.0, 0.9)
		_drip_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 1.0)
	return _drip_mat


## Elongated glassy sliver (bipyramid) for the shatter burst.
static func _get_shard_mesh() -> ArrayMesh:
	if _shard_mesh != null:
		return _shard_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0.0, 0.17, 0.0)
	var bottom := Vector3(0.02, -0.14, 0.01)
	var ring: Array[Vector3] = [
		Vector3(0.05, 0.02, 0.0),
		Vector3(-0.03, 0.0, 0.045),
		Vector3(-0.025, 0.03, -0.04),
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
		_shard_mat.albedo_color = Color(0.72, 0.88, 1.0, 0.85)
		_shard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shard_mat.roughness = 0.05
		_shard_mat.rim_enabled = true
		_shard_mat.rim = 0.7
		_shard_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _shard_mat


static func _get_ring_mesh() -> TorusMesh:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.62
		_ring_mesh.outer_radius = 0.86
		_ring_mesh.rings = 24
		_ring_mesh.ring_segments = 6
	return _ring_mesh


## Amber/black chevron stripes (shared hazard warning language).
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


static func _get_ring_material(key: String) -> StandardMaterial3D:
	if _ring_mats.has(key):
		return _ring_mats[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	match key:
		"idle":
			mat.albedo_color = Color(0.7, 0.88, 1.0, 0.2)
		"idle_hc":
			mat.albedo_color = Color(0.78, 0.92, 1.0, 0.45)
		"hot":
			mat.albedo_color = Color(1.0, 1.0, 1.0, 0.75)
			mat.albedo_texture = _get_stripe_tex()
		_:
			mat.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
			mat.albedo_texture = _get_stripe_tex()
	_ring_mats[key] = mat
	return mat
