extends Node
## Focused import/runtime contract for first authored shared penguin.

const HERO_SCENE := preload("res://assets/art/characters/hero_penguin_v1.tscn")
const HERO_MATERIAL := preload("res://assets/art/characters/hero_penguin_v1_material.tres")
const FEATHER_MAPS: Array[Texture2D] = [
	preload("res://assets/art/characters/textures/hero_penguin_v1_albedo.png"),
	preload("res://assets/art/characters/textures/hero_penguin_v1_normal.png"),
	preload("res://assets/art/characters/textures/hero_penguin_v1_orm.png"),
]

var _failures: int = 0


func _ready() -> void:
	var previous_qa_backend := PenguinVisual.use_authored_backend_for_qa
	_check(not previous_qa_backend, "production keeps unapproved authored backend disabled")
	# This fixture verifies the retained authored candidate deliberately; enabling
	# it here must never promote that model in gameplay or menu previews.
	PenguinVisual.use_authored_backend_for_qa = true
	for texture: Texture2D in FEATHER_MAPS:
		_check(texture.get_width() == 1024 and texture.get_height() == 1024,
				"sampled feather map is 1024x1024")
	_check(HERO_MATERIAL is ShaderMaterial, "registered sampled material wrapper")
	if HERO_MATERIAL is ShaderMaterial:
		for parameter: StringName in [&"feather_albedo", &"feather_normal", &"feather_orm"]:
			_check((HERO_MATERIAL as ShaderMaterial).get_shader_parameter(parameter) is Texture2D,
					"material samples %s" % parameter)
	var facade := PenguinVisual.new()
	add_child(facade)
	var facade_transform := Transform3D(Basis.IDENTITY, Vector3(4.0, 2.0, -8.0))
	facade.transform = facade_transform
	facade.setup_look(CharacterLook.from_legacy_config({
		"species": "emperor", "hat": "hat_beanie",
	}, CharacterLook.RenderRole.HERO))
	_check(facade.is_authored_backend_active(), "PenguinVisual selects authored backend")
	var hero := facade.find_child("AuthoredHeroPenguin", false, false) as HeroPenguinRig
	_check(hero != null, "facade exposes authored rig child")
	if hero == null:
		PenguinVisual.use_authored_backend_for_qa = previous_qa_backend
		get_tree().quit(1)
		return
	_check(hero.root_motion_disabled, "runtime explicitly disables root motion")
	_check(not hero.is_using_racer_lod(), "HERO role keeps complete LOD0 mesh")
	var missing := hero.missing_contract_items()
	_check(missing.is_empty(), "full clip/socket contract; missing=%s; clips=%s" % [
		", ".join(missing), ", ".join(hero.animation_names())])

	var mesh_instance := hero.find_child("HeroPenguinMesh", true, false) as MeshInstance3D
	_check(mesh_instance != null, "single named skinned mesh")
	if mesh_instance != null:
		var triangle_count := 0
		var max_influences := 0
		for surface_index: int in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangle_count += indices.size() / 3
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for vertex_index: int in weights.size() / 4:
				var influences := 0
				for influence_index: int in 4:
					if weights[vertex_index * 4 + influence_index] > 0.00001:
						influences += 1
				max_influences = maxi(max_influences, influences)
		_check(triangle_count >= 18_000 and triangle_count <= 25_000,
				"LOD0 triangle budget: %d" % triangle_count)
		_check(mesh_instance.mesh.get_surface_count() == 1,
				"shared hero/racer body uses exactly one runtime surface")
		_check(max_influences <= 4, "skin influence budget: %d" % max_influences)
		_check(mesh_instance.mesh.get_blend_shape_count() >= 8,
				"eight species proportion seams")

	var skeletons: Array[Node] = hero.find_children("*", "Skeleton3D", true, false)
	_check(skeletons.size() == 1, "single skeleton")
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		_check(skeleton.get_bone_count() == 15,
				"shared hero skeleton stays exact 15 bones: %d" % skeleton.get_bone_count())

	for socket_name: String in HeroPenguinRig.REQUIRED_SOCKETS:
		_check(hero.get_socket(socket_name) != null, "%s resolves" % socket_name)
	var transform_before := hero.transform
	hero.set_pose(PenguinVisual.Pose.RUN)
	hero.drive_motion(1.0, 0.6, 0.2, 4.0, false)
	for _frame: int in 12:
		hero.tick(1.0 / 60.0)
	_check(hero.transform.is_equal_approx(transform_before),
			"animation never applies node root motion")
	for socket_name: String in CharacterLook.REQUIRED_SOCKETS:
		_check(facade.get_socket(socket_name) != null,
				"facade authored %s resolves" % socket_name)
	var authored_head_socket := facade.get_socket(&"head_socket")
	_check(authored_head_socket != null and not authored_head_socket.find_children(
			"*", "GeometryInstance3D", true, false).is_empty(),
			"legacy hat cosmetic attaches to authored head socket")
	facade.set_pose(PenguinVisual.Pose.RUN)
	facade.drive_motion(1.0, -0.4, 0.0, 0.0, true)
	for _frame: int in 12:
		facade.tick(1.0 / 60.0, 1.0)
	_check(facade.transform.origin.is_equal_approx(facade_transform.origin),
			"facade preserves gameplay position")
	# Near non-player racers use imported generated-index LOD1, then return to
	# exact LOD0 without recreating skeleton, sockets, or role state.
	facade.set_render_role(PenguinVisual.RenderRole.RACER)
	_check(hero.is_using_racer_lod(), "RACER role selects authored LOD1")
	_check(hero.racer_lod_triangle_count() >= HeroPenguinRig.RACER_LOD_TRIANGLES_MIN
			and hero.racer_lod_triangle_count() <= HeroPenguinRig.RACER_LOD_TRIANGLES_MAX,
			"RACER LOD1 triangle budget: %d" % hero.racer_lod_triangle_count())
	facade.set_render_role(PenguinVisual.RenderRole.HERO)
	_check(not hero.is_using_racer_lod(), "RACER to HERO role restores LOD0")
	_check(hero.get_socket(&"head_socket") != null,
			"LOD role transition preserves skeleton sockets")

	var crowd := PenguinVisual.new()
	add_child(crowd)
	crowd.setup_look(CharacterLook.from_legacy_config({
		"species": "adelie",
	}, CharacterLook.RenderRole.CROWD))
	_check(not crowd.is_authored_backend_active(), "crowd keeps simplified procedural backend")
	_check(crowd.get_socket(&"head_socket") != null, "crowd fallback keeps socket contract")

	# Course builders assign racer roles before nodes enter SceneTree, and race
	# teardown can repeat it after viewport detaches. Detached LOD selection must
	# stay a silent procedural fallback rather than dereferencing null viewport.
	var detached_racer := PenguinVisual.new()
	detached_racer.setup_look(CharacterLook.from_legacy_config({
		"species": "emperor",
	}, CharacterLook.RenderRole.RACER))
	detached_racer.set_render_role(PenguinVisual.RenderRole.RACER)
	_check(detached_racer.is_authored_backend_active(),
			"detached racer retains authored backend for later near-LOD handoff")
	_check(not detached_racer.is_authored_lod_visible(),
			"detached racer selects silent procedural fallback")
	_check(not detached_racer.is_authored_racer_shadow_enabled(),
			"detached racer cannot retain authored shadow pass")
	var detached_rig := detached_racer.find_child(
			"AuthoredHeroPenguin", false, false) as HeroPenguinRig
	var detached_mesh := (detached_rig.find_child("HeroPenguinMesh", true, false)
			as MeshInstance3D) if detached_rig != null else null
	if mesh_instance != null and detached_mesh != null:
		var hero_material := mesh_instance.get_surface_override_material(0)
		var racer_material := detached_mesh.get_surface_override_material(0)
		_check(hero_material != null and racer_material != null
				and hero_material.get_instance_id() == racer_material.get_instance_id(),
				"HERO/RACER share one material+atlas resource; hero=%s racer=%s" % [
					hero_material, racer_material])
	detached_racer.free()

	# Capture/import harnesses can own a live World3D before creating a current
	# camera. This state must remain a silent cheap LOD, not call through a
	# half-initialized viewport camera and emit teardown/headless errors.
	var camera_less_viewport := SubViewport.new()
	camera_less_viewport.size = Vector2i(32, 32)
	camera_less_viewport.own_world_3d = true
	add_child(camera_less_viewport)
	var camera_less_racer := PenguinVisual.new()
	camera_less_viewport.add_child(camera_less_racer)
	camera_less_racer.setup_look(CharacterLook.from_legacy_config({
		"species": "emperor",
	}, CharacterLook.RenderRole.RACER))
	camera_less_racer.set_render_role(PenguinVisual.RenderRole.RACER)
	_check(not camera_less_racer.is_authored_lod_visible()
			and not camera_less_racer.is_authored_racer_shadow_enabled(),
			"camera-less live viewport selects silent procedural fallback")
	camera_less_viewport.free()

	# A reused facade switching back to legacy setup must not retain 22.64k backend
	# state from an earlier explicit look/role.
	facade.setup({"species": "emperor"})
	_check(not facade.is_authored_backend_active(), "legacy re-setup returns to safe fallback")

	# Re-setup retires old branches with queue_free; finish their teardown.
	await get_tree().process_frame
	await get_tree().process_frame
	if _failures == 0:
		print("HERO PENGUIN ASSET: PASS")
	else:
		push_error("HERO PENGUIN ASSET: %d failure(s)" % _failures)
	PenguinVisual.use_authored_backend_for_qa = previous_qa_backend
	get_tree().quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % label)
