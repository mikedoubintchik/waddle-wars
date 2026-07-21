class_name TrackBuilder
extends RefCounted
## Generates track ribbon meshes, walls, water channels, and shared course
## props from control-point lists. All geometry is procedural; collision uses
## trimesh shapes with surface metadata for the racer's surface detection.

const SAMPLE: float = 3.0

static var _surface_materials: Dictionary = {}


static func surface_material(surface: SurfacesDB.Surface) -> StandardMaterial3D:
	if _surface_materials.has(surface):
		return _surface_materials[surface]
	var mat := StandardMaterial3D.new()
	match surface:
		SurfacesDB.Surface.PACKED_SNOW:
			mat.albedo_color = Color(0.93, 0.96, 1.0)
			mat.roughness = 0.95
		SurfacesDB.Surface.DEEP_SNOW:
			mat.albedo_color = Color(0.99, 0.99, 1.0)
			mat.roughness = 1.0
		SurfacesDB.Surface.ICE_SMOOTH:
			mat.albedo_color = Color(0.42, 0.68, 0.94)
			mat.roughness = 0.08
			mat.metallic = 0.25
			mat.rim_enabled = true
			mat.rim = 0.4
		SurfacesDB.Surface.ICE_ROUGH:
			mat.albedo_color = Color(0.56, 0.74, 0.9)
			mat.roughness = 0.45
		SurfacesDB.Surface.BOOST:
			mat.albedo_color = Color(1.0, 0.72, 0.2)
			mat.roughness = 0.3
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.55, 0.1)
			mat.emission_energy_multiplier = 1.1
		_:
			mat.albedo_color = Color(0.9, 0.94, 1.0)
			mat.roughness = 0.9
	_surface_materials[surface] = mat
	return mat


## Builds a Curve3D through the given positions with smooth auto tangents.
static func make_curve(positions: Array) -> Curve3D:
	var curve := Curve3D.new()
	for i: int in positions.size():
		var pos: Vector3 = positions[i]
		var prev: Vector3 = positions[maxi(i - 1, 0)]
		var next: Vector3 = positions[mini(i + 1, positions.size() - 1)]
		var tangent := (next - prev) * 0.22
		curve.add_point(pos, -tangent, tangent)
	return curve


## points: Array of Dictionaries {pos: Vector3, width: float, surface: int,
## wall_l: bool, wall_r: bool}. Missing keys use defaults (width 14,
## packed snow, walls on).
## Returns a Node3D containing floor meshes/collision + walls, with a
## PathGuide stored under meta "guide".
static func build_ribbon(points: Array, name_hint: String = "Track") -> Node3D:
	var root := Node3D.new()
	root.name = name_hint
	var positions: Array = []
	for p: Dictionary in points:
		positions.append(p["pos"])
	var curve := make_curve(positions)
	var guide := PathGuide.new(curve)
	root.set_meta("guide", guide)

	# Per-control-point cumulative offsets to interpolate width/surface.
	var control_offsets: Array[float] = []
	for p: Dictionary in points:
		var res := guide.nearest(p["pos"], -1)
		control_offsets.append(float(res["offset"]))
	control_offsets[0] = 0.0
	control_offsets[control_offsets.size() - 1] = guide.length

	var sample_count := int(guide.length / SAMPLE) + 1
	var left_pts: PackedVector3Array = []
	var right_pts: PackedVector3Array = []
	var surfaces: Array[int] = []
	var walls_l: Array[bool] = []
	var walls_r: Array[bool] = []
	var gaps: Array[bool] = []
	for i: int in sample_count + 1:
		var offset := minf(float(i) * SAMPLE, guide.length)
		var ctrl := _control_index_for(control_offsets, offset)
		var p: Dictionary = points[ctrl]
		var p_next: Dictionary = points[mini(ctrl + 1, points.size() - 1)]
		var span := maxf(control_offsets[mini(ctrl + 1, points.size() - 1)] - control_offsets[ctrl], 0.001)
		var t := clampf((offset - control_offsets[ctrl]) / span, 0.0, 1.0)
		var width := lerpf(float(p.get("width", 14.0)), float(p_next.get("width", 14.0)), t)
		var xform := guide.transform_at(offset)
		left_pts.append(xform.origin - xform.basis.x * (width * 0.5))
		right_pts.append(xform.origin + xform.basis.x * (width * 0.5))
		surfaces.append(int(p.get("surface", SurfacesDB.Surface.PACKED_SNOW)))
		walls_l.append(bool(p.get("wall_l", true)) and not bool(p.get("gap", false)))
		walls_r.append(bool(p.get("wall_r", true)) and not bool(p.get("gap", false)))
		gaps.append(bool(p.get("gap", false)))

	# Floor meshes split into runs of identical surface; gap runs are skipped
	# entirely (hazard tiles or jumps bridge them).
	var run_start := 0
	for i: int in range(1, surfaces.size() + 1):
		if i == surfaces.size() or surfaces[i] != surfaces[run_start] or gaps[i] != gaps[run_start]:
			if not gaps[run_start]:
				_emit_floor_run(root, left_pts, right_pts, run_start, i, surfaces[run_start] as SurfacesDB.Surface)
			run_start = i
	# Walls split into runs of wall-enabled.
	_emit_walls(root, left_pts, right_pts, walls_l, true)
	_emit_walls(root, left_pts, right_pts, walls_r, false)
	_emit_skirt(root, left_pts, right_pts, gaps)
	return root


static func _control_index_for(offsets: Array[float], offset: float) -> int:
	for i: int in range(offsets.size() - 1, -1, -1):
		if offset >= offsets[i]:
			return i
	return 0


static func _emit_floor_run(root: Node3D, left: PackedVector3Array, right: PackedVector3Array, start: int, end: int, surface: SurfacesDB.Surface) -> void:
	if end - start < 1:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := maxi(start - 1, 0)  # overlap one sample to avoid seams
	for i: int in range(lo, end):
		if i + 1 >= left.size():
			break
		var u0 := float(i) * 0.25
		var u1 := float(i + 1) * 0.25
		_quad(st, left[i], right[i], right[i + 1], left[i + 1], u0, u1)
	st.generate_normals()
	var mesh := st.commit()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = surface_material(surface)
	root.add_child(instance)
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	body.set_meta("surface", surface)
	var shape := CollisionShape3D.new()
	shape.shape = make_solid_shape(mesh)
	body.add_child(shape)
	root.add_child(body)


static func _emit_walls(root: Node3D, left: PackedVector3Array, right: PackedVector3Array, flags: Array[bool], is_left: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var height := Vector3.UP * 1.5
	for i: int in flags.size() - 1:
		if not flags[i]:
			continue
		any = true
		var a := left[i] if is_left else right[i]
		var b := left[i + 1] if is_left else right[i + 1]
		if is_left:
			_quad(st, a, a + height, b + height, b, 0.0, 1.0)
		else:
			_quad(st, a + height, a, b, b + height, 0.0, 1.0)
	if not any:
		return
	st.generate_normals()
	var mesh := st.commit()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.65, 0.88, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = mat
	root.add_child(instance)
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = make_solid_shape(mesh)
	body.add_child(shape)
	root.add_child(body)


## Visual-only side skirts so the track reads as thick ice, not paper.
static func _emit_skirt(root: Node3D, left: PackedVector3Array, right: PackedVector3Array, gaps: Array[bool] = []) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drop := Vector3.DOWN * 10.0
	var out := 2.0
	for i: int in left.size() - 1:
		if not gaps.is_empty() and (gaps[i] or gaps[i + 1]):
			continue
		var dir_l := (left[i] - right[i]).normalized() * out
		var dir_l2 := (left[i + 1] - right[i + 1]).normalized() * out
		_quad(st, left[i], left[i] + dir_l + drop, left[i + 1] + dir_l2 + drop, left[i + 1], 0.0, 1.0)
		_quad(st, right[i] - dir_l + drop, right[i], right[i + 1], right[i + 1] - dir_l2 + drop, 0.0, 1.0)
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.6, 0.8)
	mat.roughness = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = mat
	root.add_child(instance)


## Emits a quad from corners given counter-clockwise when viewed from the
## visible side; Godot front faces are clockwise, so triangles are reversed.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u0: float, u1: float) -> void:
	st.set_uv(Vector2(0, u0)); st.add_vertex(a)
	st.set_uv(Vector2(0, u1)); st.add_vertex(d)
	st.set_uv(Vector2(1, u1)); st.add_vertex(c)
	st.set_uv(Vector2(0, u0)); st.add_vertex(a)
	st.set_uv(Vector2(1, u1)); st.add_vertex(c)
	st.set_uv(Vector2(1, u0)); st.add_vertex(b)


## Trimesh shape that collides from both sides — track geometry must never
## let a racer tunnel through because of winding direction.
static func make_solid_shape(mesh: Mesh) -> ConcavePolygonShape3D:
	var shape := mesh.create_trimesh_shape() as ConcavePolygonShape3D
	shape.backface_collision = true
	return shape


## Water channel: visual plane + swim volume + solid floor beneath.
## Returns Node3D. Racers entering the Area3D switch to swimming.
static func build_water(points: Array, name_hint: String = "Water") -> Node3D:
	var root := Node3D.new()
	root.name = name_hint
	var positions: Array = []
	for p: Dictionary in points:
		positions.append(p["pos"])
	var curve := make_curve(positions)
	var guide := PathGuide.new(curve)
	root.set_meta("guide", guide)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var floor_st := SurfaceTool.new()
	floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sample_count := int(guide.length / SAMPLE)
	var width := float(points[0].get("width", 16.0))
	for i: int in sample_count:
		var xform0 := guide.transform_at(float(i) * SAMPLE)
		var xform1 := guide.transform_at(float(i + 1) * SAMPLE)
		var l0 := xform0.origin - xform0.basis.x * (width * 0.5)
		var r0 := xform0.origin + xform0.basis.x * (width * 0.5)
		var l1 := xform1.origin - xform1.basis.x * (width * 0.5)
		var r1 := xform1.origin + xform1.basis.x * (width * 0.5)
		_quad(st, l0, r0, r1, l1, float(i) * 0.2, float(i + 1) * 0.2)
		var depth := Vector3.DOWN * 3.5
		_quad(floor_st, l0 + depth, r0 + depth, r1 + depth, l1 + depth, 0.0, 1.0)
		# Swim volume box per segment.
		var area := Area3D.new()
		area.collision_layer = GameConfig.LAYER_WATER
		area.collision_mask = GameConfig.LAYER_RACERS
		var box := BoxShape3D.new()
		var seg_len := xform0.origin.distance_to(xform1.origin) + 1.0
		box.size = Vector3(width, 4.0, seg_len)
		var shape := CollisionShape3D.new()
		shape.shape = box
		area.add_child(shape)
		var mid := (xform0.origin + xform1.origin) * 0.5 + Vector3.DOWN * 1.9
		area.transform = Transform3D(xform0.basis, mid)
		var surface_y := (xform0.origin.y + xform1.origin.y) * 0.5
		area.body_entered.connect(_on_water_entered.bind(area, surface_y))
		area.body_exited.connect(_on_water_exited.bind(area))
		root.add_child(area)

	st.generate_normals()
	var water_mesh := MeshInstance3D.new()
	water_mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.42, 0.62, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_mesh.material_override = mat
	root.add_child(water_mesh)

	floor_st.generate_normals()
	var floor_mesh_instance := MeshInstance3D.new()
	floor_mesh_instance.mesh = floor_st.commit()
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.1, 0.28, 0.42)
	floor_mesh_instance.material_override = floor_mat
	root.add_child(floor_mesh_instance)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = GameConfig.LAYER_WORLD
	floor_body.collision_mask = 0
	floor_body.set_meta("surface", SurfacesDB.Surface.WATER)
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = make_solid_shape(floor_mesh_instance.mesh)
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	return root


static func _on_water_entered(body: Node3D, area: Area3D, surface_y: float) -> void:
	if body is Racer:
		(body as Racer).enter_water(area, surface_y)


static func _on_water_exited(body: Node3D, area: Area3D) -> void:
	if body is Racer:
		(body as Racer).exit_water(area)


## --- Shared props ----------------------------------------------------------

static func prop_material(color: Color, rough: float = 0.8) -> StandardMaterial3D:
	return PenguinVisual.get_material(color, 0.0, rough)


static func add_flag(parent: Node3D, pos: Vector3, color: Color = Color(0.9, 0.25, 0.3)) -> void:
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.07
	pole_mesh.height = 3.0
	pole.mesh = pole_mesh
	pole.material_override = prop_material(Color(0.5, 0.35, 0.2))
	pole.position = pos + Vector3.UP * 1.5
	parent.add_child(pole)
	var flag := MeshInstance3D.new()
	var flag_mesh := PrismMesh.new()
	flag_mesh.size = Vector3(1.0, 0.6, 0.06)
	flag.mesh = flag_mesh
	flag.material_override = prop_material(color)
	flag.position = pos + Vector3.UP * 2.7 + Vector3(0.5, 0, 0)
	flag.rotation.z = deg_to_rad(-90)
	parent.add_child(flag)


static func add_rock(parent: Node3D, pos: Vector3, scale_factor: float = 1.0, rng: RandomNumberGenerator = null) -> void:
	var rock := MeshInstance3D.new()
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.8 * scale_factor
	rock_mesh.height = 1.1 * scale_factor
	rock_mesh.radial_segments = 8
	rock_mesh.rings = 5
	rock.mesh = rock_mesh
	rock.material_override = prop_material(Color(0.45, 0.48, 0.54))
	rock.position = pos + Vector3.UP * 0.3 * scale_factor
	if rng != null:
		rock.rotation.y = rng.randf() * TAU
		rock.scale = Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.6, 1.0), rng.randf_range(0.8, 1.4))
	parent.add_child(rock)
	# Snow cap.
	var cap := MeshInstance3D.new()
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.7 * scale_factor
	cap_mesh.height = 0.5 * scale_factor
	cap.mesh = cap_mesh
	cap.material_override = prop_material(Color(0.96, 0.98, 1.0))
	cap.position = pos + Vector3.UP * 0.75 * scale_factor
	cap.scale = rock.scale
	parent.add_child(cap)


static func add_ice_crystal(parent: Node3D, pos: Vector3, height: float = 3.0, color: Color = Color(0.55, 0.85, 1.0)) -> void:
	var crystal := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = height * 0.16
	mesh.height = height
	mesh.radial_segments = 5
	crystal.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.rim_enabled = true
	mat.rim = 0.6
	crystal.material_override = mat
	crystal.position = pos + Vector3.UP * height * 0.5
	parent.add_child(crystal)


static func add_spectator(parent: Node3D, pos: Vector3, look_target: Vector3, rng: RandomNumberGenerator) -> void:
	var penguin := PenguinVisual.new()
	var bodies: Array = ["body_classic", "body_snowy", "body_midnight"]
	var body_id: String = bodies[rng.randi_range(0, bodies.size() - 1)]
	var info := CosmeticsDB.get_item(body_id)
	penguin.setup({
		"body_color": info.get("body_color", Color(0.13, 0.16, 0.22)),
		"belly_color": info.get("belly_color", Color(0.95, 0.94, 0.9)),
	})
	penguin.position = pos
	penguin.scale = Vector3.ONE * rng.randf_range(0.7, 0.95)
	var flat_target := Vector3(look_target.x, pos.y, look_target.z)
	if flat_target.distance_squared_to(pos) > 0.01:
		penguin.look_at_from_position(pos, flat_target, Vector3.UP)
	penguin.set_pose(PenguinVisual.Pose.IDLE)
	parent.add_child(penguin)
	penguin.set_meta("spectator", true)


## Overhead bar that forces a belly slide (low ice tunnel hazard).
static func add_overhead_bar(parent: Node3D, guide: PathGuide, offset: float, clearance: float = 1.05) -> void:
	var xform := guide.transform_at(offset)
	var bar := StaticBody3D.new()
	bar.collision_layer = GameConfig.LAYER_WORLD
	bar.collision_mask = 0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(16.0, 1.3, 1.6)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = surface_material(SurfacesDB.Surface.ICE_ROUGH)
	bar.add_child(instance)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = mesh.size
	bar.add_child(shape)
	bar.transform = Transform3D(xform.basis, xform.origin + xform.basis.y * (clearance + mesh.size.y * 0.5))
	parent.add_child(bar)


static func add_boost_pad(parent: Node3D, guide: PathGuide, offset: float, lateral: float = 0.0) -> void:
	var xform := guide.transform_at(offset)
	var pad := Area3D.new()
	pad.collision_layer = GameConfig.LAYER_TRIGGERS
	pad.collision_mask = GameConfig.LAYER_RACERS
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4.0, 0.15, 6.0)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = surface_material(SurfacesDB.Surface.BOOST)
	pad.add_child(instance)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.0, 6.0)
	shape.shape = box
	pad.add_child(shape)
	pad.transform = Transform3D(xform.basis, xform.origin + xform.basis.x * lateral + xform.basis.y * 0.1)
	pad.body_entered.connect(func(body: Node3D) -> void:
		if body is Racer:
			(body as Racer).apply_boost(1.6, 1.5)
			AudioManager.play_sfx_3d("sfx_boost", body.global_position))
	parent.add_child(pad)
