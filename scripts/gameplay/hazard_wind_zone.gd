class_name HazardWindZone
extends Area3D
## Strong side-wind region: pushes racers laterally while inside. Visualized
## with streaking particles so the push direction is readable.

var push_direction: Vector3 = Vector3.RIGHT
var strength: float = 5.0
var zone_size: Vector3 = Vector3(16.0, 8.0, 40.0)

var _inside: Array[Racer] = []


func configure(p_direction: Vector3, p_strength: float, p_size: Vector3) -> void:
	push_direction = p_direction.normalized()
	strength = p_strength
	zone_size = p_size


func _ready() -> void:
	collision_layer = GameConfig.LAYER_TRIGGERS
	collision_mask = GameConfig.LAYER_RACERS
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
		var particles := GPUParticles3D.new()
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = zone_size * 0.5
		mat.direction = push_direction
		mat.spread = 4.0
		mat.initial_velocity_min = strength * 2.0
		mat.initial_velocity_max = strength * 3.0
		mat.gravity = Vector3.ZERO
		mat.scale_min = 0.03
		mat.scale_max = 0.07
		mat.color = Color(0.9, 0.96, 1.0, 0.5)
		particles.process_material = mat
		var streak := QuadMesh.new()
		streak.size = Vector2(1.6, 0.05)
		var streak_mat := StandardMaterial3D.new()
		streak_mat.albedo_color = Color(0.95, 0.98, 1.0, 0.4)
		streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		streak_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		streak.material = streak_mat
		particles.draw_pass_1 = streak
		particles.amount = 60
		particles.lifetime = 1.2
		add_child(particles)


func _physics_process(_delta: float) -> void:
	for racer: Racer in _inside:
		if is_instance_valid(racer) and racer.state != Racer.State.FINISHED:
			racer.apply_wind(push_direction * strength)
