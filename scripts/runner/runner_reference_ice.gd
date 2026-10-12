class_name RunnerReferenceIce
extends RefCounted
## Geometry-only response to the approved in-run ice references. These cached
## opaque meshes use real facets and snow-facing planes, never image billboards.
## No gameplay random stream, collider, texture, or per-frame allocation.

static var _block: ArrayMesh
static var _ridge: ArrayMesh
static var _sea: Dictionary = {}
static var _material: StandardMaterial3D

static func block_mesh() -> ArrayMesh:
	if _block == null:
		_block = _chunk(Vector3(2.3, 2.0, 1.5))
	return _block

static func ridge_mesh() -> ArrayMesh:
	if _ridge == null:
		_ridge = _chunk(Vector3(1.0, 0.8, 1.15))
	return _ridge

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.albedo_color = Color.WHITE
		_material.roughness = 0.40
		_material.metallic_specular = 0.22
		_material.emission_enabled = true
		_material.emission = Color("c5eaff")
		_material.emission_energy_multiplier = 0.055
	return _material

## Keep the approved five-mass imported topology and triangle budget. Broaden
## the shoreline silhouette, lower its rounded crown, and replace steel-atlas
## colours with the reference's blue fracture planes and bright snow caps.
static func sea_mesh(source: Mesh) -> ArrayMesh:
	var key := source.get_rid().get_id()
	if _sea.has(key):
		return _sea[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := source.get_faces()
	var height := source.get_aabb().size.y
	for i: int in range(0, faces.size(), 3):
		var a := _sea_point(faces[i])
		var b := _sea_point(faces[i + 1])
		var c := _sea_point(faces[i + 2])
		var normal := (c - a).cross(b - a).normalized()
		var centre := (a + b + c) / 3.0
		var snowy := normal.y > 0.38 or centre.y > height * 0.72
		var tone := _face_colour(normal, i / 3, snowy)
		_emit(st, a, b, c, tone)
	var mesh := st.commit()
	_sea[key] = mesh
	return mesh

static func _sea_point(v: Vector3) -> Vector3:
	# Ground pivot and waterline stay exact; only art silhouette changes.
	return Vector3(v.x * 1.13, v.y * 0.90, v.z * 1.08)

static func _chunk(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A rounded snow boulder: narrow foot, widest fractured middle, small
	# irregular crown. The middle ring keeps the full collider envelope exact;
	# tapering both ends avoids a rectangular blue stump with a flat white roof.
	var outline := [Vector2(-1.0, -0.54), Vector2(-0.57, -1.0),
		Vector2(0.48, -1.0), Vector2(1.0, -0.43), Vector2(1.0, 0.51),
		Vector2(0.53, 1.0), Vector2(-0.61, 1.0), Vector2(-1.0, 0.40)]
	var radii := [0.48, 0.86, 1.0, 0.76, 0.30]
	var heights := [0.0, 0.18, 0.49, 0.80, 0.95]
	var rings: Array[PackedVector3Array] = []
	for row: int in heights.size():
		var ring := PackedVector3Array()
		for side: int in outline.size():
			var p: Vector2 = outline[side]
			var dy := sin(float(side * 7 + row * 11)) * (0.018 if row == 4 else 0.045) if row > 0 else 0.0
			var offset := Vector2(-0.065, 0.06) * float(row) / 4.0 if row > 2 else Vector2.ZERO
			ring.append(Vector3((p.x * radii[row] + offset.x) * size.x * 0.5,
				(heights[row] + dy) * size.y, (p.y * radii[row] + offset.y) * size.z * 0.5))
		rings.append(ring)
	for row: int in 4:
		for side: int in 8:
			var next := (side + 1) % 8
			var a := rings[row][side]
			var b := rings[row][next]
			var c := rings[row + 1][next]
			var d := rings[row + 1][side]
			var outward := Vector3(a.x, 0.12, a.z).normalized()
			# Snow wraps the shoulder and most mid-faces. Sparse lower fracture
			# planes remain blue; the water ice derivative keeps its own palette.
			_face(st, a, b, c, outward, row * 16 + side * 2,
				row >= 1 and not (row == 1 and side % 4 == 0))
			_face(st, a, c, d, outward, row * 16 + side * 2 + 1,
				row >= 1 and not (row == 1 and side % 3 == 0))
	for side: int in 8:
		_face(st, rings[4][side], rings[4][(side + 1) % 8],
			Vector3(-0.02 * size.x, size.y, 0.015 * size.z), Vector3.UP, side, true)
		_face(st, rings[0][(side + 1) % 8], rings[0][side],
			Vector3.ZERO, Vector3.DOWN, side, false)
	return st.commit()

static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		outward: Vector3, index: int, snowy: bool) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
	var normal := (c - a).cross(b - a).normalized()
	_emit(st, a, b, c, _face_colour(normal, index, snowy))

static func _face_colour(normal: Vector3, index: int, snowy: bool) -> Color:
	if snowy:
		return Color("f5fcff").lerp(Color("c6e9ff"), 0.12 * float(posmod(index, 3))).srgb_to_linear()
	var t := clampf(0.42 + normal.x * 0.22 + normal.y * 0.20 + 0.13 * sin(float(index) * 2.3), 0.12, 0.86)
	return Color("218cd6").lerp(Color("8fdbff"), t).srgb_to_linear()

static func _emit(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for p: Vector3 in [a, b, c]:
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(p)
