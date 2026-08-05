class_name PenguinVisual
extends Node3D
## Procedural penguin model built from primitives, with cosmetic attachment
## points and code-driven animation (waddle, slide, swim, stun, celebrate).
## No imported assets: everything is meshes + StandardMaterial3D.

enum Pose { RUN, SLIDE, AIR, SWIM, STUN, IDLE, CELEBRATE, DEFEAT }

const BROW_REST: float = -0.1745  # ~-10 deg: relaxed determined slope

static var _material_cache: Dictionary = {}

var pose: Pose = Pose.IDLE
var anim_speed: float = 1.0

var _root: Node3D  # animated body root (bobs / tilts)
var _body: MeshInstance3D
var _belly: MeshInstance3D
var _flipper_l: Node3D
var _flipper_r: Node3D
var _foot_l: MeshInstance3D
var _foot_r: MeshInstance3D
var _head_anchor: Node3D
var _beak: MeshInstance3D
var _beak_lower: MeshInstance3D
var _eye_l: Node3D
var _eye_r: Node3D
var _brow_l: MeshInstance3D
var _brow_r: MeshInstance3D
var _hat_anchor: Node3D
var _neck_anchor: Node3D
var _face_anchor: Node3D
var _time: float = 0.0
var _pose_blend: float = 0.0
var _current_tilt: Vector3 = Vector3.ZERO
var _squash: float = 1.0
var _squash_target: float = 1.0


static func get_material(color: Color, metallic: float = 0.0, roughness: float = 0.75, emissive: bool = false) -> StandardMaterial3D:
	var key := "%s_%s_%s_%s" % [color.to_html(), metallic, roughness, emissive]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.8
	_material_cache[key] = mat
	return mat


## Body/feather material: soft rim sheen so the silhouette reads against snow.
## Rim lighting on StandardMaterial3D is cheap and supported on Forward Mobile.
static func get_body_material(color: Color, roughness: float = 0.62, rim: float = 0.28) -> StandardMaterial3D:
	var key := "body_%s_%s_%s" % [color.to_html(), roughness, rim]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.0
	mat.roughness = roughness
	mat.rim_enabled = true
	mat.rim = rim
	mat.rim_tint = 0.55
	_material_cache[key] = mat
	return mat


## Nudges saturation/value up so racer colors pop against the pale course.
static func _saturate(color: Color) -> Color:
	return Color.from_hsv(
		color.h,
		clampf(color.s * 1.28, 0.0, 0.95),
		clampf(color.v * 1.05, 0.0, 1.0),
		color.a
	)


func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, mat: Material = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat if mat != null else get_material(color)
	instance.position = pos
	instance.rotation = rot
	instance.scale = scl
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance


## config keys: body_color, belly_color, accent_color (optional),
## crest_color (optional), hat, scarf, goggles (cosmetic ids or "").
func setup(config: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	var body_color := _saturate(config.get("body_color", Color(0.13, 0.16, 0.22)) as Color)
	var belly_color := _saturate(config.get("belly_color", Color(0.95, 0.94, 0.9)) as Color)
	var beak_color := Color(0.99, 0.62, 0.13)
	var flipper_color := body_color  # exact body match so flippers read as attached
	var brow_color := body_color.darkened(0.28)

	_root = Node3D.new()
	add_child(_root)

	# Body: rounded egg.
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.34
	body_mesh.height = 0.92
	body_mesh.radial_segments = 24
	body_mesh.rings = 16
	_body = _mesh(_root, body_mesh, body_color, Vector3(0, 0.46, 0), Vector3.ZERO, Vector3.ONE, get_body_material(body_color))

	# Belly patch: flattened lighter sphere set into the front as a smooth inset.
	var belly_mesh := SphereMesh.new()
	belly_mesh.radius = 0.30
	belly_mesh.height = 0.78
	belly_mesh.radial_segments = 20
	belly_mesh.rings = 12
	_belly = _mesh(_root, belly_mesh, belly_color, Vector3(0, 0.43, -0.155), Vector3.ZERO, Vector3(0.82, 0.9, 0.68), get_body_material(belly_color, 0.78, 0.18))

	# Head anchor sits atop the egg (the egg itself is the head silhouette).
	_head_anchor = Node3D.new()
	_head_anchor.position = Vector3(0, 0.78, 0)
	_root.add_child(_head_anchor)

	_face_anchor = Node3D.new()
	_face_anchor.position = Vector3(0, 0, -0.24)
	_head_anchor.add_child(_face_anchor)

	# Eyes: glossy whites, deep pupils, emissive catchlight sphere.
	_eye_l = Node3D.new()
	_eye_l.position = Vector3(-0.11, 0.02, -0.03)
	_face_anchor.add_child(_eye_l)
	_eye_r = Node3D.new()
	_eye_r.position = Vector3(0.11, 0.02, -0.03)
	_face_anchor.add_child(_eye_r)
	var eye_white := SphereMesh.new()
	eye_white.radius = 0.056
	eye_white.height = 0.112
	eye_white.radial_segments = 12
	eye_white.rings = 8
	var pupil := SphereMesh.new()
	pupil.radius = 0.027
	pupil.height = 0.054
	pupil.radial_segments = 10
	pupil.rings = 6
	var catchlight := SphereMesh.new()
	catchlight.radius = 0.011
	catchlight.height = 0.022
	catchlight.radial_segments = 8
	catchlight.rings = 4
	var white_mat := get_material(Color(0.99, 0.99, 0.99), 0.0, 0.12)
	var pupil_mat := get_material(Color(0.05, 0.06, 0.09), 0.0, 0.08)
	var gleam_mat := get_material(Color(1.0, 1.0, 1.0), 0.0, 0.2, true)
	for eye: Node3D in [_eye_l, _eye_r]:
		_mesh(eye, eye_white, Color.WHITE, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, white_mat)
		_mesh(eye, pupil, Color.BLACK, Vector3(0, 0.004, -0.038), Vector3.ZERO, Vector3.ONE, pupil_mat)
		_mesh(eye, catchlight, Color.WHITE, Vector3(0.012, 0.018, -0.055), Vector3.ZERO, Vector3.ONE, gleam_mat)

	# Brow ridges: soft ridges over each eye, tilted for expression in tick().
	var brow_mesh := SphereMesh.new()
	brow_mesh.radius = 0.055
	brow_mesh.height = 0.11
	brow_mesh.radial_segments = 10
	brow_mesh.rings = 6
	var brow_mat := get_body_material(brow_color, 0.7, 0.2)
	_brow_l = _mesh(_face_anchor, brow_mesh, brow_color, Vector3(-0.11, 0.098, -0.02), Vector3(0, 0, BROW_REST), Vector3(1.15, 0.28, 0.55), brow_mat)
	_brow_r = _mesh(_face_anchor, brow_mesh, brow_color, Vector3(0.11, 0.098, -0.02), Vector3(0, 0, -BROW_REST), Vector3(1.15, 0.28, 0.55), brow_mat)

	# Beak: two flattened cones — wide upper bill over a shorter lower mandible.
	var beak_mat := get_body_material(beak_color, 0.5, 0.2)
	var beak_upper_mesh := CylinderMesh.new()
	beak_upper_mesh.top_radius = 0.0
	beak_upper_mesh.bottom_radius = 0.06
	beak_upper_mesh.height = 0.17
	beak_upper_mesh.radial_segments = 10
	_beak = _mesh(_face_anchor, beak_upper_mesh, beak_color, Vector3(0, -0.048, -0.095), Vector3(deg_to_rad(-92), 0, 0), Vector3(1.15, 1.0, 0.68), beak_mat)
	var beak_lower_mesh := CylinderMesh.new()
	beak_lower_mesh.top_radius = 0.0
	beak_lower_mesh.bottom_radius = 0.046
	beak_lower_mesh.height = 0.12
	beak_lower_mesh.radial_segments = 8
	var beak_lower_mat := get_body_material(beak_color.darkened(0.18), 0.55, 0.15)
	_beak_lower = _mesh(_face_anchor, beak_lower_mesh, beak_color, Vector3(0, -0.085, -0.072), Vector3(deg_to_rad(-97), 0, 0), Vector3(1.0, 1.0, 0.55), beak_lower_mat)

	# Flippers with shoulder pivots, angled slightly outward.
	_flipper_l = _make_flipper(flipper_color, -1.0)
	_flipper_r = _make_flipper(flipper_color, 1.0)

	# Feet: rounded flat paddles toed slightly outward; step animation in tick().
	var foot_mesh := SphereMesh.new()
	foot_mesh.radius = 0.1
	foot_mesh.height = 0.2
	foot_mesh.radial_segments = 14
	foot_mesh.rings = 8
	var foot_mat := get_body_material(beak_color.darkened(0.08), 0.6, 0.15)
	_foot_l = _mesh(_root, foot_mesh, beak_color, Vector3(-0.13, 0.035, -0.04), Vector3(0, deg_to_rad(10), 0), Vector3(0.85, 0.32, 1.5), foot_mat)
	_foot_r = _mesh(_root, foot_mesh, beak_color, Vector3(0.13, 0.035, -0.04), Vector3(0, deg_to_rad(-10), 0), Vector3(0.85, 0.32, 1.5), foot_mat)

	# Rounded tail nub tucked against the lower back, angled slightly up.
	# Root is buried in the body; only a short nub protrudes past the surface.
	var tail_mesh := SphereMesh.new()
	tail_mesh.radius = 0.12
	tail_mesh.height = 0.24
	tail_mesh.radial_segments = 12
	tail_mesh.rings = 8
	_mesh(_root, tail_mesh, body_color, Vector3(0, 0.32, 0.24), Vector3(deg_to_rad(-20), 0, 0), Vector3(1.0, 0.65, 1.05), get_body_material(body_color))

	# Rockhopper crest.
	if config.has("crest_color"):
		var crest_color := _saturate(config["crest_color"] as Color)
		var crest_mat := get_body_material(crest_color, 0.6, 0.25)
		var crest_mesh := CylinderMesh.new()
		crest_mesh.top_radius = 0.0
		crest_mesh.bottom_radius = 0.035
		crest_mesh.height = 0.22
		crest_mesh.radial_segments = 8
		_mesh(_head_anchor, crest_mesh, crest_color, Vector3(-0.14, 0.13, 0), Vector3(deg_to_rad(-8), 0, deg_to_rad(38)), Vector3.ONE, crest_mat)
		_mesh(_head_anchor, crest_mesh, crest_color, Vector3(0.14, 0.13, 0), Vector3(deg_to_rad(-8), 0, deg_to_rad(-38)), Vector3.ONE, crest_mat)

	_hat_anchor = Node3D.new()
	_hat_anchor.position = Vector3(0, 0.18, 0)
	_head_anchor.add_child(_hat_anchor)
	_neck_anchor = Node3D.new()
	_neck_anchor.position = Vector3(0, 0.58, 0)
	_root.add_child(_neck_anchor)

	_apply_cosmetic(String(config.get("hat", "")))
	_apply_cosmetic(String(config.get("scarf", "")))
	_apply_cosmetic(String(config.get("goggles", "")))


func _make_flipper(color: Color, side: float) -> Node3D:
	# Pivot sits INSIDE the body (egg horizontal radius ~0.32 at shoulder
	# height) so the flipper root is always embedded, in every pose. The blade
	# overlaps the body ~30% of its width at the widest ring, its shoulder end
	# is fully buried, and only the tip flares slightly outward.
	var pivot := Node3D.new()
	pivot.position = Vector3(0.26 * side, 0.62, 0)
	_root.add_child(pivot)
	# Same cached material as the body (identical color/roughness/rim) so the
	# flipper reads as one continuous surface with the torso.
	var mat := get_body_material(color)
	# Shoulder mound: mostly sunk into the body, bridges torso -> blade so no
	# seam shows even at extreme swing angles (celebrate/air).
	var shoulder_mesh := SphereMesh.new()
	shoulder_mesh.radius = 0.085
	shoulder_mesh.height = 0.17
	shoulder_mesh.radial_segments = 12
	shoulder_mesh.rings = 6
	_mesh(pivot, shoulder_mesh, color, Vector3(0.035 * side, -0.03, 0), Vector3.ZERO, Vector3(0.75, 0.8, 0.9), mat)
	# Upper blade: root end buried in the torso; small inward mesh tuck (-6 deg)
	# so the blade hugs the egg's outward curve instead of standing off it.
	var upper_mesh := CapsuleMesh.new()
	upper_mesh.radius = 0.08
	upper_mesh.height = 0.44
	upper_mesh.radial_segments = 12
	upper_mesh.rings = 6
	_mesh(pivot, upper_mesh, color, Vector3(0.045 * side, -0.171, 0), Vector3(0, 0, deg_to_rad(-6.0 * side)), Vector3(0.45, 1.0, 0.9), mat)
	# Tip: overlaps deep into the upper blade (no elbow seam) with a slight
	# extra outward flare (+4 deg past the rest pose).
	var tip_mesh := CapsuleMesh.new()
	tip_mesh.radius = 0.05
	tip_mesh.height = 0.2
	tip_mesh.radial_segments = 10
	tip_mesh.rings = 4
	_mesh(pivot, tip_mesh, color, Vector3(0.03 * side, -0.4, 0), Vector3(0, 0, deg_to_rad(4.0 * side)), Vector3(0.4, 1.0, 0.78), mat)
	# Match tick()'s rest targets (l: -16, r: +16) so static frames (previews,
	# first frame before tick) already show the correct outward-flared rest.
	pivot.rotation.z = deg_to_rad(16.0 * side)
	return pivot


## Attaches one cosmetic item by id (also used to preview AI accessories).
func _apply_cosmetic(id: String) -> void:
	if id == "":
		return
	var info := CosmeticsDB.get_item(id)
	var color: Color = info.get("color", Color.WHITE)
	match id:
		"hat_beanie":
			var dome := SphereMesh.new()
			dome.radius = 0.26
			dome.height = 0.34
			_mesh(_hat_anchor, dome, color, Vector3(0, 0.05, 0))
			var pom := SphereMesh.new()
			pom.radius = 0.07
			pom.height = 0.14
			_mesh(_hat_anchor, pom, Color(0.97, 0.97, 0.97), Vector3(0, 0.22, 0))
		"hat_earwarmers":
			var band := TorusMesh.new()
			band.inner_radius = 0.24
			band.outer_radius = 0.28
			_mesh(_hat_anchor, band, Color(0.4, 0.4, 0.45), Vector3(0, 0.02, 0), Vector3(deg_to_rad(14), 0, 0))
			var muff := SphereMesh.new()
			muff.radius = 0.1
			muff.height = 0.2
			_mesh(_hat_anchor, muff, color, Vector3(-0.26, -0.04, 0))
			_mesh(_hat_anchor, muff, color, Vector3(0.26, -0.04, 0))
		"hat_headset":
			var band := TorusMesh.new()
			band.inner_radius = 0.24
			band.outer_radius = 0.27
			_mesh(_hat_anchor, band, Color(0.2, 0.2, 0.24), Vector3(0, 0.04, 0), Vector3(deg_to_rad(10), 0, 0))
			var can := CylinderMesh.new()
			can.top_radius = 0.08
			can.bottom_radius = 0.08
			can.height = 0.05
			_mesh(_hat_anchor, can, color, Vector3(-0.25, -0.02, 0), Vector3(0, 0, deg_to_rad(90)))
			_mesh(_hat_anchor, can, color, Vector3(0.25, -0.02, 0), Vector3(0, 0, deg_to_rad(90)))
			var mic := CylinderMesh.new()
			mic.top_radius = 0.015
			mic.bottom_radius = 0.015
			mic.height = 0.2
			_mesh(_hat_anchor, mic, Color(0.2, 0.2, 0.24), Vector3(-0.16, -0.12, -0.12), Vector3(deg_to_rad(60), deg_to_rad(30), 0))
		"hat_crown":
			var ring := CylinderMesh.new()
			ring.top_radius = 0.19
			ring.bottom_radius = 0.16
			ring.height = 0.12
			_mesh(_hat_anchor, ring, color, Vector3(0, 0.08, 0))
			var spike := CylinderMesh.new()
			spike.top_radius = 0.0
			spike.bottom_radius = 0.045
			spike.height = 0.12
			for i: int in 5:
				var angle := TAU * float(i) / 5.0
				_mesh(_hat_anchor, spike, color, Vector3(sin(angle) * 0.16, 0.18, cos(angle) * 0.16))
		"scarf_red", "scarf_rainbow":
			var scarf := TorusMesh.new()
			scarf.inner_radius = 0.2
			scarf.outer_radius = 0.34
			_mesh(_neck_anchor, scarf, color, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.4, 1))
			var tail_mesh := BoxMesh.new()
			tail_mesh.size = Vector3(0.12, 0.3, 0.05)
			_mesh(_neck_anchor, tail_mesh, color, Vector3(0.12, -0.18, -0.26), Vector3(deg_to_rad(-8), 0, deg_to_rad(-8)))
			if id == "scarf_rainbow":
				var stripe := BoxMesh.new()
				stripe.size = Vector3(0.12, 0.1, 0.06)
				_mesh(_neck_anchor, stripe, Color(0.3, 0.75, 0.95), Vector3(0.12, -0.1, -0.26))
				_mesh(_neck_anchor, stripe, Color(0.45, 0.85, 0.4), Vector3(0.12, -0.26, -0.255))
		"scarf_bowtie":
			var knot := BoxMesh.new()
			knot.size = Vector3(0.07, 0.07, 0.05)
			_mesh(_neck_anchor, knot, color, Vector3(0, -0.05, -0.3))
			var wing := BoxMesh.new()
			wing.size = Vector3(0.14, 0.1, 0.04)
			_mesh(_neck_anchor, wing, color, Vector3(-0.11, -0.05, -0.3), Vector3(0, 0, deg_to_rad(12)))
			_mesh(_neck_anchor, wing, color, Vector3(0.11, -0.05, -0.3), Vector3(0, 0, deg_to_rad(-12)))
		"goggles_ski":
			var lens := BoxMesh.new()
			lens.size = Vector3(0.3, 0.11, 0.06)
			var lens_instance := _mesh(_face_anchor, lens, color, Vector3(0, 0.03, -0.02))
			lens_instance.material_override = get_material(color, 0.2, 0.15)
			var strap := TorusMesh.new()
			strap.inner_radius = 0.23
			strap.outer_radius = 0.26
			_mesh(_head_anchor, strap, Color(0.25, 0.25, 0.3), Vector3(0, 0.05, 0), Vector3(deg_to_rad(80), 0, 0))
		"goggles_aviator":
			var lens := SphereMesh.new()
			lens.radius = 0.07
			lens.height = 0.14
			var l := _mesh(_face_anchor, lens, color, Vector3(-0.11, 0.03, -0.045))
			var r := _mesh(_face_anchor, lens, color, Vector3(0.11, 0.03, -0.045))
			l.material_override = get_material(color, 0.6, 0.2)
			r.material_override = get_material(color, 0.6, 0.2)
			var bridge := BoxMesh.new()
			bridge.size = Vector3(0.1, 0.02, 0.02)
			_mesh(_face_anchor, bridge, Color(0.55, 0.42, 0.2), Vector3(0, 0.05, -0.05))
		_:
			pass


func set_pose(new_pose: Pose) -> void:
	if pose == new_pose:
		return
	pose = new_pose
	_pose_blend = 0.0


func trigger_squash(amount: float = 0.72) -> void:
	_squash = amount


## Drives all animation. speed_ratio: 0..1.5 of normal speed.
func tick(delta: float, speed_ratio: float) -> void:
	if _root == null:
		return
	_time += delta * (0.6 + anim_speed)
	_pose_blend = minf(_pose_blend + delta * 5.0, 1.0)
	_squash = lerpf(_squash, _squash_target, minf(delta * 10.0, 1.0))

	var target_tilt := Vector3.ZERO
	var target_y := 0.0
	var wave := _time * (5.0 + 7.0 * speed_ratio)
	var flipper_l_target := deg_to_rad(-16.0)
	var flipper_r_target := deg_to_rad(16.0)
	var flipper_swing := 0.0
	var brow_target := BROW_REST
	var step_lift := 0.0

	match pose:
		Pose.RUN:
			target_tilt.z = sin(wave) * deg_to_rad(9.0) * clampf(speed_ratio, 0.2, 1.0)
			target_tilt.x = deg_to_rad(6.0) * speed_ratio
			target_y = absf(sin(wave)) * 0.05 * speed_ratio
			flipper_swing = sin(wave) * deg_to_rad(22.0) * clampf(speed_ratio, 0.3, 1.0)
			_head_anchor.position.y = 0.78 + sin(wave * 2.0) * 0.012
			brow_target = deg_to_rad(-12.0)
			step_lift = 0.055 * clampf(speed_ratio, 0.0, 1.0)
		Pose.IDLE:
			target_tilt.z = sin(_time * 1.6) * deg_to_rad(2.0)
			target_y = sin(_time * 2.2) * 0.01
			flipper_swing = sin(_time * 1.8) * deg_to_rad(4.0)
			brow_target = deg_to_rad(-6.0)
		Pose.SLIDE:
			target_tilt.x = deg_to_rad(80.0)
			target_y = -0.28
			flipper_l_target = deg_to_rad(-52.0)
			flipper_r_target = deg_to_rad(52.0)
			flipper_swing = sin(_time * 3.0) * deg_to_rad(3.0)
			brow_target = deg_to_rad(-14.0)
		Pose.AIR:
			target_tilt.x = deg_to_rad(-12.0)
			flipper_l_target = deg_to_rad(-70.0)
			flipper_r_target = deg_to_rad(70.0)
			brow_target = deg_to_rad(-4.0)
		Pose.SWIM:
			target_tilt.x = deg_to_rad(72.0)
			target_y = -0.2
			flipper_swing = sin(_time * 9.0) * deg_to_rad(30.0)
			flipper_l_target = deg_to_rad(-40.0)
			flipper_r_target = deg_to_rad(40.0)
			brow_target = deg_to_rad(-12.0)
		Pose.STUN:
			target_tilt.z = sin(_time * 14.0) * deg_to_rad(14.0)
			target_tilt.x = deg_to_rad(-8.0)
			flipper_swing = sin(_time * 16.0) * deg_to_rad(35.0)
			brow_target = deg_to_rad(15.0)
		Pose.CELEBRATE:
			target_y = absf(sin(_time * 6.0)) * 0.18
			flipper_l_target = deg_to_rad(-150.0) + sin(_time * 10.0) * deg_to_rad(15.0)
			flipper_r_target = deg_to_rad(150.0) - sin(_time * 10.0) * deg_to_rad(15.0)
			brow_target = deg_to_rad(2.0)
		Pose.DEFEAT:
			target_tilt.x = deg_to_rad(18.0)
			target_y = -0.06
			_head_anchor.position.y = 0.74
			brow_target = deg_to_rad(18.0)

	_current_tilt = _current_tilt.lerp(target_tilt, minf(delta * 8.0, 1.0))
	_root.rotation = _current_tilt
	_root.position.y = lerpf(_root.position.y, target_y, minf(delta * 8.0, 1.0))
	_root.scale = Vector3(
		lerpf(_root.scale.x, 1.0 / sqrt(_squash), minf(delta * 12.0, 1.0)),
		lerpf(_root.scale.y, _squash, minf(delta * 12.0, 1.0)),
		lerpf(_root.scale.z, 1.0 / sqrt(_squash), minf(delta * 12.0, 1.0))
	)
	_squash = lerpf(_squash, 1.0, minf(delta * 6.0, 1.0))

	if _flipper_l != null:
		_flipper_l.rotation.z = lerpf(_flipper_l.rotation.z, flipper_l_target + flipper_swing, minf(delta * 10.0, 1.0))
		_flipper_r.rotation.z = lerpf(_flipper_r.rotation.z, flipper_r_target - flipper_swing, minf(delta * 10.0, 1.0))
		_flipper_l.rotation.x = flipper_swing * 0.5
		_flipper_r.rotation.x = -flipper_swing * 0.5

	if _brow_l != null:
		_brow_l.rotation.z = lerpf(_brow_l.rotation.z, brow_target, minf(delta * 6.0, 1.0))
		_brow_r.rotation.z = -_brow_l.rotation.z

	if _foot_l != null and pose == Pose.RUN:
		_foot_l.position.z = -0.04 + sin(wave) * 0.08 * speed_ratio
		_foot_r.position.z = -0.04 - sin(wave) * 0.08 * speed_ratio
		_foot_l.position.y = 0.035 + maxf(0.0, sin(wave)) * step_lift
		_foot_r.position.y = 0.035 + maxf(0.0, -sin(wave)) * step_lift
	elif _foot_l != null:
		_foot_l.position.z = -0.04
		_foot_r.position.z = -0.04
		_foot_l.position.y = 0.035
		_foot_r.position.y = 0.035
