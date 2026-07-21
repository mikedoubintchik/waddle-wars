class_name PenguinVisual
extends Node3D
## Procedural penguin model built from primitives, with cosmetic attachment
## points and code-driven animation (waddle, slide, swim, stun, celebrate).
## No imported assets: everything is meshes + StandardMaterial3D.

enum Pose { RUN, SLIDE, AIR, SWIM, STUN, IDLE, CELEBRATE, DEFEAT }

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
var _eye_l: Node3D
var _eye_r: Node3D
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


func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = get_material(color)
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
	var body_color: Color = config.get("body_color", Color(0.13, 0.16, 0.22))
	var belly_color: Color = config.get("belly_color", Color(0.95, 0.94, 0.9))
	var beak_color := Color(0.95, 0.6, 0.16)

	_root = Node3D.new()
	add_child(_root)

	# Body: rounded egg.
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.34
	body_mesh.height = 0.92
	body_mesh.radial_segments = 24
	body_mesh.rings = 16
	_body = _mesh(_root, body_mesh, body_color, Vector3(0, 0.46, 0))

	# Belly patch: flattened lighter sphere pushed forward.
	var belly_mesh := SphereMesh.new()
	belly_mesh.radius = 0.30
	belly_mesh.height = 0.78
	belly_mesh.radial_segments = 20
	belly_mesh.rings = 12
	_belly = _mesh(_root, belly_mesh, belly_color, Vector3(0, 0.42, -0.09), Vector3.ZERO, Vector3(0.82, 0.9, 0.62))

	# Head anchor sits atop the egg (the egg itself is the head silhouette).
	_head_anchor = Node3D.new()
	_head_anchor.position = Vector3(0, 0.78, 0)
	_root.add_child(_head_anchor)

	_face_anchor = Node3D.new()
	_face_anchor.position = Vector3(0, 0, -0.24)
	_head_anchor.add_child(_face_anchor)

	# Eyes.
	_eye_l = Node3D.new()
	_eye_l.position = Vector3(-0.11, 0.02, -0.03)
	_face_anchor.add_child(_eye_l)
	_eye_r = Node3D.new()
	_eye_r.position = Vector3(0.11, 0.02, -0.03)
	_face_anchor.add_child(_eye_r)
	var eye_white := SphereMesh.new()
	eye_white.radius = 0.055
	eye_white.height = 0.11
	var pupil := SphereMesh.new()
	pupil.radius = 0.026
	pupil.height = 0.052
	for eye: Node3D in [_eye_l, _eye_r]:
		_mesh(eye, eye_white, Color(0.98, 0.98, 0.98))
		_mesh(eye, pupil, Color(0.06, 0.07, 0.1), Vector3(0, 0.005, -0.038))

	# Beak: small cone pointing forward.
	var beak_mesh := CylinderMesh.new()
	beak_mesh.top_radius = 0.0
	beak_mesh.bottom_radius = 0.055
	beak_mesh.height = 0.18
	beak_mesh.radial_segments = 10
	_beak = _mesh(_face_anchor, beak_mesh, beak_color, Vector3(0, -0.06, -0.09), Vector3(deg_to_rad(-90), 0, 0))

	# Flippers with shoulder pivots.
	_flipper_l = _make_flipper(body_color, -1.0)
	_flipper_r = _make_flipper(body_color, 1.0)

	# Feet.
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(0.16, 0.05, 0.24)
	_foot_l = _mesh(_root, foot_mesh, beak_color, Vector3(-0.13, 0.03, -0.02))
	_foot_r = _mesh(_root, foot_mesh, beak_color, Vector3(0.13, 0.03, -0.02))

	# Tiny tail.
	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius = 0.0
	tail_mesh.bottom_radius = 0.09
	tail_mesh.height = 0.22
	_mesh(_root, tail_mesh, body_color, Vector3(0, 0.28, 0.3), Vector3(deg_to_rad(65), 0, 0))

	# Rockhopper crest.
	if config.has("crest_color"):
		var crest_color: Color = config["crest_color"]
		var crest_mesh := CylinderMesh.new()
		crest_mesh.top_radius = 0.0
		crest_mesh.bottom_radius = 0.035
		crest_mesh.height = 0.22
		_mesh(_head_anchor, crest_mesh, crest_color, Vector3(-0.14, 0.13, 0), Vector3(0, 0, deg_to_rad(38)))
		_mesh(_head_anchor, crest_mesh, crest_color, Vector3(0.14, 0.13, 0), Vector3(0, 0, deg_to_rad(-38)))

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
	var pivot := Node3D.new()
	pivot.position = Vector3(0.3 * side, 0.6, 0)
	_root.add_child(pivot)
	var flipper_mesh := CapsuleMesh.new()
	flipper_mesh.radius = 0.07
	flipper_mesh.height = 0.44
	var flipper := _mesh(pivot, flipper_mesh, color, Vector3(0.03 * side, -0.16, 0))
	flipper.scale = Vector3(0.45, 1.0, 0.8)
	pivot.rotation.z = deg_to_rad(-14.0 * side)
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
	var flipper_l_target := deg_to_rad(-14.0)
	var flipper_r_target := deg_to_rad(14.0)
	var flipper_swing := 0.0

	match pose:
		Pose.RUN:
			target_tilt.z = sin(wave) * deg_to_rad(9.0) * clampf(speed_ratio, 0.2, 1.0)
			target_tilt.x = deg_to_rad(6.0) * speed_ratio
			target_y = absf(sin(wave)) * 0.05 * speed_ratio
			flipper_swing = sin(wave) * deg_to_rad(22.0) * clampf(speed_ratio, 0.3, 1.0)
			_head_anchor.position.y = 0.78 + sin(wave * 2.0) * 0.012
		Pose.IDLE:
			target_tilt.z = sin(_time * 1.6) * deg_to_rad(2.0)
			target_y = sin(_time * 2.2) * 0.01
			flipper_swing = sin(_time * 1.8) * deg_to_rad(4.0)
		Pose.SLIDE:
			target_tilt.x = deg_to_rad(80.0)
			target_y = -0.28
			flipper_l_target = deg_to_rad(-52.0)
			flipper_r_target = deg_to_rad(52.0)
			flipper_swing = sin(_time * 3.0) * deg_to_rad(3.0)
		Pose.AIR:
			target_tilt.x = deg_to_rad(-12.0)
			flipper_l_target = deg_to_rad(-70.0)
			flipper_r_target = deg_to_rad(70.0)
		Pose.SWIM:
			target_tilt.x = deg_to_rad(72.0)
			target_y = -0.2
			flipper_swing = sin(_time * 9.0) * deg_to_rad(30.0)
			flipper_l_target = deg_to_rad(-40.0)
			flipper_r_target = deg_to_rad(40.0)
		Pose.STUN:
			target_tilt.z = sin(_time * 14.0) * deg_to_rad(14.0)
			target_tilt.x = deg_to_rad(-8.0)
			flipper_swing = sin(_time * 16.0) * deg_to_rad(35.0)
		Pose.CELEBRATE:
			target_y = absf(sin(_time * 6.0)) * 0.18
			flipper_l_target = deg_to_rad(-150.0) + sin(_time * 10.0) * deg_to_rad(15.0)
			flipper_r_target = deg_to_rad(150.0) - sin(_time * 10.0) * deg_to_rad(15.0)
		Pose.DEFEAT:
			target_tilt.x = deg_to_rad(18.0)
			target_y = -0.06
			_head_anchor.position.y = 0.74

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

	if _foot_l != null and pose == Pose.RUN:
		_foot_l.position.z = -0.02 + sin(wave) * 0.08 * speed_ratio
		_foot_r.position.z = -0.02 - sin(wave) * 0.08 * speed_ratio
	elif _foot_l != null:
		_foot_l.position.z = -0.02
		_foot_r.position.z = -0.02
