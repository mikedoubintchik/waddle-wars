class_name HazardWindZone
extends Area3D
## Strong side-wind region: pushes racers laterally while inside.
##
## The zone used to be an invisible box with particles floating in it. Nothing
## anchored it to the world, so it read as an effect switched on rather than a
## place, and at speed it was easy to be shoved without ever having seen a
## reason. It is now built like a piece of course furniture:
##
##   - WIND GATES mark the entry and exit on both flanks -- leaning pylons,
##     guy wires and streaming banners. They are the thing you see first, they
##     say where the zone starts and ends, and the banners point down the push
##     vector, so the direction is legible before you are in it.
##   - AIR: velocity-aligned streak lines and a bed of swirling motes fill the
##     volume so the wind has depth rather than being a surface effect.
##   - SPINDRIFT: low snow snakes race across the deck, which is how wind
##     actually reads on the ground.
##   - GUSTS: one envelope drives the banners, the streak emission AND the
##     force, so the zone breathes and what you see is what pushes you. The
##     mean is exactly the authored strength, so difficulty is unchanged.
##
## Telegraphy stays SHAPE + MOTION + BRIGHTNESS, never hue.
## "accessibility/high_contrast_pickups" brightens the streaks and banners.

## Seconds per gust cycle, and the two octaves mixed to keep it from feeling
## metronomic. Mean gain is 1.0 -- gusts redistribute the push over time, they
## do not add any.
const GUST_PERIOD: float = 3.1
const GUST_PERIOD_FAST: float = 1.27
const GUST_DEPTH: float = 0.34

## Banner geometry: segments along the streaming length, and the wave that
## travels down it.
const BANNER_SEGMENTS: int = 10
const BANNER_LENGTH: float = 4.4
const BANNER_HEIGHT: float = 0.88

static var _streak_tex: GradientTexture2D = null
static var _streak_mats: Dictionary = {}
static var _streak_ramp: GradientTexture1D = null
static var _mote_mat: StandardMaterial3D = null
static var _mote_ramp: GradientTexture1D = null
static var _spindrift_mat: StandardMaterial3D = null
static var _spindrift_ramp: GradientTexture1D = null
static var _banner_mesh: ArrayMesh = null
static var _banner_shader: Shader = null
static var _pylon_mat: StandardMaterial3D = null
static var _wire_mat: StandardMaterial3D = null
static var _bunting_mat: StandardMaterial3D = null

## Banner cloth. Waves travel along the streaming axis (+Z in banner space)
## and grow with distance from the mast, so the far edge whips and the fixed
## edge stays put. Gust strength scales the amplitude, so a lull visibly
## slackens the cloth. gl_compatibility-safe: no screen or depth reads.
const BANNER_SHADER_CODE := """shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform float wave_time = 0.0;
uniform float gust = 1.0;
uniform vec4 cloth_color : source_color = vec4(0.86, 0.93, 1.0, 0.92);
uniform vec4 stripe_color : source_color = vec4(0.36, 0.62, 0.86, 0.95);

varying float v_along;
varying float v_fold;

void vertex() {
	v_along = clamp(VERTEX.z / %LEN%, 0.0, 1.0);
	float amp = v_along * v_along * (0.16 + 0.26 * gust);
	float phase = VERTEX.z * 2.6 - wave_time * (5.0 + 3.0 * gust);
	VERTEX.x += sin(phase) * amp;
	VERTEX.y += cos(phase * 0.8) * amp * 0.45;
	// Slight droop in a lull: cloth without wind hangs.
	VERTEX.y -= v_along * (1.0 - gust) * 0.35;
	v_fold = sin(phase);
}

void fragment() {
	// Two-tone chevron stripes: reads as a marker flag at a glance and gives
	// the wave something to deform, which is what sells cloth.
	float band = step(0.5, fract(v_along * 3.0));
	vec3 col = mix(cloth_color.rgb, stripe_color.rgb, band);
	// Fake the shading a lit material would give the folds.
	col *= 0.78 + 0.22 * (v_fold * 0.5 + 0.5);
	ALBEDO = col;
	ALPHA = mix(cloth_color.a, 0.55, v_along * 0.5);
}
"""

var push_direction: Vector3 = Vector3.RIGHT
var strength: float = 5.0
var zone_size: Vector3 = Vector3(16.0, 8.0, 40.0)

var _inside: Array[Racer] = []
var _gust_time: float = 0.0
var _banner_materials: Array[ShaderMaterial] = []
var _streak_particles: GPUParticles3D = null
var _wind_audio: AudioStreamPlayer3D = null


func configure(p_direction: Vector3, p_strength: float, p_size: Vector3) -> void:
	push_direction = p_direction.normalized()
	strength = p_strength
	zone_size = p_size


func _ready() -> void:
	collision_layer = GameConfig.LAYER_TRIGGERS
	collision_mask = GameConfig.LAYER_RACERS
	# Random start phase so multiple zones on a course never gust in sync.
	_gust_time = randf() * GUST_PERIOD
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
		_build_gates()
		_build_streaks()
		_build_motes()
		_build_spindrift()
		_build_audio()


## --- Structure --------------------------------------------------------------

## Four gate pylons: one per flank at the entry and exit faces of the volume.
## These are the zone's signage. They lean away from the wind (a mast under
## constant load does), carry a guy wire back into the ground on the windward
## side, and fly a banner from the crossarm down the push vector.
func _build_gates() -> void:
	var half := zone_size * 0.5
	# Push direction in the zone's own space: the banners stream along it and
	# the masts lean with it.
	var local_push := (global_transform.basis.inverse() * push_direction).normalized() \
		if is_inside_tree() else push_direction
	local_push.y = 0.0
	if local_push.length_squared() < 0.001:
		local_push = Vector3.RIGHT
	local_push = local_push.normalized()
	var height := maxf(half.y * 1.7, 5.0)
	for z_end: float in [-half.z, half.z]:
		for x_side: float in [-half.x, half.x]:
			_build_pylon(Vector3(x_side, -half.y, z_end), height, local_push)
		# Bunting strung between the flank masts. Four separate posts read as
		# scattered furniture; a line across the gap reads as a gate, and a
		# gate is a thing you can see you are about to pass through.
		_build_bunting(z_end, half, height)


## Sagging cord between the two flank masts at one end of the volume, hung
## with alternating pennants. Built as ONE mesh: a dozen rope segments and as
## many triangles is a lot of nodes for something that never moves.
func _build_bunting(z_end: float, half: Vector3, height: float) -> void:
	var top := -half.y + height - 0.5
	var span := half.x * 2.0
	var sag := clampf(span * 0.10, 0.4, 1.3)
	var segments := 16
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := PackedVector3Array()
	for i: int in segments + 1:
		var t := float(i) / float(segments)
		var x := lerpf(-half.x, half.x, t)
		# Parabola stands in for a catenary; over one span they are the same
		# curve to the eye and this one is three operations.
		var y := top - sag * 4.0 * t * (1.0 - t)
		points.append(Vector3(x, y, z_end))
	var rope := 0.045
	for i: int in segments:
		var a := points[i]
		var b := points[i + 1]
		# Cord: a thin quad cross so it reads from every angle without a tube.
		for axis: Vector3 in [Vector3.UP * rope, Vector3(0.0, 0.0, rope)]:
			st.set_color(Color(0.16, 0.19, 0.24))
			st.add_vertex(a - axis)
			st.add_vertex(b - axis)
			st.add_vertex(b + axis)
			st.set_color(Color(0.16, 0.19, 0.24))
			st.add_vertex(a - axis)
			st.add_vertex(b + axis)
			st.add_vertex(a + axis)
	# Pennants: alternating warm/cool triangles, every other rope segment.
	for i: int in range(1, segments, 2):
		var anchor: Vector3 = points[i]
		var next: Vector3 = points[i + 1]
		var along := (next - anchor)
		# Saturated pair. The old cool tone was near-white, which vanished against
		# snow and left the run of pennants looking half-finished.
		var flag := Color(1.0, 0.68, 0.14) if (i / 2) % 2 == 0 else Color(0.20, 0.52, 0.86)
		var drop := Vector3(0.0, -0.62, 0.0)
		# Canted slightly out of the rope plane so the row does not vanish
		# edge-on from the racing line.
		var cant := Vector3(0.0, 0.0, 0.14 if (i / 2) % 2 == 0 else -0.14)
		st.set_color(flag)
		st.add_vertex(anchor)
		st.add_vertex(anchor + along)
		st.add_vertex(anchor + along * 0.5 + drop + cant)
		st.set_color(flag)
		st.add_vertex(anchor)
		st.add_vertex(anchor + along * 0.5 + drop + cant)
		st.add_vertex(anchor + along)
	st.generate_normals()
	var mesh := st.commit()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _get_bunting_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _build_pylon(base: Vector3, height: float, local_push: Vector3) -> void:
	var pylon := Node3D.new()
	pylon.position = base
	# Lean downwind: 9 degrees is enough to read as loaded, not as broken.
	pylon.basis = Basis(local_push.cross(Vector3.UP).normalized(), deg_to_rad(-9.0))
	add_child(pylon)

	var mast := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.075
	pole.bottom_radius = 0.16
	pole.height = height
	pole.radial_segments = 10
	pole.rings = 1
	mast.mesh = pole
	mast.material_override = _get_pylon_material()
	mast.position = Vector3(0.0, height * 0.5, 0.0)
	mast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pylon.add_child(mast)

	# Crossarm the banner hangs from, set across the wind so the cloth streams
	# clear of the mast.
	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.09, 0.09, 0.95)
	arm.mesh = arm_mesh
	arm.material_override = _get_pylon_material()
	arm.position = Vector3(0.0, height - 0.98, 0.0)
	arm.basis = Basis(Vector3.UP, atan2(local_push.x, local_push.z))
	pylon.add_child(arm)

	# Guy wire back into the ground on the windward side: the detail that makes
	# a pole read as rigged rather than planted.
	var wire := MeshInstance3D.new()
	var wire_mesh := BoxMesh.new()
	# Kept short: a long thin line across open snow reads as a scratch on the
	# screen rather than as rigging.
	var anchor := -local_push * (height * 0.34)
	var span := Vector3(anchor.x, -height * 0.66, anchor.z)
	wire_mesh.size = Vector3(0.05, span.length(), 0.05)
	wire.mesh = wire_mesh
	wire.material_override = _get_wire_material()
	wire.position = Vector3(0.0, height * 0.86, 0.0) + span * 0.5
	wire.basis = Basis(Quaternion(Vector3.UP, span.normalized()))
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pylon.add_child(wire)

	var banner := MeshInstance3D.new()
	banner.mesh = _get_banner_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = _get_banner_shader()
	var hc := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if hc:
		mat.set_shader_parameter("cloth_color", Color(1.0, 1.0, 1.0, 1.0))
		mat.set_shader_parameter("stripe_color", Color(1.0, 0.72, 0.1, 1.0))
	banner.material_override = mat
	banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Hung below the crossarm rather than level with it: at eye height from
	# the racing line it is read, at mast top it is decoration above the frame.
	banner.position = Vector3(0.0, height - 1.05, 0.0)
	banner.basis = Basis(Vector3.UP, atan2(local_push.x, local_push.z))
	pylon.add_child(banner)
	_banner_materials.append(mat)


## --- Air --------------------------------------------------------------------

## Long wind lines: velocity-aligned quads with a soft-ended gradient along
## their length. The dominant MOTION + SHAPE cue — every line is an arrow down
## the push vector.
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
	_streak_particles = particles


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


## Ground spindrift: flat ribbons of blown snow racing across the deck. Wind on
## snow is read from the ground first, and a zone whose whole effect floated at
## chest height never looked like it touched the course.
func _build_spindrift() -> void:
	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# A thin slab hugging the floor of the volume.
	mat.emission_box_extents = Vector3(zone_size.x * 0.5, 0.22, zone_size.z * 0.5)
	mat.direction = push_direction
	mat.spread = 9.0
	mat.initial_velocity_min = strength * 2.4
	mat.initial_velocity_max = strength * 3.6
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.7
	mat.scale_max = 1.7
	mat.lifetime_randomness = 0.45
	mat.particle_flag_align_y = true
	mat.color_ramp = _get_spindrift_ramp()
	particles.process_material = mat
	var ribbon := QuadMesh.new()
	ribbon.size = Vector2(0.5, 3.2)
	ribbon.material = _get_spindrift_material()
	particles.draw_pass_1 = ribbon
	particles.amount = 34
	particles.lifetime = 1.1
	particles.position = Vector3(0.0, -zone_size.y * 0.5 + 0.24, 0.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)


## Continuous positional wind bed, volume tracking the gust.
##
## This used to fire a one-shot every 2.6 s off the belly-slide scrape, which
## was both the wrong sound and audibly periodic. A wind zone is a place, and
## places have a continuous bed.
func _build_audio() -> void:
	var shared := AudioManager.get_stream("sfx_slide")
	if shared == null:
		return
	# Duplicate before looping it: get_stream() returns the shared resource.
	var stream := shared.duplicate() as AudioStream
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var bytes_per_sample := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
		var channels := 2 if wav.stereo else 1
		wav.loop_end = wav.data.size() / (bytes_per_sample * channels)
	_wind_audio = AudioStreamPlayer3D.new()
	_wind_audio.stream = stream
	_wind_audio.bus = &"SFX"
	# Pitched well down and spread wide: the scrape sample becomes a low rush.
	_wind_audio.pitch_scale = 0.52
	_wind_audio.unit_size = maxf(zone_size.z, zone_size.x) * 0.5
	_wind_audio.max_distance = maxf(zone_size.z, 60.0) * 1.6
	_wind_audio.volume_db = -22.0
	add_child(_wind_audio)
	_wind_audio.play()


## --- Tick -------------------------------------------------------------------

## Gust envelope, mean exactly 1.0 so the average push equals the authored
## strength and course difficulty is untouched by the addition.
func _gust() -> float:
	var slow := sin(_gust_time * TAU / GUST_PERIOD)
	var fast := sin(_gust_time * TAU / GUST_PERIOD_FAST + 1.7)
	return 1.0 + (slow * 0.7 + fast * 0.3) * GUST_DEPTH


func _physics_process(delta: float) -> void:
	_gust_time += delta
	var gust := _gust()
	for racer: Racer in _inside:
		if is_instance_valid(racer) and racer.state != Racer.State.FINISHED:
			racer.apply_wind(push_direction * strength * gust)


func _process(delta: float) -> void:
	if GameConfig.is_headless():
		return
	var gust := _gust()
	var wave := float(Time.get_ticks_msec()) * 0.001
	for mat: ShaderMaterial in _banner_materials:
		mat.set_shader_parameter("wave_time", wave)
		mat.set_shader_parameter("gust", clampf(gust, 0.4, 1.6))
	if _streak_particles != null:
		# Emission thins in a lull and floods in a gust, so the air itself
		# carries the rhythm the force does.
		_streak_particles.speed_scale = clampf(gust, 0.55, 1.5)
	if _wind_audio != null:
		_wind_audio.volume_db = lerpf(-26.0, -13.0, clampf((gust - 0.6) / 0.8, 0.0, 1.0))


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


static func _get_spindrift_material() -> StandardMaterial3D:
	if _spindrift_mat == null:
		_spindrift_mat = StandardMaterial3D.new()
		_spindrift_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spindrift_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spindrift_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_spindrift_mat.vertex_color_use_as_albedo = true
		_spindrift_mat.albedo_texture = _get_streak_texture()
		_spindrift_mat.albedo_color = Color(0.96, 0.98, 1.0, 0.5)
	return _spindrift_mat


static func _get_spindrift_ramp() -> GradientTexture1D:
	if _spindrift_ramp == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.22, 0.7, 1.0])
		g.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, 0.7),
			Color(1.0, 1.0, 1.0, 0.45),
			Color(1.0, 1.0, 1.0, 0.0),
		])
		_spindrift_ramp = GradientTexture1D.new()
		_spindrift_ramp.gradient = g
	return _spindrift_ramp


## Banner cloth: a strip along +Z, subdivided so the vertex wave has something
## to move. Shared by every banner in the game; the wave lives in the shader.
static func _get_banner_mesh() -> ArrayMesh:
	if _banner_mesh != null:
		return _banner_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_h := BANNER_HEIGHT * 0.5
	for i: int in BANNER_SEGMENTS:
		var z0 := BANNER_LENGTH * float(i) / float(BANNER_SEGMENTS)
		var z1 := BANNER_LENGTH * float(i + 1) / float(BANNER_SEGMENTS)
		# Taper to a pennant point so the far end whips rather than flapping
		# as a rectangle.
		var h0 := half_h * (1.0 - 0.55 * (z0 / BANNER_LENGTH))
		var h1 := half_h * (1.0 - 0.55 * (z1 / BANNER_LENGTH))
		var a := Vector3(0.0, h0, z0)
		var b := Vector3(0.0, -h0, z0)
		var c := Vector3(0.0, -h1, z1)
		var d := Vector3(0.0, h1, z1)
		for v: Vector3 in [a, b, c, a, c, d]:
			st.set_normal(Vector3.RIGHT)
			st.add_vertex(v)
	_banner_mesh = st.commit()
	return _banner_mesh


static func _get_banner_shader() -> Shader:
	if _banner_shader == null:
		_banner_shader = Shader.new()
		_banner_shader.code = BANNER_SHADER_CODE.replace(
			"%LEN%", "%.4f" % BANNER_LENGTH)
	return _banner_shader


static func _get_pylon_material() -> StandardMaterial3D:
	if _pylon_mat == null:
		_pylon_mat = StandardMaterial3D.new()
		# Weathered marker-post orange: warm against every course palette, and
		# the one hue in the game reserved for "course furniture".
		_pylon_mat.albedo_color = Color(0.72, 0.36, 0.16)
		_pylon_mat.roughness = 0.82
		_pylon_mat.metallic = 0.05
	return _pylon_mat


static func _get_wire_material() -> StandardMaterial3D:
	if _wire_mat == null:
		_wire_mat = StandardMaterial3D.new()
		_wire_mat.albedo_color = Color(0.45, 0.5, 0.58)
		_wire_mat.roughness = 0.55
		_wire_mat.metallic = 0.4
	return _wire_mat


static func _get_bunting_material() -> StandardMaterial3D:
	if _bunting_mat == null:
		_bunting_mat = StandardMaterial3D.new()
		_bunting_mat.vertex_color_use_as_albedo = true
		_bunting_mat.albedo_color = Color(1.0, 1.0, 1.0)
		_bunting_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bunting_mat.roughness = 0.85
		# Lifted off pure diffuse so the pennants stay readable on the night
		# course this hazard actually lives on.
		_bunting_mat.emission_enabled = true
		_bunting_mat.emission = Color(0.5, 0.62, 0.8)
		_bunting_mat.emission_energy_multiplier = 0.22
	return _bunting_mat
