class_name TrackBuilder
extends RefCounted
## Generates track ribbon meshes, walls, water channels, and shared course
## props from control-point lists. All geometry is procedural; collision uses
## trimesh shapes with surface metadata for the racer's surface detection.

const SAMPLE: float = 3.0
## Metres over which the frosted white end-border of an ice run fades out
## (encoded per-vertex into UV2.x for the ice shader's accessibility outline).
const FROST_END_RANGE: float = 2.5

const ICE_SHADER: Shader = preload("res://assets/shaders/ice.gdshader")
const ICE_WALL_SHADER: Shader = preload("res://assets/shaders/ice_wall.gdshader")
const BOOST_PAD_SHADER: Shader = preload("res://assets/shaders/boost_pad.gdshader")

static var _surface_materials: Dictionary = {}


static func surface_material(surface: SurfacesDB.Surface) -> Material:
	if _surface_materials.has(surface):
		var cached: Material = _surface_materials[surface]
		# detail_level is quality-derived: refresh on reuse so a preset change
		# (settings menu or the web auto-governor) reaches the cached ice
		# shaders on the next course build. Uniform write only — no recompile.
		if cached is ShaderMaterial and surface != SurfacesDB.Surface.BOOST:
			(cached as ShaderMaterial).set_shader_parameter("detail_level", VisualLibrary.shader_detail_level())
		return cached
	var mat: Material
	match surface:
		SurfacesDB.Surface.PACKED_SNOW:
			var snow_mat := StandardMaterial3D.new()
			snow_mat.albedo_color = Color(0.93, 0.96, 1.0)
			snow_mat.roughness = 0.95
			mat = snow_mat
		SurfacesDB.Surface.DEEP_SNOW:
			var deep_mat := StandardMaterial3D.new()
			deep_mat.albedo_color = Color(0.99, 0.99, 1.0)
			deep_mat.roughness = 1.0
			mat = deep_mat
		SurfacesDB.Surface.ICE_SMOOTH:
			# Deep glossy blue-cyan glass: voronoi crack veins, toward-camera
			# sun streak, frosted white edge border (shader outlines patches by
			# brightness + pattern, so ice reads without relying on hue).
			var ice_mat := ShaderMaterial.new()
			ice_mat.shader = ICE_SHADER
			ice_mat.set_shader_parameter("tint", Color(0.34, 0.71, 0.96))
			ice_mat.set_shader_parameter("deep_tint", Color(0.03, 0.22, 0.47))
			ice_mat.set_shader_parameter("clarity", 0.92)
			ice_mat.set_shader_parameter("roughness_base", 0.05)
			ice_mat.set_shader_parameter("crack_strength", 0.75)
			ice_mat.set_shader_parameter("streak_strength", 0.85)
			ice_mat.set_shader_parameter("detail_level", VisualLibrary.shader_detail_level())
			mat = ice_mat
		SurfacesDB.Surface.ICE_ROUGH:
			# Frosted matte variant: paler, rougher, fainter cracks/streak so
			# smooth vs rough ice contrast reads at a glance.
			var rice_mat := ShaderMaterial.new()
			rice_mat.shader = ICE_SHADER
			rice_mat.set_shader_parameter("tint", Color(0.6, 0.77, 0.92))
			rice_mat.set_shader_parameter("deep_tint", Color(0.18, 0.36, 0.55))
			rice_mat.set_shader_parameter("clarity", 0.35)
			rice_mat.set_shader_parameter("roughness_base", 0.4)
			rice_mat.set_shader_parameter("crack_strength", 0.5)
			rice_mat.set_shader_parameter("streak_strength", 0.25)
			rice_mat.set_shader_parameter("detail_level", VisualLibrary.shader_detail_level())
			mat = rice_mat
		SurfacesDB.Surface.BOOST:
			# Pulsing amber deck with hazard-striped border (see
			# boost_pad.gdshader) — pattern + brightness accessibility.
			var boost_mat := ShaderMaterial.new()
			boost_mat.shader = BOOST_PAD_SHADER
			boost_mat.set_shader_parameter("contrast_boost", _contrast_boost())
			mat = boost_mat
		_:
			var plain_mat := StandardMaterial3D.new()
			plain_mat.albedo_color = Color(0.9, 0.94, 1.0)
			plain_mat.roughness = 0.9
			mat = plain_mat
	_surface_materials[surface] = mat
	return mat


## 1.0 when "accessibility/high_contrast_pickups" is on. Boost pad shaders
## brighten their cores/outlines from this; re-applied on every add_boost_pad
## so cached materials track setting changes between races.
static func _contrast_boost() -> float:
	return 1.0 if bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups")) else 0.0


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
		_floor_quad(st, left[i], right[i], right[i + 1], left[i + 1], u0, u1,
				_frost_end_proximity(i, start, end), _frost_end_proximity(i + 1, start, end))
	st.generate_normals()
	var mesh := st.commit()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	# Snow/ice floors get the shader treatment (procedural detail + sparkle /
	# fresnel); other surfaces keep the classic flat material via fallback.
	instance.material_override = VisualLibrary.track_surface_material(surface)
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
		_wall_quad(st, a, a + height, b + height, b, not is_left)
	if not any:
		return
	st.generate_normals()
	var mesh := st.commit()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	# Glacial barrier shader: strata pattern + fresnel rim + bright frosted
	# crest lip, so the wall boundary reads by brightness/pattern (visual only;
	# collision below is unchanged).
	instance.material_override = _wall_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = make_solid_shape(mesh)
	body.add_child(shape)
	root.add_child(body)


static var _wall_material_cache: ShaderMaterial = null


static func _wall_material() -> ShaderMaterial:
	if _wall_material_cache == null:
		_wall_material_cache = ShaderMaterial.new()
		_wall_material_cache.shader = ICE_WALL_SHADER
	return _wall_material_cache


## Wall quad with UV.x = 0 at the base and 1 at the crest on BOTH track sides
## (the ice_wall shader's frost lip keys off UV.x, so it must never invert);
## flip reverses the triangle winding so the visible face looks into the track.
static func _wall_quad(st: SurfaceTool, base0: Vector3, top0: Vector3, top1: Vector3, base1: Vector3, flip: bool) -> void:
	if flip:
		_wall_vert(st, top0, 1.0, 0.0); _wall_vert(st, top1, 1.0, 1.0); _wall_vert(st, base1, 0.0, 1.0)
		_wall_vert(st, top0, 1.0, 0.0); _wall_vert(st, base1, 0.0, 1.0); _wall_vert(st, base0, 0.0, 0.0)
	else:
		_wall_vert(st, base0, 0.0, 0.0); _wall_vert(st, base1, 0.0, 1.0); _wall_vert(st, top1, 1.0, 1.0)
		_wall_vert(st, base0, 0.0, 0.0); _wall_vert(st, top1, 1.0, 1.0); _wall_vert(st, top0, 1.0, 0.0)


static func _wall_vert(st: SurfaceTool, v: Vector3, height_uv: float, along_uv: float) -> void:
	st.set_uv(Vector2(height_uv, along_uv))
	st.add_vertex(v)


## Visual-only side skirts so the track reads as thick ice, not paper.
## Vertex colors grade from a bright sunlit lip at the track edge down to deep
## glacial blue where light dies — a grayscale-safe thickness cue that matches
## the ice shader's depth language, for zero shader cost.
static func _emit_skirt(root: Node3D, left: PackedVector3Array, right: PackedVector3Array, gaps: Array[bool] = []) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drop := Vector3.DOWN * 10.0
	var out := 2.0
	var lip_col := Color(0.88, 0.93, 1.0)
	var deep_col := Color(0.15, 0.34, 0.52)
	for i: int in left.size() - 1:
		if not gaps.is_empty() and (gaps[i] or gaps[i + 1]):
			continue
		var dir_l := (left[i] - right[i]).normalized() * out
		var dir_l2 := (left[i + 1] - right[i + 1]).normalized() * out
		_color_quad(st, left[i], left[i] + dir_l + drop, left[i + 1] + dir_l2 + drop, left[i + 1],
				lip_col, deep_col, deep_col, lip_col)
		_color_quad(st, right[i] - dir_l + drop, right[i], right[i + 1], right[i + 1] - dir_l2 + drop,
				deep_col, lip_col, lip_col, deep_col)
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = _skirt_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)


static var _skirt_material_cache: StandardMaterial3D = null


## Shared skirt material: identical for every ribbon, so every skirt (main
## line + branches, all courses) reuses ONE material/pipeline instead of
## minting a fresh WebGL program per track build.
static func _skirt_material() -> StandardMaterial3D:
	if _skirt_material_cache == null:
		_skirt_material_cache = StandardMaterial3D.new()
		_skirt_material_cache.albedo_color = Color.WHITE
		_skirt_material_cache.vertex_color_use_as_albedo = true
		_skirt_material_cache.roughness = 0.6
		_skirt_material_cache.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _skirt_material_cache


## 0..1 proximity of a sample row to its surface run's start/end boundary,
## fading over FROST_END_RANGE metres. Rows outside the run (the one-sample
## seam overlap) clamp to 1 so the frost band sits exactly on the boundary.
static func _frost_end_proximity(row: int, start: int, end: int) -> float:
	var dist_m := minf(float(row - start), float(end - row)) * SAMPLE
	return clampf(1.0 - dist_m / FROST_END_RANGE, 0.0, 1.0)


## Floor variant of _quad: also writes UV2 = (end-frost proximity, 1.0).
## UV2.y == 1 flags "track floor" for the ice shader's frosted edge border;
## meshes that never set UV2 read (0,0) and stay frost-free.
static func _floor_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u0: float, u1: float, e0: float, e1: float) -> void:
	st.set_uv(Vector2(0, u0)); st.set_uv2(Vector2(e0, 1.0)); st.add_vertex(a)
	st.set_uv(Vector2(0, u1)); st.set_uv2(Vector2(e1, 1.0)); st.add_vertex(d)
	st.set_uv(Vector2(1, u1)); st.set_uv2(Vector2(e1, 1.0)); st.add_vertex(c)
	st.set_uv(Vector2(0, u0)); st.set_uv2(Vector2(e0, 1.0)); st.add_vertex(a)
	st.set_uv(Vector2(1, u1)); st.set_uv2(Vector2(e1, 1.0)); st.add_vertex(c)
	st.set_uv(Vector2(1, u0)); st.set_uv2(Vector2(e0, 1.0)); st.add_vertex(b)


## _quad with per-corner vertex colors (same corner order and winding); used by
## the skirt's depth gradient. Pair with vertex_color_use_as_albedo materials.
static func _color_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	st.set_color(ca); st.add_vertex(a)
	st.set_color(cd); st.add_vertex(d)
	st.set_color(cc); st.add_vertex(c)
	st.set_color(ca); st.add_vertex(a)
	st.set_color(cc); st.add_vertex(c)
	st.set_color(cb); st.add_vertex(b)


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
	water_mesh.material_override = _water_surface_material()
	root.add_child(water_mesh)

	floor_st.generate_normals()
	var floor_mesh_instance := MeshInstance3D.new()
	floor_mesh_instance.mesh = floor_st.commit()
	floor_mesh_instance.material_override = VisualLibrary.rock_material(Color(0.1, 0.28, 0.42), 1.0)
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


static var _water_surface_material_cache: StandardMaterial3D = null


## Shared translucent water ribbon material (channels share one instance;
## courses that restyle water swap material_override afterward).
static func _water_surface_material() -> StandardMaterial3D:
	if _water_surface_material_cache == null:
		_water_surface_material_cache = StandardMaterial3D.new()
		_water_surface_material_cache.albedo_color = Color(0.15, 0.42, 0.62, 0.78)
		_water_surface_material_cache.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_surface_material_cache.roughness = 0.05
		_water_surface_material_cache.metallic = 0.3
		_water_surface_material_cache.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _water_surface_material_cache


static func _on_water_entered(body: Node3D, area: Area3D, surface_y: float) -> void:
	if body is Racer:
		(body as Racer).enter_water(area, surface_y)


static func _on_water_exited(body: Node3D, area: Area3D) -> void:
	if body is Racer:
		(body as Racer).exit_water(area)


## --- Shared props ----------------------------------------------------------

static func prop_material(color: Color, rough: float = 0.8) -> StandardMaterial3D:
	return PenguinVisual.get_material(color, 0.0, rough)


static var _flag_pole_mesh: CylinderMesh = null
static var _flag_finial_mesh: SphereMesh = null


static func add_flag(parent: Node3D, pos: Vector3, color: Color = Color(0.9, 0.25, 0.3)) -> void:
	if _flag_pole_mesh == null:
		_flag_pole_mesh = CylinderMesh.new()
		_flag_pole_mesh.top_radius = 0.05
		_flag_pole_mesh.bottom_radius = 0.07
		_flag_pole_mesh.height = 3.0
		_flag_finial_mesh = SphereMesh.new()
		_flag_finial_mesh.radius = 0.09
		_flag_finial_mesh.height = 0.18
		_flag_finial_mesh.radial_segments = 12
		_flag_finial_mesh.rings = 6
	var pole := MeshInstance3D.new()
	pole.mesh = _flag_pole_mesh
	pole.material_override = prop_material(Color(0.5, 0.35, 0.2))
	pole.position = pos + Vector3.UP * 1.5
	VisualLibrary.apply_dressing_range(pole)
	parent.add_child(pole)
	var finial := MeshInstance3D.new()
	finial.mesh = _flag_finial_mesh
	finial.material_override = prop_material(Color(0.85, 0.72, 0.35))
	finial.position = pos + Vector3.UP * 3.05
	VisualLibrary.apply_dressing_range(finial)
	parent.add_child(finial)
	var flag := MeshInstance3D.new()
	flag.mesh = _pennant_mesh()
	var flag_mat := prop_material(color)
	flag.material_override = flag_mat
	flag.position = pos + Vector3.UP * 2.85
	VisualLibrary.apply_dressing_range(flag)
	parent.add_child(flag)


## Gently curved double-sided pennant built once and shared.
static var _pennant_cache: ArrayMesh = null
static func _pennant_mesh() -> ArrayMesh:
	if _pennant_cache != null:
		return _pennant_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Tapered pennant: 4 segments from hoist (full height) to a point, each
	# segment swept back with a slight sine curl so it reads as cloth.
	var segs := 4
	var length := 1.15
	var half_h := 0.24
	var prev_top := Vector3(0.0, half_h, 0.0)
	var prev_bot := Vector3(0.0, -half_h, 0.0)
	for i: int in segs:
		var t := float(i + 1) / float(segs)
		var x := length * t
		var z := sin(t * PI) * 0.10
		var h := half_h * (1.0 - t)
		var top := Vector3(x, h, z)
		var bot := Vector3(x, -h, z)
		for tri: Array in [[prev_top, prev_bot, top], [prev_bot, bot, top]]:
			for v: Vector3 in tri:
				st.add_vertex(v)
		for tri: Array in [[prev_top, top, prev_bot], [prev_bot, top, bot]]:
			for v: Vector3 in tri:
				st.add_vertex(v)
		prev_top = top
		prev_bot = bot
	st.generate_normals()
	_pennant_cache = st.commit()
	return _pennant_cache


static var _rock_mesh: SphereMesh = null
static var _rock_cap_mesh: SphereMesh = null


static func add_rock(parent: Node3D, pos: Vector3, scale_factor: float = 1.0, rng: RandomNumberGenerator = null) -> void:
	# Shared unit meshes, sized per instance via node scale — one rock mesh +
	# one cap mesh for every rock in the game instead of two per call.
	if _rock_mesh == null:
		_rock_mesh = SphereMesh.new()
		_rock_mesh.radius = 0.8
		_rock_mesh.height = 1.1
		_rock_mesh.radial_segments = 8
		_rock_mesh.rings = 5
		_rock_cap_mesh = SphereMesh.new()
		_rock_cap_mesh.radius = 0.7
		_rock_cap_mesh.height = 0.5
	var rock := MeshInstance3D.new()
	rock.mesh = _rock_mesh
	rock.material_override = prop_material(Color(0.45, 0.48, 0.54))
	rock.position = pos + Vector3.UP * 0.3 * scale_factor
	rock.scale = Vector3.ONE * scale_factor
	if rng != null:
		rock.rotation.y = rng.randf() * TAU
		rock.scale = Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.6, 1.0), rng.randf_range(0.8, 1.4)) * scale_factor
	VisualLibrary.apply_dressing_range(rock)
	parent.add_child(rock)
	# Snow cap.
	var cap := MeshInstance3D.new()
	cap.mesh = _rock_cap_mesh
	cap.material_override = prop_material(Color(0.96, 0.98, 1.0))
	cap.position = pos + Vector3.UP * 0.75 * scale_factor
	cap.scale = rock.scale
	VisualLibrary.apply_dressing_range(cap)
	parent.add_child(cap)


static var _crystal_mesh: CylinderMesh = null
static var _crystal_materials: Dictionary = {}


static func add_ice_crystal(parent: Node3D, pos: Vector3, height: float = 3.0, color: Color = Color(0.55, 0.85, 1.0)) -> void:
	# Shared unit spike (bottom_radius/height ratio preserved) scaled per node,
	# plus one cached transparent material per tint. Transparent uniques are
	# the most expensive kind of material explosion on WebGL — endless mode
	# used to mint one per crystal spawned mid-run.
	if _crystal_mesh == null:
		_crystal_mesh = CylinderMesh.new()
		_crystal_mesh.top_radius = 0.0
		_crystal_mesh.bottom_radius = 0.16
		_crystal_mesh.height = 1.0
		_crystal_mesh.radial_segments = 5
	var crystal := MeshInstance3D.new()
	crystal.mesh = _crystal_mesh
	crystal.material_override = _crystal_material(color)
	crystal.scale = Vector3.ONE * height
	crystal.position = pos + Vector3.UP * height * 0.5
	VisualLibrary.apply_dressing_range(crystal)
	parent.add_child(crystal)


static func _crystal_material(color: Color) -> StandardMaterial3D:
	var key := "crystal_%s" % color.to_html()
	if _crystal_materials.has(key):
		return _crystal_materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.rim_enabled = true
	mat.rim = 0.6
	_crystal_materials[key] = mat
	return mat


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


static var _bar_mesh: BoxMesh = null
static var _bar_shape: BoxShape3D = null


## Overhead bar that forces a belly slide (low ice tunnel hazard).
static func add_overhead_bar(parent: Node3D, guide: PathGuide, offset: float, clearance: float = 1.05) -> void:
	if _bar_mesh == null:
		_bar_mesh = BoxMesh.new()
		_bar_mesh.size = Vector3(16.0, 1.3, 1.6)
		_bar_shape = BoxShape3D.new()
		_bar_shape.size = _bar_mesh.size
	var xform := guide.transform_at(offset)
	var bar := StaticBody3D.new()
	bar.collision_layer = GameConfig.LAYER_WORLD
	bar.collision_mask = 0
	var instance := MeshInstance3D.new()
	instance.mesh = _bar_mesh
	instance.material_override = surface_material(SurfacesDB.Surface.ICE_ROUGH)
	bar.add_child(instance)
	var shape := CollisionShape3D.new()
	shape.shape = _bar_shape
	bar.add_child(shape)
	bar.transform = Transform3D(xform.basis, xform.origin + xform.basis.y * (clearance + _bar_mesh.size.y * 0.5))
	parent.add_child(bar)


static var _arrow_material: ShaderMaterial = null
static var _pad_rim_mesh: ArrayMesh = null
static var _pad_rim_material: StandardMaterial3D = null


static func _boost_arrow_material() -> ShaderMaterial:
	if _arrow_material == null:
		_arrow_material = ShaderMaterial.new()
		_arrow_material.shader = load("res://assets/shaders/boost_arrows.gdshader")
	return _arrow_material


## Raised curb frame around the boost pad deck: a physical SHAPE cue that
## catches real light and shadow, so pads still read if every color/emission
## cue fails (grayscale, extreme glare, any color-vision condition).
## Rings: inner deck lip -> raised crest -> outer skirt tucked into the track.
## Visual only — sized around the 4x0.15x6 deck without touching the deck mesh
## or the Area3D trigger box.
static func _boost_rim_mesh() -> ArrayMesh:
	if _pad_rim_mesh != null:
		return _pad_rim_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# (half_x, y, half_z) per ring; vertex colors grade lip -> bright crest ->
	# shadowed outer base so the curb reads as raised relief from any angle.
	var rings: Array[Vector3] = [
		Vector3(2.0, 0.075, 3.0),
		Vector3(2.14, 0.17, 3.14),
		Vector3(2.3, -0.12, 3.3),
	]
	var ring_cols: Array[Color] = [
		Color(0.86, 0.92, 1.0),
		Color(0.98, 0.99, 1.0),
		Color(0.6, 0.72, 0.88),
	]
	for r: int in rings.size() - 1:
		var pa := _rect_corners(rings[r])
		var pb := _rect_corners(rings[r + 1])
		for i: int in 4:
			var j := (i + 1) % 4
			_color_quad(st, pa[i], pa[j], pb[j], pb[i],
					ring_cols[r], ring_cols[r], ring_cols[r + 1], ring_cols[r + 1])
	st.generate_normals()
	_pad_rim_mesh = st.commit()
	return _pad_rim_mesh


## (half_x, y, half_z) -> the 4 rectangle corners at that height, CCW from above.
static func _rect_corners(ext: Vector3) -> Array[Vector3]:
	var pts: Array[Vector3] = [
		Vector3(ext.x, ext.y, ext.z),
		Vector3(-ext.x, ext.y, ext.z),
		Vector3(-ext.x, ext.y, -ext.z),
		Vector3(ext.x, ext.y, -ext.z),
	]
	return pts


static func _boost_rim_material() -> StandardMaterial3D:
	if _pad_rim_material == null:
		_pad_rim_material = StandardMaterial3D.new()
		_pad_rim_material.albedo_color = Color.WHITE
		_pad_rim_material.vertex_color_use_as_albedo = true
		_pad_rim_material.roughness = 0.45
		_pad_rim_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Faint constant ice-white glow keeps the frame legible at night.
		_pad_rim_material.emission_enabled = true
		_pad_rim_material.emission = Color(0.85, 0.92, 1.0)
		_pad_rim_material.emission_energy_multiplier = 0.18
	return _pad_rim_material


static var _pad_deck_mesh: BoxMesh = null
static var _pad_arrow_mesh: PlaneMesh = null
static var _pad_trigger_shape: BoxShape3D = null


static func add_boost_pad(parent: Node3D, guide: PathGuide, offset: float, lateral: float = 0.0) -> void:
	if _pad_deck_mesh == null:
		_pad_deck_mesh = BoxMesh.new()
		_pad_deck_mesh.size = Vector3(4.0, 0.15, 6.0)
		_pad_arrow_mesh = PlaneMesh.new()
		_pad_arrow_mesh.size = Vector2(3.6, 5.6)
		_pad_trigger_shape = BoxShape3D.new()
		_pad_trigger_shape.size = Vector3(4.0, 2.0, 6.0)
	var xform := guide.transform_at(offset)
	var pad := Area3D.new()
	pad.collision_layer = GameConfig.LAYER_TRIGGERS
	pad.collision_mask = GameConfig.LAYER_RACERS
	var instance := MeshInstance3D.new()
	instance.mesh = _pad_deck_mesh
	instance.material_override = surface_material(SurfacesDB.Surface.BOOST)
	pad.add_child(instance)
	var arrows := MeshInstance3D.new()
	arrows.mesh = _pad_arrow_mesh
	arrows.material_override = _boost_arrow_material()
	arrows.position = Vector3(0.0, _pad_deck_mesh.size.y * 0.5 + 0.03, 0.0)
	arrows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad.add_child(arrows)
	var rim := MeshInstance3D.new()
	rim.mesh = _boost_rim_mesh()
	rim.material_override = _boost_rim_material()
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad.add_child(rim)
	# Refresh accessibility contrast on the cached pad shaders so toggling the
	# setting applies to the next course build without an app restart.
	var contrast := _contrast_boost()
	(instance.material_override as ShaderMaterial).set_shader_parameter("contrast_boost", contrast)
	_boost_arrow_material().set_shader_parameter("contrast_boost", contrast)
	var shape := CollisionShape3D.new()
	shape.shape = _pad_trigger_shape
	pad.add_child(shape)
	pad.transform = Transform3D(xform.basis, xform.origin + xform.basis.x * lateral + xform.basis.y * 0.1)
	pad.body_entered.connect(func(body: Node3D) -> void:
		if body is Racer:
			(body as Racer).apply_boost(1.6, 1.5)
			AudioManager.play_sfx_3d("sfx_boost", body.global_position))
	parent.add_child(pad)
