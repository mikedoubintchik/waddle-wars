class_name HazardWindZone
extends Area3D
## Strong side-wind region: pushes racers laterally while inside. The push
## reads by SHAPE + MOTION + BRIGHTNESS, colorblind-safe: long wind lines
## aligned to the push vector stream through the volume (velocity-aligned
## soft-ended quads, additive), and a bed of swirling snow motes fills the
## air so the zone has depth. "accessibility/high_contrast_pickups" swaps
## the wind lines for a brighter, fully opaque set. Collision volume, push
## values, and whoosh audio untouched.

const WHOOSH_INTERVAL: float = 2.6

static var _streak_tex: GradientTexture2D = null
static var _streak_mats: Dictionary = {}
static var _streak_ramp: GradientTexture1D = null
static var _mote_mat: StandardMaterial3D = null
static var _mote_ramp: GradientTexture1D = null

var push_direction: Vector3 = Vector3.RIGHT
var strength: float = 5.0
var zone_size: Vector3 = Vector3(16.0, 8.0, 40.0)

var _inside: Array[Racer] = []
var _whoosh_timer: float = 0.0


func configure(p_direction: Vector3, p_strength: float, p_size: Vector3) -> void:
	push_direction = p_direction.normalized()
	strength = p_strength
	zone_size = p_size


func _ready() -> void:
	collision_layer = GameConfig.LAYER_TRIGGERS
	collision_mask = GameConfig.LAYER_RACERS
	# Random start phase so multiple zones on a course never whoosh in sync.
	_whoosh_timer = randf() * WHOOSH_INTERVAL
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = zone_size
	shape.shape = box
	add_child(shape)
	body_entered.connect(func(body: Node3D) -> void:
		if body is Racer:
			_inside.append(body as Racer))
	body_exited.connect(func(body: Node3D) -> void:
		if body is Racer:
			_inside.erase(body as Racer))

	if not GameConfig.is_headless():
		_build_streaks()
		_build_motes()


## Long wind lines: velocity-aligned quads with a soft-ended gradient along
## their length, fading in/out over life. The dominant MOTION + SHAPE cue —
## every line is an arrow down the push vector.
func _build_streaks() -> void:
	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = zone_size * 0.5
	mat.direction = push_direction
	mat.spread = 4.0
	mat.initial_velocity_min = strength * 2.0
	mat.initial_velocity_max = strength * 3.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.55
	mat.scale_max = 1.25
	mat.lifetime_randomness = 0.4
	mat.particle_flag_align_y = true
	mat.color_ramp = _get_streak_ramp()
	particles.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 2.6)
	quad.material = _get_streak_material(
		bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups")))
	particles.draw_pass_1 = quad
	particles.amount = 64
	particles.lifetime = 1.2
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)


## Swirling snow motes: slower drift with tangential churn, filling the
## volume so the wind reads in depth, not just as surface lines.
func _build_motes() -> void:
	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = zone_size * 0.5
	mat.direction = push_direction
	mat.spread = 18.0
	mat.initial_velocity_min = strength * 0.8
	mat.initial_velocity_max = strength * 1.6
	mat.gravity = Vector3.ZERO
	mat.tangential_accel_min = -7.0
	mat.tangential_accel_max = 7.0
	mat.scale_min = 0.5
	mat.scale_max = 1.1
	mat.lifetime_randomness = 0.5
	mat.color_ramp = _get_mote_ramp()
	particles.process_material = mat
	var puff := QuadMesh.new()
	puff.size = Vector2(0.16, 0.16)
	puff.material = _get_mote_material()
	particles.draw_pass_1 = puff
	particles.amount = 40
	particles.lifetime = 2.0
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)


func _physics_process(delta: float) -> void:
	# Periodic low whoosh telegraphs the zone like seal/geyser audio; 3D
	# falloff keeps it local and the interval keeps it from spamming.
	_whoosh_timer -= delta
	if _whoosh_timer <= 0.0:
		_whoosh_timer = WHOOSH_INTERVAL
		AudioManager.play_sfx_3d("sfx_slide", global_position, 0.65, -6.0)
	for racer: Racer in _inside:
		if is_instance_valid(racer) and racer.state != Racer.State.FINISHED:
			racer.apply_wind(push_direction * strength)


## --- Shared visual resources ----------------------------------------------


## Soft-ended line gradient along the quad's long (V) axis.
static func _get_streak_texture() -> GradientTexture2D:
	if _streak_tex != null:
		return _streak_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	_streak_tex = GradientTexture2D.new()
	_streak_tex.gradient = g
	_streak_tex.fill_from = Vector2(0.5, 0.0)
	_streak_tex.fill_to = Vector2(0.5, 1.0)
	_streak_tex.width = 16
	_streak_tex.height = 64
	return _streak_tex


static func _get_streak_material(hc: bool) -> StandardMaterial3D:
	var key := "hc" if hc else "std"
	if _streak_mats.has(key):
		return _streak_mats[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _get_streak_texture()
	if hc:
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.95)
	else:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(0.62, 0.7, 0.8, 1.0)
	_streak_mats[key] = mat
	return mat


static func _get_streak_ramp() -> GradientTexture1D:
	if _streak_ramp == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
		g.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0, 0.0),
		])
		_streak_ramp = GradientTexture1D.new()
		_streak_ramp.gradient = g
	return _streak_ramp


static func _get_mote_material() -> StandardMaterial3D:
	if _mote_mat == null:
		_mote_mat = StandardMaterial3D.new()
		_mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mote_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_mote_mat.vertex_color_use_as_albedo = true
		_mote_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
	return _mote_mat


static func _get_mote_ramp() -> GradientTexture1D:
	if _mote_ramp == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		g.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, 0.6),
			Color(1.0, 1.0, 1.0, 0.0),
		])
		_mote_ramp = GradientTexture1D.new()
		_mote_ramp.gradient = g
	return _mote_ramp
