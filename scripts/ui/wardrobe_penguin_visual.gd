extends PenguinVisual
## Dressing-room adapter for the existing authored hero. Gameplay keeps its
## chosen backend. Correct the Blender socket coordinate convention locally;
## garments remain genuine geometry attached to the animated skeleton.

const SOCKET_TARGETS := {
	"head_socket": Vector3(0, 1.76, -0.02),
	# Eye centers are authored at height1.545; the goggle outline's center
	# adds 0.029 gameplay meters to this socket (1.49*0.54+0.029=0.834).
	"face_socket": Vector3(0, 1.49, -0.64),
	"neck_socket": Vector3(0, 1.22, 0),
	"trail_socket": Vector3(0, 0.38, 0.35),
}
const KNIT := preload("res://scripts/shaders/wardrobe_knit.gdshader")
# Exact authored shape-key profiles from create_species_shapes() in
# tools/art/build_hero_penguin_v1.py: width, height, depth, head shift.
# Shape keys move vertices, not socket bones, so attachments must follow too.
const SPECIES_FIT := {
	"emperor": Vector4(1, 1, 1, 0), "king": Vector4(0.94, 1.055, 0.97, 0),
	"adelie": Vector4(0.92, 0.91, 1.04, 0.015), "gentoo": Vector4(1.02, 0.98, 1.02, -0.010),
	"chinstrap": Vector4(0.95, 0.94, 1, 0.008), "rockhopper": Vector4(0.92, 0.88, 1.04, 0.022),
	"macaroni": Vector4(0.98, 0.93, 1.04, 0.018), "little_blue": Vector4(0.80, 0.74, 0.90, 0.026),
}


func _try_enable_authored_backend(_config: Dictionary, species_id: String) -> void:
	var rig := _instantiate_authored_backend() as HeroPenguinRig
	if rig == null:
		return
	rig.name = "WardrobeAuthoredPenguin"
	rig.scale = Vector3.ONE * AUTHORED_HERO_GAME_SCALE
	add_child(rig)
	rig.configure(species_id, _ident)
	if not rig.missing_contract_items().is_empty():
		rig.queue_free()
		return
	_authored_backend = rig
	rig.set_pose(int(pose))
	for socket_id: String in SOCKET_TARGETS:
		var exported := rig.get_socket(StringName(socket_id))
		var fitted := Node3D.new()
		fitted.name = "Wardrobe_%s" % socket_id
		exported.add_child(fitted)
		# Existing accessories are measured in gameplay meters. The authored
		# model is 1.94m before its 0.54 scale and exports sockets with a +90 X
		# basis. Cancel both conventions in the child, retaining bone motion.
		var profile: Vector4 = SPECIES_FIT[species_id]
		var point: Vector3 = SOCKET_TARGETS[socket_id]
		var head_factor := smoothstep(1.12, 1.32, point.y)
		var fit := Vector3(lerpf(profile.x, profile.z, head_factor * 0.32), profile.y, profile.z)
		point = point * fit + Vector3(0, profile.w * head_factor, 0)
		var target := Transform3D(Basis.IDENTITY.scaled(fit / AUTHORED_HERO_GAME_SCALE), point)
		fitted.transform = exported.global_transform.affine_inverse() * rig.global_transform * target
		_authored_sockets[socket_id] = fitted
	_add_species_crest(species_id)
	_set_authored_lod_visible(true, true)


func _add_species_crest(species_id: String) -> void:
	if species_id not in ["rockhopper", "macaroni"]:
		return
	var head := get_socket(&"head_socket")
	var color := Color("efbd27") if species_id == "rockhopper" else Color("ee981b")
	for side: float in [-1.0, 1.0]:
		for i: int in 6:
			var feather := CylinderMesh.new()
			feather.top_radius = 0.0015
			feather.bottom_radius = 0.009
			feather.height = 0.16 + i * 0.007
			feather.radial_segments = 10
			var fan := (48.0 + i * 8.0) if species_id == "rockhopper" else (68.0 + i * 7.0)
			_mesh(head, feather, color, Vector3(side * (0.07 + i * 0.009), 0.005 - i * 0.004, -0.10),
				Vector3(-0.28, 0, deg_to_rad(-fan * side)), Vector3.ONE, get_material(color, 0, 0.78))


func _apply_cosmetic(id: String) -> void:
	if id.is_empty():
		return
	var info := CosmeticsDB.get_item(id)
	var color: Color = info.get("color", Color.WHITE)
	var face := get_socket(&"face_socket")
	var neck := get_socket(&"neck_socket")
	if id == "goggles_ski":
		var outline := PackedVector2Array([
			Vector2(-0.16, 0.045), Vector2(-0.13, 0.072), Vector2(0, 0.066),
			Vector2(0.13, 0.072), Vector2(0.16, 0.045), Vector2(0.15, -0.018),
			Vector2(0.105, -0.044), Vector2(0.055, -0.035), Vector2(0, 0.005),
			Vector2(-0.055, -0.035), Vector2(-0.105, -0.044), Vector2(-0.15, -0.018)])
		_mesh(face, _soft_prism(outline, 0.035), Color("132e43"), Vector3(0, 0.015, 0))
		var inner := PackedVector2Array()
		for point: Vector2 in outline:
			inner.append(point * Vector2(0.90, 0.79))
		_mesh(face, _soft_prism(inner, 0.012), Color("167893"), Vector3(0, 0.016, -0.024),
			Vector3.ZERO, Vector3.ONE, get_material(Color("177c99"), 0.36, 0.17))
		# Highlights follow the curved lens; they are narrow meshes, not decals.
		for side: float in [-1.0, 1.0]:
			var shine := CapsuleMesh.new()
			shine.radius = 0.003
			shine.height = 0.045
			_mesh(face, shine, Color("c9f4ff"), Vector3(side * 0.08, 0.035, -0.032),
				Vector3(0, 0, -0.5), Vector3.ONE, get_material(Color("c9f4ff"), 0.1, 0.2))
		var strap := TorusMesh.new()
		strap.inner_radius = 0.205
		strap.outer_radius = 0.226
		_mesh(get_socket(&"head_socket"), strap, Color("16364c"), Vector3(0, -0.15, 0))
		return
	if id in ["scarf_red", "scarf_rainbow"]:
		var fabric := _knit_material(color, id == "scarf_rainbow")
		var collar := TorusMesh.new()
		collar.inner_radius = 0.195
		collar.outer_radius = 0.265
		collar.rings = 48
		collar.ring_segments = 24
		_mesh(neck, collar, color, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.3, 1), fabric)
		var tail := PackedVector2Array([Vector2(-0.065, 0.015), Vector2(0.065, 0.015),
			Vector2(0.06, -0.23), Vector2(0.045, -0.285), Vector2(-0.045, -0.30), Vector2(-0.065, -0.27)])
		_mesh(neck, _soft_prism(tail, 0.024, 0.075), color, Vector3(0.085, -0.02, -0.265),
			Vector3(0.08, 0, -0.13), Vector3.ONE, fabric)
		for i: int in 6:
			var fringe := CapsuleMesh.new()
			fringe.radius = 0.006
			fringe.height = 0.065
			_mesh(neck, fringe, color, Vector3(0.005 + i * 0.019, -0.335, -0.365),
				Vector3(0.05, 0, -0.13), Vector3.ONE, fabric)
		return
	# Remaining shapes already fit the production sockets. Add close-up
	# surface treatment without modifying shared gameplay mesh/material caches.
	var before: Array[Node] = []
	for socket_id: String in SOCKET_TARGETS:
		before.append_array(get_socket(StringName(socket_id)).get_children())
	super._apply_cosmetic(id)
	for socket_id: String in SOCKET_TARGETS:
		for child: Node in get_socket(StringName(socket_id)).get_children():
			var mesh := child as MeshInstance3D
			if mesh == null or child in before:
				continue
			if id in ["hat_beanie", "hat_earwarmers"]:
				var source := mesh.material_override as StandardMaterial3D
				mesh.material_override = _knit_material(source.albedo_color if source != null else color)
			elif id == "hat_crown":
				mesh.material_override = get_material(Color("dba63c"), 0.78, 0.28)
			elif id == "scarf_bowtie" and mesh.mesh is BoxMesh:
				var dimensions := (mesh.mesh as BoxMesh).size
				mesh.mesh = _soft_prism(PackedVector2Array([
					Vector2(-dimensions.x, dimensions.y) * 0.5, Vector2(dimensions.x, dimensions.y) * 0.5,
					Vector2(dimensions.x, -dimensions.y) * 0.5, Vector2(-dimensions.x, -dimensions.y) * 0.5]), dimensions.z)
				mesh.material_override = _knit_material(color)
			if id in ["hat_earwarmers", "hat_headset"]:
				mesh.position.y -= 0.055


func _knit_material(color: Color, multicolor: bool = false) -> Material:
	if GameConfig.is_headless():
		return get_material(color, 0.0, 0.94)
	var material := ShaderMaterial.new()
	material.shader = KNIT
	material.set_shader_parameter("yarn_color", color)
	material.set_shader_parameter("rainbow", multicolor)
	return material


func _soft_prism(control_points: PackedVector2Array, depth: float, drape: float = 0.0) -> ArrayMesh:
	# Rounded Catmull-Rom outline with bevelled front and back: one compact
	# mesh gives cloth tails and goggles soft silhouettes and real thickness.
	var outline := PackedVector2Array()
	for i: int in control_points.size():
		var a := control_points[posmod(i - 1, control_points.size())]
		var b := control_points[i]
		var c := control_points[(i + 1) % control_points.size()]
		var d := control_points[(i + 2) % control_points.size()]
		for step: int in 4:
			var t := float(step) / 4.0
			outline.append(0.5 * ((2.0 * b) + (-a + c) * t +
				(2.0 * a - 5.0 * b + 4.0 * c - d) * t * t +
				(-a + 3.0 * b - 3.0 * c + d) * t * t * t))
	var center := Vector2.ZERO
	for point: Vector2 in outline:
		center += point
	center /= outline.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i: int in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var ai := center + (a - center) * 0.90
		var bi := center + (b - center) * 0.90
		for sign: float in [-1.0, 1.0]:
			var front := [Vector3(center.x, center.y, sign * depth * 0.5),
				Vector3(ai.x, ai.y, sign * depth * 0.5), Vector3(bi.x, bi.y, sign * depth * 0.5)]
			if sign > 0:
				front.reverse()
			_triangle(st, front, drape)
			var bevel := [Vector3(ai.x, ai.y, sign * depth * 0.5), Vector3(a.x, a.y, 0),
				Vector3(b.x, b.y, 0), Vector3(bi.x, bi.y, sign * depth * 0.5)]
			if sign > 0:
				bevel.reverse()
			_triangle(st, [bevel[0], bevel[1], bevel[2]], drape)
			_triangle(st, [bevel[0], bevel[2], bevel[3]], drape)
	st.generate_normals()
	return st.commit()


func _triangle(surface: SurfaceTool, vertices: Array, drape: float = 0.0) -> void:
	for vertex: Vector3 in vertices:
		# Follow the convex chest: collar depth at the top, belly clearance
		# lower down. A flat tail intersects the rounded torso halfway down.
		vertex.z -= drape * smoothstep(0.0, 0.13, -vertex.y)
		surface.set_uv(Vector2(vertex.x * 2.5 + 0.5, vertex.y * 2.5 + 0.5))
		surface.add_vertex(vertex)
