class_name HazardPlatform
extends AnimatableBody3D
## Moving / tilting ice platform. Modes: "slide" (oscillates along an axis)
## and "tilt" (rocks around its travel axis). Used for iceberg water hops.

var platform_size: Vector3 = Vector3(9.0, 0.8, 9.0)
var move_axis: Vector3 = Vector3.RIGHT
var move_range: float = 4.0
var period: float = 5.0
var tilt_degrees: float = 0.0
var phase_offset: float = 0.0

var _origin: Vector3
var _time: float = 0.0


func configure(p_size: Vector3, p_axis: Vector3, p_range: float, p_period: float, p_tilt: float = 0.0, p_phase: float = 0.0) -> void:
	platform_size = p_size
	move_axis = p_axis.normalized() if p_axis.length_squared() > 0.001 else Vector3.ZERO
	move_range = p_range
	period = maxf(p_period, 0.5)
	tilt_degrees = p_tilt
	phase_offset = p_phase


func _ready() -> void:
	sync_to_physics = false
	collision_layer = GameConfig.LAYER_WORLD
	collision_mask = 0
	set_meta("surface", SurfacesDB.Surface.ICE_ROUGH)
	_origin = global_position
	_time = phase_offset

	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = platform_size
	visual.mesh = mesh
	visual.material_override = TrackBuilder.surface_material(SurfacesDB.Surface.ICE_ROUGH)
	add_child(visual)
	# Icy skirt under the platform so it reads as a floating berg.
	var skirt := MeshInstance3D.new()
	var skirt_mesh := BoxMesh.new()
	skirt_mesh.size = Vector3(platform_size.x * 0.8, platform_size.y * 3.0, platform_size.z * 0.8)
	skirt.mesh = skirt_mesh
	skirt.material_override = PenguinVisual.get_material(Color(0.5, 0.68, 0.85))
	skirt.position.y = -platform_size.y * 1.6
	add_child(skirt)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = platform_size
	shape.shape = box
	add_child(shape)


func _physics_process(delta: float) -> void:
	_time += delta
	var t := _time * TAU / period
	if move_axis != Vector3.ZERO and move_range > 0.0:
		global_position = _origin + move_axis * sin(t) * move_range
	if tilt_degrees > 0.0:
		rotation.z = deg_to_rad(tilt_degrees) * sin(t * 0.8)
