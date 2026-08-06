class_name HazardPlatform
extends AnimatableBody3D
## Moving / tilting ice platform. Modes: "slide" (oscillates along an axis)
## and "tilt" (rocks around its travel axis). Used for iceberg water hops.
##
## Visuals: the slab uses the shared glossy ice shader (voronoi crack plates,
## internal veins, glint facets) with the shader's frosted WHITE border
## enabled on the top face via baked UV2 — a ragged bright edge ring so the
## landing area and its edges read by BRIGHTNESS + PATTERN at any palette.
## The berg skirt below uses a deeper, cloudier ice. When
## "accessibility/high_contrast_pickups" is on, amber edge strips outline the
## walkable top. Collision shape, sizes, and motion values untouched.

static var _slab_meshes: Dictionary = {}
static var _edge_mat: StandardMaterial3D = null

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
	visual.mesh = _get_slab_mesh(platform_size)
	visual.material_override = VisualLibrary.ice_material(Color(0.56, 0.77, 0.94), 0.6)
	add_child(visual)
	# Icy skirt under the platform so it reads as a floating berg: deeper,
	# cloudier ice than the polished top.
	var skirt := MeshInstance3D.new()
	var skirt_mesh := BoxMesh.new()
	skirt_mesh.size = Vector3(platform_size.x * 0.8, platform_size.y * 3.0, platform_size.z * 0.8)
	skirt.mesh = skirt_mesh
	skirt.material_override = VisualLibrary.ice_material(Color(0.45, 0.62, 0.8), 0.35)
	skirt.position.y = -platform_size.y * 1.6
	add_child(skirt)
	if not GameConfig.is_headless() \
			and bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups")):
		_add_edge_strips()

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = platform_size
	shape.shape = box
	add_child(shape)


## Amber edge strips outlining the walkable top (high-contrast mode): the
## drop-off edge reads by a hue-independent bright band, matching the game's
## hazard warning language.
func _add_edge_strips() -> void:
	var hy := platform_size.y * 0.5
	for side: int in 2:
		var s := -1.0 if side == 0 else 1.0
		var strip_x := MeshInstance3D.new()
		var mesh_x := BoxMesh.new()
		mesh_x.size = Vector3(platform_size.x * 0.96, 0.06, 0.18)
		strip_x.mesh = mesh_x
		strip_x.material_override = _get_edge_material()
		strip_x.position = Vector3(0.0, hy + 0.04, s * (platform_size.z * 0.5 - 0.15))
		strip_x.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip_x)
		var strip_z := MeshInstance3D.new()
		var mesh_z := BoxMesh.new()
		mesh_z.size = Vector3(0.18, 0.06, platform_size.z * 0.96)
		strip_z.mesh = mesh_z
		strip_z.material_override = _get_edge_material()
		strip_z.position = Vector3(s * (platform_size.x * 0.5 - 0.15), hy + 0.04, 0.0)
		strip_z.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip_z)


func _physics_process(delta: float) -> void:
	_time += delta
	var t := _time * TAU / period
	if move_axis != Vector3.ZERO and move_range > 0.0:
		global_position = _origin + move_axis * sin(t) * move_range
	if tilt_degrees > 0.0:
		rotation.z = deg_to_rad(tilt_degrees) * sin(t * 1.2)


## --- Shared visual resources ----------------------------------------------


## Slab mesh with baked UV2 frost flags: subdivided box whose TOP vertices
## carry UV2 = (edge_proximity, 1.0) so the shared ice shader draws its
## ragged frosted border as a ring around the platform lip (the shader gates
## the frost path on UV2.y > 0.5; sides/bottom stay clear glass). Cached per
## size; exact same outer dimensions as the collider box.
static func _get_slab_mesh(size: Vector3) -> ArrayMesh:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if _slab_meshes.has(key):
		return _slab_meshes[key]
	var box := BoxMesh.new()
	box.size = size
	box.subdivide_width = 6
	box.subdivide_depth = 6
	var arrays: Array = box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv2 := PackedVector2Array()
	uv2.resize(verts.size())
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	for i: int in verts.size():
		if normals[i].y > 0.9:
			# Remap edge proximity so frost hugs the outer band only.
			var e := maxf(absf(verts[i].x) / hx, absf(verts[i].z) / hz)
			uv2[i] = Vector2(clampf((e - 0.5) * 2.0, 0.0, 1.0), 1.0)
		else:
			uv2[i] = Vector2.ZERO
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_slab_meshes[key] = mesh
	return mesh


static func _get_edge_material() -> StandardMaterial3D:
	if _edge_mat == null:
		_edge_mat = StandardMaterial3D.new()
		_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_edge_mat.albedo_color = Color(1.0, 0.72, 0.12)
	return _edge_mat
