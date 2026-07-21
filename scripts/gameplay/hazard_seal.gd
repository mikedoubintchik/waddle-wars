class_name HazardSeal
extends Node3D
## Friendly seal that slides back and forth across the track. Bumping into
## it causes a comedic stumble (never a hard stun); the seal is unharmed
## and unbothered.

var guide: PathGuide = null
var track_offset: float = 0.0
var sweep: float = 8.0  # lateral half-range
var speed: float = 4.0

var _phase: float = 0.0
var _area: Area3D
var _body_visual: Node3D
var _hit_cooldown: Dictionary = {}


func configure(p_guide: PathGuide, p_offset: float, p_sweep: float, p_speed: float = 4.0) -> void:
	guide = p_guide
	track_offset = p_offset
	sweep = p_sweep
	speed = p_speed


func _ready() -> void:
	add_to_group(&"hazards")
	_phase = randf() * TAU
	_body_visual = Node3D.new()
	add_child(_body_visual)
	# Rounded seal: capsule body + tail + head + snout, soft gray.
	var seal_color := Color(0.62, 0.64, 0.7)
	var belly_color := Color(0.82, 0.83, 0.86)
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.55
	body_mesh.height = 2.2
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = PenguinVisual.get_material(seal_color)
	body.rotation.x = deg_to_rad(90)
	body.position.y = 0.5
	_body_visual.add_child(body)
	var belly := MeshInstance3D.new()
	var belly_mesh := CapsuleMesh.new()
	belly_mesh.radius = 0.45
	belly_mesh.height = 1.9
	belly.mesh = belly_mesh
	belly.material_override = PenguinVisual.get_material(belly_color)
	belly.rotation.x = deg_to_rad(90)
	belly.position = Vector3(0, 0.38, 0)
	belly.scale = Vector3(0.9, 0.9, 0.9)
	_body_visual.add_child(belly)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.4
	head_mesh.height = 0.8
	head.mesh = head_mesh
	head.material_override = PenguinVisual.get_material(seal_color)
	head.position = Vector3(0, 0.72, -1.05)
	_body_visual.add_child(head)
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.06
		eye_mesh.height = 0.12
		eye.mesh = eye_mesh
		eye.material_override = PenguinVisual.get_material(Color(0.08, 0.08, 0.1))
		eye.position = Vector3(0.16 * side, 0.85, -1.32)
		_body_visual.add_child(eye)
	var tail := MeshInstance3D.new()
	var tail_mesh := PrismMesh.new()
	tail_mesh.size = Vector3(0.7, 0.4, 0.3)
	tail.mesh = tail_mesh
	tail.material_override = PenguinVisual.get_material(seal_color)
	tail.position = Vector3(0, 0.42, 1.25)
	_body_visual.add_child(tail)

	_area = Area3D.new()
	_area.collision_layer = GameConfig.LAYER_HAZARDS
	_area.collision_mask = GameConfig.LAYER_RACERS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 1.4, 2.6)
	shape.shape = box
	shape.position.y = 0.7
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(_on_bump)


func _physics_process(delta: float) -> void:
	if guide == null:
		return
	_phase += delta * speed / maxf(sweep, 1.0)
	var lateral := sin(_phase) * sweep
	global_position = guide.point_at(track_offset, lateral, 0.0)
	# Face the direction of travel, belly-sliding style, with a happy wobble.
	var moving_right := cos(_phase) > 0.0
	var xform := guide.transform_at(track_offset)
	var face_dir := xform.basis.x * (1.0 if moving_right else -1.0)
	if face_dir.length_squared() > 0.01:
		look_at(global_position + face_dir, Vector3.UP)
	_body_visual.rotation.z = sin(_phase * 8.0) * 0.08


func _on_bump(body: Node3D) -> void:
	if not body is Racer:
		return
	var racer := body as Racer
	var now := Time.get_ticks_msec()
	if int(_hit_cooldown.get(racer.racer_key, 0)) > now:
		return
	_hit_cooldown[racer.racer_key] = now + 2500
	racer.receive_shove_from_position(global_position)
	AudioManager.play_sfx_3d("sfx_stumble", global_position, 0.85)
	# The seal barks happily, unharmed.
	AudioManager.play_sfx_3d("sfx_chirp", global_position, 0.6, -4.0)
