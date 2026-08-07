class_name PolarBear
extends Node3D
## Ambient trackside polar bear. PURE DRESSING: no collision shape, no Area3D,
## no groups, no gameplay hooks — racers pass straight through the space it
## occupies. It exists to make the glacier read as inhabited wilderness.
##
## Visual: a real ursine build rather than a capsule with ears. One continuous
## neck+torso lathe (long low barrel, humped withers, a dip through the loin, a
## high rounded rump and a stub tail) with egg-shaped cross sections — deep
## chest, flatter back — plus four thick columnar limbs whose shoulder and
## haunch masses deliberately bulge past the flank so the body reads as muscle
## over bone. Paws are broad slabs with five toe domes and dark claws; the head
## is a small braincase running out into a long, subtly dished muzzle with a
## black nose button, small rounded ears set well back, and glossy dark eyes.
##
## Polar bears are NOT white. The vertex colors run cream/ivory along the sunlit
## spine down through buff flanks into a warm ochre-shadowed underside, with
## FastNoiseLite guard-hair clumping, yellowed patches, damp-dark lower legs, a
## black lip line and darkened eye surrounds. A shared fur shader adds
## hemispheric countershading, two scales of strand detail that fade out with
## distance, a weak warm rim and matte roughness.
##
## Everything (meshes, materials, noise) is built once into static caches, so
## the fifth bear on a course costs node allocation only. Per-frame work is a
## handful of sines on three nodes, and it is skipped entirely when headless or
## when reduced motion is on.

enum Pose {
	STANDING,  ## Four-square, weight settled, head carried below the withers.
	SITTING,   ## Rump down, forelegs propped straight, hind legs forward.
	LYING,     ## Belly down and sprawled, limbs splayed, head low.
}

## --- Coat palette -----------------------------------------------------------
## Deliberately low values. ACES tonemapping plus the courses' strong sky
## ambient lift vertex colors roughly two stops, so an "ivory" authored at 0.95
## renders as paper white indistinguishable from the snow behind it; authored
## here, the coat lands a clear step darker than the drift it stands on, which
## is what a polar bear actually looks like.
const FUR_TOP := Color(0.52, 0.49, 0.43)    # sunlit ivory along the spine
const FUR_MID := Color(0.42, 0.38, 0.30)    # cream flank
const FUR_LOW := Color(0.22, 0.19, 0.145)   # warm ochre shadow underside
const FUR_BUFF := Color(0.40, 0.32, 0.20)   # yellowed guard-hair patches
const FUR_DAMP := Color(0.18, 0.16, 0.13)   # wet/dirty lower legs
const NOSE_DARK := Color(0.05, 0.045, 0.048)
const LIP_DARK := Color(0.13, 0.11, 0.10)
const CLAW_DARK := Color(0.24, 0.21, 0.18)

## --- Build proportions (metres; the bear faces -Z, ground at y = 0) ---------
## Adult male: 1.32 m at the withers, 2.46 m nose to tail, belly clearance 0.60.
## The ratio that matters is body depth (0.72) BEATING visible leg length
## (0.60) — get that backwards and the silhouette reads as a big white dog no
## matter how good the head is.
const BODY_SEGS: int = 26
const LEG_SEGS: int = 16
const HEAD_SEGS: int = 22
const HEAD_JOINT := Vector3(0.0, 1.14, -0.80)   # atlas: where the head pivots
const FRONT_SOCKET := Vector3(0.225, 1.02, -0.36)
const HIND_SOCKET := Vector3(0.225, 1.02, 0.54)

## Fur shader. gl_compatibility-safe: no screen or depth reads, no instance
## uniforms, object-space detail so nothing swims when the body breathes.
const FUR_SHADER_CODE := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float rim_strength : hint_range(0.0, 2.0) = 0.14;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float dist = length(VERTEX);
	// Two scales of pelt detail. Guard-hair strands only survive close up;
	// the broader clumping carries to mid distance, past which the coat is
	// meant to go smooth rather than sparkle into noise.
	float near_k = 1.0 - smoothstep(4.0, 14.0, dist);
	float mid_k = 1.0 - smoothstep(12.0, 34.0, dist);
	float strand = sin(v_obj.x * 190.0 + v_obj.y * 64.0) * sin(v_obj.z * 165.0 - v_obj.y * 43.0);
	float clump = sin(v_obj.y * 23.0 + sin(v_obj.x * 8.0 + v_obj.z * 6.0) * 2.1)
		* (0.55 + 0.45 * sin(v_obj.x * 13.0 - v_obj.z * 9.0));

	// Hemispheric countershading. INV_VIEW_MATRIX's second row is world up in
	// view space, which is one dot product and no extra varying. (Do NOT reach
	// for MODEL_NORMAL_MATRIX here: it is not emitted in every
	// gl_compatibility specialization and additive light passes fail to link.)
	vec3 world_up = vec3(INV_VIEW_MATRIX[0][1], INV_VIEW_MATRIX[1][1], INV_VIEW_MATRIX[2][1]);
	float up = clamp(dot(NORMAL, world_up) * 0.5 + 0.5, 0.0, 1.0);
	float shade = up * up * (3.0 - 2.0 * up);
	vec3 col = base * (mix(0.56, 1.16, shade) + strand * 0.055 * near_k + clump * 0.05 * mid_k);
	col += vec3(0.05, 0.07, 0.11) * (shade * shade * 0.09);

	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 3.2);
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	// Warm, weak edge light: enough to lift the silhouette off sunlit snow,
	// far too weak to read as a sticker outline.
	EMISSION = vec3(1.0, 0.88, 0.68) * (rim * rim_strength * (0.30 + 0.70 * up));
	ROUGHNESS = mix(0.94, 0.80, shade);
	SPECULAR = 0.22;
}
"""

static var _torso_mesh: ArrayMesh = null
static var _front_leg_mesh: ArrayMesh = null
static var _hind_leg_mesh: ArrayMesh = null
static var _head_mesh: ArrayMesh = null
static var _face_mesh: ArrayMesh = null
static var _gleam_mesh: SphereMesh = null
static var _fur_shader: Shader = null
static var _fur_mat: ShaderMaterial = null
static var _face_mat: StandardMaterial3D = null
static var _gleam_mat: StandardMaterial3D = null

var pose: Pose = Pose.STANDING

var _rig: Node3D
var _torso: MeshInstance3D
var _head_pivot: Node3D
var _legs: Array[Node3D] = []
var _head_base: Vector3 = Vector3.ZERO   # pose head rotation the idle adds to
var _phase: float = 0.0
var _turn_timer: float = 0.0
var _turn_yaw: float = 0.0
var _turn_target: float = 0.0


## Picks the resting pose. Safe to call before or after the node enters the
## tree; placement code calls it right after instancing.
func configure(p_pose: Pose) -> void:
	pose = p_pose
	if _rig != null:
		_apply_pose()


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_phase = rng.randf() * TAU
	_turn_timer = rng.randf_range(2.0, 7.0)

	_rig = Node3D.new()
	add_child(_rig)

	_torso = MeshInstance3D.new()
	_torso.mesh = _get_torso_mesh()
	_torso.material_override = _get_fur_material()
	_rig.add_child(_torso)

	for i: int in 4:
		var leg := MeshInstance3D.new()
		leg.mesh = _get_hind_leg_mesh() if i >= 2 else _get_front_leg_mesh()
		leg.material_override = _get_fur_material()
		_rig.add_child(leg)
		_legs.append(leg)

	_head_pivot = Node3D.new()
	_head_pivot.position = HEAD_JOINT
	_rig.add_child(_head_pivot)
	var head := MeshInstance3D.new()
	head.mesh = _get_head_mesh()
	head.material_override = _get_fur_material()
	_head_pivot.add_child(head)
	# Eyes + nose share one dark glossy surface; the catchlights are two tiny
	# emissive spheres, the same trick the seal and the racers use to keep an
	# eye from reading as a flat black dot.
	var face := MeshInstance3D.new()
	face.mesh = _get_face_mesh()
	face.material_override = _get_face_material()
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head_pivot.add_child(face)
	for side: float in [-1.0, 1.0]:
		var gleam := MeshInstance3D.new()
		gleam.mesh = _get_gleam_mesh()
		gleam.material_override = _get_gleam_material()
		gleam.position = Vector3(side * 0.116, 0.058, -0.240)
		gleam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_head_pivot.add_child(gleam)

	_apply_pose()
	set_process(not GameConfig.is_headless() and not UITheme.reduced_motion())


## --- Poses ------------------------------------------------------------------

func _apply_pose() -> void:
	match pose:
		Pose.SITTING:
			_pose_sitting()
		Pose.LYING:
			_pose_lying()
		_:
			_pose_standing()


## Rotation about an arbitrary pivot, so the body swings around a contact point
## (the shoulder line when it sits up, its own centre when it settles) instead
## of around the ground origin.
static func _pivoted(basis: Basis, pivot: Vector3, offset: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(basis, pivot - basis * pivot + offset)


## side: -1 left, +1 right. Bears are pigeon-toed, so the paws toe inward.
func _place_leg(index: int, socket: Vector3, side: float, rot: Vector3) -> void:
	_legs[index].position = Vector3(socket.x * side, socket.y, socket.z)
	_legs[index].rotation = Vector3(rot.x, rot.y * side, rot.z * side)


func _pose_standing() -> void:
	_rig.transform = Transform3D.IDENTITY
	# A hair of stagger front to back: a bear stood perfectly square reads as a
	# toy, and the paws stay on the ground either way (a 6 degree swing off a
	# 1.03 m limb lifts the sole by 6 mm).
	_place_leg(0, FRONT_SOCKET, -1.0, Vector3(deg_to_rad(-5.0), deg_to_rad(9.0), 0.0))
	_place_leg(1, FRONT_SOCKET, 1.0, Vector3(deg_to_rad(3.0), deg_to_rad(9.0), 0.0))
	_place_leg(2, HIND_SOCKET, -1.0, Vector3(deg_to_rad(4.0), deg_to_rad(-6.0), deg_to_rad(2.0)))
	_place_leg(3, HIND_SOCKET, 1.0, Vector3(deg_to_rad(-3.0), deg_to_rad(-6.0), deg_to_rad(2.0)))
	_head_base = Vector3(deg_to_rad(-7.0), 0.0, 0.0)
	_head_pivot.rotation = _head_base


## Sits up on the rump with the forelegs propped straight, the way a bear
## surveys open ice. The body pitches around the SHOULDER line, which is what
## keeps the (rigid) forelegs standing on the ground while the hindquarters
## drop; the hind legs then swing forward to lie under the belly.
func _pose_sitting() -> void:
	var pitch := deg_to_rad(33.0)
	_rig.transform = _pivoted(Basis(Vector3.RIGHT, pitch),
		Vector3(0.0, FRONT_SOCKET.y, FRONT_SOCKET.z), Vector3(0.0, 0.06, 0.0))
	_place_leg(0, FRONT_SOCKET, -1.0, Vector3(-pitch + deg_to_rad(3.0), deg_to_rad(11.0), deg_to_rad(-3.0)))
	_place_leg(1, FRONT_SOCKET, 1.0, Vector3(-pitch - deg_to_rad(2.0), deg_to_rad(11.0), deg_to_rad(-3.0)))
	_place_leg(2, HIND_SOCKET, -1.0, Vector3(deg_to_rad(40.0), deg_to_rad(-4.0), deg_to_rad(18.0)))
	_place_leg(3, HIND_SOCKET, 1.0, Vector3(deg_to_rad(44.0), deg_to_rad(-4.0), deg_to_rad(15.0)))
	# The rig carries +33 degrees of pitch, so the head has to give most of it
	# back or the muzzle points at the sky; the remainder reads as looking up.
	_head_base = Vector3(-pitch + deg_to_rad(9.0), deg_to_rad(-8.0), 0.0)
	_head_pivot.rotation = _head_base


## Sprawled belly-down and asleep: body settled onto the snow, forelegs pushed
## out ahead, hind legs trailing back and splayed frog-wise, head laid low.
func _pose_lying() -> void:
	_rig.transform = _pivoted(
		Basis.from_euler(Vector3(deg_to_rad(-2.0), 0.0, deg_to_rad(5.0))),
		Vector3(0.0, 1.0, 0.0), Vector3(0.0, -0.55, 0.0))
	_place_leg(0, FRONT_SOCKET, -1.0, Vector3(deg_to_rad(63.0), deg_to_rad(16.0), deg_to_rad(-22.0)))
	_place_leg(1, FRONT_SOCKET, 1.0, Vector3(deg_to_rad(58.0), deg_to_rad(16.0), deg_to_rad(-26.0)))
	_place_leg(2, HIND_SOCKET, -1.0, Vector3(deg_to_rad(-56.0), deg_to_rad(-10.0), deg_to_rad(-34.0)))
	_place_leg(3, HIND_SOCKET, 1.0, Vector3(deg_to_rad(-60.0), deg_to_rad(-10.0), deg_to_rad(-30.0)))
	_head_base = Vector3(deg_to_rad(-13.0), deg_to_rad(22.0), deg_to_rad(-6.0))
	_head_pivot.rotation = _head_base


## --- Idle -------------------------------------------------------------------
## Slow breath through the ribcage, a lazy head sway, and an occasional look
## around. Six sines and a lerp per frame, on three node transforms.

func _process(delta: float) -> void:
	_phase += delta
	var breath := sin(_phase * 0.62)
	var deep := 1.0 if pose == Pose.LYING else 0.72  # a sleeping bear heaves
	_torso.scale = Vector3(
		1.0 + breath * 0.012 * deep,
		1.0 + breath * 0.016 * deep,
		1.0 + breath * 0.004 * deep)

	_turn_timer -= delta
	if _turn_timer <= 0.0:
		_turn_timer = randf_range(4.0, 9.5)
		_turn_target = randf_range(-0.42, 0.42)
	_turn_yaw = lerpf(_turn_yaw, _turn_target, clampf(delta * 1.6, 0.0, 1.0))

	_head_pivot.rotation = _head_base + Vector3(
		sin(_phase * 0.47 + 1.1) * 0.035 + breath * 0.012,
		_turn_yaw + sin(_phase * 0.31) * 0.045,
		sin(_phase * 0.53) * 0.03)


## --- Procedural mesh construction -------------------------------------------
## Every part is a lathe built in a canonical frame (rings advance +Z, ring 0
## starts at the top and sweeps toward +X) and then transformed into place.
## Stations are [z, centre_y, half_width, radius_up, radius_down]; cross
## sections are eggs rather than circles, which is what separates a deep-chested
## animal from a tube.

static func _cat(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return (p1 * 2.0 + (p2 - p0) * t
		+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
		+ (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3) * 0.5


static func _station(z: float, cy: float, r_side: float, r_up: float, r_down: float) -> PackedFloat32Array:
	return PackedFloat32Array([z, cy, r_side, r_up, r_down])


## Smooth Catmull-Rom pass over the stations, component-wise.
static func _sample_stations(ctrl: Array, subdiv: int) -> Array:
	var out: Array = []
	for i: int in ctrl.size() - 1:
		var p0: PackedFloat32Array = ctrl[maxi(i - 1, 0)]
		var p1: PackedFloat32Array = ctrl[i]
		var p2: PackedFloat32Array = ctrl[i + 1]
		var p3: PackedFloat32Array = ctrl[mini(i + 2, ctrl.size() - 1)]
		for s: int in subdiv:
			var t := float(s) / float(subdiv)
			var row := PackedFloat32Array()
			for c: int in 5:
				row.append(_cat(p0[c], p1[c], p2[c], p3[c], t))
			out.append(row)
	out.append(ctrl[ctrl.size() - 1])
	return out


## Stitches equal-length vertex rings into a smooth tube. Same winding as
## PenguinVisual._grid_mesh and HazardSeal._stitch: rings must advance along
## cross(sin axis, cos axis), which for the canonical frame is +Z.
static func _stitch(st: SurfaceTool, rings: Array[PackedVector3Array], colors: Array[PackedColorArray]) -> void:
	var n := rings[0].size()
	for j: int in rings.size() - 1:
		var ra := rings[j]
		var rb := rings[j + 1]
		var ca := colors[j]
		var cb := colors[j + 1]
		for i: int in n:
			var i2 := (i + 1) % n
			st.set_color(ca[i]); st.add_vertex(ra[i])
			st.set_color(ca[i2]); st.add_vertex(ra[i2])
			st.set_color(cb[i2]); st.add_vertex(rb[i2])
			st.set_color(ca[i]); st.add_vertex(ra[i])
			st.set_color(cb[i2]); st.add_vertex(rb[i2])
			st.set_color(cb[i]); st.add_vertex(rb[i])


## Builds one lathe into `st`. `color_fn` receives (world_pos, up, t) where up
## is cos(theta) over -1..1 in the CANONICAL frame (+1 = the ring's top) and t
## is the 0..1 position along the lathe.
static func _lathe(st: SurfaceTool, ctrl: Array, subdiv: int, segs: int,
		xform: Transform3D, color_fn: Callable) -> void:
	var prof := _sample_stations(ctrl, subdiv)
	var rings: Array[PackedVector3Array] = []
	var colors: Array[PackedColorArray] = []
	var last := prof.size() - 1
	for k: int in prof.size():
		var s: PackedFloat32Array = prof[k]
		var t := float(k) / float(last)
		var ring := PackedVector3Array()
		var col := PackedColorArray()
		# Egg section: the vertical radius eases from r_up at the crown to
		# r_down at the keel with no crease at the sides.
		var r_mean := (s[3] + s[4]) * 0.5
		var r_bias := (s[3] - s[4]) * 0.5
		for i: int in segs:
			var ang := TAU * float(i) / float(segs)
			var c := cos(ang)
			var local := Vector3(
				sin(ang) * maxf(s[2], 0.004),
				s[1] + c * maxf(r_mean + r_bias * c, 0.004),
				s[0])
			var pos := xform * local
			ring.append(pos)
			col.append(color_fn.call(pos, c, t) as Color)
		rings.append(ring)
		colors.append(col)
	_stitch(st, rings, colors)


## A squashed ball (toe domes, the nose button, eyes) as a five-station lathe.
static func _blob(st: SurfaceTool, centre: Vector3, radii: Vector3, segs: int, color: Color) -> void:
	var ctrl: Array = [
		_station(-radii.z, 0.0, 0.02, 0.02, 0.02),
		_station(-radii.z * 0.72, 0.0, radii.x * 0.70, radii.y * 0.70, radii.y * 0.70),
		_station(0.0, 0.0, radii.x, radii.y, radii.y),
		_station(radii.z * 0.72, 0.0, radii.x * 0.70, radii.y * 0.70, radii.y * 0.70),
		_station(radii.z, 0.0, 0.02, 0.02, 0.02),
	]
	_lathe(st, ctrl, 3, segs, Transform3D(Basis.IDENTITY, centre),
		func(_p: Vector3, _u: float, _t: float) -> Color: return color)


static func _make_noise(noise_seed: int, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 1.0
	n.fractal_octaves = octaves
	return n


## Coat colour. `up` is -1 (underside) .. +1 (sunlit top). `warm` pushes the
## yellowed guard-hair tone, `damp` the dark wet tone of the lower legs.
static func _fur(pos: Vector3, up: float, na: FastNoiseLite, nb: FastNoiseLite,
		warm: float = 0.0, damp: float = 0.0) -> Color:
	var u := clampf(up * 0.5 + 0.5, 0.0, 1.0)
	var col := FUR_LOW.lerp(FUR_MID, smoothstep(0.06, 0.56, u))
	col = col.lerp(FUR_TOP, smoothstep(0.54, 1.0, u) * 0.9)
	# Guard-hair clumping: broad soft patches, strongest down the flanks where
	# real bears yellow the most, plus finer pale flecks catching the sun.
	var clump := smoothstep(-0.14, 0.36, na.get_noise_3d(pos.x * 2.6, pos.y * 2.1, pos.z * 1.4))
	col = col.lerp(FUR_BUFF, clampf(clump * (0.30 - 0.12 * u) + warm * 0.30, 0.0, 1.0))
	var fleck := smoothstep(0.22, 0.62, nb.get_noise_3d(pos.x * 5.4, pos.y * 4.4, pos.z * 3.2))
	col = col.lerp(FUR_TOP, fleck * 0.20 * u)
	if damp > 0.0:
		col = col.lerp(FUR_DAMP, damp)
	var g := 1.0 + sin(pos.x * 83.0 + pos.y * 57.0 + pos.z * 67.0) * 0.014
	return Color(clampf(col.r * g, 0.0, 1.0), clampf(col.g * g, 0.0, 1.0), clampf(col.b * g, 0.0, 1.0), 1.0)


## Neck + torso + rump + tail stub as one continuous lathe. Withers ride at
## 1.31 m, the loin dips to 1.27, the rump comes back up to 1.30: that back
## line, not the leg count, is what makes a shape read as a bear.
static func _get_torso_mesh() -> ArrayMesh:
	if _torso_mesh != null:
		return _torso_mesh
	var na := _make_noise(23, 3)
	var nb := _make_noise(57, 2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var ctrl: Array = [
		_station(-0.86, 1.140, 0.090, 0.085, 0.085),  # throat cap (inside the head)
		_station(-0.80, 1.135, 0.155, 0.145, 0.155),  # upper neck
		_station(-0.70, 1.115, 0.200, 0.185, 0.200),  # neck, thick as the skull
		_station(-0.60, 1.075, 0.245, 0.225, 0.260),  # neck into shoulders
		_station(-0.46, 1.015, 0.300, 0.290, 0.415),  # chest, keel below the elbow
		_station(-0.30, 0.985, 0.335, 0.350, 0.415),  # withers hump, 1.335
		_station(-0.10, 0.975, 0.345, 0.305, 0.405),  # ribs, widest
		_station(0.12, 0.972, 0.335, 0.283, 0.372),   # loin dip, 1.255
		_station(0.34, 0.985, 0.345, 0.295, 0.355),   # loin, belly tucking up
		_station(0.56, 1.000, 0.365, 0.310, 0.345),   # hips, 1.31
		_station(0.76, 1.005, 0.350, 0.300, 0.330),   # rump
		_station(0.92, 1.010, 0.335, 0.290, 0.305),   # a bear's rump is BLUNT,
		_station(1.04, 1.015, 0.280, 0.250, 0.255),   # never tapered to a cone
		_station(1.12, 1.020, 0.175, 0.160, 0.160),
		_station(1.17, 1.020, 0.075, 0.070, 0.070),   # tail stub
		_station(1.20, 1.015, 0.025, 0.025, 0.025),
	]
	_lathe(st, ctrl, 3, BODY_SEGS, Transform3D.IDENTITY,
		func(p: Vector3, u: float, t: float) -> Color:
			# Flanks yellow more than the spine; the throat stays pale.
			var warm := smoothstep(0.30, 0.75, t) * 0.22 + (1.0 - absf(u)) * 0.10
			return _fur(p, u, na, nb, warm))
	st.generate_normals()
	st.index()
	_torso_mesh = st.commit()
	return _torso_mesh


## Foreleg: shoulder mass -> straight column -> broad paw. Built in leg space
## with the origin at the shoulder socket and the limb running down -Y, so the
## posing code only ever sets a rotation.
static func _get_front_leg_mesh() -> ArrayMesh:
	if _front_leg_mesh != null:
		return _front_leg_mesh
	_front_leg_mesh = _build_leg([
		# [depth below socket, fore/aft centre, half width, radius aft, radius fore]
		_station(0.16, 0.0, 0.060, 0.060, 0.060),      # cap, buried in the torso
		_station(0.06, -0.010, 0.160, 0.175, 0.175),
		_station(-0.04, -0.010, 0.182, 0.196, 0.198),  # shoulder, bulges past the flank
		_station(-0.18, -0.010, 0.175, 0.190, 0.190),
		_station(-0.32, -0.015, 0.158, 0.168, 0.172),
		_station(-0.46, -0.020, 0.148, 0.156, 0.162),  # elbow clears the belly line
		_station(-0.62, -0.025, 0.140, 0.147, 0.155),  # a bear's foreleg is a
		_station(-0.78, -0.030, 0.136, 0.142, 0.155),  # column, never waisted
		_station(-0.88, -0.042, 0.144, 0.146, 0.176),
		_station(-0.97, -0.055, 0.158, 0.152, 0.212),  # paw
		_station(-1.02, -0.055, 0.152, 0.146, 0.202),
		_station(-1.04, -0.055, 0.030, 0.030, 0.030),  # sole
	], 0.27)
	return _front_leg_mesh


## Hind leg: heavy haunch, stifle, a hock kicked back, then the same broad paw.
static func _get_hind_leg_mesh() -> ArrayMesh:
	if _hind_leg_mesh != null:
		return _hind_leg_mesh
	_hind_leg_mesh = _build_leg([
		_station(0.16, 0.0, 0.065, 0.065, 0.065),
		_station(0.05, 0.012, 0.185, 0.205, 0.200),
		_station(-0.06, 0.016, 0.205, 0.236, 0.228),   # haunch, widest of the animal
		_station(-0.22, 0.016, 0.205, 0.235, 0.225),
		_station(-0.38, 0.006, 0.180, 0.200, 0.190),   # stifle
		_station(-0.54, 0.022, 0.152, 0.170, 0.155),   # hock, set back
		_station(-0.70, 0.012, 0.140, 0.150, 0.148),
		_station(-0.84, -0.015, 0.144, 0.146, 0.170),
		_station(-0.95, -0.040, 0.158, 0.152, 0.212),
		_station(-1.02, -0.045, 0.152, 0.146, 0.202),
		_station(-1.04, -0.045, 0.030, 0.030, 0.030),
	], 0.26)
	return _hind_leg_mesh


## Shared limb builder. `toe_z` is where the five toe domes sit ahead of the
## paw centre. Rings advance down -Y, so the canonical +Z axis is rotated onto
## -Y and the canonical "up" becomes the AFT side of the limb.
static func _build_leg(ctrl: Array, toe_z: float) -> ArrayMesh:
	var na := _make_noise(91, 3)
	var nb := _make_noise(113, 2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	# This basis maps canonical (x, y, z) -> leg (x, z, -y): the lathe axis
	# becomes the limb's vertical, and the canonical "up" becomes its FORE
	# side. Stations are authored top-down, so they are reversed here to keep
	# canonical z increasing (which is what makes the winding face outward),
	# the fore/aft centre is negated into canonical y, and the fore/aft radii
	# swap into up/down.
	var down := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3.ZERO)
	var flipped: Array = []
	for i: int in ctrl.size():
		var s: PackedFloat32Array = ctrl[ctrl.size() - 1 - i]
		flipped.append(_station(s[0], -s[1], s[2], s[4], s[3]))
	_lathe(st, flipped, 3, LEG_SEGS, down,
		func(p: Vector3, _u: float, _t: float) -> Color:
			# Legs read by height, not by ring angle: shoulder tops catch the
			# sun, the trousers go warm, the paws are damp and dark.
			var h := clampf((p.y + 1.04) / 1.18, 0.0, 1.0)
			var damp := smoothstep(0.16, 0.0, h) * 0.55
			return _fur(p, h * 1.7 - 0.75, na, nb, smoothstep(0.55, 0.12, h) * 0.35, damp))
	# Five toe domes across the front of the paw, with a small dark claw ahead
	# of each. A bear paw is the tell at any distance, so it is not a stub.
	var toe_y := -0.955
	for k: int in 5:
		var x := -0.108 + 0.054 * float(k)
		var spread := 1.0 - absf(float(k) - 2.0) * 0.08
		_blob(st, Vector3(x, toe_y, -toe_z - 0.035), Vector3(0.046, 0.044, 0.060) * spread,
			10, _fur(Vector3(x, toe_y, -toe_z), -0.30, na, nb, 0.30, 0.30))
		# Claws: mostly buried in toe fur, just the dark hooks showing.
		_blob(st, Vector3(x * 1.03, toe_y - 0.036, -toe_z - 0.082),
			Vector3(0.014, 0.012, 0.028) * spread, 8, CLAW_DARK)
	st.generate_normals()
	st.index()
	return st.commit()


## Head: braincase running out into a long dished muzzle, with small rounded
## ears set well back on the skull. Head space has its origin at the atlas
## joint and the muzzle running out along -Z, so the idle sway pivots where a
## real neck would.
static func _get_head_mesh() -> ArrayMesh:
	if _head_mesh != null:
		return _head_mesh
	var na := _make_noise(41, 3)
	var nb := _make_noise(67, 2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var ctrl: Array = [
		_station(-0.525, -0.098, 0.032, 0.028, 0.028),  # blunt face, not a point
		_station(-0.505, -0.096, 0.082, 0.068, 0.076),  # a bear muzzle is BLUNT:
		_station(-0.460, -0.090, 0.088, 0.072, 0.082),  # it barely tapers
		_station(-0.400, -0.080, 0.094, 0.078, 0.088),
		_station(-0.340, -0.060, 0.101, 0.084, 0.094),  # the dish: this top line
		_station(-0.275, -0.044, 0.114, 0.092, 0.104),  # runs concave to the stop
		_station(-0.205, -0.020, 0.140, 0.118, 0.122),  # stop, brow over the eye
		_station(-0.135, 0.000, 0.160, 0.144, 0.138),   # braincase
		_station(-0.055, -0.004, 0.163, 0.146, 0.142),  # occiput and jowl
		_station(0.020, -0.016, 0.145, 0.130, 0.132),
		_station(0.100, -0.026, 0.112, 0.102, 0.104),   # swallowed by the neck
		_station(0.170, -0.030, 0.035, 0.032, 0.032),
	]
	_lathe(st, ctrl, 3, HEAD_SEGS, Transform3D.IDENTITY,
		func(p: Vector3, u: float, _t: float) -> Color:
			return _head_fur(p, u, na, nb))
	# Ears: small rounded flaps, set well back and canted out and aft. Tiny
	# ears are one of the few reliable polar-bear-versus-brown-bear reads.
	for side: float in [-1.0, 1.0]:
		# Canonical +Z (the lathe axis) ends up pointing up, a little outboard
		# and a little aft, which is where a bear carries its ears.
		var ear_basis := Basis(Vector3.UP, side * deg_to_rad(26.0)) \
			* Basis(Vector3.RIGHT, deg_to_rad(-62.0))
		# The base station is wide and starts BELOW the skull surface, so the
		# ear grows out of the head instead of sitting on it like a bead.
		_lathe(st, [
			_station(-0.060, 0.0, 0.048, 0.048, 0.048),
			_station(-0.010, 0.002, 0.055, 0.058, 0.052),
			_station(0.028, 0.004, 0.058, 0.062, 0.054),
			_station(0.058, 0.002, 0.046, 0.050, 0.042),
			_station(0.070, 0.0, 0.014, 0.014, 0.014),
		], 3, 14, Transform3D(ear_basis, Vector3(side * 0.092, 0.104, -0.082)),
			func(p: Vector3, u: float, t: float) -> Color:
				# The inner face of the ear is shaded and a touch ruddier.
				return _fur(p, u * 0.6 + 0.2, na, nb, 0.25 + t * 0.25, t * 0.18))
	st.generate_normals()
	st.index()
	_head_mesh = st.commit()
	return _head_mesh


## Face colour: the pale muzzle mask, a black lip line down the lower jaw and
## darkened eye surrounds, over the standard coat.
static func _head_fur(pos: Vector3, up: float, na: FastNoiseLite, nb: FastNoiseLite) -> Color:
	var muzzle := smoothstep(-0.16, -0.38, pos.z)
	var col := _fur(pos, up, na, nb, muzzle * 0.30)
	# Lip line: a thin dark band low on the sides of the muzzle.
	var u := up * 0.5 + 0.5
	var lip := muzzle * (1.0 - smoothstep(0.10, 0.34, absf(u - 0.22)) )
	col = col.lerp(LIP_DARK, clampf(lip, 0.0, 1.0) * 0.55)
	# Eye surrounds.
	for side: float in [-1.0, 1.0]:
		var d := pos.distance_to(Vector3(side * 0.108, 0.045, -0.225))
		if d < 0.090:
			col = col.lerp(LIP_DARK, (1.0 - d / 0.090) * 0.50)
	return col


## Eyes and nose button in one dark glossy surface, in head space.
static func _get_face_mesh() -> ArrayMesh:
	if _face_mesh != null:
		return _face_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for side: float in [-1.0, 1.0]:
		_blob(st, Vector3(side * 0.108, 0.046, -0.228), Vector3(0.028, 0.028, 0.028), 14,
			Color(0.04, 0.035, 0.034))
	# The nose is a big black button — the single most recognisable feature on
	# a white animal, so it is deliberately oversized rather than a dot.
	_blob(st, Vector3(0.0, -0.103, -0.502), Vector3(0.064, 0.050, 0.042), 16, NOSE_DARK)
	st.generate_normals()
	st.index()
	_face_mesh = st.commit()
	return _face_mesh


static func _get_gleam_mesh() -> SphereMesh:
	if _gleam_mesh == null:
		_gleam_mesh = SphereMesh.new()
		_gleam_mesh.radius = 0.007
		_gleam_mesh.height = 0.014
		_gleam_mesh.radial_segments = 8
		_gleam_mesh.rings = 4
	return _gleam_mesh


static func _get_fur_material() -> ShaderMaterial:
	if _fur_mat == null:
		if _fur_shader == null:
			_fur_shader = Shader.new()
			_fur_shader.code = FUR_SHADER_CODE
		_fur_mat = ShaderMaterial.new()
		_fur_mat.shader = _fur_shader
		_fur_mat.set_shader_parameter("rim_strength", 0.14)
	return _fur_mat


static func _get_face_material() -> StandardMaterial3D:
	if _face_mat == null:
		_face_mat = StandardMaterial3D.new()
		_face_mat.vertex_color_use_as_albedo = true
		_face_mat.albedo_color = Color(1.0, 1.0, 1.0)
		_face_mat.roughness = 0.16
		_face_mat.metallic = 0.0
		_face_mat.metallic_specular = 0.6
	return _face_mat


static func _get_gleam_material() -> StandardMaterial3D:
	if _gleam_mat == null:
		_gleam_mat = StandardMaterial3D.new()
		_gleam_mat.albedo_color = Color(1.0, 1.0, 1.0)
		_gleam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _gleam_mat
