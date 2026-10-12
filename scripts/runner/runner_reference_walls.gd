extends RefCounted
## Reference-blue barrier bays. Source deck, snow caps and warning tabs survive
## unchanged; only the old pale wall and raised coral strip are replaced.
## Cached once per imported mesh. One opaque surface, no frame callback/RNG.

const INNER_X := 5.40
const OUTER_X := 5.95
const BAY_LENGTH := 6.0
const SOURCE_BODY_TOP := 1.44
static var _decks: Dictionary = {}
static var _material: StandardMaterial3D

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.resource_name = "Runner reference blue wall paint"
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.53
		_material.metallic_specular = 0.20
		_material.emission_enabled = true
		_material.emission = Color("acd7f2")
		_material.emission_energy_multiplier = 0.035
	return _material

static func deck_mesh(source: Mesh) -> ArrayMesh:
	var key := source.get_rid().get_id()
	if _decks.has(key):
		return _decks[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for surface: int in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for triangle: int in range(0, count, 3):
			var ids := PackedInt32Array()
			for corner: int in 3:
				ids.append(indices[triangle + corner] if not indices.is_empty() else triangle + corner)
			if _old_wall_triangle(vertices[ids[0]], vertices[ids[1]], vertices[ids[2]],
					colours[ids[0]], colours[ids[1]], colours[ids[2]]):
				continue
			for index: int in ids:
				st.set_color(colours[index])
				st.set_normal(normals[index])
				st.set_uv(uvs[index])
				st.add_vertex(vertices[index])
	append_bays(st, BAY_LENGTH, SOURCE_BODY_TOP, 3.0)
	st.index()
	var result := st.commit()
	result.resource_name = "Reference blue bays: " + source.resource_name
	result.set_meta("runner_reference_walls", true)
	_decks[key] = result
	return result

static func _old_wall_triangle(a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> bool:
	# The wall lies outside the playable strip. Do not infer roles from UV cells:
	# authored face shading mapped some pale FROST faces into the DECK cell,
	# producing the alternating white/blue bays in the live course.
	var same_side := signf(a.x) == signf(b.x) and signf(b.x) == signf(c.x)
	var outside := minf(absf(a.x), minf(absf(b.x), absf(c.x))) >= 5.30
	var below_cap := maxf(a.y, maxf(b.y, c.y)) <= SOURCE_BODY_TOP + 0.001
	var snow := minf(ca.r, minf(cb.r, cc.r)) > 0.88 \
		and minf(ca.b, minf(cb.b, cc.b)) > 0.88
	return same_side and outside and below_cap and not snow

## Six-metre joints match the existing cassette boundaries. All front faces
## remain at x=+/-5.40; the insert sits 11 cm behind the frame, inside the wall.
## Fallback keeps its original cap height and outer drop face attachment.
static func append_bays(st: SurfaceTool, length: float, body_top: float,
		start_z: float = 0.0, outer_bottom: float = 0.0) -> void:
	var scale_y := body_top / SOURCE_BODY_TOP
	for side: float in [-1.0, 1.0]:
		for bay: int in roundi(length / BAY_LENGTH):
			var z0 := start_z - float(bay + 1) * BAY_LENGTH
			var z1 := z0 + BAY_LENGTH
			var blue := Color("2386bb").srgb_to_linear()
			var rail := Color("328fc3").srgb_to_linear()
			var post := Color("23668f").srgb_to_linear()
			var dark := Color("09243a").srgb_to_linear()
			var rim := Color("56383b").srgb_to_linear()
			# Backing front, outer face and ends close the recessed body without
			# overlapping the fallback's separate drop-off surface below it.
			_face(st, Vector3(5.53, 0, z0), Vector3(5.53, body_top, z0),
				Vector3(5.53, body_top, z1), Vector3(5.53, 0, z1), side, Vector3.LEFT, blue)
			_face(st, Vector3(OUTER_X, outer_bottom, z1), Vector3(OUTER_X, body_top, z1),
				Vector3(OUTER_X, body_top, z0), Vector3(OUTER_X, outer_bottom, z0), side, Vector3.RIGHT, post)
			_box(st, Vector3(INNER_X, 0, z0), Vector3(5.53, 0.28 * scale_y, z1), side, blue)
			_box(st, Vector3(INNER_X, 0.91 * scale_y, z0), Vector3(5.53, body_top, z1), side, rail)
			for joint_z: float in [z0, z1 - 0.16]:
				_box(st, Vector3(INNER_X, 0, joint_z), Vector3(5.53, body_top, joint_z + 0.16), side, post)
			# Inset is dark blue with restrained warm edging, never a bright red
			# hazard strip. Real depth/shadows distinguish it from a painted decal.
			_box(st, Vector3(5.510, 0.29 * scale_y, z0 + 0.18),
				Vector3(5.526, 0.90 * scale_y, z1 - 0.18), side, rim)
			_box(st, Vector3(5.505, 0.315 * scale_y, z0 + 0.205),
				Vector3(5.520, 0.875 * scale_y, z1 - 0.205), side, dark)
			# Narrow bevel highlight and shadow line give the wide upper rail
			# thickness while retaining the source cap and irregular snow pillows.
			_box(st, Vector3(INNER_X - 0.004, 1.28 * scale_y, z0 + 0.16),
				Vector3(INNER_X, 1.315 * scale_y, z1 - 0.16), side,
				Color("67b6dc").srgb_to_linear())

static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, side: float, colour: Color) -> void:
	var p: Array[Vector3] = [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	_face(st, p[0], p[1], p[5], p[4], side, Vector3.FORWARD, colour * Color(0.8, 0.85, 0.9))
	_face(st, p[2], p[3], p[7], p[6], side, Vector3.BACK, colour)
	_face(st, p[1], p[2], p[6], p[5], side, Vector3.RIGHT, colour)
	_face(st, p[3], p[0], p[4], p[7], side, Vector3.LEFT, colour)
	_face(st, p[4], p[5], p[6], p[7], side, Vector3.UP, colour.lightened(0.04))
	_face(st, p[3], p[2], p[1], p[0], side, Vector3.DOWN, colour)

static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		side: float, normal: Vector3, colour: Color) -> void:
	var points := PackedVector3Array([a, b, c, d])
	for i: int in points.size():
		points[i].x *= side
	normal.x *= side
	var order := [0, 1, 2, 0, 2, 3]
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i: int in order:
		st.set_color(colour)
		st.set_normal(normal)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(points[i])
