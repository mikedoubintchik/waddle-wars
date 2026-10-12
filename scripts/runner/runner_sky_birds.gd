extends Node3D
## Six small distant gulls: one cached mesh, one draw, no streamed resources,
## gameplay randomness or per-frame instance writes. Owner supplies active time.
const COUNT := 6
const BIRD_SHADER := preload("res://assets/shaders/runner_sky_birds.gdshader")
static var _mesh_cache: ArrayMesh
var _birds: MultiMeshInstance3D
var _material: ShaderMaterial
var _placements: Array[Transform3D] = []
var _clock := 0.0
var _last_shape := Vector2.ZERO
var _last_fov := -1.0

func setup() -> void:
	if _birds != null:
		return
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.mesh = bird_mesh()
	batch.instance_count = COUNT
	for index: int in COUNT:
		batch.set_instance_custom_data(index, Color(float(index) * 0.73, 0.0, 0.0, 1.0))
	_material = ShaderMaterial.new()
	_material.shader = BIRD_SHADER
	_birds = MultiMeshInstance3D.new()
	_birds.name = "DistantGulls"
	_birds.multimesh = batch
	_birds.material_override = _material
	_birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_birds)

func present(camera: Camera3D, delta: float, reduced_motion: bool, open_sky: bool) -> void:
	visible = open_sky
	if _birds == null or camera == null or not open_sky:
		return
	_clock += maxf(delta, 0.0) if not reduced_motion else 0.0
	_material.set_shader_parameter("flight_clock", _clock)
	_material.set_shader_parameter("wing_motion", 0.0 if reduced_motion else 1.0)
	# Distant flock remains behind the course and ahead of sky. Camera-relative
	# ray placement keeps the tiny silhouettes out of challenge/boost cards on
	# both orientations. Only the six transforms change when lens/shape changes.
	global_transform = camera.global_transform
	var shape := camera.get_viewport().get_visible_rect().size
	if shape == _last_shape and absf(camera.fov - _last_fov) < 0.1:
		return
	_last_shape = shape
	_last_fov = camera.fov
	var portrait := shape.y >= shape.x
	var depth := 400.0
	var vertical_span := 2.0 * depth * tan(deg_to_rad(camera.fov * 0.5))
	var horizontal_span := vertical_span * shape.x / maxf(shape.y, 1.0)
	var spots: Array = [Vector2(0.30, 0.25), Vector2(0.35, 0.28),
		Vector2(0.275, 0.29), Vector2(0.325, 0.315), Vector2(0.365, 0.245), Vector2(0.29, 0.34)] \
		if portrait else [Vector2(0.31, 0.205), Vector2(0.34, 0.245),
		Vector2(0.285, 0.255), Vector2(0.325, 0.295), Vector2(0.36, 0.30), Vector2(0.345, 0.335)]
	_placements.clear()
	for index: int in COUNT:
		var spot: Vector2 = spots[index]
		var width := horizontal_span * (0.040 if portrait else 0.018) * (1.0 - float(index % 3) * 0.16)
		var origin := Vector3((spot.x - 0.5) * horizontal_span,
			(0.5 - spot.y) * vertical_span, -depth)
		var placement := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * width), origin)
		_placements.append(placement)
		_birds.multimesh.set_instance_transform(index, placement)

func reset() -> void:
	_clock = 0.0
	if _material != null:
		_material.set_shader_parameter("flight_clock", 0.0)

static func bird_mesh() -> ArrayMesh:
	if _mesh_cache != null:
		return _mesh_cache
	var vertices := PackedVector3Array()
	# Two gently curved, tapered gull wings, each six triangles. Local width1.
	for sign_x: float in [-1.0, 1.0]:
		var ridge := [Vector3(0.0, 0.0, 0.0), Vector3(sign_x * 0.18, 0.11, 0.0),
			Vector3(sign_x * 0.34, 0.14, 0.0), Vector3(sign_x * 0.5, 0.07, 0.0)]
		var lower := [Vector3(0.0, -0.035, 0.0), Vector3(sign_x * 0.18, 0.055, 0.0),
			Vector3(sign_x * 0.34, 0.12, 0.0), Vector3(sign_x * 0.5, 0.07, 0.0)]
		for segment: int in 3:
			vertices.append_array(PackedVector3Array([ridge[segment], lower[segment], ridge[segment + 1],
				ridge[segment + 1], lower[segment], lower[segment + 1]]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	_mesh_cache = ArrayMesh.new()
	_mesh_cache.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh_cache
