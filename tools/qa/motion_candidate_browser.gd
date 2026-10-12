extends Node
## Imported rig/clip review in the actual frozen runner, using its camera,
## lighting and floor. Gameplay physics owns the jump arc; clips own articulation.

const MODEL := "res://qa_motion/candidate.glb"
var _bridge: Node
var _binding: Dictionary = {}
var _game: RunnerGame
var _original: PenguinVisual
var _holder: Node3D
var _model: Node3D
var _camera: Camera3D
var _chase_transform := Transform3D.IDENTITY
var _chase_fov := 0.0
var _camera_before: Dictionary = {}
var _camera_after: Dictionary = {}
var _baseline_bounds: Dictionary = {}
var _repairs: Array[Dictionary] = []
var _color_transfers: Array[Dictionary] = []
var _draws := 0
var _installed_draw := 0
var _view := "rear"
var _error := ""
var _initial_signature := ""
var _material_ids: Dictionary = {}
var _texture_ids: Dictionary = {}
var _texture_cache: Dictionary = {}
var _pickup_overlay_saved: Array[Dictionary] = []
var _pickup_overlay_detail := false
var _grounding: Dictionary = {}
var _read_callback: JavaScriptObject
var _status_callback: JavaScriptObject
var _view_callback: JavaScriptObject
var _action_callback: JavaScriptObject
var _play_callback: JavaScriptObject
var _sample_callback: JavaScriptObject
var _animation: AnimationPlayer
var _skeleton: Skeleton3D
var _action := "waddle"
var _phase := 0.0
var _playing := true
var _holder_rest := Vector3.ZERO
var _jump_height := 0.0
var _clip_names: Dictionary = {}
const JUMP_AIRTIME := 2.0 * RunnerConfig.JUMP_SPEED / RunnerConfig.GRAVITY


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web") or ProjectSettings.get_setting("qa/hero_motion_enabled", false) != true:
		set_process(false)
		return
	_bridge = get_node_or_null("/root/ChromeReferenceQA")
	if _bridge == null or _bridge.get("_enabled") != true or _bridge.call("_offline_fixture_ready") != true:
		set_process(false)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa_motion/candidate_binding.json"))
	if not parsed is Dictionary or parsed.get("gate") != "rear-motion-v1" \
			or parsed.get("material_contract") != "rear-surface-pbr-v1" \
			or parsed.get("production_ready") != false \
			or String(parsed.get("glb_sha256", "")).length() != 64:
		_error = "Invalid motion package binding"
	else:
		_binding = parsed
	_read_callback = JavaScriptBridge.create_callback(_on_read)
	_status_callback = JavaScriptBridge.create_callback(_on_status)
	_view_callback = JavaScriptBridge.create_callback(_on_view)
	_action_callback = JavaScriptBridge.create_callback(_on_action)
	_play_callback = JavaScriptBridge.create_callback(_on_play)
	_sample_callback = JavaScriptBridge.create_callback(_on_sample)
	JavaScriptBridge.eval("""(() => {
	  let readCallback, statusCallback, viewCallback, actionCallback, playCallback, sampleCallback;
	  window.__wwMotionCandidate = {
	    _reply: null,
	    bind_callbacks(read, status, view, action, play, sample) {
	      readCallback=read; statusCallback=status; viewCallback=view;
	      actionCallback=action; playCallback=play; sampleCallback=sample;
	    },
	    read() { readCallback(); return this._reply; },
	    status() { statusCallback(); return this._reply; },
	    view(name) { viewCallback(name); return this.status(); },
	    action(name) { actionCallback(name); return this.status(); },
	    play(enabled) { playCallback(enabled); return this.status(); },
	    sample(name, phase) { sampleCallback(name, phase); return this.status(); }
	  };
	})();""", true)
	JavaScriptBridge.get_interface("__wwMotionCandidate").bind_callbacks(_read_callback, _status_callback,
		_view_callback, _action_callback, _play_callback, _sample_callback)
	RenderingServer.frame_post_draw.connect(_on_draw)


func _on_draw() -> void:
	_draws += 1


func _exit_tree() -> void:
	_restore_pickup_overlay()
	if is_instance_valid(_original):
		_original.visible = true


func _process(delta: float) -> void:
	if _binding.is_empty() or not _error.is_empty():
		return
	var current := get_tree().current_scene as RunnerGame
	if is_instance_valid(_model) and current == _game:
		_advance_motion(delta)
		return
	if current == null or current.player == null or current.camera == null or not get_tree().paused:
		return
	var stage: Dictionary = _bridge.call("snapshot")
	if stage.get("status") != "ready" or stage.get("route") != "runner_hud":
		return
	_install(current)


func _camera_state() -> Dictionary:
	return {"transform": var_to_str(_camera.global_transform), "fov": _camera.fov}


func _visible_bounds(root: Node3D) -> Dictionary:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for raw: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree():
			continue
		var bounds := instance.mesh.get_aabb()
		for index: int in 8:
			var point := bounds.position + Vector3(bounds.size.x if index & 1 else 0.0,
				bounds.size.y if index & 2 else 0.0, bounds.size.z if index & 4 else 0.0)
			point = instance.global_transform * point
			minimum = minimum.min(point)
			maximum = maximum.max(point)
	return {"minimum": var_to_str(minimum), "maximum": var_to_str(maximum),
		"height_m": maximum.y - minimum.y, "scope": "World-space visible mesh union AABB at frozen original pose"}


func _install(game: RunnerGame) -> void:
	_restore_pickup_overlay()
	_pickup_overlay_saved.clear()
	_game = game
	_original = game.player._visual
	_camera = game.camera
	if _original == null or not _original.is_visible_in_tree():
		_error = "Original game visual unavailable before shape replacement"
		return
	if not _remember_pickup_overlay():
		return
	_camera_before = _camera_state()
	_chase_transform = _camera.global_transform
	_chase_fov = _camera.fov
	_baseline_bounds = _visible_bounds(_original)
	var packed := load(MODEL) as PackedScene
	_model = packed.instantiate() as Node3D if packed != null else null
	if _model == null or not _model.transform.is_equal_approx(Transform3D.IDENTITY) \
			or _model.find_children("*", "Skeleton3D", true, false).size() != 1 \
			or _model.find_children("*", "AnimationPlayer", true, false).size() != 1:
		_error = "Motion package requires identity root, one skeleton and one AnimationPlayer"
		if _model != null:
			_model.free()
		return
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_animation = _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var names: Array = Array(_animation.get_animation_list())
	names.sort()
	if names != ["jump", "slide", "waddle"]:
		_error = "Motion import must expose exactly jump, slide and waddle"
		_model.free()
		return
	for clip_name: String in names:
		var clip := _animation.get_animation(clip_name)
		var contract: Dictionary = _binding.clips[clip_name]
		if absf(clip.length - float(contract.duration)) > 0.0001 \
				or clip.loop_mode != (Animation.LOOP_LINEAR if contract.loop else Animation.LOOP_NONE):
			_error = "Imported motion duration/loop mismatch: " + clip_name
			_model.free()
			return
		_clip_names[clip_name] = clip_name
	_holder = Node3D.new()
	_holder.name = "RiggedMotionReview"
	game.player.add_child(_holder)
	_holder.transform = _original.transform
	_holder.scale *= float(_binding.get("gameplay_scale", 0.0))
	_model.name = "Model"
	_holder.add_child(_model)
	_grounding = seat_model_on_visual_floor(game.track, game.player, _holder, _model, _camera)
	if not String(_grounding.error).is_empty():
		_error = _grounding.error
		_holder.queue_free()
		return
	_holder_rest = _holder.position
	_repairs.clear()
	_color_transfers.clear()
	_material_ids.clear()
	_texture_ids.clear()
	_texture_cache.clear()
	for raw: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null:
			continue
		var transfer := material_contract_mesh(instance.mesh as ArrayMesh,
			RenderingServer.get_current_rendering_method(), String(_binding.material_contract))
		if not String(transfer.error).is_empty():
			_error = transfer.error
			continue
		instance.mesh = transfer.mesh
		for receipt: Dictionary in transfer.surfaces:
			receipt["mesh"] = String(instance.name)
			_color_transfers.append(receipt)
		for index: int in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(index) as BaseMaterial3D
			var colors: Variant = instance.mesh.surface_get_arrays(index)[Mesh.ARRAY_COLOR]
			if material == null or (not _is_surface_review() and (not colors is PackedColorArray or colors.is_empty())):
				_error = "Shape surface lacks imported literal-color PBR"
				continue
			if not _is_surface_review() and not material.vertex_color_use_as_albedo:
				material.vertex_color_use_as_albedo = true
				_repairs.append({"mesh": String(instance.name), "surface": index,
					"explicit_import_flag_repair": "vertex_color_use_as_albedo=true"})
			_material_ids[str(instance.get_instance_id()) + ":" + str(index)] = material.get_instance_id()
	_original.visible = false
	_view = "rear"
	_installed_draw = _draws
	_camera_after = _camera_state()
	if _camera_after != _camera_before:
		_error = "Shape replacement changed the actual runner camera"
	var active := _active_resources()
	if not active.errors.is_empty():
		_error = "; ".join(active.errors)
	_initial_signature = active.signature
	_start_action("waddle", 0.0)
	if not _error.is_empty():
		_original.visible = true
		_holder.queue_free()


static func _world_transform(node: Node3D) -> Transform3D:
	# Equivalent to global_transform; also usable by off-tree resource tests.
	var result := node.transform
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is Node3D:
			result = (ancestor as Node3D).transform * result
		ancestor = ancestor.get_parent()
	return result


static func visual_floor_at(track: Node3D, point: Vector3) -> Dictionary:
	var result := {"error": "", "paths": [], "height": 0.0, "kind": ""}
	# Only the named playable planes are eligible. Prefer the visible ice skin
	# over the collision-height deck it covers; never choose a nearby prop.
	for kind: String in ["GlacialIceSkin", "Deck"]:
		var heights: Array[float] = []
		for raw: Node in track.find_children(kind, "MeshInstance3D", true, false):
			var instance := raw as MeshInstance3D
			if not instance.visible or (instance.is_inside_tree() and not instance.is_visible_in_tree()) \
					or instance.mesh == null:
				continue
			var world := _world_transform(instance)
			var box := instance.mesh.get_aabb()
			var low := Vector3(INF, INF, INF)
			var high := Vector3(-INF, -INF, -INF)
			for corner: int in 8:
				var local := box.position + Vector3(box.size.x if corner & 1 else 0.0,
					box.size.y if corner & 2 else 0.0, box.size.z if corner & 4 else 0.0)
				var transformed := world * local
				low = low.min(transformed)
				high = high.max(transformed)
			if point.x < low.x or point.x > high.x or point.z < low.z or point.z > high.z:
				continue
			if not instance.mesh is PlaneMesh or high.y - low.y > 0.00001 \
					or (kind == "Deck" and not is_zero_approx(low.y)):
				result.error = "Unsupported playable visual-floor geometry at the player"
				return result
			heights.append(low.y)
			result.paths.append(String(track.get_path_to(instance)))
		if not heights.is_empty():
			for height: float in heights:
				if not is_equal_approx(height, heights[0]):
					result.error = "Ambiguous visual-floor heights at the player"
					return result
			result.height = heights[0]
			result.kind = kind
			return result
	result.error = "No supported visible gameplay floor below the shape candidate"
	return result


static func _lowest_vertex_y(model: Node3D) -> float:
	var lowest := INF
	for raw: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null:
			continue
		var world := _world_transform(instance)
		for surface: int in instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				lowest = minf(lowest, (world * vertex).y)
	return lowest


static func seat_model_on_visual_floor(track: Node3D, player: Node3D, holder: Node3D,
		model: Node3D, camera: Camera3D) -> Dictionary:
	var result := visual_floor_at(track, _world_transform(player).origin)
	if not String(result.error).is_empty():
		return result
	var player_before := _world_transform(player)
	var camera_before := _world_transform(camera)
	var minimum := _lowest_vertex_y(model)
	if not is_finite(minimum):
		result.error = "Cannot locate shape candidate soles"
		return result
	var offset: float = float(result.height) - minimum
	var parent := holder.get_parent() as Node3D
	if parent == null:
		result.error = "Shape holder requires a gameplay parent"
		return result
	holder.position += _world_transform(parent).basis.inverse() * Vector3.UP * offset
	result.merge({"sole_min_before": minimum, "sole_min_after": _lowest_vertex_y(model),
		"world_y_offset": offset, "player_transform_unchanged": _world_transform(player) == player_before,
		"camera_transform_unchanged": _world_transform(camera) == camera_before,
		"policy": "Seat candidate geometry on the actual visible gameplay plane; collision and camera unchanged"})
	if not is_equal_approx(result.sole_min_after, result.height) \
			or not result.player_transform_unchanged or not result.camera_transform_unchanged:
		result.error = "Shape seating changed gameplay or failed to reach the visible floor"
	return result


func _remember_pickup_overlay() -> bool:
	# These are the small HUD reward sprites flying into the fish counter,
	# not the course's Fish MultiMeshes or the permanent HUD currency icon.
	if _game.hud == null or _game.hud._float_fish_icons.is_empty() \
			or _game.hud._float_fish_icons.size() != _game.hud._float_labels.size():
		_error = "Shape review cannot identify the HUD pickup overlay pool"
		return false
	for index: int in _game.hud._float_fish_icons.size():
		var icon: TextureRect = _game.hud._float_fish_icons[index]
		if not is_instance_valid(icon) or icon.get_parent() != _game.hud._float_labels[index] \
				or not _game.hud.is_ancestor_of(icon):
			_error = "Shape review HUD pickup overlay ownership changed"
			return false
		_pickup_overlay_saved.append({"node": icon, "path": String(icon.get_path()),
			"visible": icon.visible, "visible_in_tree": icon.is_visible_in_tree()})
	return true


func _set_pickup_overlay_detail(detail: bool) -> bool:
	# Validate every saved node before changing any visibility. Zero active
	# floaters is valid; a missing/replaced pool during a frozen review is not.
	for saved: Dictionary in _pickup_overlay_saved:
		if not is_instance_valid(saved.node) or not _game.hud.is_ancestor_of(saved.node):
			_error = "Shape review lost a saved HUD pickup overlay node"
			return false
	for saved: Dictionary in _pickup_overlay_saved:
		var icon := saved.node as TextureRect
		icon.visible = false if detail else bool(saved.visible)
	_pickup_overlay_detail = detail
	return true


func _restore_pickup_overlay() -> void:
	for saved: Dictionary in _pickup_overlay_saved:
		if is_instance_valid(saved.node):
			var icon := saved.node as TextureRect
			icon.visible = bool(saved.visible)
	_pickup_overlay_detail = false


func _pickup_overlay_receipt() -> Dictionary:
	var result := {"policy": "Hide only transient HUD fish pickup icons in rear_detail; restore every original visibility in rear",
		"pool_source": "RunnerHUD._float_fish_icons", "detail_active": _pickup_overlay_detail,
		"matched_nodes": _pickup_overlay_saved.size(), "original_visible_nodes": 0,
		"original_visible_in_tree_nodes": 0, "hidden_nodes": 0, "visibility_mismatches": 0,
		"missing_nodes": 0, "world_collectibles_modified": false, "hud_counters_modified": false,
		"simulation_modified": false, "nodes": []}
	for saved: Dictionary in _pickup_overlay_saved:
		var row := {"path": saved.path, "original_visible": saved.visible,
			"original_visible_in_tree": saved.visible_in_tree, "current_visible": false,
			"current_visible_in_tree": false}
		if saved.visible:
			result.original_visible_nodes += 1
		if saved.visible_in_tree:
			result.original_visible_in_tree_nodes += 1
		if not is_instance_valid(saved.node):
			result.missing_nodes += 1
		else:
			var icon := saved.node as TextureRect
			row.current_visible = icon.visible
			row.current_visible_in_tree = icon.is_visible_in_tree()
			if icon.visible != (false if _pickup_overlay_detail else bool(saved.visible)):
				result.visibility_mismatches += 1
			if saved.visible and not icon.visible:
				result.hidden_nodes += 1
		result.nodes.append(row)
	return result


static func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()


static func compatibility_color_mesh(imported: ArrayMesh, renderer: String) -> Dictionary:
	var result := {"mesh": imported, "surfaces": [], "error": ""}
	if renderer != "gl_compatibility":
		return result
	if imported == null or imported.get_blend_shape_count() != 0:
		result.error = "Shape color transfer requires an unrigged ArrayMesh"
		return result
	# glTF COLOR_0 is linear. Godot 4.7 Compatibility decodes final ALBEDO
	# from sRGB; FLAG_SRGB_VERTEX_COLOR only acts when !OUTPUT_IS_SRGB.
	# Encode a private mesh copy once, preserving source paint and imported PBR.
	# https://github.com/godotengine/godot/blob/4.7-stable/drivers/gles3/shaders/scene.glsl#L2203
	# https://github.com/godotengine/godot/blob/4.7-stable/scene/resources/material.cpp#L1113
	var converted := ArrayMesh.new()
	converted.resource_name = imported.resource_name
	for surface: int in imported.get_surface_count():
		var arrays := imported.surface_get_arrays(surface).duplicate(true)
		var original: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		if original.is_empty():
			result.error = "Shape surface lacks linear vertex colors"
			return result
		var colors := original.duplicate()
		for index: int in colors.size():
			colors[index] = colors[index].linear_to_srgb()
		arrays[Mesh.ARRAY_COLOR] = colors
		converted.add_surface_from_arrays(imported.surface_get_primitive_type(surface), arrays)
		converted.surface_set_material(surface, imported.surface_get_material(surface))
		converted.surface_set_name(surface, imported.surface_get_name(surface))
		var active: PackedColorArray = converted.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
		var maximum_error := 0.0
		for index: int in active.size():
			var decoded := active[index].srgb_to_linear()
			var expected := original[index]
			maximum_error = maxf(maximum_error, maxf(absf(decoded.r - expected.r),
				maxf(absf(decoded.g - expected.g), absf(decoded.b - expected.b))))
		# ArrayMesh stores color in RGBA8; allow at most one encoded byte step.
		if maximum_error > 0.009:
			result.error = "Shape vertex color transfer exceeds RGBA8 roundtrip tolerance"
			return result
		result.surfaces.append({"surface": surface, "renderer": renderer,
			"transfer": "linear_to_srgb on private mesh; Compatibility decodes to original linear paint",
			"imported_color_sha256": _hash(original), "active_color_sha256": _hash(active),
			"linear_roundtrip_max_error": maximum_error, "linear_roundtrip_tolerance": 0.009,
			"source_mesh_unchanged": _hash(imported.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]) == _hash(original),
			"material_retained": converted.surface_get_material(surface) == imported.surface_get_material(surface)})
	result.mesh = converted
	return result


func _is_surface_review() -> bool:
	return _binding.get("material_contract") == "rear-surface-pbr-v1"


static func material_contract_mesh(imported: ArrayMesh, renderer: String, contract: String) -> Dictionary:
	if contract == "rear-surface-pbr-v1":
		return {"mesh": imported, "surfaces": [], "error": "" if imported != null else "Surface mesh missing"}
	return compatibility_color_mesh(imported, renderer)


func _texture_changed(texture_id: int) -> void:
	# Imported textures are immutable during this frozen review. Never silently
	# recalculate a changed texture and bless it as the original package.
	_texture_cache.erase(texture_id)
	_error = "Imported surface texture changed during review"


func _surface_map_receipts(material: BaseMaterial3D) -> Dictionary:
	var result := {"maps": {}, "errors": []}
	var slots := {"base_color": BaseMaterial3D.TEXTURE_ALBEDO,
		"normal": BaseMaterial3D.TEXTURE_NORMAL, "metallic_roughness": BaseMaterial3D.TEXTURE_ROUGHNESS}
	for name: String in slots:
		var texture := material.get_texture(slots[name])
		var expected: Dictionary = _binding.get("surface_maps", {}).get(name, {})
		if texture == null or expected.is_empty():
			result.errors.append("Imported surface map missing: " + name)
			continue
		var texture_id := texture.get_instance_id()
		if _texture_ids.has(name) and _texture_ids[name] != texture_id:
			result.errors.append("Imported surface texture replaced: " + name)
			continue
		_texture_ids[name] = texture_id
		if not _texture_cache.has(texture_id):
			var pixels := texture.get_image()
			if pixels == null or pixels.is_empty():
				result.errors.append("Imported surface map has no readable pixels: " + name)
				continue
			# get_image returns image data; duplicate before format normalization.
			var has_mipmaps := pixels.has_mipmaps()
			var mipmap_count := pixels.get_mipmap_count()
			pixels = pixels.duplicate()
			if pixels.is_compressed() and pixels.decompress() != OK:
				result.errors.append("Imported surface map cannot be decoded: " + name)
				continue
			pixels.clear_mipmaps()
			pixels.convert(Image.FORMAT_RGBA8)
			var hash_context := HashingContext.new()
			hash_context.start(HashingContext.HASH_SHA256)
			hash_context.update(pixels.get_data())
			_texture_cache[texture_id] = {"width": pixels.get_width(), "height": pixels.get_height(),
				"rgba8_sha256": hash_context.finish().hex_encode(), "texture_class": texture.get_class(),
				"has_mipmaps": has_mipmaps, "mipmap_count": mipmap_count,
				"resource_path": texture.resource_path, "pixel_policy": "Exact imported base-level RGBA8; no material/map substitution"}
			texture.changed.connect(_texture_changed.bind(texture_id))
		var receipt: Dictionary = _texture_cache[texture_id].duplicate()
		for field: String in ["width", "height", "rgba8_sha256"]:
			if receipt[field] != expected.get(field):
				result.errors.append("Imported surface map differs from embedded source: " + name + "/" + field)
		if not receipt.has_mipmaps:
			result.errors.append("Imported surface map lacks mipmaps: " + name)
		receipt["source_png_sha256"] = expected.get("sha256")
		receipt["color_space"] = expected.get("color_space")
		result.maps[name] = receipt
	if material.get_texture(BaseMaterial3D.TEXTURE_METALLIC) != material.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS):
		result.errors.append("Imported roughness/metallic do not share their bound G/B map")
	return result


func _surface_material_error(material: BaseMaterial3D) -> String:
	var expected: Dictionary = _binding.get("materials", [{}])[0]
	if not material is StandardMaterial3D or material.vertex_color_use_as_albedo \
			or material.albedo_color != Color.WHITE or not is_equal_approx(material.roughness, 1.0) \
			or not is_equal_approx(material.metallic, 1.0) or not material.normal_enabled \
			or not is_equal_approx(material.metallic_specular, float(expected.get("specular", 0.5))) \
			or material.get_meta("motion_surface_revision", "") != _binding.get("material_revision", {}).get("id", "") \
			or not is_equal_approx(material.normal_scale, float(expected.get("normal_scale", -1.0))) \
			or material.roughness_texture_channel != BaseMaterial3D.TEXTURE_CHANNEL_GREEN \
			or material.metallic_texture_channel != BaseMaterial3D.TEXTURE_CHANNEL_BLUE \
			or material.texture_filter not in [BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC] \
			or material.uv1_scale != Vector3.ONE or material.uv1_offset != Vector3.ZERO \
			or material.next_pass != null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
			or material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL \
			or material.cull_mode != (BaseMaterial3D.CULL_DISABLED if expected.get("double_sided", false) else BaseMaterial3D.CULL_BACK):
		return "Surface material differs from imported standard PBR contract"
	for slot: int in BaseMaterial3D.TEXTURE_MAX:
		if material.get_texture(slot) != null and slot not in [BaseMaterial3D.TEXTURE_ALBEDO,
				BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC]:
			return "Surface material has an undeclared texture slot"
	return ""


func _active_resources() -> Dictionary:
	var result := {"model": "", "surfaces": [], "errors": [], "signature": "", "original_hidden": false}
	if not is_instance_valid(_model) or not is_instance_valid(_original):
		result.errors.append("Shape or original visual missing")
		return result
	result.model = _model.scene_file_path
	result.original_hidden = not _original.visible and not _original.is_visible_in_tree()
	if result.model != MODEL or not result.original_hidden or not _model.is_visible_in_tree():
		result.errors.append("Bound shape is not the sole visible player model")
	for raw: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null:
			continue
		if instance.skin == null or instance.material_override != null or instance.material_overlay != null:
			result.errors.append("Motion surface lost skinning or has material substitution")
		for index: int in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(index)
			var material := instance.get_active_material(index) as BaseMaterial3D
			var row := {"mesh": String(_model.get_path_to(instance)), "surface": index,
				"geometry_sha256": _hash(arrays), "material": {}}
			if material == null or instance.get_surface_override_material(index) != null \
					or material.get_instance_id() != _material_ids.get(str(instance.get_instance_id()) + ":" + str(index)):
				result.errors.append("Shape material differs from the imported package")
			else:
				row.material = {"class": material.get_class(), "name": material.resource_name,
					"albedo": var_to_str(material.albedo_color), "roughness": material.roughness,
					"metallic": material.metallic, "vertex_color": material.vertex_color_use_as_albedo,
					"specular": material.metallic_specular, "source_material_revision": material.get_meta("motion_surface_revision", ""),
					"vertex_color_is_srgb": material.vertex_color_is_srgb, "cull_mode": material.cull_mode,
					"shading_mode": material.shading_mode, "normal_enabled": material.normal_enabled,
					"normal_scale": material.normal_scale, "roughness_channel": material.roughness_texture_channel,
					"metallic_channel": material.metallic_texture_channel, "texture_filter": material.texture_filter,
					"uv1_scale": var_to_str(material.uv1_scale), "uv1_offset": var_to_str(material.uv1_offset)}
				if _is_surface_review():
					var material_error := _surface_material_error(material)
					if not material_error.is_empty():
						result.errors.append(material_error)
					var maps := _surface_map_receipts(material)
					row.material["maps"] = maps.maps
					result.errors.append_array(maps.errors)
				else:
					if not material.vertex_color_use_as_albedo or material.albedo_color != Color.WHITE \
							or material.roughness < 0.8 or material.metallic != 0.0 or material.next_pass != null \
							or material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
						result.errors.append("Shape material no longer matches plain matte PBR")
					for slot: int in BaseMaterial3D.TEXTURE_MAX:
						if material.get_texture(slot) != null:
							result.errors.append("Shape material unexpectedly uses texture maps")
			result.surfaces.append(row)
	if result.surfaces.size() != int(_binding.get("surface_count", -1)):
		result.errors.append("Shape surface count differs from bound source")
	var rig := _rig_resources()
	result["rig"] = rig
	result.errors.append_array(rig.errors)
	result.signature = _hash([result.model, result.surfaces, rig.signature])
	return result


func status() -> Dictionary:
	var state := {"status": "pending", "error": _error, "view": _view,
		"settled_frames": maxi(0, _draws - _installed_draw), "tree_paused": get_tree().paused, "action": _action, "phase": _phase, "playing": _playing}
	if not _error.is_empty():
		state.status = "error"
	elif is_instance_valid(_model) and get_tree().paused and state.settled_frames >= 2:
		state.status = "ready"
	return state


func _rendering_environment() -> Dictionary:
	# Read existing renderer resources only. No loading, parameter writes or
	# per-frame texture readback; these few scalars accompany an explicit read().
	var result: Dictionary = {"available": false, "errors": [], "deck_tints": []}
	if not is_instance_valid(_game) or not is_instance_valid(_game._world_env) \
			or _game._world_env.environment == null or not is_instance_valid(_game._sun) \
			or not is_instance_valid(_game._fill) or not is_instance_valid(_game._rim):
		result.errors.append("Runner lighting resources unavailable")
		return result
	var env: Environment = _game._world_env.environment
	result.merge({"sun_energy": _game._sun.light_energy, "fill_energy": _game._fill.light_energy,
		"rim_energy": _game._rim.light_energy, "ambient_energy": env.ambient_light_energy,
		"ambient_sky_contribution": env.ambient_light_sky_contribution,
		"tonemap_mode": env.tonemap_mode, "tonemap_exposure": env.tonemap_exposure,
		"tonemap_white": env.tonemap_white, "glow_enabled": env.glow_enabled,
		"fog_density": env.fog_density})
	var sky_material: ProceduralSkyMaterial = env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
	if sky_material == null:
		result.errors.append("Runner procedural sky unavailable")
	else:
		var top: Color = sky_material.sky_top_color
		var horizon: Color = sky_material.sky_horizon_color
		result.sky_top = [top.r, top.g, top.b, top.a]
		result.sky_horizon = [horizon.r, horizon.g, horizon.b, horizon.a]
	var sea: RunnerPaintedSea = _game._painted_sea
	var material: ShaderMaterial = sea.material_override as ShaderMaterial if is_instance_valid(sea) else null
	if material == null:
		result.errors.append("Runner water material unavailable")
	else:
		var water_value: Variant = material.get_shader_parameter("water_tint")
		if water_value is Color:
			var water: Color = water_value
			result.water_tint = [water.r, water.g, water.b, water.a]
		else:
			result.errors.append("Runner water tint unavailable")
		# Ordinary exports retain the original fixed shader haze. A review
		# shader exposes its actual distances; no inferred default is reported.
		var haze_value: Variant = material.get_shader_parameter("haze_distances")
		if haze_value is Vector2:
			var haze: Vector2 = haze_value
			result.water_haze = [haze.x, haze.y]
		var crest_value: Variant = material.get_shader_parameter("crest_tint")
		if crest_value is Vector3:
			var crest: Vector3 = crest_value
			result.water_crest_tint = [crest.x, crest.y, crest.z]
		# Explicit water candidate parameters only; absent overrides remain
		# absent so capture receipts never mislabel inferred shader defaults.
		var detail_value: Variant = material.get_shader_parameter("day_detail_weight")
		if detail_value is float:
			result.water_day_detail_weight = detail_value
		var lateral_value: Variant = material.get_shader_parameter("day_lateral_reference_metres")
		if lateral_value is float:
			result.water_day_lateral_reference_metres = lateral_value
		var tile_value: Variant = material.get_shader_parameter("day_tile_metres")
		if tile_value is Vector2:
			result.water_day_tile_metres = [tile_value.x, tile_value.y]
		for parameter: String in ["day_trough_tint", "day_body_tint", "day_face_tint", "day_crest_tint"]:
			var palette_value: Variant = material.get_shader_parameter(parameter)
			if palette_value is Color:
				result["water_" + parameter] = [palette_value.r, palette_value.g, palette_value.b, palette_value.a]
	for path: String in _grounding.get("paths", []):
		var floor_mesh: MeshInstance3D = _game.track.get_node_or_null(path) as MeshInstance3D
		var floor_material: ShaderMaterial = floor_mesh.get_active_material(0) as ShaderMaterial if is_instance_valid(floor_mesh) else null
		var tint_value: Variant = floor_material.get_shader_parameter("tint") if floor_material != null else null
		if tint_value is Color:
			var tint: Color = tint_value
			result.deck_tints.append({"path": path, "rgba": [tint.r, tint.g, tint.b, tint.a]})
		else:
			result.errors.append("Grounding floor tint unavailable: " + path)
	if result.deck_tints.is_empty():
		result.errors.append("Grounding floor material not observed")
	result.available = result.errors.is_empty()
	return result


func snapshot() -> Dictionary:
	var result := status()
	result.merge({"schema_version": 1, "gate": _binding.get("gate"), "bound_source": _binding,
		"label": "Motion review • front and final integration pending", "unrigged": false,
		"animation_ready": true, "production_ready": false, "performance_measured": false,
		"camera_before_swap": _camera_before, "camera_after_swap": _camera_after,
		"original_visible_bounds": _baseline_bounds, "import_flag_repairs": _repairs,
		"vertex_color_transfers": _color_transfers,
		"pickup_overlay": _pickup_overlay_receipt(),
		"grounding": _grounding,
		"renderer": RenderingServer.get_current_rendering_method(), "active_renderer": {},
		"logical_viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]})
	if result.status != "ready":
		return result
	result.active_renderer = _active_resources()
	result.rendering_environment = _rendering_environment()
	result.motion = _motion_receipt()
	result.camera = _camera_state()
	result.camera.merge({"projection": _camera.projection, "keep_aspect": _camera.keep_aspect,
		"near": _camera.near, "far": _camera.far, "h_offset": _camera.h_offset, "v_offset": _camera.v_offset,
		"frustum_offset": var_to_str(_camera.frustum_offset)})
	result.transforms = {"player_global": var_to_str(_game.player.global_transform),
		"holder_global": var_to_str(_holder.global_transform), "model_global": var_to_str(_model.global_transform),
		"skeleton_global": var_to_str(_skeleton.global_transform)}
	result.gameplay_scale = _binding.get("gameplay_scale")
	if result.pickup_overlay.missing_nodes > 0 or result.pickup_overlay.visibility_mismatches > 0:
		result.active_renderer.errors.append("HUD pickup overlay visibility differs from declared view policy")
	if result.active_renderer.signature != _initial_signature:
		result.active_renderer.errors.append("Shape geometry or material changed after installation")
	if not result.active_renderer.errors.is_empty():
		result.status = "error"
		result.error = "; ".join(result.active_renderer.errors)
	return result


func _on_status(_args: Array) -> void:
	JavaScriptBridge.eval("window.__wwMotionCandidate._reply = " + JSON.stringify(status()), true)


func _on_read(_args: Array) -> void:
	JavaScriptBridge.eval("window.__wwMotionCandidate._reply = " + JSON.stringify(snapshot()), true)


func _on_view(args: Array) -> void:
	if args.size() != 1 or not args[0] is String or args[0] not in ["rear", "rear_detail"]:
		_error = "Shape review permits only rear gameplay and rear detail"
		return
	if status().status != "ready":
		return
	if not _set_pickup_overlay_detail(args[0] == "rear_detail"):
		return
	if args[0] == "rear":
		_camera.global_transform = _chase_transform
		_camera.fov = _chase_fov
	else:
		var height := float(_binding.gameplay_height_m)
		# One fixed camera for all phases; leave room above the avalanche HUD
		# and below the score HUD for the whole grounded-to-apex motion envelope.
		var target := _game.player.global_position + Vector3.UP * height * 1.32
		_camera.fov = 34.0
		# Match the gameplay eye elevation/distance; only framing and FOV differ.
		_camera.look_at_from_position(target + Vector3.BACK * height * 8.6 + Vector3.UP * height * 1.55, target)
	_view = String(args[0])
	_installed_draw = _draws


func _duration(action: String) -> float:
	return JUMP_AIRTIME if action == "jump" else _animation.get_animation(_clip_names[action]).length


func _apply_jump_height() -> void:
	var time := _phase * JUMP_AIRTIME
	_jump_height = maxf(0.0, RunnerConfig.JUMP_SPEED * time - 0.5 * RunnerConfig.GRAVITY * time * time) if _action == "jump" else 0.0
	_holder.position = _holder_rest + Vector3.UP * _jump_height


func _start_action(action: String, blend: float) -> void:
	_action = action
	_phase = 0.0
	var clip := _animation.get_animation(_clip_names[action])
	# Clip speed belongs to this playback, while blend timers use real seconds.
	_animation.play(_clip_names[action], blend, clip.length / _duration(action))
	# play() resumes an already selected clip; restart its clock with the arc.
	_animation.seek(0.0, true)
	_animation.advance(0.0)
	_apply_jump_height()
	_installed_draw = _draws


func _advance_motion(delta: float) -> void:
	if not _playing or not is_instance_valid(_animation) or delta <= 0.0:
		return
	var remaining := delta
	if _action == "jump":
		var to_landing := maxf(0.0, (1.0 - _phase) * JUMP_AIRTIME)
		var jump_delta := minf(remaining, to_landing)
		_phase = minf(1.0, _phase + jump_delta / JUMP_AIRTIME)
		_animation.advance(jump_delta)
		_apply_jump_height()
		if remaining < to_landing:
			return
		# Finish the authored landing before blending, even when a frame straddles it.
		_phase = 1.0
		_animation.seek(_animation.get_animation(_clip_names["jump"]).length, true)
		_apply_jump_height()
		remaining -= jump_delta
		_start_action("waddle", 0.12)
	if remaining > 0.0:
		_phase = fmod(_phase + remaining / _duration(_action), 1.0)
		_animation.advance(remaining)
		_apply_jump_height()


func _on_action(args: Array) -> void:
	if args.size() != 1 or args[0] not in ["waddle", "jump", "slide"] or not is_instance_valid(_animation):
		return
	_playing = true
	_start_action(String(args[0]), 0.12)


func _on_play(args: Array) -> void:
	if args.size() == 1 and (args[0] is bool or (args[0] is int and args[0] in [0, 1])):
		_playing = bool(args[0])


func _on_sample(args: Array) -> void:
	if args.size() != 2 or args[0] not in ["waddle", "jump", "slide"] \
			or not (args[1] is float or args[1] is int) or not is_instance_valid(_animation):
		return
	var phase := float(args[1])
	if not is_finite(phase) or phase < 0.0 or phase > 1.0:
		_error = "Motion sample phase outside [0,1]"
		return
	_playing = false
	_start_action(String(args[0]), 0.0)
	_phase = phase
	_animation.seek(phase * _animation.get_animation(_clip_names[_action]).length, true)
	_skeleton.force_update_all_bone_transforms()
	_apply_jump_height()
	_installed_draw = _draws


func _motion_receipt() -> Dictionary:
	var bones: Array[Dictionary] = []
	for index: int in _skeleton.get_bone_count():
		bones.append({"name": _skeleton.get_bone_name(index), "parent": _skeleton.get_bone_parent(index),
			"pose": var_to_str(_skeleton.get_bone_global_pose(index)),
			"rest": var_to_str(_skeleton.get_bone_global_rest(index))})
	return {"action": _action, "phase": _phase, "playing": _playing,
		"imported_clip": _clip_names[_action], "clip_time": _animation.current_animation_position,
		"clip_length": _animation.get_animation(_clip_names[_action]).length,
		"game_duration_s": _duration(_action), "jump_height_m": _jump_height,
		"jump_speed": RunnerConfig.JUMP_SPEED, "gravity": RunnerConfig.GRAVITY,
		"root_motion_policy": "Controller ballistic height; imported clip articulation. No per-frame floor snapping.",
		"source": "Actual imported AnimationPlayer and skinned mesh; no hand-reposed capture geometry",
		"bones": bones}


func _rig_resources() -> Dictionary:
	# Read only on explicit verification, never per frame. Hash actual resources,
	# so replacing a bind pose/clip with the same source metadata cannot pass.
	var result := {"errors": [], "bones": [], "skins": [], "clips": {}, "signature": ""}
	if not is_instance_valid(_skeleton) or not is_instance_valid(_animation):
		result.errors.append("Imported motion skeleton/AnimationPlayer missing")
		return result
	var names: Array = []
	var parents: Array = []
	for bone: int in _skeleton.get_bone_count():
		names.append(_skeleton.get_bone_name(bone))
		var parent: int = _skeleton.get_bone_parent(bone)
		parents.append(_skeleton.get_bone_name(parent) if parent >= 0 else null)
		result.bones.append({"name": _skeleton.get_bone_name(bone), "parent": parent,
			"rest": var_to_str(_skeleton.get_bone_rest(bone))})
	var source_names: Array = _binding.get("rig", {}).get("joints", [])
	var source_parents: Array = _binding.get("rig", {}).get("parents", [])
	var expected_parents: Dictionary = {}
	var actual_parents: Dictionary = {}
	for index: int in source_names.size():
		expected_parents[source_names[index]] = source_parents[index]
	for index: int in names.size():
		actual_parents[names[index]] = parents[index]
	var sorted_names: Array = names.duplicate()
	var expected_names: Array = source_names.duplicate()
	sorted_names.sort()
	expected_names.sort()
	if sorted_names != expected_names or names.size() != actual_parents.size() or actual_parents != expected_parents:
		result.errors.append("Imported skeleton names/parents differ from source: " + str(names))
	for raw: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.skin == null:
			result.errors.append("Imported skin missing")
			continue
		var binds: Array = []
		for bind: int in instance.skin.get_bind_count():
			binds.append({"name": String(instance.skin.get_bind_name(bind)),
				"bone": instance.skin.get_bind_bone(bind), "pose": var_to_str(instance.skin.get_bind_pose(bind))})
		result.skins.append({"mesh": String(_model.get_path_to(instance)), "binds": binds,
			"skeleton": String(instance.skeleton)})
	var actual: Array = Array(_animation.get_animation_list())
	var expected: Array = _binding.get("clips", {}).keys()
	actual.sort()
	expected.sort()
	if actual != expected:
		result.errors.append("Imported motion clip names differ from source")
	for clip_name: String in actual:
		var clip := _animation.get_animation(clip_name)
		var contract: Dictionary = _binding.get("clips", {}).get(clip_name, {})
		if contract.is_empty():
			continue
		if absf(clip.length - float(contract.duration)) > 0.0001 				or clip.loop_mode != (Animation.LOOP_LINEAR if contract.loop else Animation.LOOP_NONE):
			result.errors.append("Imported clip duration/loop differs: " + clip_name)
		var tracks: Array = []
		for track: int in clip.get_track_count():
			var path: NodePath = clip.track_get_path(track)
			var kind: int = clip.track_get_type(track)
			if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] 					or path.get_subname_count() != 1 or not names.has(String(path.get_subname(0))):
				result.errors.append("Imported clip contains non-joint track: " + clip_name)
			var keys: Array = []
			for key: int in clip.track_get_key_count(track):
				keys.append([clip.track_get_key_time(track, key), clip.track_get_key_value(track, key),
					clip.track_get_key_transition(track, key)])
			tracks.append({"path": String(path), "type": kind, "enabled": clip.track_is_enabled(track),
				"interpolation": clip.track_get_interpolation_type(track), "keys": keys})
		result.clips[clip_name] = {"length": clip.length, "loop": clip.loop_mode,
			"tracks": tracks.size(), "keys_sha256": _hash(tracks)}
	result.signature = _hash([result.bones, result.skins, result.clips])
	return result
