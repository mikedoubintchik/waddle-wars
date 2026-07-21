class_name Snowball
extends Area3D
## Thrown snowball with forgiving homing toward a target racer ahead.
## Can miss, hit course geometry, or be blocked by a shield.

const SPEED: float = 30.0
const HOMING_STRENGTH: float = 3.2
const LIFETIME: float = 4.0

var thrower: Racer = null
var target: Racer = null
var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0


func launch(p_thrower: Racer, p_target: Racer) -> void:
	thrower = p_thrower
	target = p_target
	var forward := -p_thrower.global_transform.basis.z
	global_position = p_thrower.global_position + Vector3.UP * 1.2 + forward * 1.0
	_velocity = forward * SPEED + Vector3.UP * 2.0


func _ready() -> void:
	collision_layer = GameConfig.LAYER_HAZARDS
	collision_mask = GameConfig.LAYER_RACERS | GameConfig.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	visual.mesh = mesh
	visual.material_override = PenguinVisual.get_material(Color(0.95, 0.97, 1.0), 0.0, 0.9)
	add_child(visual)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		_pop()
		return
	if target != null and is_instance_valid(target) and target.state != Racer.State.FINISHED:
		var to_target := (target.global_position + Vector3.UP * 0.7) - global_position
		var desired := to_target.normalized() * SPEED
		_velocity = _velocity.lerp(desired, minf(delta * HOMING_STRENGTH, 1.0))
	else:
		_velocity.y -= 9.0 * delta
	global_position += _velocity * delta


func _on_body_entered(body: Node3D) -> void:
	if body == thrower:
		return
	if body is Racer:
		var racer := body as Racer
		racer.apply_stun("snowball")
		if racer.is_player or (thrower != null and thrower.is_player):
			AudioManager.play_sfx_3d("sfx_snowball_hit", global_position)
	_pop()


func _pop() -> void:
	var course := get_tree().get_first_node_in_group(&"course") as CourseBase
	if course != null:
		course.spawn_land_puff(global_position)
	queue_free()
