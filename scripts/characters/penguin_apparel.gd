extends RefCounted
## Fitted procedural apparel for the production hero. Fixed catalogue recipes
## share meshes/materials across species, retries and racers; no per-frame resources.
## Coordinates are relative to the existing animated head/face/neck sockets.

const IDS := ["hat_beanie", "hat_earwarmers", "hat_headset", "hat_crown", "scarf_red", "scarf_rainbow", "scarf_bowtie", "goggles_ski", "goggles_aviator"]
static var _recipes: Dictionary = {}
static var _materials: Dictionary = {}
static var _moving_tail_meshes: Dictionary = {}

class ScarfTail:
	extends MeshInstance3D
	var rest_mesh: Mesh
	var moving_mesh: Mesh
	var rest_transform: Transform3D
	var flutter_phase := 0.0

	func present(moving: bool, clock: float, speed: float) -> void:
		if not moving:
			if mesh != rest_mesh:
				mesh = rest_mesh
				transform = rest_transform
			return
		if mesh != moving_mesh:
			mesh = moving_mesh
			transform = Transform3D.IDENTITY
		# Small rigid cloth sway only: shared rounded mesh supplies the curved
		# drape; no soft-body solver, mesh rebuild, animation resource or timer.
		rotation = Vector3(0.0, sin(clock*7.5+flutter_phase)*0.018*minf(speed,1.0),
			sin(clock*6.0+flutter_phase)*0.015*minf(speed,1.0))

static func attach(id: String, head: Node3D, face: Node3D, neck: Node3D) -> Array:
	var tails: Array = []
	if not id in IDS: return tails
	if not _recipes.has(id): _recipes[id] = _build(id)
	var socket := head if id.begins_with("hat_") else (neck if id.begins_with("scarf_") else face)
	var root := Node3D.new()
	root.name = id
	root.set_meta("apparel_id", id)
	socket.add_child(root)
	for part: Dictionary in _recipes[id]:
		var instance := ScarfTail.new() if part.has("moving_mesh") else MeshInstance3D.new()
		instance.name = part.name
		instance.set_meta("apparel_no_shadow", true)
		instance.mesh = part.mesh
		instance.material_override = part.material
		instance.transform = part.transform
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
		if instance is ScarfTail:
			instance.rest_mesh = part.mesh
			instance.moving_mesh = part.moving_mesh
			instance.rest_transform = part.transform
			instance.flutter_phase = part.phase
			tails.append(instance)
	return tails

static func _part(name: String, mesh: Mesh, material: Material, position: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE, rotation: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"name": name, "mesh": mesh, "material": material,
		"transform": Transform3D(Basis.from_euler(rotation).scaled(scale), position)}

static func _mat(key: String, color: Color, metal: float = 0.0, roughness: float = 0.86) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = roughness
	_materials[key] = material
	return material

static func _rainbow(neck: bool) -> StandardMaterial3D:
	var key := "rainbow_neck" if neck else "rainbow_tail"
	if _materials.has(key): return _materials[key]
	var material := _mat(key, Color.WHITE)
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	gradient.offsets = PackedFloat32Array([0.0, 0.1667, 0.3333, 0.5, 0.6667, 0.8333])
	gradient.colors = PackedColorArray([Color("eb4447"), Color("f49334"), Color("f6cc45"), Color("60ad63"), Color("4d8bd2"), Color("9363bc")])
	var texture := GradientTexture2D.new()
	texture.width = 64 if neck else 1
	texture.height = 1 if neck else 64
	texture.gradient = gradient
	texture.fill_to = Vector2.RIGHT if neck else Vector2.DOWN
	material.albedo_texture = texture
	return material

static func _build(id: String) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var color: Color = CosmeticsDB.get_item(id).get("color", Color.WHITE)
	var cloth := _mat(id, color)
	var dark := _mat("padding", Color("202c3a"), 0.0, 0.94)
	match id:
		"hat_beanie":
			parts.append(_part("BeanieDome", _lathe([Vector2(-0.045, 0.207), Vector2(0.0, 0.219), Vector2(0.05, 0.208), Vector2(0.115, 0.172), Vector2(0.17, 0.116), Vector2(0.20, 0.05), Vector2(0.207, 0.0)], 64, 0.002), cloth, Vector3(0, 0, -0.023)))
			parts.append(_part("BeanieFoldedCuff", _lathe([Vector2(-0.062, 0.193), Vector2(-0.055, 0.223), Vector2(-0.043, 0.233), Vector2(-0.003, 0.233), Vector2(0.011, 0.221), Vector2(0.013, 0.207)], 96, 0.003), _mat("beanie_cuff", color.lightened(0.12)), Vector3(0, 0, -0.023)))
			parts.append(_part("BeaniePom", _sphere(0.067), _mat("beanie_pom", color.lightened(0.08)), Vector3(0, 0.232, -0.023)))
		"hat_earwarmers", "hat_headset":
			var headset := id == "hat_headset"
			var arch := PackedVector3Array()
			for i: int in 25:
				var angle := PI * float(i) / 24.0
				arch.append(Vector3(-0.227 * cos(angle), -0.102 + 0.20 * sin(angle), 0.015))
			parts.append(_part("Headband", _tube(arch, 0.016 if headset else 0.019, 0.036, 8), cloth))
			var cups: Array[Dictionary] = []
			var pads: Array[Dictionary] = []
			for side: int in [-1, 1]:
				cups.append(_part("", _sphere(0.09), cloth, Vector3(side * 0.231, -0.104, 0.015), Vector3(0.56 if headset else 0.73, 1.0, 0.90)))
				if headset: pads.append(_part("", _sphere(0.071), dark, Vector3(side * 0.211, -0.104, 0.015), Vector3(0.42, 1, 0.94)))
			parts.append(_part("EarCups", _merge(cups), cloth))
			if headset:
				parts.append(_part("EarCushions", _merge(pads), dark))
				parts.append(_part("MicrophoneArm", _tube(PackedVector3Array([Vector3(-0.267,-0.12,0),Vector3(-0.27,-0.17,-0.07),Vector3(-0.245,-0.20,-0.15),Vector3(-0.19,-0.205,-0.225),Vector3(-0.135,-0.20,-0.254)]), 0.009, 0.009, 8), dark))
				parts.append(_part("MicrophoneFoam", _sphere(0.025), dark, Vector3(-0.129,-0.20,-0.257), Vector3(1.2,0.7,0.8)))
		"hat_crown":
			var gold := _mat("crown_gold", color, 0.72, 0.25)
			parts.append(_part("CrownScallopedBand", _crown(), gold))
			var tips: Array[Dictionary] = []
			for i: int in 5:
				var angle := TAU * float(i) / 5.0
				tips.append(_part("", _sphere(0.022), gold, Vector3(sin(angle)*0.167,0.158,cos(angle)*0.167)))
			parts.append(_part("CrownRoundedTips", _merge(tips), gold))
		"scarf_red", "scarf_rainbow":
			var rainbow := id == "scarf_rainbow"
			var collar_mat := _rainbow(true) if rainbow else cloth
			var tail_mat := _rainbow(false) if rainbow else cloth
			var collar := TorusMesh.new()
			collar.inner_radius = 0.197
			collar.outer_radius = 0.267
			collar.rings = 40
			collar.ring_segments = 12
			parts.append(_part("ScarfCollar", collar, collar_mat, Vector3(0,0.004,-0.009), Vector3(1,1.25,1)))
			var tail := _scarf_tail()
			for side: int in [-1, 1]:
				var part := _part("ScarfTailLeft" if side < 0 else "ScarfTailRight", tail, tail_mat, Vector3(side*0.082,0.0,0.0))
				part["moving_mesh"] = _moving_scarf_tail(side)
				part["phase"] = 0.0 if side < 0 else 2.3
				parts.append(part)
		"scarf_bowtie":
			var band := TorusMesh.new()
			band.inner_radius = 0.201
			band.outer_radius = 0.227
			band.rings = 40
			band.ring_segments = 8
			parts.append(_part("BowtieNeckband", band, cloth, Vector3(0,0.02,-0.011), Vector3(1,1.8,1)))
			var wings: Array[Dictionary] = []
			for side: int in [-1, 1]:
				var outline := PackedVector2Array([Vector2(0.017,0.017),Vector2(0.12,0.068),Vector2(0.158,0.052),Vector2(0.153,-0.054),Vector2(0.12,-0.069),Vector2(0.017,-0.019)])
				wings.append(_part("", _padded_shape(_mirror(outline,side), 0.026, 0.08), cloth, Vector3(0,-0.018,-0.267)))
			parts.append(_part("BowtieFabricWings", _merge(wings), cloth))
			parts.append(_part("BowtieKnot", _sphere(0.041), _mat("bowtie_knot",color.lightened(0.09)), Vector3(0,-0.018,-0.296), Vector3(0.72,1,0.55)))
		"goggles_ski":
			var strap_path := PackedVector3Array()
			# Face origin is 0.20m in front of head; band circles the head, not face.
			for i: int in 49:
				var angle := TAU * float(i) / 48.0
				strap_path.append(Vector3(sin(angle)*0.217,0.035,0.175+cos(angle)*0.216))
			parts.append(_part("GoggleFabricStrap", _tube(strap_path,0.012,0.025,8,Vector3.UP), _mat("goggle_strap",color,0,0.85)))
			var outline := PackedVector2Array([Vector2(-0.168,0.055),Vector2(-0.13,0.071),Vector2(0.13,0.071),Vector2(0.168,0.055),Vector2(0.175,-0.008),Vector2(0.153,-0.053),Vector2(0.072,-0.06),Vector2(0.03,-0.04),Vector2(0,-0.021),Vector2(-0.03,-0.04),Vector2(-0.072,-0.06),Vector2(-0.153,-0.053),Vector2(-0.175,-0.008)])
			parts.append(_part("GoggleCushion", _padded_shape(outline,0.024,2.0), dark, Vector3(0,0.018,-0.036),Vector3(1.035,1.07,1)))
			parts.append(_part("GoggleIvoryRim", _padded_shape(outline,0.022,2.0), _mat("goggle_ivory",Color("ede7d9"),0.05,0.38), Vector3(0,0.018,-0.058)))
			parts.append(_part("GoggleCurvedLens", _padded_shape(outline,0.008,2.0), _mat("goggle_lens",Color("338a9a"),0.22,0.16), Vector3(0,0.018,-0.085),Vector3(0.90,0.79,1)))
		"goggles_aviator":
			var gold := _mat("aviator_gold",Color("d5ad53"),0.75,0.25)
			var lens_mat := _mat("aviator_lens",Color("243c58"),0.27,0.15)
			var outline := PackedVector2Array([Vector2(-0.070,0.043),Vector2(-0.038,0.057),Vector2(0.036,0.057),Vector2(0.070,0.035),Vector2(0.067,-0.012),Vector2(0.044,-0.055),Vector2(0.011,-0.061),Vector2(-0.027,-0.043),Vector2(-0.057,-0.013)])
			var rims: Array[Dictionary] = []
			var arms: Array[Dictionary] = []
			for side: int in [-1,1]:
				var position := Vector3(side*0.09,0.029,-0.052)
				parts.append(_part("AviatorLensLeft" if side < 0 else "AviatorLensRight", _padded_shape(_mirror(outline,side),0.006,0.6), lens_mat, position))
				var rim_path := PackedVector3Array()
				for point: Vector2 in outline: rim_path.append(Vector3(point.x*side,point.y,-0.012+point.x*point.x*0.6))
				rim_path.append(rim_path[0])
				rims.append(_part("", _tube(rim_path,0.006,0.006,8),gold,position))
				arms.append(_part("",_tube(PackedVector3Array([Vector3(side*0.153,0.053,-0.048),Vector3(side*0.196,0.048,0.015),Vector3(side*0.22,0.039,0.13),Vector3(side*0.213,0.014,0.24),Vector3(side*0.194,-0.022,0.267)]),0.006,0.007,8),gold))
			var bridge := PackedVector3Array([Vector3(-0.026,0.059,-0.057),Vector3(0,0.067,-0.06),Vector3(0.026,0.059,-0.057)])
			rims.append(_part("",_tube(bridge,0.006,0.006,8),gold))
			parts.append(_part("AviatorGoldFrames",_merge(rims),gold))
			parts.append(_part("AviatorTempleArms",_merge(arms),gold))
	return parts

static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	return mesh

static func _merge(parts: Array[Dictionary]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Dictionary in parts: surface.append_from(part.mesh,0,part.transform)
	return surface.commit()

static func _quad(surface: SurfaceTool, a: Vector3,b: Vector3,c: Vector3,d: Vector3, uv_a: Vector2,uv_b: Vector2,uv_c: Vector2,uv_d: Vector2) -> void:
	for pair: Array in [[a,uv_a],[b,uv_b],[c,uv_c],[a,uv_a],[c,uv_c],[d,uv_d]]:
		surface.set_uv(pair[1])
		surface.add_vertex(pair[0])

static func _finish(surface: SurfaceTool) -> ArrayMesh:
	surface.generate_normals()
	surface.index()
	return surface.commit()

static func _lathe(profile: Array[Vector2], segments: int, rib: float = 0.0) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in profile.size()-1:
		for i: int in segments:
			var points: Array[Vector3] = []
			for rc: Vector2i in [Vector2i(row,i),Vector2i(row,i+1),Vector2i(row+1,i+1),Vector2i(row+1,i)]:
				var theta := TAU*float(rc.y)/segments
				var radius := maxf(0.0,profile[rc.x].y + rib*cos(theta*32.0))
				points.append(Vector3(sin(theta)*radius,profile[rc.x].x,cos(theta)*radius))
			_quad(surface,points[0],points[1],points[2],points[3],Vector2(float(i)/segments,float(row)/(profile.size()-1)),Vector2(float(i+1)/segments,float(row)/(profile.size()-1)),Vector2(float(i+1)/segments,float(row+1)/(profile.size()-1)),Vector2(float(i)/segments,float(row+1)/(profile.size()-1)))
	return _finish(surface)

static func _tube(path: PackedVector3Array, radius: float, depth: float, segments: int, fixed_axis: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for i: int in path.size():
		var tangent := (path[mini(i+1,path.size()-1)]-path[maxi(i-1,0)]).normalized()
		var axis := fixed_axis if not fixed_axis.is_zero_approx() else (Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < 0.9 else Vector3.UP)
		var u := tangent.cross(axis).normalized()
		var v := tangent.cross(u).normalized()
		var ring := PackedVector3Array()
		for j: int in segments:
			var theta := TAU*float(j)/segments
			ring.append(path[i]+u*cos(theta)*radius+v*sin(theta)*depth)
		rings.append(ring)
	for row: int in path.size()-1:
		for j: int in segments:
			var next := (j+1)%segments
			_quad(surface,rings[row][j],rings[row][next],rings[row+1][next],rings[row+1][j],Vector2(float(j)/segments,float(row)/(path.size()-1)),Vector2(float(j+1)/segments,float(row)/(path.size()-1)),Vector2(float(j+1)/segments,float(row+1)/(path.size()-1)),Vector2(float(j)/segments,float(row+1)/(path.size()-1)))
	if not path[0].is_equal_approx(path[path.size()-1]):
		for end: int in [0,path.size()-1]:
			for j: int in segments:
				var next := (j+1)%segments
				var points: Array = [path[end],rings[end][next],rings[end][j]] if end == 0 else [path[end],rings[end][j],rings[end][next]]
				for point: Vector3 in points:
					surface.set_uv(Vector2(0.5,float(end)/(path.size()-1)))
					surface.add_vertex(point)
	return _finish(surface)

static func _mirror(outline: PackedVector2Array, side: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in outline: result.append(Vector2(point.x*side,point.y))
	return result

static func _padded_shape(source: PackedVector2Array, depth: float, curve: float) -> ArrayMesh:
	# Two corner-cut passes soften rims and fabric without a box silhouette.
	var outline := source.duplicate()
	for iteration: int in 2:
		var rounded := PackedVector2Array()
		for i: int in outline.size():
			var p := outline[i]
			var q := outline[(i+1)%outline.size()]
			rounded.append(p.lerp(q,0.12))
			rounded.append(p.lerp(q,0.88))
		outline = rounded
	# Normalize to clockwise in XY, independently of mirrored left/right gear.
	var signed_area := 0.0
	for i: int in outline.size(): signed_area += outline[i].cross(outline[(i+1)%outline.size()])
	if signed_area > 0.0: outline.reverse()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(outline)
	for side: int in [-1,1]:
		for i: int in range(0,indices.size(),3):
			var p := outline[indices[i]]*0.96
			var q := outline[indices[i+1]]*0.96
			var r := outline[indices[i+2]]*0.96
			var points: Array = [p,q,r] if signf((q-p).cross(r-p)) == side else [p,r,q]
			for point: Vector2 in points:
				surface.set_uv(point+Vector2(0.5,0.5))
				surface.add_vertex(Vector3(point.x,point.y,side*depth+curve*point.x*point.x))
	for i: int in outline.size():
		var p := outline[i]
		var q := outline[(i+1)%outline.size()]
		var rings: Array[Vector2] = [Vector2(-depth,0.96),Vector2(0.0,1.0),Vector2(depth,0.96)]
		for j: int in 2:
			var a := Vector3(p.x*rings[j].y,p.y*rings[j].y,rings[j].x+curve*pow(p.x*rings[j].y,2.0))
			var b := Vector3(q.x*rings[j].y,q.y*rings[j].y,rings[j].x+curve*pow(q.x*rings[j].y,2.0))
			var c := Vector3(q.x*rings[j+1].y,q.y*rings[j+1].y,rings[j+1].x+curve*pow(q.x*rings[j+1].y,2.0))
			var d := Vector3(p.x*rings[j+1].y,p.y*rings[j+1].y,rings[j+1].x+curve*pow(p.x*rings[j+1].y,2.0))
			_quad(surface,d,c,b,a,p,q,q,p)
	return _finish(surface)

static func _scarf_tail() -> ArrayMesh:
	# Body radius grows below neck; drape follows that profile with clearance.
	# Old z=-.24 box was inside the chest. Elliptic tube gives rounded cloth
	# edges, then pinches closed above feet. UV.y keeps rainbow stripes broad.
	var path := PackedVector3Array([Vector3(0,0.015,-0.249),Vector3(0,-0.04,-0.28),Vector3(0,-0.10,-0.311),Vector3(0,-0.18,-0.345),Vector3(0,-0.26,-0.362),Vector3(0,-0.31,-0.361)])
	return _tube(path,0.051,0.014,12)

static func _moving_scarf_tail(side: int) -> Mesh:
	if _moving_tail_meshes.has(side): return _moving_tail_meshes[side]
	# Wind carries the ends from the side of the neck-wrap past the shoulder.
	# The whole ribbon stays outside the lathe torso, including its wide edges.
	# A horizontal ribbon points into the chase camera and collapses to a collar
	# tab. This modest downward drape keeps a readable tail below each shoulder,
	# above the feet; rear reach and shared draw count remain unchanged.
	var path := PackedVector3Array([Vector3(0.232,0.021,0.098),Vector3(0.282,-0.025,0.164),
		Vector3(0.317,-0.084,0.252),Vector3(0.319,-0.157,0.343),
		Vector3(0.307,-0.211,0.414),Vector3(0.285,-0.260,0.461)])
	for i: int in path.size(): path[i].x *= side
	var cloth := _tube(path,0.038,0.009,12,Vector3.UP)
	var pieces: Array[Dictionary] = [_part("",cloth,null)]
	var end := path[path.size()-1]
	var tangent := (end-path[path.size()-2]).normalized()
	var across := tangent.cross(Vector3.UP).normalized()
	for i: int in 5:
		var start := end+across*(float(i)-2.0)*0.013
		var fringe := _tube(PackedVector3Array([start,start+tangent*0.029+Vector3(0,-0.006,0),start+tangent*0.046+Vector3(0,-0.014,0)]),0.0032,0.0024,6,Vector3.UP)
		# Fringe continues the final UV band, rather than repeating a whole rainbow.
		var arrays := fringe.surface_get_arrays(0)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for j: int in uv.size(): uv[j].y = 0.995
		arrays[Mesh.ARRAY_TEX_UV] = uv
		var capped := ArrayMesh.new()
		capped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		pieces.append(_part("",capped,null))
	var combined := _merge(pieces)
	_moving_tail_meshes[side] = combined
	return combined

static func _crown() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in 80:
		var corners: Array[Vector3] = []
		for step: int in [i,i+1]:
			var theta := TAU*float(step)/80.0
			var top := 0.065+0.088*pow((cos(theta*5.0)+1.0)*0.5,2.0)
			for yr: Vector2 in [Vector2(-0.024,0.135),Vector2(top,0.167),Vector2(top,0.154),Vector2(-0.024,0.122)]:
				corners.append(Vector3(sin(theta)*yr.y,yr.x,cos(theta)*yr.y))
		for band: int in 4:
			var next := (band+1)%4
			_quad(surface,corners[band],corners[4+band],corners[4+next],corners[next],Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN)
	return _finish(surface)
