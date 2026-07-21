class_name HazardCrackingIce
extends Node3D
## Ice tile that cracks under a racer's weight and breaks after a short
## delay, dropping anyone still on it. Regenerates a few seconds later.
## Speed is safety: fast racers clear it before it breaks.

const CRACK_TIME: float = 0.55
const REGEN_TIME: float = 3.5

var tile_size: Vector2 = Vector2(6.0, 6.0)

var _visual: MeshInstance3D
var _body: StaticBody3D
var _detector: Area3D
var _state: int = 0  # 0 solid, 1 cracking, 2 broken
var _timer: float = 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	_visual = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tile_size.x, 0.5, tile_size.y)
	_visual.mesh = mesh
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.62, 0.85, 0.98, 0.95)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.06
	_mat.rim_enabled = true
	_mat.rim = 0.5
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


func _on_stepped(body: Node3D) -> void:
	if _state == 0 and body is Racer:
		_state = 1
		_timer = CRACK_TIME
		_mat.albedo_color = Color(0.85, 0.92, 1.0, 0.9)
		AudioManager.play_sfx_3d("sfx_stumble", global_position, 1.5, -6.0)


func _physics_process(delta: float) -> void:
	match _state:
		1:
			_timer -= delta
			_visual.position.y = sin(_timer * 60.0) * 0.03
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
	var course := get_tree().get_first_node_in_group(&"course") as CourseBase
	if course != null:
		course.spawn_splash(global_position)


func _restore() -> void:
	_state = 0
	_visual.visible = true
	_visual.position.y = 0.0
	_mat.albedo_color = Color(0.62, 0.85, 0.98, 0.95)
	_body.get_child(0).set_deferred("disabled", false)
