extends Node
## Production meshes, socket fitting and shared-resource lifetime. No raster claim.
const Apparel = preload("res://scripts/characters/penguin_apparel.gd")
var checks: Array[Dictionary] = []

func _ready() -> void:
	if not String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("waddle-wars-apparel-"):
		push_error("Requires isolated waddle-wars-apparel-* profile")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	var save_before := JSON.stringify(SaveManager.data)
	var shared: Dictionary = {}
	var meshes := 0
	for species: String in PenguinVisual.SPECIES:
		for id: String in Apparel.IDS:
			var visual := PenguinVisual.new()
			add_child(visual)
			var category := "hat" if id.begins_with("hat_") else ("scarf" if id.begins_with("scarf_") else "goggles")
			visual.setup({"species":species,category:id})
			var root := visual.find_child(id,true,false) as Node3D
			var socket := visual.get_socket(&"head" if category == "hat" else (&"neck" if category == "scarf" else &"face"))
			_check(root != null and root.get_parent() == socket, species+"/"+id+" follows actual animated socket")
			if root == null:
				visual.free()
				continue
			_check(root.get_child_count() <= 5, id+" <=5 draw parts, no eight-cylinder arch")
			for node: Node in root.get_children():
				var part := node as MeshInstance3D
				var key := id+"/"+str(part.name)
				var material := part.material_override as StandardMaterial3D
				_check(part.mesh != null and material != null and part.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, key+" valid inexpensive render resources")
				if shared.has(key):
					_check(part.mesh == shared[key][0] and material == shared[key][1], key+" mesh/material shared across species")
				else:
					shared[key] = [part.mesh,material]
					meshes += 1
					_check(_finite_geometry(part.mesh), key+" finite complete triangles and normals")
					_check(part.mesh.get_aabb().size.length() < 1.0, key+" item has bounded world geometry")
			if species == "emperor": _fit(visual,id)
			var root_transform := visual.transform
			for pose: int in [PenguinVisual.Pose.RUN,PenguinVisual.Pose.SLIDE,PenguinVisual.Pose.AIR]:
				visual.set_pose(pose as PenguinVisual.Pose)
				for frame: int in 12: visual.tick(1.0/60.0,1.0)
				if id in ["scarf_red","scarf_rainbow"]:
					var tail := root.find_child("ScarfTailLeft",true,false) as Apparel.ScarfTail
					_check(tail.mesh == (tail.moving_mesh if pose != PenguinVisual.Pose.SLIDE else tail.rest_mesh),id+" production tick selects moving drape only in RUN/AIR")
				_check(root.get_parent() == socket and root.transform == Transform3D.IDENTITY and visual.transform == root_transform, id+" pose keeps gear attached without gameplay root motion")
			visual.setup({"species":species})
			_check(visual.find_child(id,true,false) == null, id+" removing gear drops old attachment immediately")
			visual.free()
		await get_tree().process_frame
	_check(Apparel._recipes.size() == 9 and shared.size() == meshes and meshes <= 36, "bounded nine-item cache and shared draw-part budget")
	var invalid := Node3D.new()
	Apparel.attach("unregistered",invalid,invalid,invalid)
	_check(invalid.get_child_count() == 0 and Apparel._recipes.size() == 9, "invalid IDs never allocate or grow cache")
	invalid.free()
	_check(JSON.stringify(SaveManager.data) == save_before,"apparel construction/animation/removal never changes saved equipment or economy")
	# Combined real RunnerPlayer configuration also preserves physics and gets all slots.
	var player := RunnerPlayer.new()
	add_child(player)
	player.setup({"species":"little_blue","hat":"hat_headset","scarf":"scarf_rainbow","goggles":"goggles_ski"})
	var collider := player._shape.shape
	var collider_transform := player._shape.transform
	for frame: int in 20: player._visual.tick(1.0/60.0,1.0)
	_check(player._shape.shape == collider and player._shape.transform == collider_transform and player.hits_left == 3, "full outfit leaves collision and hits authoritative")
	player.queue_free()
	await get_tree().process_frame
	var passed := checks.filter(func(row: Dictionary) -> bool: return row.passed).size()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			var path := arg.trim_prefix("out=")
			DirAccess.make_dir_recursive_absolute(path)
			var file := FileAccess.open(path.path_join("apparel.json"),FileAccess.WRITE)
			file.store_string(JSON.stringify({"passed":passed,"total":checks.size(),"mesh_parts":meshes,"cache_items":Apparel._recipes.size(),"checks":checks,"limits":"Actual production geometry/material/lifecycle checks. Final Chrome visual acceptance separate."},"\t"))
	print("[runner-apparel] %d/%d passed; %d shared mesh parts" % [passed,checks.size(),meshes])
	get_tree().quit(0 if passed == checks.size() else 1)

func _fit(visual: PenguinVisual,id: String) -> void:
	var root := visual.find_child(id,true,false)
	if id.begins_with("scarf_") and id != "scarf_bowtie":
		for name: String in ["ScarfTailLeft","ScarfTailRight"]:
			var tail := root.find_child(name,true,false) as MeshInstance3D
			var vertices: PackedVector3Array = tail.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var clear := true
			for vertex: Vector3 in vertices:
				var body_local := visual._root.to_local(tail.to_global(vertex))
				# The analytically measured lathe maximum chest radius is .336m.
				# Check sampled cross-sections against exact production profile.
				var radius := _body_radius(body_local.y)
				var center_z := -maxf(0.0,body_local.y-0.66)*0.20
				var front_z := center_z-sqrt(maxf(0.0,radius*radius-body_local.x*body_local.x))
				clear = clear and body_local.z <= front_z-0.008
			_check(clear,id+" "+name+" entire cloth surface clears chest by8mm")
		var moving_shared: Array = []
		for name: String in ["ScarfTailLeft","ScarfTailRight"]:
			var tail := root.find_child(name,true,false) as MeshInstance3D
			var original_mesh := tail.mesh
			var original_transform := tail.transform
			var original_material := tail.material_override
			for step: int in 20:
				tail.present(true,float(step)*0.11,1.5)
				var vertices: PackedVector3Array = tail.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var clear := true
				var visible_behind := false
				var bounded := true
				var projection_min := INF
				var projection_max := -INF
				var min_y := INF
				var max_x := 0.0
				var max_z := 0.0
				for vertex: Vector3 in vertices:
					var local := visual._root.to_local(tail.to_global(vertex))
					var center_z := -maxf(0.0,local.y-0.66)*0.20
					clear = clear and Vector2(local.x,local.z-center_z).length() >= _body_radius(local.y)+0.008
					visible_behind = visible_behind or local.z > 0.48
					bounded = bounded and absf(local.x) < 0.37 and local.z < 0.55 and local.y > 0.40
					min_y = minf(min_y,local.y)
					max_x = maxf(max_x,absf(local.x))
					max_z = maxf(max_z,local.z)
					var projected_y := _chase_y(local)
					projection_min = minf(projection_min, projected_y)
					projection_max = maxf(projection_max, projected_y)
				_check(clear and visible_behind and bounded,id+" "+name+" flutter phase%d clears body, visible behind, stays modest (clear=%s rear=%s x=%.3f ymin=%.3f z=%.3f)" % [step,clear,visible_behind,max_x,min_y,max_z])
				var hero_span := absf(_chase_y(Vector3(0,1.16,0))-_chase_y(Vector3.ZERO))
				_check(projection_max-projection_min >= hero_span*0.28,
					id+" "+name+" readable vertical silhouette in actual desktop chase angle")
				_check(tail.material_override == original_material,id+" motion keeps exact cloth/rainbow material")
			moving_shared.append(tail.mesh)
			tail.present(false,0.0,0.0)
			_check(tail.mesh == original_mesh and tail.transform == original_transform,id+" idle/slide restores exact front-drape mesh and transform")
		_check(moving_shared[0] != moving_shared[1] and Apparel._moving_tail_meshes.size() == 2,"two mirrored moving meshes cached across red/rainbow only")
	if id == "hat_beanie":
		var cuff := root.find_child("BeanieFoldedCuff",true,false) as MeshInstance3D
		var bounds := cuff.transform*cuff.mesh.get_aabb()
		_check(bounds.position.y < -0.05 and bounds.end.y < 0.02,"beanie brim rests over crown, not floating above head")
	if id == "hat_crown":
		var crown := root.find_child("CrownScallopedBand",true,false) as MeshInstance3D
		var mat := crown.material_override as StandardMaterial3D
		_check(mat.metallic >= 0.7 and mat.roughness <= 0.3,"crown polished gold rather than matte yellow")
	if id == "goggles_ski":
		var rim := root.find_child("GoggleIvoryRim",true,false) as MeshInstance3D
		var lens := root.find_child("GoggleCurvedLens",true,false) as MeshInstance3D
		var band := root.find_child("GoggleFabricStrap",true,false) as MeshInstance3D
		_check((rim.material_override as StandardMaterial3D).albedo_color.r > 0.8 and lens.mesh.get_aabb().size.x > 0.32,"wide curved cyan goggles keep contrasting ivory frame")
		_check(band.mesh.get_aabb().end.z > 0.38 and band.mesh.get_aabb().size.y >= 0.048,"wide cyan strap actually wraps behind head")
		_check(_front_normals(lens.mesh),"visor front face normals face outward")
	if id == "goggles_aviator":
		var arms := root.find_child("AviatorTempleArms",true,false) as MeshInstance3D
		_check(arms.mesh.get_aabb().end.z > 0.26,"aviator sidearms reach behind temples")
		_check(_front_normals((root.find_child("AviatorLensLeft",true,false) as MeshInstance3D).mesh) and _front_normals((root.find_child("AviatorLensRight",true,false) as MeshInstance3D).mesh),"both mirrored lenses retain outward front normals")

func _body_radius(y: float) -> float:
	var profile := [Vector2(.40,.330),Vector2(.50,.313),Vector2(.60,.281),Vector2(.68,.241),Vector2(.74,.202),Vector2(.783,.184)]
	for i: int in profile.size()-1:
		if y <= profile[i+1].x: return lerpf(profile[i].y,profile[i+1].y,clampf((y-profile[i].x)/(profile[i+1].x-profile[i].x),0,1))
	return .184

func _chase_y(point: Vector3) -> float:
	# Perspective projection at the captured production chase position/pitch.
	# This catches the former horizontal tail's camera foreshortening even when
	# its world-space bounds and torso clearance were individually valid.
	var pitch := deg_to_rad(5.251)
	var relative := point-Vector3(0,3.016,9.032)
	var up := Vector3(0,cos(pitch),-sin(pitch))
	var forward := Vector3(0,-sin(pitch),-cos(pitch))
	return relative.dot(up)/relative.dot(forward)

func _front_normals(mesh: Mesh) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var found := 0
	for i: int in vertices.size():
		if absf(vertices[i].x) < 0.05 and normals[i].z < -0.8: found += 1
	return found >= 3

func _finite_geometry(mesh: Mesh) -> bool:
	if mesh.get_surface_count() != 1: return false
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if vertices.is_empty() or vertices.size() != normals.size(): return false
	for i: int in vertices.size():
		if not vertices[i].is_finite() or not normals[i].is_finite(): return false
	return true

func _check(ok: bool, description: String) -> void:
	checks.append({"passed":ok,"description":description})
	if not ok: push_error(description)
