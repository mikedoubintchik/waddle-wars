class_name HazardGeyser
extends Node3D
## Ice geyser: bubbles as a telegraph, then erupts on a fixed cycle,
## launching racers upward. Doubles as a jump pad on courses that place it
## under a gap — energetic, not punishing.

var cycle_time: float = 3.2
var warn_time: float = 0.8
var launch_velocity: float = 15.0
var phase_offset: float = 0.0

var _time: float = 0.0
var _area: Area3D
var _column: MeshInstance3D
var _base: MeshInstance3D
var _erupting: bool = false


func _ready() -> void:
	_time = phase_offset
	_base = MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.4
	base_mesh.bottom_radius = 1.8
	base_mesh.height = 0.4
	_base.mesh = base_mesh
	_base.material_override = PenguinVisual.get_material(Color(0.55, 0.8, 0.95), 0.0, 0.3)
	add_child(_base)

	_column = MeshInstance3D.new()
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = 0.9
	column_mesh.bottom_radius = 1.2
	column_mesh.height = 6.0
	_column.mesh = column_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.92, 1.0, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_column.material_override = mat
	_column.position.y = 3.0
	_column.visible = false
	add_child(_column)

	_area = Area3D.new()
	_area.collision_layer = GameConfig.LAYER_TRIGGERS
	_area.collision_mask = GameConfig.LAYER_RACERS
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.5
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position.y = 1.5
	_area.add_child(shape)
	add_child(_area)


func _physics_process(delta: float) -> void:
	_time += delta
	var t := fmod(_time, cycle_time)
	var erupt_start := cycle_time - 1.0
	var warn_start := erupt_start - warn_time

	if t >= warn_start and t < erupt_start:
		# Telegraph: base pulses.
		var pulse := 1.0 + sin((t - warn_start) * 30.0) * 0.08
		_base.scale = Vector3(pulse, 1.0, pulse)
		_erupting = false
		_column.visible = false
	elif t >= erupt_start:
		_base.scale = Vector3.ONE
		if not _erupting:
			_erupting = true
			AudioManager.play_sfx_3d("sfx_splash", global_position, 0.8, -4.0)
		_column.visible = true
		_column.scale.y = clampf((t - erupt_start) * 6.0, 0.1, 1.0)
		for body: Node3D in _area.get_overlapping_bodies():
			if body is Racer:
				var racer := body as Racer
				if racer.vertical_velocity < launch_velocity * 0.8:
					racer.vertical_velocity = launch_velocity
					AudioManager.play_sfx_3d("sfx_jump", racer.global_position, 0.8)
	else:
		_erupting = false
		_column.visible = false
		_base.scale = Vector3.ONE
