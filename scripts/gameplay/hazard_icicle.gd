class_name HazardIcicle
extends Node3D
## Falling icicle: hangs above the track, shivers as a warning when a racer
## approaches, drops, shatters, then regrows. Readable and fair.

const TRIGGER_DISTANCE: float = 26.0
const WARN_TIME: float = 0.85

var _visual: MeshInstance3D
var _area: Area3D
var _state: int = 0  # 0 idle, 1 warning, 2 falling, 3 regrow
var _timer: float = 0.0
var _fall_speed: float = 0.0
var _rest_y: float = 0.0
var _floor_y: float = 0.0


func _ready() -> void:
	_rest_y = position.y
	_floor_y = position.y - 12.0
	var space_check := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * 30.0, GameConfig.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(space_check)
	if not hit.is_empty():
		_floor_y = (hit["position"] as Vector3).y

	_visual = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.34
	mesh.bottom_radius = 0.0
	mesh.height = 2.2
	mesh.radial_segments = 6
	_visual.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.88, 1.0, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.rim_enabled = true
	mat.rim = 0.6
	_visual.material_override = mat
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
			if _timer <= 0.0:
				_state = 2
				_fall_speed = 0.0
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
